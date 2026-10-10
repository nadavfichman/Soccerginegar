-- ============================================================================
-- Migration 0031 — מקור אמת יחיד לספירת משחקי שחקן (2026-10-10)
-- ============================================================================
-- המשתמש (אחרי שעדכון 19, טור השוואה ויזואלי, נדחה במפורש): "יש רק
-- כמות הגעה אחת נכונה... לא יכול להיות שכל נתון יישאב ממקור אחר...
-- רוצה בדיקה פנימית מנגנון שמוודא שתמיד הנתונים יוצאים מאותו מקור."
--
-- עד כה היו שלושה מימושים עצמאיים של "אילו משחקים נספרים לשחקן":
-- attendanceCounts (JS בצד לקוח, index.html), admin_get_player_stats
-- ו-admin_get_all_player_stats (שני "unified" CTE-ים זהים-בכוונה אבל
-- מקודדים בנפרד, migrations/0022+0028/0029+0030). שלוש הגדרות נפרדות
-- של אותו דבר בדיוק = בדיוק המתכון לסטייה — וזה כבר קרה: attendanceCounts
-- (דרך get_counted_results_players) חסרה את מקור "נוכחות-נעולה-בלי-
-- תוצאה" ש-admin_get_*_player_stats כן כוללות. זה הגורם האמיתי לפער.
--
-- פתרון: get_counted_results_players הופכת לעצמה למקור הקנוני (לא
-- מוחלפת בשם חדש!) — מורחבת לכלול גם outcome וגם את מקור "נוכחות-
-- נעולה-בלי-תוצאה". **בכוונה לא rename** ל-get_player_game_log כמו
-- בניסיון הראשון: זו פונקציה ציבורית שנקראת בלי תנאי בכל טעינת עמוד
-- (api.loadAll, index.html) — rename היה שובר אותה בפועל בכל טעינה
-- מהרגע שהקוד עולה ועד שה-SQL הזה רץ (ה-e2e CI תפס את זה: 404 על RPC
-- לשם-שעוד-לא-קיים נרשם כשגיאת קונסולה ע"י Chromium, גם בלי קריסה
-- אמיתית ב-JS). שמירת השם הקיים = אין בכלל חלון-זמן שבור, גם לא רגע
-- אחד, כי הפונקציה הישנה ממשיכה לשרת (בהיקף הישן) עד שה-SQL רץ.
-- admin_get_player_stats/admin_get_all_player_stats מתכווצות ל-SELECT
-- פשוט מ-get_counted_results_players(), בלי לשכפל אף לוגיקה.
-- ============================================================================

drop function if exists get_counted_results_players();

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
  from legacy_player_games lpg
  union all
  select r.game_id, r.player_id, null::text as outcome
  from registrations r
  join games g on g.id = r.game_id
  where r.attended = true
    and g.attendance_locked = true
    and not exists (
      select 1 from game_teams gt2
      join game_results gr2 on gr2.game_id = gt2.game_id
      where gt2.game_id = r.game_id and gt2.player_id = r.player_id
    );
$$;

grant execute on function get_counted_results_players() to anon, authenticated;

create or replace function admin_get_player_stats(input_player_id text, input_pw text, input_phone text, input_pin text)
returns table(games_count integer, wins integer, losses integer, draws integer)
language plpgsql security definer as $$
declare v_role text;
begin
  v_role := require_admin(input_pw, input_phone, input_pin);
  return query
    select count(*)::integer as games_count,
      coalesce(sum((gc.outcome = 'win')::integer), 0)::integer as wins,
      coalesce(sum((gc.outcome = 'loss')::integer), 0)::integer as losses,
      coalesce(sum((gc.outcome = 'draw')::integer), 0)::integer as draws
    from get_counted_results_players() gc
    where gc.player_id = input_player_id;
end; $$;

create or replace function admin_get_all_player_stats(input_pw text, input_phone text, input_pin text)
returns table(player_id text, games_count integer, wins integer, losses integer, draws integer)
language plpgsql security definer as $$
declare v_role text;
begin
  v_role := require_admin(input_pw, input_phone, input_pin);
  return query
    select gc.player_id,
      count(*)::integer as games_count,
      coalesce(sum((gc.outcome = 'win')::integer), 0)::integer as wins,
      coalesce(sum((gc.outcome = 'loss')::integer), 0)::integer as losses,
      coalesce(sum((gc.outcome = 'draw')::integer), 0)::integer as draws
    from get_counted_results_players() gc
    group by gc.player_id;
end; $$;
