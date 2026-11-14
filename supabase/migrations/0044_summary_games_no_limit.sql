-- ============================================================================
-- Migration 0044 — בורר המשחקים לסיכום שניידר: בלי הגבלת כמות בכלל
-- ============================================================================
-- המשתמש: "המשחק האמיתי תמיד צריך להופיע גם אם יש 100 משחקים..." —
-- בצדק: limit קשיח הוא שביר ועלול להסתיר משחק אמיתי בלי שום אזהרה.
-- מסירים את ה-limit לגמרי — הטבלה הזו (משחקים עם חלוקה שמורה) לא
-- צפויה להיות גדולה בקבוצה חובבנית, אין שום סיבה לחתוך אותה.
-- ============================================================================

create or replace function summary_get_recent_games(input_summary_pw text, input_pw text default null, input_phone text default null, input_pin text default null)
returns table(game_id text, kickoff bigint, team1_score integer, team2_score integer, published boolean)
language plpgsql security definer as $$
begin
  perform require_summary_access(input_summary_pw, input_pw, input_phone, input_pin);
  return query
    select distinct g.id, g.kickoff, grs.team1_score, grs.team2_score, coalesce(grs.published, false)
    from games g
    join game_teams gt on gt.game_id = g.id
    left join game_round_summary grs on grs.game_id = g.id
    order by g.kickoff desc;
end; $$;
