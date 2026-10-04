-- ============================================================================
-- Migration 0013 — Team balancing, phase A: grade-only split (2026-10-04)
-- ============================================================================
-- שלב A מתוך תוכנית רב-שלבית לחלוקת כוחות (ר' שיחה עם המשתמש) — מחליף את
-- הצורך להעתיק-להדביק רשימות ל-TeamPicker (אפליקציה נפרדת) כדי לחלק
-- לקבוצות מאוזנות. בשלב הזה: איזון לפי דירוג מספרי בלבד, בלי כימיה/
-- היסטוריית ניצחונות (אלה דורשים ייבוא היסטוריה אמיתית — שלב נפרד,
-- ממתין לפעולה מהמשתמש).
--
-- players.grade — תבנית "ניהול שחקן" (super בלבד), כמו is_ganigari/
-- is_vatik/player_group הקיימים — לא תבנית "ניהול משחק" (admin רגיל).
-- registrations.team — תבנית "ניהול משחק" (admin רגיל), כמו
-- registration_ts/attendance הקיימים — שיבוץ הקבוצה שייך למשחק הספציפי.
-- ============================================================================

alter table players add column if not exists grade integer not null default 50
  check (grade between 1 and 99);

alter table registrations add column if not exists team smallint
  check (team in (1, 2));

create or replace function admin_set_player_grade(input_player_id text, input_grade integer, input_pw text)
returns boolean language plpgsql security definer as $$
declare v_role text;
begin
  v_role := require_admin(input_pw, null, null);
  if v_role <> 'super' then raise exception 'not_authorized'; end if;
  if input_grade < 1 or input_grade > 99 then raise exception 'grade_out_of_range'; end if;
  update players set grade = input_grade where id = input_player_id;
  perform log_admin_action('super', 'super', 'admin_set_player_grade', jsonb_build_object('player_id', input_player_id, 'grade', input_grade));
  return true;
end; $$;

-- שומר חלוקה שלמה בעסקה אחת (לא round-trip לכל שחקן) — מאפס team לכולם
-- במשחק קודם, ואז משבץ לפי שתי רשימות ה-id. מי שלא ברשימה (ספסל) נשאר null.
create or replace function admin_set_game_teams(input_game_id text, input_team1_ids text[], input_team2_ids text[], input_pw text, input_phone text, input_pin text)
returns boolean language plpgsql security definer as $$
declare v_role text;
begin
  v_role := require_admin(input_pw, input_phone, input_pin);
  update registrations set team = null where game_id = input_game_id;
  update registrations set team = 1 where game_id = input_game_id and player_id = any(input_team1_ids);
  update registrations set team = 2 where game_id = input_game_id and player_id = any(input_team2_ids);
  perform log_admin_action(v_role, coalesce(input_phone,'super'), 'admin_set_game_teams', jsonb_build_object('game_id', input_game_id, 'team1_count', coalesce(array_length(input_team1_ids,1),0), 'team2_count', coalesce(array_length(input_team2_ids,1),0)));
  return true;
end; $$;
