# SQL Guide — Adding Content to Supabase

Run these in the **Supabase SQL Editor**.
Always bump the content version at the end so the app re-syncs.

---

## 1. Add a New Teacher

```sql
INSERT INTO teachers (id, name, description)
VALUES (1, 'Maria Garcia', 'Spanish teacher at University X');
```
> Note: `id` is NOT auto-generated — pick the next available integer.

---

## 2. Add a New Book

```sql
INSERT INTO books (title, level, teacher_id, source_language)
VALUES ('Spanish Basics', 'A1', 1, 'es');
```
> `id` is auto-generated. To get the id after insert:
> ```sql
> INSERT INTO books (title, level, teacher_id, source_language)
> VALUES ('Spanish Basics', 'A1', 1, 'es')
> RETURNING id;
> ```

---

## 3. Add a New Lesson

```sql
INSERT INTO lessons (book_id, title, chapter_number)
VALUES (1, 'Greetings', 1);
```
> Use `RETURNING id;` to get the lesson id.

---

## 4. Add New Words

```sql
INSERT INTO words (lesson_id, es, en, category) VALUES
  (1, 'hola',         'hello',     'greetings'),
  (1, 'adiós',        'goodbye',   'greetings'),
  (1, 'buenos días',  'good morning', 'greetings'),
  (1, 'buenas noches','good night',   'greetings');
```
> `lesson_id` = the lesson these words originally belong to.
> Use `RETURNING id;` to get word ids for the next step.

---

## 5. Link Words to Lessons (lesson_words)

**This is required!** The app downloads words through `lesson_words`, not through `words.lesson_id`.

```sql
INSERT INTO lesson_words (lesson_id, word_id) VALUES
  (1, 101),
  (1, 102),
  (1, 103),
  (1, 104);
```

### Quick way — add words AND link them in one go:

```sql
-- Step 1: Insert words and capture their IDs
WITH new_words AS (
  INSERT INTO words (lesson_id, es, en, category) VALUES
    (1, 'hola',         'hello',     'greetings'),
    (1, 'adiós',        'goodbye',   'greetings'),
    (1, 'buenos días',  'good morning', 'greetings')
  RETURNING id
)
-- Step 2: Link them to the lesson
INSERT INTO lesson_words (lesson_id, word_id)
SELECT 1, id FROM new_words;
```
> Replace `1` (after SELECT) with the target lesson_id.

### Share a word across multiple lessons:

```sql
INSERT INTO lesson_words (lesson_id, word_id) VALUES
  (2, 101),  -- word 101 now also appears in lesson 2
  (3, 101);  -- and lesson 3
```

---

## 6. Update Book Word Count

After adding words to a book's lessons, update the count:

```sql
UPDATE books
SET total_words = (
  SELECT COUNT(DISTINCT lw.word_id)
  FROM lessons l
  JOIN lesson_words lw ON lw.lesson_id = l.id
  WHERE l.book_id = books.id
)
WHERE id = 1;  -- book id
```

Or update ALL books at once:

```sql
UPDATE books
SET total_words = sub.cnt
FROM (
  SELECT l.book_id, COUNT(DISTINCT lw.word_id) AS cnt
  FROM lessons l
  JOIN lesson_words lw ON lw.lesson_id = l.id
  GROUP BY l.book_id
) sub
WHERE books.id = sub.book_id;
```

---

## 7. BUMP THE CONTENT VERSION (always do this last!)

```sql
UPDATE app_settings SET value = (value::int + 1)::text WHERE key = 'content_version';
```

> **Do this every time you add, change, or delete any content.**
> Without this, the app won't re-sync and users won't see changes.

---

## Complete Example: Add a full lesson with words

```sql
-- 1. Create the lesson (book_id = 1, chapter 5)
INSERT INTO lessons (book_id, title, chapter_number)
VALUES (1, 'Food & Drink', 5)
RETURNING id;
-- Let's say it returns id = 10

-- 2. Add words and link them to the lesson in one step
WITH new_words AS (
  INSERT INTO words (lesson_id, es, en, category) VALUES
    (10, 'agua',    'water',  'food'),
    (10, 'pan',     'bread',  'food'),
    (10, 'leche',   'milk',   'food'),
    (10, 'manzana', 'apple',  'food'),
    (10, 'arroz',   'rice',   'food')
  RETURNING id
)
INSERT INTO lesson_words (lesson_id, word_id)
SELECT 10, id FROM new_words;

-- 3. Update the book's word count
UPDATE books
SET total_words = (
  SELECT COUNT(DISTINCT lw.word_id)
  FROM lessons l
  JOIN lesson_words lw ON lw.lesson_id = l.id
  WHERE l.book_id = 1
)
WHERE id = 1;

-- 4. Bump version so the app syncs
UPDATE app_settings SET value = (value::int + 1)::text WHERE key = 'content_version';
```

---

## Deleting Content

### Delete a word
```sql
-- Remove from lesson_words first (FK constraint)
DELETE FROM lesson_words WHERE word_id = 101;
-- Remove any user progress (FK constraint)
DELETE FROM user_word_progress WHERE word_id = 101;
DELETE FROM attempts WHERE word_id = 101;
-- Then delete the word
DELETE FROM words WHERE id = 101;
```

### Delete a lesson
```sql
-- Remove all lesson_words links
DELETE FROM lesson_words WHERE lesson_id = 10;
-- Remove words that only belonged to this lesson
DELETE FROM words WHERE lesson_id = 10
  AND id NOT IN (SELECT word_id FROM lesson_words);
-- Delete the lesson
DELETE FROM lessons WHERE id = 10;
```

### After any deletion, always:
```sql
UPDATE app_settings SET value = (value::int + 1)::text WHERE key = 'content_version';
```

---

## Quick Reference

| Action | Tables touched | Bump version? |
|--------|---------------|---------------|
| Add teacher | `teachers` | YES |
| Add book | `books` | YES |
| Add lesson | `lessons` | YES |
| Add words | `words` + `lesson_words` | YES |
| Share word to another lesson | `lesson_words` | YES |
| Delete word | `lesson_words` → `user_word_progress` → `attempts` → `words` | YES |
| Delete lesson | `lesson_words` → `words` → `lessons` | YES |
| Update book word count | `books` | YES |
| Check current version | `SELECT * FROM app_settings;` | — |
