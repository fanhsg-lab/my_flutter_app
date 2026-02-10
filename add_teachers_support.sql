-- =========================================================
-- MULTI-TEACHER SUPPORT: Database Migration
-- =========================================================

-- Step 1: Create teachers table
CREATE TABLE IF NOT EXISTS public.teachers (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Step 2: Add teacher_id to books table
ALTER TABLE public.books
ADD COLUMN IF NOT EXISTS teacher_id INTEGER REFERENCES public.teachers(id);

-- Step 3: Create sample teachers (you can modify these)
INSERT INTO public.teachers (id, name, description)
VALUES
  (1, 'Teacher A', 'Spanish Language Teacher'),
  (2, 'Teacher B', 'French Language Teacher')
ON CONFLICT (id) DO NOTHING;

-- Step 4: Assign existing books to teachers
-- Assign Book 2 and Book 3 to Teacher A (you can modify this)
UPDATE public.books
SET teacher_id = 1
WHERE id IN (2, 3);

-- Step 5: Add index for faster queries
CREATE INDEX IF NOT EXISTS idx_books_teacher_id
ON public.books(teacher_id);

-- Step 6: Enable RLS (Row Level Security) on teachers table
ALTER TABLE public.teachers ENABLE ROW LEVEL SECURITY;

-- Step 7: Policy: Everyone can view teachers (public data)
CREATE POLICY "Teachers are viewable by everyone"
ON public.teachers FOR SELECT
USING (true);

-- =========================================================
-- VERIFICATION QUERIES
-- =========================================================

-- Check teachers
SELECT * FROM public.teachers ORDER BY id;

-- Check books with their teachers
SELECT
  b.id as book_id,
  b.title,
  b.level,
  t.id as teacher_id,
  t.name as teacher_name
FROM public.books b
LEFT JOIN public.teachers t ON b.teacher_id = t.id
ORDER BY b.id;

-- Check lessons per teacher
SELECT
  t.id as teacher_id,
  t.name as teacher_name,
  COUNT(DISTINCT b.id) as book_count,
  COUNT(DISTINCT l.id) as lesson_count
FROM public.teachers t
LEFT JOIN public.books b ON b.teacher_id = t.id
LEFT JOIN public.lessons l ON l.book_id = b.id
GROUP BY t.id, t.name
ORDER BY t.id;
