-- ============================================================================
-- Migration 0025 — הזנת תוצאה (בלבד) מספיקה לספירת "מתמיד", בלי תלות
-- בפרסום הכוחות לשחקנים (2026-10-06)
-- ============================================================================
-- המשתמש דיווח: "הזנתי תוצאה של משחק היום... צריך שזה יספור בכמות
-- משחקים אצל כל שחקן" — אבל זה לא נספר. הסיבה: migrations/0024 תנה את
-- הספירה גם בתוצאה שמורה *וגם* ב-games.teams_published=true (פרסום
-- הכוחות לשחקנים באפליקציה) — פעולה נפרדת לגמרי מהזנת התוצאה
-- (admin_set_game_result), שקל לשכוח ללחוץ עליה בכלל אם לא רוצים
-- שהשחקנים יראו את החלוקה (שיקול תצוגה, לא קשור לספירה הפנימית).
--
-- מוסר את התנאי על teams_published — game_results+game_teams (שהמשחק
-- קרה בפועל, עם חלוקה שנשמרה) מספיקים כסימן אמין, בלי תלות בפעולת UI
-- נפרדת שלא תמיד נעשית. RPC עצמו ציבורי כמו קודם (attendanceCounts
-- מחושב גם למסך שחקן); לא חושף שום דבר חוץ מ-player_id/game_id גולמיים.
create or replace function get_counted_results_players()
returns table(game_id text, player_id text)
language sql security definer as $$
  select gt.game_id, gt.player_id
  from game_results gr
  join game_teams gt on gt.game_id = gr.game_id;
$$;
