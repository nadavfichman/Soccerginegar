-- ============================================================================
-- Migration 0026 — סימון "שחקן מצטיין" (MVP) למשחק (2026-10-06)
-- ============================================================================
-- בהשוואה לאפליקציה של דרור (TeamPicker) — שם יש סימון MVP לכל משחק,
-- מוצג בהיסטוריה. כאן: עמודה חדשה על game_results (לא טבלה נפרדת —
-- "מצטיין" הוא תכונה של אותה תוצאה/משחק, לא נתון עצמאי), free-text
-- player_id בלי FK (כמו שאר העמודות מהסוג הזה באפליקציה — תומך גם
-- באורח, guest_<uuid>, בדיוק כמו registrations/game_teams).
--
-- RPC חדש ונפרד (admin_set_game_mvp) — לא פרמטר נוסף על admin_set_game_result
-- הקיים — בכוונה: קריאה ל-RPC עם פרמטר שהשרת עדיין לא מכיר (אם היינו
-- מרחיבים את admin_set_game_result) תיכשל לגמרי עד שהמיגרציה הזו רצה,
-- ואז גם שמירת תוצאה רגילה (בלי MVP) הייתה נשברת. RPC נפרד = אם המשתמש
-- עדיין לא הריץ את זה, רק בחירת MVP נכשלת (עם ההודעה הידידותית הקיימת
-- של callAdmin) — שמירת תוצאה עצמה ממשיכה לעבוד בלי שום תלות.
-- ============================================================================

alter table game_results add column if not exists mvp_player_id text;

create or replace function admin_set_game_mvp(input_game_id text, input_player_id text, input_pw text, input_phone text, input_pin text)
returns boolean language plpgsql security definer as $$
declare v_role text;
begin
  v_role := require_admin(input_pw, input_phone, input_pin);
  if not exists (select 1 from game_results where game_id = input_game_id) then raise exception 'result_not_saved'; end if;
  update game_results set mvp_player_id = input_player_id where game_id = input_game_id;
  perform log_admin_action(v_role, coalesce(input_phone,'super'), 'admin_set_game_mvp', jsonb_build_object('game_id', input_game_id, 'player_id', input_player_id));
  return true;
end; $$;

-- מחזירה גם mvp_player_id עכשיו — שינוי בסוג ההחזרה, דורש drop (אי אפשר
-- create or replace עם עמודות פלט שונות).
drop function if exists admin_get_game_result(text, text, text, text);
create or replace function admin_get_game_result(input_game_id text, input_pw text, input_phone text, input_pin text)
returns table(team1_score integer, team2_score integer, mvp_player_id text)
language plpgsql security definer as $$
declare v_role text;
begin
  v_role := require_admin(input_pw, input_phone, input_pin);
  return query select gr.team1_score, gr.team2_score, gr.mvp_player_id from game_results gr where gr.game_id = input_game_id;
end; $$;

-- אותו דבר להיסטוריה המלאה — מצטיין מוצג גם בטאב "📜 היסטוריה". למשחקים
-- מיובאים מ-TeamPicker ("legacy:") אין את הנתון הזה בסכימה שלנו
-- (legacy_player_games, migrations/0019) — null קבוע, בלי קריסה בצד הלקוח.
drop function if exists admin_get_all_game_results(text, text, text);
create or replace function admin_get_all_game_results(input_pw text, input_phone text, input_pin text)
returns table(game_id text, team1_score integer, team2_score integer, team1_count bigint, team2_count bigint, kickoff bigint, team1_player_ids text[], team2_player_ids text[], mvp_player_id text)
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
      (select array_agg(gt.player_id) from game_teams gt where gt.game_id = gr.game_id and gt.team = 2) as team2_player_ids,
      gr.mvp_player_id
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
      array_agg(lpg.player_id) filter (where lpg.team = 2) as team2_player_ids,
      null::text as mvp_player_id
    from legacy_player_games lpg
    group by lpg.source_game_id
    order by kickoff desc;
end; $$;
