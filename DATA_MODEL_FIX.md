# Data Model Fix: Separating Cumulative Metrics from Daily Activity

## The Problem

**Symptoms:**
- Weekly card showing 3,535 total words
- Heatmap showing 500+ per day
- Numbers didn't make sense for daily activity

**Root Cause:**
The statistics page was using **cumulative totals** (total words learned over time) for both:
1. Velocity chart (correct usage) ✅
2. Heatmap calendar (wrong usage) ❌
3. Weekly summary card (wrong usage) ❌

This caused the heatmap to show the total number of words you've ever learned (which grows over time), not the number of attempts you made each day.

## The Solution

### Two Different Metrics in `daily_stats` Table

```sql
CREATE TABLE daily_stats (
  user_id TEXT,
  date TEXT,

  -- CUMULATIVE METRICS (snapshot that grows over time)
  total_words INTEGER,      -- Total unique words practiced
  learned_count INTEGER,    -- Words in learned/consolidating status
  reviewing_count INTEGER,  -- Words in learning status

  -- DAILY ACTIVITY METRIC (daily count, NOT cumulative)
  attempts_sum INTEGER,     -- Number of attempts made this day

  UNIQUE(user_id, date)
);
```

### What Each Metric Is Used For

| Metric | Type | Range | Used For | Example |
|--------|------|-------|----------|---------|
| `total_words` | Cumulative | 0-5000+ | Velocity chart | Day 1: 50, Day 2: 75, Day 3: 100 |
| `learned_count` | Cumulative | 0-5000+ | Velocity chart | Day 1: 10, Day 2: 25, Day 3: 40 |
| `reviewing_count` | Cumulative | 0-5000+ | Velocity chart | Day 1: 40, Day 2: 50, Day 3: 60 |
| `attempts_sum` | Daily | 0-500 | Heatmap, Weekly card | Day 1: 25, Day 2: 15, Day 3: 30 |

### Visual Comparison

**Before (Wrong):**
```
Heatmap using total_words (cumulative):
Mon: 450  Tue: 475  Wed: 500  Thu: 520  Fri: 545  Sat: 560  Sun: 580
           ↑ This grows every day (wrong for heatmap!)
Weekly Total: 3,530 words
```

**After (Correct):**
```
Heatmap using attempts_sum (daily activity):
Mon: 25   Tue: 30   Wed: 15   Thu: 20   Fri: 35   Sat: 10   Sun: 40
         ↑ This shows activity for each day (correct!)
Weekly Total: 175 attempts
```

## Code Changes

### 1. Added `attempts_sum` Column

**local_db.dart (Line 103):**
```dart
CREATE TABLE daily_stats (
  ...
  attempts_sum INTEGER DEFAULT 0,  // NEW: Daily activity count
  UNIQUE(user_id, date)
)
```

### 2. Calculate `attempts_sum` During Aggregation

**local_db.dart (_aggregateAndSyncDailyStats, Line 382):**
```dart
dailyStatsPayload.add({
  'user_id': userId,
  'date': date,
  'total_words': stats['total_words'] ?? 0,  // Cumulative snapshot
  'learned_count': stats['learned_count'] ?? 0,  // Cumulative snapshot
  'reviewing_count': stats['reviewing_count'] ?? 0,  // Cumulative snapshot
  'attempts_sum': dayLog['total_attempts'] ?? 0,  // NEW: Daily activity count
});
```

The `total_attempts` comes from:
```sql
SELECT
  DATE(attempted_at) as date,
  COUNT(*) as total_attempts,  -- This is the daily activity!
  ...
FROM attempt_logs
WHERE user_id = ? AND synced = 0
GROUP BY DATE(attempted_at)
```

### 3. Updated Heatmap Query

**local_db.dart (getDailyActivityHeatmap, Line 630):**
```dart
// BEFORE (wrong):
SELECT date, total_words  -- This is cumulative!
FROM daily_stats
WHERE user_id = ? AND date >= ?

// AFTER (correct):
SELECT date, attempts_sum  -- This is daily activity!
FROM daily_stats
WHERE user_id = ? AND date >= ?
```

### 4. Updated Supabase Schema

**supabase_schema_fixes.sql (Line 49):**
```sql
-- Add attempts_sum column to daily_stats
ALTER TABLE public.daily_stats
ADD COLUMN IF NOT EXISTS attempts_sum INTEGER DEFAULT 0;

-- Add helpful comments
COMMENT ON COLUMN public.daily_stats.attempts_sum IS
  'Number of attempts made on this day (daily activity count, not cumulative)';
```

## Migration Path

### For Existing Data

The migration automatically handles existing databases:

1. **New installs:** `attempts_sum` column included from start
2. **Upgrading from v1 → v2:** Migration adds `attempts_sum` column with default 0
3. **Next sync:** New data will populate `attempts_sum` correctly

### For Supabase Cloud

Run the SQL commands in `supabase_schema_fixes.sql`:
```bash
# In Supabase SQL Editor, run:
ALTER TABLE public.daily_stats
ADD COLUMN IF NOT EXISTS attempts_sum INTEGER DEFAULT 0;
```

### Backfilling Old Data (Optional)

If you have historical `daily_stats` records without `attempts_sum`, you can backfill from `attempt_logs`:

```sql
-- Run in Supabase SQL Editor
UPDATE public.daily_stats ds
SET attempts_sum = (
  SELECT COUNT(*)
  FROM public.attempt_logs al
  WHERE al.user_id = ds.user_id
    AND DATE(al.attempted_at) = ds.date
)
WHERE attempts_sum = 0 OR attempts_sum IS NULL;
```

**Note:** Only run this if you still have old `attempt_logs` in Supabase. If you've already cleaned them up (as recommended), the old stats will remain at 0 (which is fine, since they're historical).

## Testing Checklist

After deploying these changes:

- [ ] Run `supabase_schema_fixes.sql` in Supabase SQL Editor
- [ ] Deploy updated app to your device
- [ ] Complete a few lessons (10-20 attempts)
- [ ] Trigger sync (close/reopen app)
- [ ] Open Statistics page
- [ ] Verify weekly card shows realistic numbers (10-100 range, not 500+)
- [ ] Verify heatmap shows activity levels (0-100 range, not cumulative totals)
- [ ] Verify velocity chart still shows growth over time
- [ ] Check Supabase daily_stats table - should have `attempts_sum` column

## Expected Results

### Weekly Summary Card
```
THIS WEEK
Total: 175 words     ← Daily attempts summed (not cumulative)
Days: 5             ← Active days
Avg: 35/day         ← Average daily activity
```

### Heatmap Calendar
- Light green: 1-10 attempts
- Medium green: 11-30 attempts
- Dark green: 31+ attempts
- Not 500+ like before! ✅

### Velocity Chart (Unchanged)
- Still shows cumulative growth
- Learned line should trend upward
- Reviewing line shows active learning words

## Summary

✅ **Fixed heatmap** - Now shows daily activity (10-100 range) instead of cumulative totals (500+)
✅ **Fixed weekly card** - Shows realistic attempt counts (e.g., 175) instead of inflated numbers (3,535)
✅ **Preserved velocity chart** - Still uses cumulative metrics to show growth over time
✅ **Database migration** - Automatically adds `attempts_sum` column to existing databases
✅ **Backward compatible** - Old devices still work, just don't track attempts_sum yet
✅ **No data loss** - All existing data preserved

The data model now correctly separates:
- **Cumulative metrics** → Velocity chart (shows growth)
- **Daily activity** → Heatmap & weekly card (shows daily effort)
