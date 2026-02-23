-- ============================================================
-- SUBSCRIPTION SCHEMA CHANGES
-- Run this in Supabase SQL Editor (Dashboard > SQL Editor)
-- ============================================================

-- 1. Add trial_started_at to profiles
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS trial_started_at TIMESTAMPTZ;

-- Reset trial for ALL existing users (fresh 2 months from today)
UPDATE profiles SET trial_started_at = now() WHERE trial_started_at IS NULL;

-- 2. Update the handle_new_user trigger to set trial_started_at on signup
-- (Check your existing trigger first — you may need to adapt this)
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, email, trial_started_at)
  VALUES (NEW.id, NEW.email, now())
  ON CONFLICT (id) DO UPDATE SET
    email = EXCLUDED.email,
    trial_started_at = COALESCE(profiles.trial_started_at, now());
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Make sure the trigger exists
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- 3. Create subscriptions table
CREATE TABLE IF NOT EXISTS subscriptions (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  product_id TEXT NOT NULL,
  purchase_token TEXT,
  status TEXT NOT NULL DEFAULT 'active',
  platform TEXT NOT NULL DEFAULT 'android',
  starts_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(user_id)
);

CREATE INDEX IF NOT EXISTS idx_subscriptions_user_id ON subscriptions(user_id);

-- 4. RLS for subscriptions
ALTER TABLE subscriptions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can read own subscriptions" ON subscriptions;
CREATE POLICY "Users can read own subscriptions"
  ON subscriptions FOR SELECT
  USING (auth.uid() = user_id);

-- Service role (edge functions) can do everything — no policy needed,
-- service role bypasses RLS by default.

-- 5. RPC function to check subscription status
CREATE OR REPLACE FUNCTION get_subscription_status(p_user_id UUID)
RETURNS TABLE(
  is_trial BOOLEAN,
  trial_days_left INT,
  has_active_sub BOOLEAN,
  sub_expires_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_trial_started TIMESTAMPTZ;
  v_trial_end TIMESTAMPTZ;
BEGIN
  SELECT trial_started_at INTO v_trial_started
  FROM profiles WHERE id = p_user_id;

  -- Default to now() if no trial_started_at (new user edge case)
  IF v_trial_started IS NULL THEN
    v_trial_started := now();
    UPDATE profiles SET trial_started_at = now() WHERE id = p_user_id;
  END IF;

  v_trial_end := v_trial_started + INTERVAL '2 months';

  RETURN QUERY
  SELECT
    (now() < v_trial_end) AS is_trial,
    GREATEST(0, EXTRACT(DAY FROM v_trial_end - now())::INT) AS trial_days_left,
    EXISTS(
      SELECT 1 FROM subscriptions s
      WHERE s.user_id = p_user_id
        AND s.status IN ('active', 'grace_period')
        AND (s.expires_at IS NULL OR s.expires_at > now())
    ) AS has_active_sub,
    (SELECT MAX(s.expires_at) FROM subscriptions s
     WHERE s.user_id = p_user_id
       AND s.status IN ('active', 'grace_period')
    ) AS sub_expires_at;
END;
$$;
