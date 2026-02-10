-- =========================================================
-- MULTI-BOOK SUPPORT: USER SETTINGS TABLE (OPTIONAL)
-- Run this in Supabase SQL Editor to sync book selection across devices
-- =========================================================

-- NOTE: This is OPTIONAL! The app works perfectly without this.
-- Only run if you want book selection to sync across devices.

-- 1. Create user_settings table for storing preferences
CREATE TABLE IF NOT EXISTS public.user_settings (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  current_book_id INTEGER,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 2. Add index for faster queries
CREATE INDEX IF NOT EXISTS idx_user_settings_user_id
ON public.user_settings(user_id);

-- 3. Enable Row Level Security
ALTER TABLE public.user_settings ENABLE ROW LEVEL SECURITY;

-- 4. Policy: Users can view their own settings
CREATE POLICY "Users can view own settings"
ON public.user_settings FOR SELECT
USING (auth.uid() = user_id);

-- 5. Policy: Users can insert their own settings
CREATE POLICY "Users can insert own settings"
ON public.user_settings FOR INSERT
WITH CHECK (auth.uid() = user_id);

-- 6. Policy: Users can update their own settings
CREATE POLICY "Users can update own settings"
ON public.user_settings FOR UPDATE
USING (auth.uid() = user_id);

-- =========================================================
-- VERIFICATION QUERIES
-- =========================================================

-- Check if you have multiple books
SELECT DISTINCT book_id, COUNT(*) as lesson_count
FROM public.lessons
WHERE book_id IS NOT NULL
GROUP BY book_id
ORDER BY book_id;

-- Check if user_settings table was created successfully
SELECT * FROM information_schema.tables
WHERE table_schema = 'public'
AND table_name = 'user_settings';
