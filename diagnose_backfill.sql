-- =========================================================
-- DIAGNOSTIC QUERIES FOR BACKFILL ISSUE
-- Run these to figure out why attempts_sum is 0
-- =========================================================

-- 1. Check if you have ANY attempt_logs at all
SELECT
  COUNT(*) as total_logs,
  MIN(attempted_at) as oldest,
  MAX(attempted_at) as newest
FROM public.attempt_logs;

-- 2. Check the date format in attempt_logs
SELECT
  attempted_at,
  DATE(attempted_at) as date_only,
  attempted_at::date as date_cast
FROM public.attempt_logs
LIMIT 5;

-- 3. Check the date format in daily_stats
SELECT
  date,
  date::date as date_cast
FROM public.daily_stats
ORDER BY date DESC
LIMIT 5;

-- 4. See if there's a mismatch between the two tables
SELECT
  ds.date as daily_stats_date,
  COUNT(al.id) as matching_logs
FROM public.daily_stats ds
LEFT JOIN public.attempt_logs al
  ON al.user_id = ds.user_id
  AND DATE(al.attempted_at) = ds.date::date
GROUP BY ds.date
ORDER BY ds.date DESC
LIMIT 10;

-- 5. Try different date comparison methods
SELECT
  ds.date as date_text,
  ds.date::date as date_converted,
  ds.user_id,
  -- Method 1: Cast daily_stats.date to date type first
  (SELECT COUNT(*) FROM public.attempt_logs al
   WHERE al.user_id = ds.user_id
   AND DATE(al.attempted_at) = ds.date::date) as method1,
  -- Method 2: Convert attempted_at to text for comparison
  (SELECT COUNT(*) FROM public.attempt_logs al
   WHERE al.user_id = ds.user_id
   AND DATE(al.attempted_at)::text = ds.date) as method2,
  -- Method 3: Use TO_DATE on daily_stats.date
  (SELECT COUNT(*) FROM public.attempt_logs al
   WHERE al.user_id = ds.user_id
   AND DATE(al.attempted_at) = TO_DATE(ds.date, 'YYYY-MM-DD')) as method3
FROM public.daily_stats ds
ORDER BY ds.date DESC
LIMIT 5;
