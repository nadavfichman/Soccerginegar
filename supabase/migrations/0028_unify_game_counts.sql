-- ============================================================================
-- Migration 0028 — איחוד שני מנגנוני ספירת "כמה משחקים שיחק שחקן"
-- (2026-10-10)
-- ============================================================================
-- המשתמש שם לב שתג "X הגעות" ברשימת השחקנים (attendanceCounts, index.html)
-- ו"X משחקים" במסך מידע שחקן (PlayerStatsScreen) מציגים מספרים שונים לאותו
-- שחקן. הסיבה: כל אחד מהם מסתכל על תת-קבוצה אחרת של המקורות —
-- get_counted_results_players (migrations/0025) סופר רק משחקים חיים
-- (game_teams+game_results), בלי היסטוריה מיובאת מ-TeamPicker
-- (legacy_player_games); admin_get_player_stats (migrations/0022) סופר
-- game_teams+game_results+legacy_player_games, אבל בלי משחקים עם נוכחות
-- נעולה (registrations.attended) שלא עברו דרך חלוקת-כוחות/תוצאה בכלל.
-- המשתמש: "מבחינתי שיהיו זהים במידע שלהם" — שני ה-RPCs עוברים עכשיו
-- לאותם שלושה מקורות בדיוק, עם אותו היגיון דה-דופליקציה (חלוקה+תוצאה
-- גוברת על נוכחות-נעולה-בלבד לאותו משחק, כדי לא לספור פעמיים).
-- ============================================================================

-- 1. get_counted_results_players — מקבל UNION נוסף עם legacy_player_games.
-- game_id מקודד 'legacy:'||source_game_id (אותה קונבנציה כבר בשימוש
-- ב-admin_get_all_game_results/GameResultsHistory) כדי שלא יתנגש עם מזהי
-- משחק חיים אמיתיים בתוך ה-Set של דה-דופליקציה בצד הלקוח
-- (countedGamePlayer, index.html). index.html לא משתנה בכלל — attendanceCounts
-- כבר עושה resultPlayers.forEach(r => countAttendance(r.game_id, r.player_id))
-- בלי תלות בפורמט ה-game_id.
create or replace function get_counted_results_players()
returns table(game_id text, player_id text)
language sql security definer as $$
  select gt.game_id, gt.player_id
  from game_results gr
  join game_teams gt on gt.game_id = gr.game_id
  union
  select 'legacy:'||lpg.source_game_id, lpg.player_id
  from legacy_player_games lpg;
$$;

-- 2. admin_get_player_stats — מקבל מקור שלישי: משחקים עם נוכחות נעולה
-- שהשחקן לא מופיע בהם ב-game_teams+game_results (כדי לא לספור פעמיים
-- משחק שכבר נספר כ"חי"). למשחק כזה אין תוצאה ידועה — נכנס ל-games_count
-- בלי להשפיע על wins/losses/draws (outcome=null; PlayerStatsScreen כבר
-- מחשב winRate רק מתוך wins+losses, לא דורש games_count===wins+losses+draws).
create or replace function admin_get_player_stats(input_player_id text, input_pw text, input_phone text, input_pin text)
returns table(games_count integer, wins integer, losses integer, draws integer)
language plpgsql security definer as $$
declare v_role text;
begin
  v_role := require_admin(input_pw, input_phone, input_pin);
  return query
    with unified as (
      select
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
      where gt.player_id = input_player_id
      union all
      select lpg.outcome
      from legacy_player_games lpg
      where lpg.player_id = input_player_id
      union all
      select null::text as outcome
      from registrations r
      join games g on g.id = r.game_id
      where r.player_id = input_player_id
        and r.attended = true
        and g.attendance_locked = true
        and not exists (
          select 1 from game_teams gt2
          join game_results gr2 on gr2.game_id = gt2.game_id
          where gt2.game_id = r.game_id and gt2.player_id = r.player_id
        )
    )
  select count(*)::integer as games_count,
    coalesce(sum((outcome = 'win')::integer), 0)::integer as wins,
    coalesce(sum((outcome = 'loss')::integer), 0)::integer as losses,
    coalesce(sum((outcome = 'draw')::integer), 0)::integer as draws
  from unified;
end; $$;
