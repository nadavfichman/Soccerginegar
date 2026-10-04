-- ============================================================================
-- Migration 0015 — דירוג לאורח בעת הוספתו למשחק (2026-10-05)
-- ============================================================================
-- אורח (admin_add_guest_registration, migrations/0008) מקבל player_id סינתטי
-- (guest_<uuid>) בלי שורה ב-players, ולכן גם לא ב-player_grades (ה-FK
-- references players(id) חוסם את זה) — כך שבפאנל חלוקת הכוחות הוא תמיד
-- מקבל 50 ברירת מחדל, גם אם האדמין יודע שהרמה שלו שונה (ר' שיחה עם המשתמש).
--
-- התיקון: מרפים את ה-FK על player_grades.player_id — אותו עיקרון בדיוק כמו
-- registrations.player_id שכבר "text חופשי, בלי FK ל-players" בשביל אורחים
-- (ר' סעיף "אורחים" ב-CLAUDE.md). כך player_grades יכולה להכיל גם שורת
-- דירוג לאורח, בלי שום שינוי בקוד הקריאה הקיים (admin_get_player_grades,
-- grades[r.player_id] ב-AdminGameRow) — זה כבר מסתכל על player_grades לפי
-- player_id גנרי, לא רק שחקנים אמיתיים.
-- ============================================================================

alter table player_grades drop constraint if exists player_grades_player_id_fkey;

-- admin_add_guest_registration מקבל input_grade אופציונלי — אם ניתן, נשמרת
-- גם שורת דירוג לאורח (player_id הסינתטי זהה בדיוק לזה שבטבלת registrations,
-- כך שחלוקת הכוחות למשחק הזה תראה את הדירוג האמיתי במקום הנפילה ל-50).
create or replace function admin_add_guest_registration(
  input_game_id text, input_guest_name text,
  input_pw text default null, input_phone text default null, input_pin text default null,
  input_grade integer default null
) returns text language plpgsql security definer as $$
declare v_role text; v_name text; v_guest_id text;
begin
  v_role := require_admin(input_pw, input_phone, input_pin);
  v_name := trim(input_guest_name);
  if v_name = '' then raise exception 'empty_guest_name'; end if;
  if input_grade is not null and (input_grade < 1 or input_grade > 99) then raise exception 'grade_out_of_range'; end if;
  v_guest_id := 'guest_' || replace(gen_random_uuid()::text, '-', '');
  insert into registrations (game_id, player_id, guest_name, ts)
    values (input_game_id, v_guest_id, v_name, (extract(epoch from now())*1000)::bigint);
  if input_grade is not null then
    insert into player_grades (player_id, grade) values (v_guest_id, input_grade);
  end if;
  perform log_admin_action(v_role, coalesce(input_phone,'super'), 'admin_add_guest_registration', jsonb_build_object('game_id', input_game_id, 'guest_name', v_name, 'player_id', v_guest_id, 'grade', input_grade));
  return v_guest_id;
end; $$;
