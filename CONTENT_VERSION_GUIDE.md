# Content Version Guide

## How it works
The app checks `app_settings.content_version` in Supabase on every sync.
If the remote version is higher than the local version, it re-downloads all content (teachers, books, lessons, lesson_words, words).
If versions match, content pull is skipped — only progress and daily stats sync.

## When to bump the version
Run this in Supabase SQL Editor whenever you add, change, or delete lessons or words:

```sql
UPDATE app_settings SET value = value::int + 1 WHERE key = 'content_version';
```

## Examples of when to bump:
- Added new words to a lesson
- Created a new lesson or book
- Deleted or merged words (dedup)
- Changed lesson_words mappings
- Added a new teacher or book

## Current table setup
```sql
CREATE TABLE public.app_settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

INSERT INTO public.app_settings (key, value) VALUES ('content_version', '1');

ALTER TABLE public.app_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone can read app_settings"
ON public.app_settings FOR SELECT USING (true);
```
