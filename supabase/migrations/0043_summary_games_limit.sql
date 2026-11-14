-- ============================================================================
-- Migration 0043 — הגדלת מגבלת המשחקים האחרונים בבורר של שניידר
-- ============================================================================
-- המשתמש דיווח שהבורר ("בחר משחק...") הציג רשימה ריקה למרות שלמשחק
-- אמיתי (אתמול) כן יש חלוקה שמורה. ייתכן ומשחקי-בדיקה/סימולציה עם
-- kickoff מאוחר יותר דחקו אותו מחוץ ל-limit 10 (אין WHERE על תאריך
-- בכלל — "10 האחרונים לפי kickoff" יכול לכלול בדיקות ישנות). הגדלה
-- ל-30 כגיבוי בטוח, בנוסף לחשיפת שגיאות ב-UI (ר' index.html) במקום
-- בליעה שקטה לרשימה ריקה.
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
    order by g.kickoff desc
    limit 30;
end; $$;
