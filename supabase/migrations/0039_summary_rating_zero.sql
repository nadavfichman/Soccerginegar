-- ============================================================================
-- Migration 0039 — ציון שניידר: טווח 0 עד 10 (במקום 1 עד 10)
-- ============================================================================
-- המשתמש: "מבקש שהציונים יכולים להיות בין אפס ל-10 לא יותר מזה,
-- שתהיה מגבלה שלא ניתן לא פחות ולא יותר." אכיפה בצד השרת (check
-- constraint), לא רק min/max ב-UI — אותו עיקרון בדיוק כמו אכיפת
-- החצאים (rating*2 = floor(rating*2)) מ-migration 0037.
-- ============================================================================

alter table game_round_summary_ratings drop constraint if exists game_round_summary_ratings_rating_check;
alter table game_round_summary_ratings add constraint game_round_summary_ratings_rating_check
  check (rating >= 0 and rating <= 10 and rating*2 = floor(rating*2));
