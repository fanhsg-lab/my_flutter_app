-- =========================================================
-- CREATE BOOK 2 FOR TESTING MULTI-BOOK FEATURE
-- This adds a second book with 3 lessons and ~15 words
-- =========================================================

-- =========================================================
-- BOOK 2: LESSONS
-- =========================================================

-- Lesson 1: Colors (Book 2)
INSERT INTO public.lessons (id, title, chapter_number, book_id)
VALUES (101, 'Los Colores', 1, 2)
ON CONFLICT (id) DO NOTHING;

-- Lesson 2: Numbers 11-20 (Book 2)
INSERT INTO public.lessons (id, title, chapter_number, book_id)
VALUES (102, 'Números 11-20', 2, 2)
ON CONFLICT (id) DO NOTHING;

-- Lesson 3: Family Members (Book 2)
INSERT INTO public.lessons (id, title, chapter_number, book_id)
VALUES (103, 'La Familia', 3, 2)
ON CONFLICT (id) DO NOTHING;

-- =========================================================
-- BOOK 2: WORDS
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

-- Lesson 103: Family (5 words - some overlap with Book 1 to test global progress)
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

-- Check that Book 2 was created
SELECT
  l.book_id,
  l.title as lesson_title,
  l.chapter_number,
  COUNT(w.id) as word_count
FROM public.lessons l
LEFT JOIN public.words w ON w.lesson_id = l.id
WHERE l.book_id = 2
GROUP BY l.book_id, l.title, l.chapter_number
ORDER BY l.chapter_number;

-- Check all books
SELECT DISTINCT book_id, COUNT(*) as lesson_count
FROM public.lessons
WHERE book_id IS NOT NULL
GROUP BY book_id
ORDER BY book_id;
