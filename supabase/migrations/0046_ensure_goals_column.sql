-- ============================================================================
-- Migration 0046 — ודא שעמודת goals קיימת בפועל (לא רק בפונקציות)
-- ============================================================================
-- יומן השגיאות הראה: "get_round_summary_by_game: column rt.goals
-- does not exist". הפונקציות (summary_save/summary_get_draft/
-- get_round_summary_by_game/admin_get_round_summaries) כבר עודכנו
-- להשתמש ב-goals (migrations/0040-0041), אבל העמודה עצמה בטבלה
-- כנראה לא נוספה בפועל — ה-ALTER TABLE המקורי לא רץ בהצלחה. הכל כאן
-- idempotent (IF NOT EXISTS / DROP IF EXISTS) — בטוח להריץ גם אם חלק
-- כבר קיים.
-- ============================================================================

alter table game_round_summary_ratings alter column rating drop not null;
alter table game_round_summary_ratings add column if not exists goals integer;

alter table game_round_summary_ratings drop constraint if exists game_round_summary_ratings_rating_check;
alter table game_round_summary_ratings add constraint game_round_summary_ratings_rating_check
  check (rating is null or (rating >= 0 and rating <= 10 and rating*2 = floor(rating*2)));

alter table game_round_summary_ratings drop constraint if exists game_round_summary_ratings_goals_check;
alter table game_round_summary_ratings add constraint game_round_summary_ratings_goals_check
  check (goals is null or (goals >= -5 and goals <= 10));
