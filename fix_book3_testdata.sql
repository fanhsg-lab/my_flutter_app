-- =========================================================
-- FIX: Move test lessons from Book 2 to Book 3
-- This deletes the accidentally added lessons and recreates them in Book 3
-- =========================================================

-- =========================================================
-- STEP 1: DELETE THE ACCIDENTALLY ADDED DATA (CORRECT ORDER!)
-- =========================================================

-- 1. Delete from attempts table FIRST (if it exists)
DELETE FROM public.attempts
WHERE word_id BETWEEN 1001 AND 1015;

-- 2. Delete from attempt_logs SECOND (if it exists)
DELETE FROM public.attempt_logs
WHERE word_id BETWEEN 1001 AND 1015;

-- 3. Delete user progress THIRD
DELETE FROM public.user_word_progress
WHERE word_id BETWEEN 1001 AND 1015;

-- 4. Delete words FOURTH
DELETE FROM public.words
WHERE id BETWEEN 1001 AND 1015;

-- 5. Delete lessons FIFTH
DELETE FROM public.lessons
WHERE id IN (101, 102, 103);

-- =========================================================
-- STEP 2: CREATE BOOK 3 (if not exists)
-- =========================================================

-- Create Book 3 entry in books table
INSERT INTO public.books (id, title, level)
VALUES (3, 'Test Book - Spanish A1', 'A1')
ON CONFLICT (id) DO NOTHING;

-- =========================================================
-- STEP 3: ADD BOOK 3 LESSONS
-- =========================================================

-- Lesson 1: Colors (Book 3)
INSERT INTO public.lessons (id, title, chapter_number, book_id)
VALUES (101, 'Los Colores', 1, 3)
ON CONFLICT (id) DO NOTHING;

-- Lesson 2: Numbers 11-20 (Book 3)
INSERT INTO public.lessons (id, title, chapter_number, book_id)
VALUES (102, 'Números 11-20', 2, 3)
ON CONFLICT (id) DO NOTHING;

-- Lesson 3: Family Members (Book 3)
INSERT INTO public.lessons (id, title, chapter_number, book_id)
VALUES (103, 'La Familia', 3, 3)
ON CONFLICT (id) DO NOTHING;

-- =========================================================
-- STEP 4: ADD BOOK 3 WORDS
-- =========================================================

-- Lesson 101: Colors (5 words)
INSERT INTO public.words (id, lesson_id, es, en)
VALUES
  (1001, 101, 'rojo', 'red'),
  (1002, 101, 'azul', 'blue'),
  (1003, 101, 'verde', 'green'),
  (1004, 101, 'amarillo', 'yellow'),
  (1005, 101, 'negro', 'black')
ON CONFLICT (id) DO NOTHING;

-- Lesson 102: Numbers 11-20 (5 words)
INSERT INTO public.words (id, lesson_id, es, en)
VALUES
  (1006, 102, 'once', 'eleven'),
  (1007, 102, 'doce', 'twelve'),
  (1008, 102, 'trece', 'thirteen'),
  (1009, 102, 'catorce', 'fourteen'),
  (1010, 102, 'quince', 'fifteen')
ON CONFLICT (id) DO NOTHING;

-- Lesson 103: Family (5 words)
INSERT INTO public.words (id, lesson_id, es, en)
VALUES
  (1011, 103, 'madre', 'mother'),
  (1012, 103, 'padre', 'father'),
  (1013, 103, 'hermano', 'brother'),
  (1014, 103, 'hermana', 'sister'),
  (1015, 103, 'abuelo', 'grandfather')
ON CONFLICT (id) DO NOTHING;

-- =========================================================
-- VERIFICATION
-- =========================================================

-- Check all books
SELECT * FROM public.books ORDER BY id;

-- Check that Book 3 was created with lessons
SELECT
  l.book_id,
  l.title as lesson_title,
  l.chapter_number,
  COUNT(w.id) as word_count
FROM public.lessons l
LEFT JOIN public.words w ON w.lesson_id = l.id
WHERE l.book_id = 3
GROUP BY l.book_id, l.title, l.chapter_number
ORDER BY l.chapter_number;

-- Check all books with lesson counts
SELECT DISTINCT book_id, COUNT(*) as lesson_count
FROM public.lessons
WHERE book_id IS NOT NULL
GROUP BY book_id
ORDER BY book_id;

-- Verify Book 2 doesn't have the test lessons anymore
SELECT
  l.book_id,
  l.title as lesson_title,
  l.chapter_number
FROM public.lessons l
WHERE l.book_id = 2
ORDER BY l.chapter_number;
