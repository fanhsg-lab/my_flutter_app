-- =========================================================
-- CHECK TOTAL WORD COUNT - Single Query
-- =========================================================

SELECT
  'Total Words' as metric,
  COUNT(*) as count
FROM public.words

UNION ALL

SELECT
  'Book 2 Words' as metric,
  COUNT(w.id) as count
FROM public.words w
JOIN public.lessons l ON w.lesson_id = l.id
WHERE l.book_id = 2

UNION ALL

SELECT
  'Book 3 Words' as metric,
  COUNT(w.id) as count
FROM public.words w
JOIN public.lessons l ON w.lesson_id = l.id
WHERE l.book_id = 3

UNION ALL

SELECT
  'Orphaned Words' as metric,
  COUNT(*) as count
FROM public.words w
LEFT JOIN public.lessons l ON w.lesson_id = l.id
WHERE l.id IS NULL

ORDER BY metric;
