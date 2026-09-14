-- ============================================================================
-- כדורגל גניגרי ושות' — פונקציות מסד הנתונים (Supabase / Postgres)
-- ============================================================================
-- קובץ זה מתעד את כל פונקציות ה-RPC שנכתבו/עודכנו עבור הפרויקט, כדי שיהיה
-- תיעוד גרסה מסודר בגיטהאב ולא רק ב-Supabase Dashboard.
--
-- כל הפונקציות הן SECURITY DEFINER (רצות בהרשאת בעל הפונקציה, עוקפות RLS
-- בכוונה — זו הדרך היחידה לכתוב לטבלאות אחרי שה-RLS ננעל ל-SELECT בלבד,
-- ר' policies.sql).
--
-- הערה חשובה: זהו "צילום מצב סופי" של הפונקציות — לא היסטוריית migrations
-- כרונולוגית. אפשר להריץ את כל הקובץ מחדש בבטחה (כל הפונקציות משתמשות ב-
-- create or replace).
-- ============================================================================


-- ============================================================================
-- חלק א: פונקציות שנכתבו/שונו במהלך הפרויקט הזה
-- ============================================================================

-- עזר משותף: מוודא הרשאת מנהל/אדמין-על על ידי שימוש חוזר ב-check_login
-- הקיים (ר' חלק ב). זורק חריגה אם ההתחברות לא תקפה.
create or replace function require_admin(input_pw text, input_phone text, input_pin text)
returns text language plpgsql security definer as $$
declare v_role text;
begin
  v_role := check_login(input_pw, input_phone, input_pin);
  if v_role is null then raise exception 'not_authorized'; end if;
  if v_role = 'locked' then raise exception 'locked'; end if;
  return v_role; -- 'super' | 'admin'
end; $$;

-- עזר משותף: רושם פעולת ניהול ל-admin_audit_log (ר' schema_additions.sql).
-- לא נחשף ל-anon/authenticated ישירות (revoke למטה) — נקרא רק מתוך פונקציות
-- SECURITY DEFINER אחרות, אחרי שהרשאת הקורא כבר אומתה על ידן. לעולם לא
-- מקבל סיסמה/PIN בתוך p_details — רק פרטי הפעולה עצמה.
create or replace function log_admin_action(p_role text, p_actor text, p_action text, p_details jsonb)
returns void language plpgsql security definer as $$
begin
  insert into admin_audit_log (actor_role, actor_identifier, action, details)
    values (p_role, p_actor, p_action, p_details);
end; $$;
revoke all on function log_admin_action(text,text,text,jsonb) from public;

-- אישור/דחייה/שקילה מחדש של בקשות הצטרפות (אדמין-על בלבד)
create or replace function approve_player_request(
  input_request_id text, input_is_ganigari boolean, input_is_vatik boolean, input_pw text
) returns text language plpgsql security definer as $$
declare v_role text; r record;
begin
  v_role := require_admin(input_pw, null, null);
  if v_role <> 'super' then raise exception 'not_authorized'; end if;
  select * into r from player_requests where id = input_request_id;
  if r is null then return 'not_found'; end if;
  if exists (select 1 from players where phone = r.phone) then return 'phone_taken'; end if;
  insert into players (id, name, phone, is_ganigari, is_vatik, email, auth_user_id)
    values ('p'||floor(extract(epoch from now())*1000)::text, r.name, r.phone, input_is_ganigari, input_is_vatik, r.email, r.auth_user_id);
  delete from player_requests where id = input_request_id;
  perform log_admin_action('super', 'super', 'approve_player_request', jsonb_build_object('request_id', input_request_id, 'name', r.name, 'phone', r.phone, 'is_ganigari', input_is_ganigari, 'is_vatik', input_is_vatik));
  return 'ok';
end; $$;

create or replace function reject_player_request(input_request_id text, input_pw text)
returns boolean language plpgsql security definer as $$
declare v_role text;
begin
  v_role := require_admin(input_pw, null, null);
  if v_role <> 'super' then raise exception 'not_authorized'; end if;
  update player_requests set status='rejected', decided_at = now() where id = input_request_id;
  perform log_admin_action('super', 'super', 'reject_player_request', jsonb_build_object('request_id', input_request_id));
  return true;
end; $$;

create or replace function reconsider_player_request(input_request_id text, input_pw text)
returns boolean language plpgsql security definer as $$
declare v_role text;
begin
  v_role := require_admin(input_pw, null, null);
  if v_role <> 'super' then raise exception 'not_authorized'; end if;
  update player_requests set status='pending', decided_at = null where id = input_request_id;
  perform log_admin_action('super', 'super', 'reconsider_player_request', jsonb_build_object('request_id', input_request_id));
  return true;
end; $$;

-- הסרת מנהל (אדמין-על בלבד)
create or replace function remove_admin(input_admin_id text, input_pw text)
returns boolean language plpgsql security definer as $$
declare v_role text;
begin
  v_role := require_admin(input_pw, null, null);
  if v_role <> 'super' then raise exception 'not_authorized'; end if;
  delete from admins where id = input_admin_id;
  perform log_admin_action('super', 'super', 'remove_admin', jsonb_build_object('admin_id', input_admin_id));
  return true;
end; $$;

-- ניהול שחקנים ידני ברשימה המאושרת (אדמין-על בלבד)
create or replace function admin_add_player(input_name text, input_phone text, input_is_ganigari boolean, input_is_vatik boolean, input_pw text)
returns text language plpgsql security definer as $$
declare v_role text;
begin
  v_role := require_admin(input_pw, null, null);
  if v_role <> 'super' then raise exception 'not_authorized'; end if;
  if exists (select 1 from players where phone = input_phone) then return 'phone_taken'; end if;
  insert into players (id, name, phone, is_ganigari, is_vatik)
    values ('p'||floor(extract(epoch from now())*1000)::text, input_name, input_phone, input_is_ganigari, input_is_vatik);
  perform log_admin_action('super', 'super', 'admin_add_player', jsonb_build_object('name', input_name, 'phone', input_phone, 'is_ganigari', input_is_ganigari, 'is_vatik', input_is_vatik));
  return 'ok';
end; $$;

create or replace function admin_delete_player(input_player_id text, input_pw text)
returns boolean language plpgsql security definer as $$
declare v_role text; v_name text;
begin
  v_role := require_admin(input_pw, null, null);
  if v_role <> 'super' then raise exception 'not_authorized'; end if;
  select name into v_name from players where id = input_player_id;
  delete from registrations where player_id = input_player_id;
  delete from players where id = input_player_id;
  perform log_admin_action('super', 'super', 'admin_delete_player', jsonb_build_object('player_id', input_player_id, 'name', v_name));
  return true;
end; $$;

create or replace function admin_set_player_ganigari(input_player_id text, input_value boolean, input_pw text)
returns boolean language plpgsql security definer as $$
declare v_role text;
begin
  v_role := require_admin(input_pw, null, null);
  if v_role <> 'super' then raise exception 'not_authorized'; end if;
  update players set is_ganigari = input_value where id = input_player_id;
  perform log_admin_action('super', 'super', 'admin_set_player_ganigari', jsonb_build_object('player_id', input_player_id, 'value', input_value));
  return true;
end; $$;

create or replace function admin_set_player_vatik(input_player_id text, input_value boolean, input_pw text)
returns boolean language plpgsql security definer as $$
declare v_role text;
begin
  v_role := require_admin(input_pw, null, null);
  if v_role <> 'super' then raise exception 'not_authorized'; end if;
  update players set is_vatik = input_value where id = input_player_id;
  perform log_admin_action('super', 'super', 'admin_set_player_vatik', jsonb_build_object('player_id', input_player_id, 'value', input_value));
  return true;
end; $$;

create or replace function admin_update_player_name(input_player_id text, input_name text, input_pw text)
returns boolean language plpgsql security definer as $$
declare v_role text;
begin
  v_role := require_admin(input_pw, null, null);
  if v_role <> 'super' then raise exception 'not_authorized'; end if;
  update players set name = input_name where id = input_player_id;
  perform log_admin_action('super', 'super', 'admin_update_player_name', jsonb_build_object('player_id', input_player_id, 'new_name', input_name));
  return true;
end; $$;

create or replace function admin_update_player_phone(input_player_id text, input_phone text, input_pw text)
returns text language plpgsql security definer as $$
declare v_role text;
begin
  v_role := require_admin(input_pw, null, null);
  if v_role <> 'super' then raise exception 'not_authorized'; end if;
  if exists (select 1 from players where phone = input_phone and id <> input_player_id) then return 'phone_taken'; end if;
  update players set phone = input_phone where id = input_player_id;
  perform log_admin_action('super', 'super', 'admin_update_player_phone', jsonb_build_object('player_id', input_player_id, 'new_phone', input_phone));
  return 'ok';
end; $$;

create or replace function admin_update_player_email(input_player_id text, input_email text, input_pw text)
returns boolean language plpgsql security definer as $$
declare v_role text;
begin
  v_role := require_admin(input_pw, null, null);
  if v_role <> 'super' then raise exception 'not_authorized'; end if;
  update players set email = input_email where id = input_player_id;
  perform log_admin_action('super', 'super', 'admin_update_player_email', jsonb_build_object('player_id', input_player_id, 'new_email', input_email));
  return true;
end; $$;

-- ניהול משחקים והרשמות (אדמין או אדמין-על)
create or replace function admin_create_game(input_kickoff bigint, input_opens_at bigint, input_pw text, input_phone text, input_pin text)
returns text language plpgsql security definer as $$
declare v_role text; v_game_id text;
begin
  v_role := require_admin(input_pw, input_phone, input_pin);
  v_game_id := 'g'||floor(extract(epoch from now())*1000)::text;
  insert into games (id, kickoff, opens_at, published, roster_published)
    values (v_game_id, input_kickoff, input_opens_at, false, false);
  perform log_admin_action(v_role, coalesce(input_phone,'super'), 'admin_create_game', jsonb_build_object('game_id', v_game_id, 'kickoff', input_kickoff, 'opens_at', input_opens_at));
  return 'ok';
end; $$;

create or replace function admin_set_game_published(input_game_id text, input_published boolean, input_pw text, input_phone text, input_pin text)
returns boolean language plpgsql security definer as $$
declare v_role text;
begin
  v_role := require_admin(input_pw, input_phone, input_pin);
  update games set published = input_published where id = input_game_id;
  perform log_admin_action(v_role, coalesce(input_phone,'super'), 'admin_set_game_published', jsonb_build_object('game_id', input_game_id, 'published', input_published));
  return true;
end; $$;

create or replace function admin_set_roster_published(input_game_id text, input_roster_published boolean, input_pw text, input_phone text, input_pin text)
returns boolean language plpgsql security definer as $$
declare v_role text;
begin
  v_role := require_admin(input_pw, input_phone, input_pin);
  update games set roster_published = input_roster_published where id = input_game_id;
  perform log_admin_action(v_role, coalesce(input_phone,'super'), 'admin_set_roster_published', jsonb_build_object('game_id', input_game_id, 'roster_published', input_roster_published));
  return true;
end; $$;

create or replace function admin_delete_game(input_game_id text, input_pw text, input_phone text, input_pin text)
returns boolean language plpgsql security definer as $$
declare v_role text;
begin
  v_role := require_admin(input_pw, input_phone, input_pin);
  delete from registrations where game_id = input_game_id;
  delete from games where id = input_game_id;
  perform log_admin_action(v_role, coalesce(input_phone,'super'), 'admin_delete_game', jsonb_build_object('game_id', input_game_id));
  return true;
end; $$;

create or replace function admin_set_registration_ts(input_game_id text, input_player_id text, input_ts bigint, input_pw text, input_phone text, input_pin text)
returns boolean language plpgsql security definer as $$
declare v_role text;
begin
  v_role := require_admin(input_pw, input_phone, input_pin);
  update registrations set ts = input_ts where game_id = input_game_id and player_id = input_player_id;
  perform log_admin_action(v_role, coalesce(input_phone,'super'), 'admin_set_registration_ts', jsonb_build_object('game_id', input_game_id, 'player_id', input_player_id, 'ts', input_ts));
  return true;
end; $$;

-- הוחלפו (drop + create) כי היו קיימות קודם עם 2 פרמטרים בלבד, בלי אימות הרשאה כלל
drop function if exists admin_add_registration(text, text);
create or replace function admin_add_registration(
  input_game_id text, input_player_id text, input_pw text default null, input_phone text default null, input_pin text default null
) returns boolean language plpgsql security definer as $$
declare v_role text;
begin
  v_role := require_admin(input_pw, input_phone, input_pin);
  insert into registrations (game_id, player_id, ts) values (input_game_id, input_player_id, (extract(epoch from now())*1000)::bigint);
  perform log_admin_action(v_role, coalesce(input_phone,'super'), 'admin_add_registration', jsonb_build_object('game_id', input_game_id, 'player_id', input_player_id));
  return true;
end; $$;

drop function if exists admin_remove_registration(text, text);
create or replace function admin_remove_registration(
  input_game_id text, input_player_id text, input_pw text default null, input_phone text default null, input_pin text default null
) returns boolean language plpgsql security definer as $$
declare v_role text;
begin
  v_role := require_admin(input_pw, input_phone, input_pin);
  delete from registrations where game_id=input_game_id and player_id=input_player_id;
  perform log_admin_action(v_role, coalesce(input_phone,'super'), 'admin_remove_registration', jsonb_build_object('game_id', input_game_id, 'player_id', input_player_id));
  return true;
end; $$;

-- סימון נוכחות בפועל למשחק (אדמין או אדמין-על)
create or replace function admin_set_attendance(
  input_game_id text, input_player_id text, input_attended boolean,
  input_pw text default null, input_phone text default null, input_pin text default null
) returns boolean language plpgsql security definer as $$
declare v_role text;
begin
  v_role := require_admin(input_pw, input_phone, input_pin);
  update registrations set attended = input_attended where game_id = input_game_id and player_id = input_player_id;
  perform log_admin_action(v_role, coalesce(input_phone,'super'), 'admin_set_attendance', jsonb_build_object('game_id', input_game_id, 'player_id', input_player_id, 'attended', input_attended));
  return true;
end; $$;

-- נעילת נוכחות למשחק — רק משחקים נעולים נספרים בעדיפות "מתמיד" (ר' index.html)
create or replace function admin_set_attendance_locked(
  input_game_id text, input_locked boolean,
  input_pw text default null, input_phone text default null, input_pin text default null
) returns boolean language plpgsql security definer as $$
declare v_role text;
begin
  v_role := require_admin(input_pw, input_phone, input_pin);
  update games set attendance_locked = input_locked where id = input_game_id;
  perform log_admin_action(v_role, coalesce(input_phone,'super'), 'admin_set_attendance_locked', jsonb_build_object('game_id', input_game_id, 'locked', input_locked));
  return true;
end; $$;

-- עוטפת את update_settings הקיימת (ר' חלק ב) בדרישת אימות מייל אמיתי ל-
-- nadavfichman@gmail.com לפני שמאפשרים שינוי סיסמת אדמין-על, בנוסף לסיסמה
-- הנוכחית. משתמשת ב-auth.jwt() כדי לוודא שהקורא אכן מאומת עם המייל הזה
-- (דרך db.auth.signInWithOtp הקיים כבר לשחקנים).
create or replace function update_settings_secure(
  current_super_pw text, new_super_pw text, new_super_phone text
) returns boolean
language plpgsql security definer as $$
declare v_email text; v_result boolean;
begin
  select lower(coalesce(auth.jwt() ->> 'email', '')) into v_email;
  if v_email is distinct from 'nadavfichman@gmail.com' then
    raise exception 'email_verification_required';
  end if;
  v_result := update_settings(
    current_super_pw => current_super_pw,
    new_super_pw => new_super_pw,
    new_super_phone => new_super_phone
  );
  -- לעולם לא רושמים את הסיסמה עצמה ללוג — רק את העובדה שהיא השתנתה
  if v_result then
    perform log_admin_action('super', 'super', 'update_settings_secure', jsonb_build_object('changed_password', new_super_pw is not null, 'changed_phone', new_super_phone is not null));
  end if;
  return v_result;
end; $$;

-- תיקון קריטי: הגרסה המקורית עשתה "select * from (...) t" שכלל גם את עמודת
-- המיון הפנימית pr, מה שגרם לשגיאת 42804 ("structure of query does not
-- match function result type") בכל קריאה יחידה — identity תמיד חזר null,
-- מה שגרם לכל שחקן (מאושר או לא) לראות תמיד את מסך ההצטרפות/השלמת פרטים.
-- זה היה כנראה הבאג האמיתי מאחורי כל הבעיה המקורית של "שחקן תקוע בהרשמה".
create or replace function get_my_identity()
returns table(status text, player_id text, name text, phone text, is_ganigari boolean, is_vatik boolean)
language plpgsql security definer as $$
declare v_uid uuid;
begin
  v_uid := auth.uid();
  if v_uid is null then return; end if;
  return query
    select t.status, t.player_id, t.name, t.phone, t.is_ganigari, t.is_vatik
    from (
      select 1 as pr, 'approved'::text as status, p.id as player_id, p.name, p.phone, p.is_ganigari, p.is_vatik
      from players p where p.auth_user_id = v_uid
      union all
      select 2 as pr, 'pending'::text, null::text, r.name, r.phone, null::boolean, null::boolean
      from player_requests r where r.auth_user_id = v_uid and coalesce(r.status,'pending') != 'rejected'
    ) t
    order by t.pr limit 1;
end; $$;

-- מטפלת בהרשמה ראשונית + שני מקרי קישור-מחדש אוטומטיים:
-- (1) שחקן שהוזן ידנית ע"י אדמין בלי מייל מקושר (auth_user_id is null)
-- (2) שחקן שכבר מאושר ומקושר, אבל חוזר מסשן/מכשיר אחר — אם גם הטלפון וגם
--     המייל תואמים לרשומה קיימת, מקשרים מחדש במקום לחסום עם phone_taken.
create or replace function submit_player_request(input_name text, input_phone text, input_email text)
returns text language plpgsql security definer as $$
declare
  v_uid uuid;
  v_existing_player_id text;
begin
  v_uid := auth.uid();
  if v_uid is null then return 'not_authenticated'; end if;
  if exists (select 1 from players where auth_user_id = v_uid) then return 'already_player'; end if;
  if exists (select 1 from player_requests where auth_user_id = v_uid) then return 'already_pending'; end if;

  select id into v_existing_player_id from players where phone = input_phone and auth_user_id is null;
  if v_existing_player_id is not null then
    update players set auth_user_id = v_uid, email = input_email where id = v_existing_player_id;
    return 'linked_existing';
  end if;

  select id into v_existing_player_id
  from players
  where phone = input_phone and lower(trim(email)) = lower(trim(input_email));
  if v_existing_player_id is not null then
    update players set auth_user_id = v_uid where id = v_existing_player_id;
    return 'linked_existing';
  end if;

  if exists (select 1 from players where phone = input_phone) then return 'phone_taken'; end if;

  insert into player_requests (id, name, phone, email, auth_user_id)
    values ('req'||floor(extract(epoch from now())*1000)::text, input_name, input_phone, input_email, v_uid);
  return 'ok';
end; $$;

-- רישום שגיאת קליינט (Error Boundary של React, window.onerror, כישלון RPC
-- ב-callAdmin) לצורך ניטור — בלי לחכות שמישהו ידווח ידנית. write-only בכוונה:
-- אין מדיניות SELECT על client_errors (ר' policies.sql), רק אדמין שמריץ
-- שאילתה ישירה ב-Supabase Dashboard יכול לקרוא. כל אחד יכול לקרוא לפונקציה
-- הזו בלי אימות — הסיכון היחיד הוא ספאם של רשומות לוג חסרות ערך, לא דליפת
-- מידע או כתיבה לטבלאות אמיתיות.
create or replace function log_client_error(
  p_message text, p_stack text, p_user_agent text, p_url text, p_context text
) returns void language plpgsql security definer as $$
begin
  insert into client_errors (message, stack, user_agent, url, context)
    values (left(p_message,2000), left(p_stack,4000), left(p_user_agent,500), left(p_url,500), left(p_context,200));
end; $$;

grant execute on function log_client_error(text,text,text,text,text) to anon, authenticated;

-- קריאת יומן השגיאות (אדמין-על בלבד) — client_errors חסומה לגמרי ל-SELECT
-- ישיר (ר' policies.sql), כך שזו הדרך היחידה לצפות בה, כולל מתוך האפליקציה
-- עצמה (ר' ClientErrorLog ב-index.html) ולא רק דרך שאילתה ב-Dashboard.
create or replace function get_client_errors(input_pw text, input_limit int default 200)
returns table(id bigint, created_at timestamptz, message text, stack text, user_agent text, url text, context text)
language plpgsql security definer as $$
declare v_role text;
begin
  v_role := require_admin(input_pw, null, null);
  if v_role <> 'super' then raise exception 'not_authorized'; end if;
  return query
    select e.id, e.created_at, e.message, e.stack, e.user_agent, e.url, e.context
    from client_errors e
    order by e.created_at desc
    limit greatest(coalesce(input_limit, 200), 1);
end; $$;


-- ============================================================================
-- חלק ב: פונקציות קיימות מראש (נכתבו לפני הפרויקט הזה) — כאן כהפניה בלבד
-- אלה לא נערכו על ידינו; מתועדות כאן כי הגוף שלהן ידוע ומשמש פונקציות אחרות
-- למעלה (בעיקר check_login, שעליה מבוססת require_admin).
-- ============================================================================

-- check_login: מאמת סיסמת אדמין-על (input_pw) או PIN אישי של מנהל
-- (input_phone + input_pin), עם הגבלת קצב (8 ניסיונות שגויים / 10 דקות).
-- מסתמכת על טבלאות settings (super_pw) ו-login_attempts.
create or replace function check_login(input_pw text default null, input_phone text default null, input_pin text default null)
returns text language plpgsql security definer as $$
declare s record; fail_count int; window_minutes int := 10; max_attempts int := 8;
begin
  if input_pw is not null then
    select count(*) into fail_count from login_attempts where kind='super' and created_at > now() - (window_minutes||' minutes')::interval;
    if fail_count >= max_attempts then return 'locked'; end if;
    select super_pw into s from settings where id = 1;
    if input_pw = s.super_pw then
      delete from login_attempts where kind='super';
      return 'super';
    else
      insert into login_attempts (kind, key) values ('super','x');
      return null;
    end if;
  end if;

  if input_phone is not null and input_pin is not null then
    select count(*) into fail_count from login_attempts where kind='admin_pin' and key=input_phone and created_at > now() - (window_minutes||' minutes')::interval;
    if fail_count >= max_attempts then return 'locked'; end if;
    if exists(select 1 from admins where phone=input_phone and pin=input_pin) then
      delete from login_attempts where kind='admin_pin' and key=input_phone;
      return 'admin';
    else
      insert into login_attempts (kind, key) values ('admin_pin', input_phone);
      return null;
    end if;
  end if;
  return null;
end; $$;

-- register_for_game: שחקן נרשם לעצמו למשחק. בודקת בעלות אמיתית
-- (players.auth_user_id = auth.uid()) לפני ההרשמה.
create or replace function register_for_game(input_game_id text, input_player_id text)
returns text language plpgsql security definer as $$
declare v_uid uuid; already_registered boolean;
begin
  v_uid := auth.uid();
  if v_uid is null or not exists (select 1 from players where id=input_player_id and auth_user_id=v_uid) then
    return 'not_authorized';
  end if;
  select exists(select 1 from registrations where game_id=input_game_id and player_id=input_player_id) into already_registered;
  if already_registered then return 'already_registered'; end if;
  insert into registrations (game_id, player_id, ts) values (input_game_id, input_player_id, (extract(epoch from now())*1000)::bigint);
  return 'ok';
end; $$;

-- cancel_own_registration: שחקן מבטל את ההרשמה של עצמו. אותה בדיקת בעלות.
create or replace function cancel_own_registration(input_game_id text, input_player_id text)
returns boolean language plpgsql security definer as $$
declare v_uid uuid;
begin
  v_uid := auth.uid();
  if v_uid is null or not exists (select 1 from players where id=input_player_id and auth_user_id=v_uid) then
    return false;
  end if;
  delete from registrations where game_id=input_game_id and player_id=input_player_id;
  return found;
end; $$;

-- הפונקציות הבאות קיימות במערכת אך הגוף שלהן לא תועד כאן (לא הוצג לנו
-- במהלך הפרויקט) — הן קיימות ופועלות, רק שהעתק הקוד שלהן לא נאסף:
--   login_hint(input_phone)
--   update_settings(current_super_pw, new_super_pw, new_super_phone)
--   create_admin_invite / list_pending_invites / cancel_admin_invite / redeem_admin_invite
--   create_pin_reset / list_pending_resets / cancel_pin_reset / redeem_pin_reset
-- אם ירצו לתעד גם אותן — יש להעתיק את הגוף שלהן מ-Database → Functions
-- ולהוסיף לקובץ הזה.
