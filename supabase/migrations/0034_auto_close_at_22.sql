-- ============================================================================
-- Migration 0034 — נעילת הרשמה אוטומטית בהגעה ל-22 (2026-10-12)
-- ============================================================================
-- המשתמש: "האם אפשרי לעשות שכאשר הרשימה מגיעה ל-22 מקומות היא תנעל
-- אוטומטית. כמובן שלי כאדמין יש אפשרות לפתוח. כי אני חושש מזה שהרשימה
-- פתאום תגיע ל-25 ואני בכלל לא עצרתי אותה."
--
-- registration_closed (עמודת boolean על games) כבר קיימת ופעילה — דגל
-- סגור/פתוח ידני, עם UI מלא קיים ב-AdminGameRow ואכיפה מלאה בצד השרת
-- (register_for_game כבר בודק אותו). כל מנגנון הפתיחה/סגירה הידנית
-- כבר קיים ועובד. מה שחסר: שום דבר לא סוגר אותו אוטומטית לפי כמות.
--
-- 22 = MAX_PLAYERS (index.html) — קבוע תצוגה בלבד עד כה, לא נאכף
-- בשרת. מקודד קשיח כאן (לא שיתוף קבוע בין JS/SQL) — אם 22 ישתנה
-- ב-index.html, לזכור לעדכן גם כאן.
--
-- לא משחזרים את לוגיקת-העדיפות (tierRank/sortRegs, logic.js) ב-SQL —
-- זו בדיוק מחלקת-הבאג שתוקנה הרגע בספירת המשחקים (מימושים נפרדים של
-- אותו דבר שסוטים זה מזה). במקום זה: ברגע שסך ההרשמות הפעילות מגיע
-- ל-22, נועלים לגמרי (כמו נעילה ידנית היום) — שקול ל"main מלא" בכל
-- מצב רגיל. חד-כיווני בכוונה: רק סוגר, אף פעם לא פותח אוטומטית.
--
-- שלושה נתיבים נפרדים מוסיפים שורה ל-registrations
-- (register_for_game, admin_add_registration, admin_add_guest_registration)
-- — פונקציית עזר פנימית אחת מונעת שכפול הבדיקה שלוש פעמים.
-- ============================================================================

create or replace function close_registration_if_full(input_game_id text)
returns void language plpgsql security definer as $$
declare v_count integer;
begin
  select count(*) into v_count from registrations where game_id = input_game_id;
  if v_count >= 22 then
    update games set registration_closed = true where id = input_game_id;
  end if;
end; $$;

revoke all on function close_registration_if_full(text) from public;

create or replace function register_for_game(input_game_id text, input_player_id text)
returns text language plpgsql security definer as $$
declare v_uid uuid; already_registered boolean;
begin
  v_uid := auth.uid();
  if v_uid is null or not exists (select 1 from players where id=input_player_id and auth_user_id=v_uid) then
    return 'not_authorized';
  end if;
  if exists (select 1 from games where id = input_game_id and registration_closed) then
    return 'registration_closed';
  end if;
  select exists(select 1 from registrations where game_id=input_game_id and player_id=input_player_id) into already_registered;
  if already_registered then return 'already_registered'; end if;
  delete from game_declines where game_id=input_game_id and player_id=input_player_id;
  insert into registrations (game_id, player_id, ts) values (input_game_id, input_player_id, (extract(epoch from now())*1000)::bigint);
  perform close_registration_if_full(input_game_id);
  return 'ok';
end; $$;

drop function if exists admin_add_registration(text, text);
create or replace function admin_add_registration(
  input_game_id text, input_player_id text, input_pw text default null, input_phone text default null, input_pin text default null
) returns boolean language plpgsql security definer as $$
declare v_role text;
begin
  v_role := require_admin(input_pw, input_phone, input_pin);
  insert into registrations (game_id, player_id, ts) values (input_game_id, input_player_id, (extract(epoch from now())*1000)::bigint);
  perform close_registration_if_full(input_game_id);
  perform log_admin_action(v_role, coalesce(input_phone,'super'), 'admin_add_registration', jsonb_build_object('game_id', input_game_id, 'player_id', input_player_id));
  return true;
end; $$;

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
  perform close_registration_if_full(input_game_id);
  if input_grade is not null then
    insert into player_grades (player_id, grade) values (v_guest_id, input_grade);
  end if;
  perform log_admin_action(v_role, coalesce(input_phone,'super'), 'admin_add_guest_registration', jsonb_build_object('game_id', input_game_id, 'guest_name', v_name, 'player_id', v_guest_id, 'grade', input_grade));
  return v_guest_id;
end; $$;
