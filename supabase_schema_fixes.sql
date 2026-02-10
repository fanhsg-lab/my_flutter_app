-- =========================================================
-- SUPABASE SCHEMA FIXES FOR MULTI-USER SUPPORT
-- Run these commands in your Supabase SQL Editor
-- =========================================================

-- 1. FIX: Allow 'new' status in user_word_progress
-- The current CHECK constraint is missing 'new' status
ALTER TABLE public.user_word_progress
DROP CONSTRAINT IF EXISTS user_word_progress_status_check;

ALTER TABLE public.user_word_progress
ADD CONSTRAINT user_word_progress_status_check
CHECK (status = ANY (ARRAY['new'::text, 'learning'::text, 'consolidating'::text, 'learned'::text]));

-- 2. ADD: Unique constraint on (user_id, word_id)
-- This prevents duplicate progress records for the same user+word
ALTER TABLE public.user_word_progress
DROP CONSTRAINT IF EXISTS user_word_progress_unique_user_word;

ALTER TABLE public.user_word_progress
ADD CONSTRAINT user_word_progress_unique_user_word
UNIQUE (user_id, word_id);

-- 3. ADD: Index for faster queries
CREATE INDEX IF NOT EXISTS idx_user_word_progress_user_id
ON public.user_word_progress(user_id);

CREATE INDEX IF NOT EXISTS idx_user_word_progress_next_due
ON public.user_word_progress(user_id, next_due_at);

CREATE INDEX IF NOT EXISTS idx_attempt_logs_user_id
ON public.attempt_logs(user_id);

CREATE INDEX IF NOT EXISTS idx_attempt_logs_user_word
ON public.attempt_logs(user_id, word_id);

-- 4. ADD: Unique constraint on daily_stats (user_id, date)
ALTER TABLE public.daily_stats
DROP CONSTRAINT IF EXISTS daily_stats_unique_user_date;

ALTER TABLE public.daily_stats
ADD CONSTRAINT daily_stats_unique_user_date
UNIQUE (user_id, date);

-- 5. ADD: Index on daily_stats for fast queries
CREATE INDEX IF NOT EXISTS idx_daily_stats_user_date
ON public.daily_stats(user_id, date DESC);

-- 6. ADD: attempts_sum column to daily_stats (for daily activity tracking)
-- This separates cumulative metrics (total_words, learned_count) from daily activity
ALTER TABLE public.daily_stats
ADD COLUMN IF NOT EXISTS attempts_sum INTEGER DEFAULT 0;

COMMENT ON COLUMN public.daily_stats.attempts_sum IS 'Number of attempts made on this day (daily activity count, not cumulative)';
COMMENT ON COLUMN public.daily_stats.total_words IS 'Total unique words practiced on this day (snapshot for velocity chart)';
COMMENT ON COLUMN public.daily_stats.learned_count IS 'Count of words in learned/consolidating status on this day (cumulative snapshot)';
COMMENT ON COLUMN public.daily_stats.reviewing_count IS 'Count of words in learning status on this day (cumulative snapshot)';

-- 7. VERIFY: Check how many days will be backfilled
SELECT
  COUNT(*) as days_to_backfill,
  MIN(date) as oldest_date,
  MAX(date) as newest_date
FROM public.daily_stats
WHERE attempts_sum = 0 OR attempts_sum IS NULL;

-- If you have attempt_logs available, this shows how much data you can recover:
SELECT
  COUNT(DISTINCT DATE(attempted_at)) as days_with_logs,
  MIN(DATE(attempted_at)) as oldest_log,
  MAX(DATE(attempted_at)) as newest_log,
  COUNT(*) as total_logs
FROM public.attempt_logs;

-- OPTIONAL: Drop the duplicate 'attempts' table if you're only using 'attempt_logs'
-- CAUTION: Only run this if you're sure you don't need the 'attempts' table
-- DROP TABLE IF EXISTS public.attempts;

-- 8. BACKFILL: Populate attempts_sum from existing attempt_logs
-- This calculates the count of attempts per day and updates daily_stats
UPDATE public.daily_stats ds
SET attempts_sum = COALESCE(
  (
    SELECT COUNT(*)
    FROM public.attempt_logs al
    WHERE al.user_id = ds.user_id
      AND DATE(al.attempted_at) = ds.date::date
  ),
  0
)
WHERE ds.attempts_sum = 0 OR ds.attempts_sum IS NULL;

-- 9. OPTIONAL: Clean up old attempt_logs (keep last 2 years, use daily_stats for older data)
-- Uncomment to run:
-- DELETE FROM public.attempt_logs WHERE attempted_at < NOW() - INTERVAL '2 years';

-- 10. VERIFY: Check the schema is correct
SELECT
  table_name,
  constraint_name,
  constraint_type
FROM information_schema.table_constraints
WHERE table_schema = 'public'
  AND table_name IN ('user_word_progress', 'attempt_logs')
ORDER BY table_name, constraint_type;
