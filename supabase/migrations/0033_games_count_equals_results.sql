-- ============================================================================
-- Migration 0033 — "משחקים" חייב תמיד לשוות נצחונות+הפסדים+תיקו
-- (2026-10-10)
-- ============================================================================
-- המשתמש: "כמות המשחקים של כל שחקן חייבת להוציא תמיד לכמות ניצחונות
-- פלוס הפסדים פלוס תיקו. אחרת כל המידע שלנו מעוות."
--
-- migrations/0028 הוסיפה מקור שלישי ל-get_counted_results_players:
-- משחקים עם נוכחות נעולה שאף פעם לא הוזנה להם תוצאה — נספרו ב-
-- games_count בלי תוצאה ידועה (outcome=null), כדי להתיישר עם ההגדרה
-- הישנה של "מתמיד" (עדיפות הרשמה, לא קשורה לתוצאות משחק בכלל). זו
-- הייתה הסיבה לקטגוריית "ללא תוצאה" שנוספה בקומיט הקודם — אבל המשתמש
-- קבע עכשיו במפורש: הגדרת "משחקים" חייבת להיות "משחקים עם תוצאה
-- ידועה", נקודה. מסירים את המקור השלישי לגמרי.
--
-- אין שינוי בחתימה (עדיין game_id/player_id/outcome) — רק create or
-- replace, בלי drop. admin_get_player_stats/admin_get_all_player_stats/
-- get_player_attendance_counts לא צריכות שינוי כלל — הן רק מצרפות את
-- תוצאת הפונקציה הזו, שעכשיו פשוט לא מכילה יותר שורות עם outcome=null.
--
-- השפעת-לוואי מודעת (לא מוסתרת): "מתמיד" (עדיפות הרשמה, sortRegs/
-- tierRank ב-logic.js) נשען על אותו attendanceCounts — מעכשיו שחקן
-- שהשתתף במשחק שננעלה לו נוכחות אבל אף פעם לא הוזנה תוצאה, לא יקבל
-- עליו קרדיט בשובר-השוויון בתוך השכבה שלו (גניגרי/ותיק/רגיל). לא
-- משפיע על עצם השיוך לשכבה — רק על הסדר הפנימי בתוכה.
-- ============================================================================

create or replace function get_counted_results_players()
returns table(game_id text, player_id text, outcome text)
language sql security definer as $$
  select gt.game_id, gt.player_id,
    case
      when gt.team = 1 and gr.team1_score > gr.team2_score then 'win'
      when gt.team = 1 and gr.team1_score < gr.team2_score then 'loss'
      when gt.team = 1 then 'draw'
      when gt.team = 2 and gr.team2_score > gr.team1_score then 'win'
      when gt.team = 2 and gr.team2_score < gr.team1_score then 'loss'
      else 'draw'
    end as outcome
  from game_teams gt
  join game_results gr on gr.game_id = gt.game_id
  union all
  select 'legacy:'||lpg.source_game_id, lpg.player_id, lpg.outcome
  from legacy_player_games lpg;
$$;
