-- =========================================================
-- CHECK TOTAL WORD COUNT IN DATABASE
-- =========================================================

-- Total words across all books
SELECT COUNT(*) as total_words FROM public.words;

-- Words per book
SELECT
  l.book_id,
  COUNT(w.id) as word_count
FROM public.lessons l
LEFT JOIN public.words w ON w.lesson_id = l.id
GROUP BY l.book_id
ORDER BY l.book_id;

-- Words per lesson (shows which lessons have how many words)
SELECT
  l.id as lesson_id,
  l.title,
  l.book_id,
  COUNT(w.id) as word_count
FROM public.lessons l
LEFT JOIN public.words w ON w.lesson_id = l.id
GROUP BY l.id, l.title, l.book_id
ORDER BY l.book_id, l.id;

-- Check for any orphaned words (words without a lesson)
SELECT COUNT(*) as orphaned_words
FROM public.words w
LEFT JOIN public.lessons l ON w.lesson_id = l.id
WHERE l.id IS NULL;
