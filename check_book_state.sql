-- =========================================================
-- DIAGNOSTIC: Check which book has lessons 101, 102, 103
-- =========================================================

-- Check if Book 3 exists
SELECT * FROM public.books WHERE id = 3;

-- Check where lessons 101, 102, 103 are located
SELECT id, title, chapter_number, book_id
FROM public.lessons
WHERE id IN (101, 102, 103)
ORDER BY id;

-- Check all lessons in Book 2
SELECT id, title, chapter_number, book_id
FROM public.lessons
WHERE book_id = 2
ORDER BY chapter_number;

-- Check all lessons in Book 3
SELECT id, title, chapter_number, book_id
FROM public.lessons
WHERE book_id = 3
ORDER BY chapter_number;

-- Check word counts per book
SELECT
  l.book_id,
  COUNT(DISTINCT l.id) as lesson_count,
  COUNT(w.id) as word_count
FROM public.lessons l
LEFT JOIN public.words w ON w.lesson_id = l.id
GROUP BY l.book_id
ORDER BY l.book_id;
