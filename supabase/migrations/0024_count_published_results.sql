-- ============================================================================
-- Migration 0024 — משחק עם תוצאה שמורה + כוחות מפורסמים נספר ב"מתמיד"
-- גם בלי נעילת נוכחות (2026-10-05)
-- ============================================================================
-- המשתמש: "אם משחק נכנס להיסטוריה [=הוזנה לו תוצאה], יספר הכמות משחקים
-- של השחקן... גם אם משחק לא ננעל, לפי הרשימה של הכוחות שפורסמה." זה
-- פרמטר חשוב לקראת מגבלת 22 השחקנים (MAX_PLAYERS) — attendanceCounts
-- (עדיפות "מתמיד", index.html) נספר עד כה רק מ-registrations.attended על
-- משחקים עם attendance_locked=true; משחק שכבר הוזנה לו תוצאה אמיתית אבל
-- עדיין לא ננעל (או לא יינעל בכלל) לא נספר, למרות שברור שהוא קרה בפועל.
--
-- RPC ציבורי (כמו get_published_teams, migrations/0020) — בלי דרישת
-- אישורי אדמין, כי attendanceCounts מחושב ב-App.refresh() גם למסך שחקן
-- רגיל (למיון התור שלו), לא רק לאדמין. מחזיר, לכל משחק עם גם תוצאה שמורה
-- (game_results) וגם כוחות מפורסמים (games.teams_published=true), את כל
-- player_id-ים שהיו באחת משתי הקבוצות (game_teams) — דווקא לפי "פורסם",
-- לא כל חלוקה שמורה, בדיוק לפי בקשת המשתמש. game_teams/game_results
-- עצמן נשארות נעולות לגמרי — זה הנתיב הציבורי היחיד לנתון הזה.
create or replace function get_counted_results_players()
returns table(game_id text, player_id text)
language sql security definer as $$
  select gt.game_id, gt.player_id
  from games g
  join game_results gr on gr.game_id = g.id
  join game_teams gt on gt.game_id = g.id
  where g.teams_published = true;
$$;

grant execute on function get_counted_results_players() to anon, authenticated;
