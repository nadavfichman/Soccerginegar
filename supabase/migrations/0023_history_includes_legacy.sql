-- ============================================================================
-- Migration 0023 — טאב "היסטוריה" כולל גם את 416 המשחקים שיובאו מ-TeamPicker
-- (2026-10-05)
-- ============================================================================
-- המשתמש: "כאשר לוחץ היסטוריה רוצה לראות את כל המשחקים מהמאגר שדרור יצר,
-- ובהמשך חדשים". עד עכשיו admin_get_all_game_results החזירה רק תוצאות
-- חיות (game_results, שהחלו להצטבר רק מ-migrations/0016 והלאה) — ה-416
-- משחקים ההיסטוריים ב-legacy_player_games (migrations/0019) לא הופיעו בה
-- בכלל, למרות שהם כבר משמשים ל"פורמה"/"כימיה" (admin_get_player_form/
-- admin_get_player_chemistry).
--
-- מאחדת (UNION ALL) את שני המקורות לרשימת משחקים אחת, ממוינת לפי תאריך
-- יורד. legacy_player_games מאוחסנת שורה-לכל-שחקן (לא שורה-למשחק), אז
-- מקובצת לפי source_game_id כדי לשחזר שורת-משחק (תוצאה+רשימת שחקנים
-- לכל קבוצה), בדיוק כמו שהחלוקה החיה משוחזרת מ-game_teams.
--
-- team1_player_ids/team2_player_ids מצורפים ישירות לשורה (array_agg) —
-- כך שהרחבת-שורה בצד הלקוח (הצגת הכוחות) לא צריכה round-trip נוסף דרך
-- admin_get_game_teams (שממילא לא עובד על מזהי משחק מיובאים, רק חיים).
-- ============================================================================

drop function if exists admin_get_all_game_results(text, text, text);
create or replace function admin_get_all_game_results(input_pw text, input_phone text, input_pin text)
returns table(game_id text, team1_score integer, team2_score integer, team1_count bigint, team2_count bigint, kickoff bigint, team1_player_ids text[], team2_player_ids text[])
language plpgsql security definer as $$
declare v_role text;
begin
  v_role := require_admin(input_pw, input_phone, input_pin);
  return query
    select ('live:'||gr.game_id) as game_id, gr.team1_score, gr.team2_score,
      (select count(*) from game_teams gt where gt.game_id = gr.game_id and gt.team = 1) as team1_count,
      (select count(*) from game_teams gt where gt.game_id = gr.game_id and gt.team = 2) as team2_count,
      g.kickoff,
      (select array_agg(gt.player_id) from game_teams gt where gt.game_id = gr.game_id and gt.team = 1) as team1_player_ids,
      (select array_agg(gt.player_id) from game_teams gt where gt.game_id = gr.game_id and gt.team = 2) as team2_player_ids
    from game_results gr
    join games g on g.id = gr.game_id
    union all
    select ('legacy:'||lpg.source_game_id) as game_id,
      min(lpg.own_score) filter (where lpg.team = 1) as team1_score,
      min(lpg.own_score) filter (where lpg.team = 2) as team2_score,
      count(*) filter (where lpg.team = 1) as team1_count,
      count(*) filter (where lpg.team = 2) as team2_count,
      floor(extract(epoch from min(lpg.game_date)) * 1000)::bigint as kickoff,
      array_agg(lpg.player_id) filter (where lpg.team = 1) as team1_player_ids,
      array_agg(lpg.player_id) filter (where lpg.team = 2) as team2_player_ids
    from legacy_player_games lpg
    group by lpg.source_game_id
    order by kickoff desc;
end; $$;
