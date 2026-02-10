# Multi-Book Support Setup Guide

## Overview

Your app now supports multiple books! Users can switch between books and see:
- **Filtered Dashboard**: Only lessons from the selected book
- **Global Progress**: Word progress is shared across all books (if the same word appears in multiple books, you only learn it once)
- **Global Statistics**: Heatmap, velocity chart, and stats show total activity across all books
- **Per-Book Progress Circles**: Each lesson shows progress using global word data

---

## Database Changes

### Local Database (SQLite)

**No schema changes needed!** ✅

The local database already has everything we need:
- `app_meta` table for storing `current_book_id`
- `lessons` table with `book_id` column
- `user_progress` table with no `book_id` (global progress)

### Supabase (Cloud Database)

**Optional:** If you want to sync current book selection across devices, you can add it to the user profile.

#### Option 1: Add to existing profile table

```sql
-- Add current_book_id to user_profiles (if you have one)
ALTER TABLE public.user_profiles
ADD COLUMN IF NOT EXISTS current_book_id INTEGER;

-- Add index for faster queries
CREATE INDEX IF NOT EXISTS idx_user_profiles_current_book
ON public.user_profiles(user_id, current_book_id);
```

#### Option 2: Create user_settings table (recommended)

```sql
-- Create a dedicated user_settings table for preferences
CREATE TABLE IF NOT EXISTS public.user_settings (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  current_book_id INTEGER,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Add index
CREATE INDEX IF NOT EXISTS idx_user_settings_user_id
ON public.user_settings(user_id);

-- Enable RLS (Row Level Security)
ALTER TABLE public.user_settings ENABLE ROW LEVEL SECURITY;

-- Policy: Users can only see their own settings
CREATE POLICY "Users can view own settings"
ON public.user_settings FOR SELECT
USING (auth.uid() = user_id);

-- Policy: Users can insert their own settings
CREATE POLICY "Users can insert own settings"
ON public.user_settings FOR INSERT
WITH CHECK (auth.uid() = user_id);

-- Policy: Users can update their own settings
CREATE POLICY "Users can update own settings"
ON public.user_settings FOR UPDATE
USING (auth.uid() = user_id);
```

**Note:** For now, the app works perfectly without syncing `current_book_id` to Supabase. Each device will remember its own book selection locally. You can add cloud sync later if needed.

---

## Testing Your Multi-Book Setup

### 1. Check Your Data

First, verify you have multiple books in your database:

```sql
-- In Supabase SQL Editor, run:
SELECT DISTINCT book_id, COUNT(*) as lesson_count
FROM public.lessons
WHERE book_id IS NOT NULL
GROUP BY book_id
ORDER BY book_id;
```

**Expected Result:**
```
book_id | lesson_count
--------|-------------
   1    |     12
   2    |     15
   3    |     10
```

If you only see one book, you'll need to add more books to test the feature.

### 2. Deploy and Test on Your Device

1. **Deploy the updated app:**
   ```bash
   flutter run
   ```

2. **Tap the book icon** (top-left corner of main screen)

3. **You should see:**
   - A bottom sheet with list of available books
   - Current selected book is highlighted
   - Each book shows its lesson count

4. **Select a different book:**
   - Tap on another book
   - Dashboard should refresh automatically
   - You should see only that book's lessons

5. **Verify progress circles:**
   - If you've already learned words from Book 1
   - And those same words appear in Book 2
   - The progress circles should show them as "Mastered" (not "New")
   - This confirms global progress is working!

### 3. Verify Statistics (Unchanged)

1. Go to **Stats** tab
2. Verify heatmap shows ALL activity (not filtered by book) ✅
3. Verify velocity chart shows total learned words ✅
4. Verify weekly card shows total attempts ✅

---

## How It Works

### Architecture Summary

```
┌─────────────────────────────────────────────────────────┐
│  USER SWITCHES BOOK (tap top-left icon)                │
│  ↓                                                      │
│  current_book_id stored in app_meta table               │
│  ↓                                                      │
│  getDashboardLessons() filters by current_book_id      │
│  ↓                                                      │
│  Dashboard shows only current book's lessons            │
│  ↓                                                      │
│  Each lesson uses GLOBAL word progress                  │
└─────────────────────────────────────────────────────────┘
```

### Data Flow

1. **Book Selection:**
   - Stored locally in `app_meta` table (key: `current_book_id`)
   - Persists between app restarts
   - Can be synced to cloud (optional)

2. **Dashboard Filtering:**
   - `getDashboardLessons()` queries: `WHERE book_id = current_book_id`
   - Returns only lessons from selected book
   - Each lesson calculates progress from global `user_progress` table

3. **Word Progress (Global):**
   - `user_progress` table has NO `book_id` column
   - One record per user + word combination
   - Same word in different books shares progress
   - If you learn "hola" in Book 1, it's marked learned in Book 2 too

4. **Statistics (Global):**
   - `daily_stats` table has NO `book_id` column
   - Shows total activity across all books
   - Motivates users to keep learning

---

## Code Changes Summary

### lib/local_db.dart

Added three new functions:

```dart
// Get currently selected book ID
Future<int?> getCurrentBookId()

// Set currently selected book ID
Future<void> setCurrentBookId(int bookId)

// Get all available books with lesson counts
Future<List<BookData>> getAllBooks()
```

Updated one existing function:

```dart
// Now filters by current book
Future<List<LessonData>> getDashboardLessons()
```

### lib/pages/MainScreen.dart

Added one new function:

```dart
// Shows book selector dialog
Future<void> _showBookSelector()
```

Updated one widget:

```dart
// Leading icon now opens book selector
AppBar(
  leading: IconButton(
    icon: const Icon(Icons.menu_book),
    onPressed: _showBookSelector,
  ),
  ...
)
```

---

## Troubleshooting

### No books appear in selector

**Problem:** Book selector shows "No books available yet"

**Solution:**
1. Check Supabase has books in `lessons` table with `book_id` populated
2. Run sync: Pull to refresh on main screen
3. Verify locally: Open database inspector and check `lessons` table

### All lessons still show after selecting a book

**Problem:** Changing book doesn't filter lessons

**Solutions:**
1. Do a **full app restart** (not hot reload) - database changes require restart
2. Check logs for errors in `getDashboardLessons()`
3. Verify `current_book_id` is stored: Check `app_meta` table in local database

### Progress shows words as "unseen" when they should be learned

**Problem:** Word learned in Book 1 shows as "New" in Book 2

**Solutions:**
1. Verify `user_progress` table doesn't have duplicate entries for same word
2. Check `word_id` is the same for the same word across books
3. If words are different (different IDs), they're treated as separate words (this is expected if books use different word entries)

---

## Next Steps (Optional Enhancements)

### 1. Sync current book across devices

If you want the selected book to sync across devices:

1. Run the Supabase SQL from "Option 2" above
2. Update `setCurrentBookId()` in local_db.dart to also push to Supabase
3. Update `getCurrentBookId()` to pull from Supabase on first load

### 2. Add book names instead of "Book 1", "Book 2"

Currently books are identified by ID. To add names:

1. Add `name` column to `lessons` table in Supabase:
   ```sql
   ALTER TABLE public.lessons ADD COLUMN book_name TEXT;
   UPDATE public.lessons SET book_name = 'Spanish A1' WHERE book_id = 1;
   UPDATE public.lessons SET book_name = 'Spanish A2' WHERE book_id = 2;
   ```

2. Update `getAllBooks()` query to select book_name
3. Update `BookData` class to include name
4. Update book selector UI to show name instead of "Book ${book.id}"

### 3. Per-book statistics (advanced)

If you later want per-book statistics:

1. Add `book_id` column to `daily_stats` table
2. Update aggregation to track per-book stats
3. Add filter toggle in statistics page

---

## Summary

✅ **Multi-book support is now live!**
✅ **No database migration needed** (local DB already compatible)
✅ **Global word progress** (learn once, mastered everywhere)
✅ **Filtered dashboard** (show only current book's lessons)
✅ **Global statistics** (total motivation across all books)
✅ **Backward compatible** (old devices still work without updates)

Your users can now:
- Switch between books seamlessly
- See focused progress per book
- Build global learning momentum
- Never re-learn the same word twice

**Ready to test!** 🚀
