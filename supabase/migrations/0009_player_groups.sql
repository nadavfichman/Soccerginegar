-- ============================================================================
-- Migration 0009 — Player groups + per-game group visibility (2026-09-29)
-- ============================================================================
-- כל שחקן מאושר משויך לאחת משתי קבוצות: "ראשית" (primary, ברירת מחדל —
-- גישה לכל המשחקים כברירת מחדל) או "משנית" (secondary). לכל משחק שני
-- דגלים עצמאיים: visible_to_primary / visible_to_secondary — קובעים אילו
-- קבוצות בכלל *רואות* את המשחק ברשימה שלהן. שחקן שהקבוצה שלו לא מסומנת
-- לא חסום מהרשמה — הוא לא רואה את המשחק בכלל, כאילו לא נשלחה לו הזמנה.
-- ר' שיחה עם המשתמש (29.09) ו-PlayerView.visible ב-index.html.
--
-- ברירות המחדל הופכות את המיגרציה הזו ל-no-op התנהגותי: כל שחקן קיים
-- כבר 'primary', כל משחק קיים ממשיך גלוי לקבוצה הראשית בלבד — עד שהאדמין
-- בפועל משייך מישהו ל"משנית" או מסמן את התיבה השנייה במשחק חדש.
--
-- שיוך קבוצה לשחקן חדש (בהוספה ידנית או באישור בקשה) נשאר בברירת המחדל
-- 'primary' במכוון — לא נוסף שדה קבוצה לטפסי admin_add_player/
-- approve_player_request, כדי לא לפרק את מטריצת 4 כפתורי האישור הקיימת
-- (גניגרי×ותיק) ל-8. האדמין משייך ל"משנית" אחרי ההוספה, מתוך רשימת
-- השחקנים המאושרים — בדיוק כמו is_vatik/is_ganigari.
-- ============================================================================

alter table players add column if not exists player_group text not null default 'primary'
  check (player_group in ('primary','secondary'));

alter table games add column if not exists visible_to_primary boolean not null default true;
alter table games add column if not exists visible_to_secondary boolean not null default false;

drop function if exists admin_create_game(bigint, bigint, text, text, text);
create or replace function admin_create_game(
  input_kickoff bigint, input_opens_at bigint,
  input_visible_to_primary boolean, input_visible_to_secondary boolean,
  input_pw text, input_phone text, input_pin text
) returns text language plpgsql security definer as $$
declare v_role text; v_game_id text;
begin
  v_role := require_admin(input_pw, input_phone, input_pin);
  v_game_id := 'g'||floor(extract(epoch from now())*1000)::text;
  insert into games (id, kickoff, opens_at, published, roster_published, visible_to_primary, visible_to_secondary)
    values (v_game_id, input_kickoff, input_opens_at, false, false, input_visible_to_primary, input_visible_to_secondary);
  perform log_admin_action(v_role, coalesce(input_phone,'super'), 'admin_create_game', jsonb_build_object('game_id', v_game_id, 'kickoff', input_kickoff, 'opens_at', input_opens_at, 'visible_to_primary', input_visible_to_primary, 'visible_to_secondary', input_visible_to_secondary));
  return 'ok';
end; $$;

create or replace function admin_set_game_visible_primary(input_game_id text, input_value boolean, input_pw text, input_phone text, input_pin text)
returns boolean language plpgsql security definer as $$
declare v_role text;
begin
  v_role := require_admin(input_pw, input_phone, input_pin);
  update games set visible_to_primary = input_value where id = input_game_id;
  perform log_admin_action(v_role, coalesce(input_phone,'super'), 'admin_set_game_visible_primary', jsonb_build_object('game_id', input_game_id, 'value', input_value));
  return true;
end; $$;

create or replace function admin_set_game_visible_secondary(input_game_id text, input_value boolean, input_pw text, input_phone text, input_pin text)
returns boolean language plpgsql security definer as $$
declare v_role text;
begin
  v_role := require_admin(input_pw, input_phone, input_pin);
  update games set visible_to_secondary = input_value where id = input_game_id;
  perform log_admin_action(v_role, coalesce(input_phone,'super'), 'admin_set_game_visible_secondary', jsonb_build_object('game_id', input_game_id, 'value', input_value));
  return true;
end; $$;

-- שיוך קבוצה לשחקן (אדמין-על בלבד, כמו admin_set_player_ganigari/vatik)
create or replace function admin_set_player_group(input_player_id text, input_group text, input_pw text)
returns boolean language plpgsql security definer as $$
declare v_role text;
begin
  v_role := require_admin(input_pw, null, null);
  if v_role <> 'super' then raise exception 'not_authorized'; end if;
  update players set player_group = input_group where id = input_player_id;
  perform log_admin_action('super', 'super', 'admin_set_player_group', jsonb_build_object('player_id', input_player_id, 'group', input_group));
  return true;
end; $$;
