-- =========================================================
-- BACKFILL attempts_sum FROM EXISTING attempt_logs
-- Run this in Supabase SQL Editor to populate historical data
-- =========================================================

-- This updates all daily_stats rows with the count of attempts from attempt_logs
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

-- Check how many rows were updated
SELECT
  COUNT(*) as total_days,
  SUM(CASE WHEN attempts_sum > 0 THEN 1 ELSE 0 END) as days_with_data,
  SUM(CASE WHEN attempts_sum = 0 THEN 1 ELSE 0 END) as days_without_data,
  SUM(attempts_sum) as total_attempts
FROM public.daily_stats
WHERE user_id = (SELECT id FROM auth.users LIMIT 1);  -- Replace with your user_id if you know it

-- Optional: View the results to verify
SELECT
  date,
  total_words,
  learned_count,
  reviewing_count,
  attempts_sum
FROM public.daily_stats
WHERE user_id = (SELECT id FROM auth.users LIMIT 1)  -- Replace with your user_id
ORDER BY date DESC
LIMIT 30;
