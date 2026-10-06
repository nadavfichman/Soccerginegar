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
-- input_group נבחר בטופס האישור עצמו (ר' PendingRequestRow, migrations/0009)
drop function if exists approve_player_request(text, boolean, boolean, text);
create or replace function approve_player_request(
  input_request_id text, input_is_ganigari boolean, input_is_vatik boolean, input_group text, input_pw text
) returns text language plpgsql security definer as $$
declare v_role text; r record;
begin
  v_role := require_admin(input_pw, null, null);
  if v_role <> 'super' then raise exception 'not_authorized'; end if;
  select * into r from player_requests where id = input_request_id;
  if r is null then return 'not_found'; end if;
  if exists (select 1 from players where phone = r.phone) then return 'phone_taken'; end if;
  insert into players (id, name, phone, is_ganigari, is_vatik, player_group, email, auth_user_id)
    values ('p'||floor(extract(epoch from now())*1000)::text, r.name, r.phone, input_is_ganigari, input_is_vatik, coalesce(input_group,'primary'), r.email, r.auth_user_id);
  delete from player_requests where id = input_request_id;
  perform log_admin_action('super', 'super', 'approve_player_request', jsonb_build_object('request_id', input_request_id, 'name', r.name, 'phone', r.phone, 'is_ganigari', input_is_ganigari, 'is_vatik', input_is_vatik, 'group', input_group));
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
-- input_group נבחר בטופס ההוספה עצמו (ר' AdminRoster, migrations/0009)
drop function if exists admin_add_player(text, text, boolean, boolean, text);
create or replace function admin_add_player(input_name text, input_phone text, input_is_ganigari boolean, input_is_vatik boolean, input_group text, input_pw text)
returns text language plpgsql security definer as $$
declare v_role text;
begin
  v_role := require_admin(input_pw, null, null);
  if v_role <> 'super' then raise exception 'not_authorized'; end if;
  if exists (select 1 from players where phone = input_phone) then return 'phone_taken'; end if;
  insert into players (id, name, phone, is_ganigari, is_vatik, player_group)
    values ('p'||floor(extract(epoch from now())*1000)::text, input_name, input_phone, input_is_ganigari, input_is_vatik, coalesce(input_group,'primary'));
  perform log_admin_action('super', 'super', 'admin_add_player', jsonb_build_object('name', input_name, 'phone', input_phone, 'is_ganigari', input_is_ganigari, 'is_vatik', input_is_vatik, 'group', input_group));
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

-- דירוג מספרי לחלוקת כוחות (ר' migrations/0013, שלב A) — מוזן/נערך ידנית
-- בלבד, לא מתעדכן אוטומטית לפי תוצאות (אין עדיין היסטוריית תוצאות
-- ב-Soccerginegar). קלט לאלגוריתם splitTeamsByGrade (logic.js).
-- מ-migration 0014: נשמר בטבלה נפרדת ונעולה (player_grades, בלי policy
-- ציבורי, ר' policies.sql) — לא בעמודה על players הפתוחה ל-SELECT ציבורי
-- — כי "אסור ששחקן יראה ציונים, גלוי רק לאדמין" (ר' שיחה עם המשתמש).
create or replace function admin_set_player_grade(input_player_id text, input_grade integer, input_pw text)
returns boolean language plpgsql security definer as $$
declare v_role text;
begin
  v_role := require_admin(input_pw, null, null);
  if v_role <> 'super' then raise exception 'not_authorized'; end if;
  if input_grade < 1 or input_grade > 99 then raise exception 'grade_out_of_range'; end if;
  insert into player_grades (player_id, grade) values (input_player_id, input_grade)
    on conflict (player_id) do update set grade = excluded.grade;
  perform log_admin_action('super', 'super', 'admin_set_player_grade', jsonb_build_object('player_id', input_player_id, 'grade', input_grade));
  return true;
end; $$;

-- קריאת כל הדירוגים (ר' migrations/0014) — אדמין רגיל *או* על, כי חלוקת
-- כוחות (AdminGameRow) היא "ניהול משחק" ולא "ניהול שחקן" (בניגוד לכתיבה
-- למעלה, שנשארת super-בלבד — עריכת דירוג בסיס לשחקן).
create or replace function admin_get_player_grades(input_pw text, input_phone text, input_pin text)
returns table(player_id text, grade integer) language plpgsql security definer as $$
declare v_role text;
begin
  v_role := require_admin(input_pw, input_phone, input_pin);
  return query select pg.player_id, pg.grade from player_grades pg;
end; $$;

-- שיוך קבוצה לשחקן (ר' migrations/0009) — קובע אילו משחקים בכלל מוצגים
-- לו (ר' visible_to_primary/visible_to_secondary למעלה)
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
-- visible_to_primary/visible_to_secondary נקבעים ביצירה (ר' migrations/0009) —
-- קובעים אילו קבוצות שחקנים בכלל רואות את המשחק ברשימה שלהן.
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

-- עריכת שעת/תאריך משחק אחרי פרסום (ר' migrations/0010) — כל התצוגות
-- לשחקנים קוראות ישירות מ-games.kickoff, אז השינוי מתעדכן בכל מקום
-- אוטומטית בלי צורך לעדכן עותקים נפרדים. אימות בצד השרת נוסף ב-
-- migrations/0011 — ה-UI חוסם עריכה למשחק שכבר קרה, אבל זו הייתה בדיקת
-- לקוח בלבד; קריאה ישירה ל-RPC יכלה לעקוף אותה או להזיז קיקאוף לפני
-- opens_at.
create or replace function admin_set_game_kickoff(input_game_id text, input_kickoff bigint, input_pw text, input_phone text, input_pin text)
returns boolean language plpgsql security definer as $$
declare v_role text; v_old_kickoff bigint; v_opens_at bigint;
begin
  v_role := require_admin(input_pw, input_phone, input_pin);
  select kickoff, opens_at into v_old_kickoff, v_opens_at from games where id = input_game_id;
  if v_old_kickoff is null then raise exception 'game_not_found'; end if;
  if v_old_kickoff < floor(extract(epoch from now())*1000) then raise exception 'game_already_happened'; end if;
  if input_kickoff <= v_opens_at then raise exception 'kickoff_before_opens'; end if;
  update games set kickoff = input_kickoff where id = input_game_id;
  perform log_admin_action(v_role, coalesce(input_phone,'super'), 'admin_set_game_kickoff', jsonb_build_object('game_id', input_game_id, 'kickoff', input_kickoff));
  return true;
end; $$;

-- "סגור הרשמה" (ר' migrations/0012) — דגל נפרד מ-roster_published/
-- attendance_locked: מקפיא ידנית את רשימת הנרשמים למשחק, בלי קשר ל-
-- opens_at, וניתן לפתיחה מחדש (toggle). אכיפה בצד השרת בכל ה-RPCs
-- שמשנים הרשמה/סימון של שחקן (register_for_game, decline_game,
-- cancel_own_registration, cancel_own_decline) — לא רק חסימת UI.
create or replace function admin_set_registration_closed(input_game_id text, input_value boolean, input_pw text, input_phone text, input_pin text)
returns boolean language plpgsql security definer as $$
declare v_role text;
begin
  v_role := require_admin(input_pw, input_phone, input_pin);
  update games set registration_closed = input_value where id = input_game_id;
  perform log_admin_action(v_role, coalesce(input_phone,'super'), 'admin_set_registration_closed', jsonb_build_object('game_id', input_game_id, 'value', input_value));
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

-- שומר חלוקה לקבוצות (חלוקת כוחות, ר' migrations/0013 שלב A) בעסקה אחת —
-- מאפס את כל השיבוצים הקיימים למשחק הזה, ואז משבץ לפי שתי רשימות ה-id.
-- מי שלא ברשימה (ספסל) נשאר בלי שורה בכלל.
-- מ-migration 0014: נשמר בטבלה נפרדת ונעולה (game_teams, בלי policy
-- ציבורי) במקום בעמודת registrations.team הפתוחה ל-SELECT ציבורי — אותה
-- סיבה בדיוק כמו player_grades למעלה.
create or replace function admin_set_game_teams(input_game_id text, input_team1_ids text[], input_team2_ids text[], input_pw text, input_phone text, input_pin text)
returns boolean language plpgsql security definer as $$
declare v_role text;
begin
  v_role := require_admin(input_pw, input_phone, input_pin);
  delete from game_teams where game_id = input_game_id;
  insert into game_teams (game_id, player_id, team)
    select input_game_id, pid, 1 from unnest(input_team1_ids) as pid
    union all
    select input_game_id, pid, 2 from unnest(input_team2_ids) as pid;
  perform log_admin_action(v_role, coalesce(input_phone,'super'), 'admin_set_game_teams', jsonb_build_object('game_id', input_game_id, 'team1_count', coalesce(array_length(input_team1_ids,1),0), 'team2_count', coalesce(array_length(input_team2_ids,1),0)));
  return true;
end; $$;

-- קריאת השיבוץ השמור למשחק ספציפי (ר' migrations/0014) — אותה רמת
-- הרשאה בדיוק כמו הכתיבה למעלה (ניהול משחק, לא ניהול שחקן).
create or replace function admin_get_game_teams(input_game_id text, input_pw text, input_phone text, input_pin text)
returns table(player_id text, team smallint) language plpgsql security definer as $$
declare v_role text;
begin
  v_role := require_admin(input_pw, input_phone, input_pin);
  return query select gt.player_id, gt.team from game_teams gt where gt.game_id = input_game_id;
end; $$;

-- פרסום חלוקת הכוחות לשחקנים בתוך האפליקציה (ר' migrations/0020) — אותו
-- דפוס בדיוק כמו roster_published/admin_set_roster_published: שליטת
-- אדמין מפורשת, לא אוטומטי ברגע ששומרים חלוקה.
create or replace function admin_set_teams_published(input_game_id text, input_value boolean, input_pw text, input_phone text, input_pin text)
returns boolean language plpgsql security definer as $$
declare v_role text;
begin
  v_role := require_admin(input_pw, input_phone, input_pin);
  update games set teams_published = input_value where id = input_game_id;
  perform log_admin_action(v_role, coalesce(input_phone,'super'), 'admin_set_teams_published', jsonb_build_object('game_id', input_game_id, 'value', input_value));
  return true;
end; $$;

-- קריאה ציבורית (anon/authenticated, בלי אישורי אדמין) — בכוונה, כדי
-- שכל שחקן שרואה את המשחק (דרך סינון visible_to_primary/secondary הקיים)
-- יוכל לראות את הכוחות בלי להזדקק לאישורי ניהול. game_teams עצמה נשארת
-- נעולה לגמרי — זה הנתיב הציבורי היחיד, ובודק teams_published בפנים
-- לפני שמחזיר שורות (אחרת ריק). בלי דירוג/ציון בחתימה.
create or replace function get_published_teams(input_game_id text)
returns table(player_id text, team smallint)
language plpgsql security definer as $$
begin
  if not exists (select 1 from games where id = input_game_id and teams_published = true) then
    return;
  end if;
  return query select gt.player_id, gt.team from game_teams gt where gt.game_id = input_game_id;
end; $$;

grant execute on function get_published_teams(text) to anon, authenticated;

-- משחק עם תוצאה שמורה נספר ב"מתמיד" (attendanceCounts, index.html) גם
-- בלי נעילת נוכחות (ר' migrations/0024+0025, שיחה עם המשתמש — "אם משחק
-- נכנס להיסטוריה יספר בכמות המשחקים... גם אם לא ננעל"). migrations/0024
-- תנה את זה גם בפרסום הכוחות לשחקנים (teams_published) — תנאי נפרד
-- שהתברר כמבלבל בפועל (המשתמש הזין תוצאה אבל זה לא נספר, כי לא לחץ
-- בנפרד על "פרסם כוחות"); migrations/0025 הסיר את התנאי הזה — תוצאה
-- שמורה + חלוקה שמורה (game_teams) מספיקות, בלי תלות בפעולת UI נפרדת.
-- ציבורי כמו get_published_teams, מאותה סיבה בדיוק — מחושב גם למסך
-- שחקן רגיל, לא רק לאדמין. לא חושף שום דבר חוץ מ-player_id/game_id גולמיים.
create or replace function get_counted_results_players()
returns table(game_id text, player_id text)
language sql security definer as $$
  select gt.game_id, gt.player_id
  from game_results gr
  join game_teams gt on gt.game_id = gr.game_id;
$$;

grant execute on function get_counted_results_players() to anon, authenticated;

-- תיעוד תוצאות משחק (ר' migrations/0016) — צעד ראשון לקראת שלב C
-- (כימיה/אחוזי-ניצחון), לא תלוי בייבוא היסטוריה מ-TeamPicker. דורש
-- שחלוקת קבוצות כבר נשמרה לאותו משחק (אכיפה בצד השרת).
create or replace function admin_set_game_result(input_game_id text, input_team1_score integer, input_team2_score integer, input_pw text, input_phone text, input_pin text)
returns boolean language plpgsql security definer as $$
declare v_role text;
begin
  v_role := require_admin(input_pw, input_phone, input_pin);
  if not exists (select 1 from game_teams where game_id = input_game_id) then raise exception 'teams_not_saved'; end if;
  if input_team1_score < 0 or input_team2_score < 0 then raise exception 'invalid_score'; end if;
  insert into game_results (game_id, team1_score, team2_score, recorded_at) values (input_game_id, input_team1_score, input_team2_score, now())
    on conflict (game_id) do update set team1_score = excluded.team1_score, team2_score = excluded.team2_score, recorded_at = now();
  perform log_admin_action(v_role, coalesce(input_phone,'super'), 'admin_set_game_result', jsonb_build_object('game_id', input_game_id, 'team1_score', input_team1_score, 'team2_score', input_team2_score));
  return true;
end; $$;

-- מחזירה גם mvp_player_id (ר' migrations/0026) — דורש drop כי סוג ההחזרה משתנה.
drop function if exists admin_get_game_result(text, text, text, text);
create or replace function admin_get_game_result(input_game_id text, input_pw text, input_phone text, input_pin text)
returns table(team1_score integer, team2_score integer, mvp_player_id text)
language plpgsql security definer as $$
declare v_role text;
begin
  v_role := require_admin(input_pw, input_phone, input_pin);
  return query select gr.team1_score, gr.team2_score, gr.mvp_player_id from game_results gr where gr.game_id = input_game_id;
end; $$;

-- סימון "שחקן מצטיין" למשחק (ר' migrations/0026, בהשוואה לאפליקציה של
-- דרור) — RPC נפרד מ-admin_set_game_result בכוונה, כדי ששמירת תוצאה
-- רגילה לעולם לא תלויה בזה שהמיגרציה הזו רצה.
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

-- כל התוצאות בעסקה אחת, כולל תאריך וספירת שחקנים לכל קבוצה — לרשימת
-- "היסטוריית תוצאות" (GameResultsHistory). מ-migrations/0023: מאחדת
-- (UNION ALL) משחקים חיים (game_results) עם 416 המשחקים ההיסטוריים
-- שיובאו מ-TeamPicker (legacy_player_games, מקובצת לפי source_game_id
-- כדי לשחזר שורת-משחק מתוך שורה-לכל-שחקן). team1_player_ids/
-- team2_player_ids מצורפים ישירות לשורה כך שהרחבת-שורה בצד הלקוח (הצגת
-- הכוחות) לא צריכה round-trip נוסף — admin_get_game_teams ממילא לא
-- עובד על מזהי משחק מיובאים.
-- מחזירה גם mvp_player_id (ר' migrations/0026) — null קבוע למשחקים
-- מיובאים מ-TeamPicker (legacy_player_games אין לה עמודת MVP בסכימה שלנו).
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

-- "פורמה" — 5 התוצאות האחרונות לכל שחקן (ר' migrations/0017, עודכן ב-0019
-- לאחד עם היסטוריה מיובאת מ-TeamPicker). ניצחון/הפסד/תיקו נקבע לפי team
-- ששויך לו מול game_results (חי) או legacy_player_games (מיובא). לתצוגה
-- כנקודות צבעוניות ליד כל שם בפאנל חלוקת הכוחות (ירוק/אדום/כחול).
create or replace function admin_get_player_form(input_player_ids text[], input_pw text, input_phone text, input_pin text)
returns table(player_id text, kickoff bigint, outcome text)
language plpgsql security definer as $$
declare v_role text;
begin
  v_role := require_admin(input_pw, input_phone, input_pin);
  return query
    select x.player_id, x.kickoff, x.outcome from (
      select combined.player_id, combined.kickoff, combined.outcome,
        row_number() over (partition by combined.player_id order by combined.kickoff desc) as rn
      from (
        select gt.player_id, g.kickoff,
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
        join games g on g.id = gt.game_id
        where gt.player_id = any(input_player_ids)
        union all
        select lpg.player_id, floor(extract(epoch from lpg.game_date) * 1000)::bigint as kickoff, lpg.outcome
        from legacy_player_games lpg
        where lpg.player_id = any(input_player_ids)
      ) combined
    ) x
    where x.rn <= 5
    order by x.player_id, x.kickoff desc;
end; $$;

-- נתוני "כימיה" לאיזון כוחות כמו אצל דרור (ר' migrations/0021) — אימוץ
-- מדויק של אלגוריתם DivideCollaboration מ-TeamPicker, לא ניחוש (נקרא קוד
-- המקור הציבורי במפורש). מחזיר שורות גולמיות (לא ציון מחושב) כדי
-- שהחיפוש האקראי (200 ניסיונות, logic.js) ירוץ בצד הלקוח על נתונים
-- שנשלפו פעם אחת. חלון: 50 המשחקים האחרונים של כל שחקן. שורת "עצמי"
-- (teammate_id = player_id) מקודדת את הסטטיסטיקה האישית הכוללת.
create or replace function admin_get_player_chemistry(input_player_ids text[], input_pw text, input_phone text, input_pin text)
returns table(player_id text, teammate_id text, games_with integer, wins_with integer, decisive_with integer)
language plpgsql security definer as $$
declare v_role text;
begin
  v_role := require_admin(input_pw, input_phone, input_pin);
  return query
    with unified as (
      select gt.player_id, ('live:'||gt.game_id) as gkey, gt.team, g.kickoff as sort_ts,
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
      join games g on g.id = gt.game_id
      union all
      select lpg.player_id, ('legacy:'||lpg.source_game_id) as gkey, lpg.team,
        floor(extract(epoch from lpg.game_date) * 1000)::bigint as sort_ts, lpg.outcome
      from legacy_player_games lpg
    ),
    recent as (
      select x.player_id, x.gkey, x.team, x.outcome from (
        select u.player_id, u.gkey, u.team, u.outcome,
          row_number() over (partition by u.player_id order by u.sort_ts desc) as rn
        from unified u
        where u.player_id = any(input_player_ids)
      ) x
      where x.rn <= 50
    )
  select r.player_id, r.player_id as teammate_id, count(*)::integer as games_with,
    sum((r.outcome = 'win')::integer)::integer as wins_with,
    sum((r.outcome in ('win','loss'))::integer)::integer as decisive_with
  from recent r
  group by r.player_id
  union all
  select a.player_id, b.player_id, count(*)::integer,
    sum((a.outcome = 'win')::integer)::integer,
    sum((a.outcome in ('win','loss'))::integer)::integer
  from recent a
  join unified b on b.gkey = a.gkey and b.team = a.team and b.player_id <> a.player_id
  where b.player_id = any(input_player_ids)
  group by a.player_id, b.player_id;
end; $$;

-- "מידע על שחקן" (ר' migrations/0022) — נתוני קריירה מצטברים (בלי חלון
-- 50 משחקים כמו admin_get_player_chemistry) לשחקן יחיד: סה"כ משחקים/
-- ניצחונות/הפסדים/תיקו, מ-game_teams+game_results (חי) ו-
-- legacy_player_games (מיובא) יחד.
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
    )
  select count(*)::integer as games_count,
    coalesce(sum((outcome = 'win')::integer), 0)::integer as wins,
    coalesce(sum((outcome = 'loss')::integer), 0)::integer as losses,
    coalesce(sum((outcome = 'draw')::integer), 0)::integer as draws
  from unified;
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

-- אורח חד-פעמי למשחק ספציפי (ר' migrations/0008) — player_id סינתטי
-- וייחודי (guest_<uuid>) מאוחסן בעמודת player_id הרגילה, כך ש-
-- admin_remove_registration/admin_set_attendance/admin_set_registration_ts
-- הקיימות (מעל) ממשיכות לעבוד עליו בלי שום שינוי.
-- input_grade אופציונלי (ר' migrations/0015) — דירוג לחלוקת כוחות למשחק
-- הזה בלבד. player_grades.player_id בלי FK ל-players (כמו registrations),
-- אז אפשר לשמור שורת דירוג גם לאורח, עם אותו player_id סינתטי בדיוק.
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

-- נעילת נוכחות למשחק — רק משחקים נעולים נספרים בעדיפות "מתמיד" (ר' index.html).
-- מ-migration 0018: אסור לנעול משחק שעדיין לא התקיים (אין עדיין נוכחות
-- אמיתית לנעול) — אותו דפוס כמו ה-guard ב-admin_set_game_kickoff. פתיחה
-- מחדש (input_locked=false) תמיד מותרת.
create or replace function admin_set_attendance_locked(
  input_game_id text, input_locked boolean,
  input_pw text default null, input_phone text default null, input_pin text default null
) returns boolean language plpgsql security definer as $$
declare v_role text; v_kickoff bigint;
begin
  v_role := require_admin(input_pw, input_phone, input_pin);
  if input_locked then
    select kickoff into v_kickoff from games where id = input_game_id;
    if v_kickoff is null then raise exception 'game_not_found'; end if;
    if v_kickoff > floor(extract(epoch from now())*1000) then raise exception 'game_not_happened_yet'; end if;
  end if;
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


-- אבטחה: סיסמת אדמין-על הייתה שמורה בטקסט גלוי ב-settings.super_pw. הוחלף
-- בהאש bcrypt (pgcrypto, כבר מותקן בפרויקט) — crypt(value, gen_salt('bf'))
-- ליצירה, crypt(input, stored_hash) = stored_hash להשוואה (crypt שולפת את
-- ה-salt מתוך ההאש הקיים בעצמה). זה עדכון לשתי פונקציות שהיו קיימות מראש
-- (check_login, update_settings) — לכן, בשונה מכל שאר הקובץ, הועברו לכאן
-- מ"חלק ב'" למטה: מעכשיו הן כן נערכות ומתוחזקות כחלק מהפרויקט הזה.

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
    if crypt(input_pw, s.super_pw) = s.super_pw then
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

-- update_settings: משנה את סיסמת/טלפון האדמין-על, אחרי אימות הסיסמה
-- הנוכחית. נקראת דרך update_settings_secure שמוסיפה מעליה דרישת אימות מייל
-- (ר' למעלה). מ-migration 0005: הסיסמה החדשה נשמרת מוצפנת (bcrypt), לא בטקסט גלוי.
create or replace function update_settings(current_super_pw text, new_super_pw text, new_super_phone text)
returns boolean language plpgsql security definer
set search_path to 'public' as $$
begin
  if not exists (select 1 from settings where id = 1 and crypt(current_super_pw, super_pw) = super_pw) then return false; end if;
  update settings set super_pw = crypt(new_super_pw, gen_salt('bf')), super_phone = new_super_phone where id = 1;
  return true;
end; $$;

-- "לא אגיע" — סימון מפורש שהשחקן לא יגיע למשחק (בשונה מסתם לא להירשם), כדי
-- שלאדמין יהיה נתון אמיתי כמה אנשים בפועל הודיעו שלא יגיעו. קריאה ישירה
-- (db.from("game_declines")) מותרת דרך policies.sql, אין צורך ב-RPC לקריאה.
-- מבטלת אוטומטית הרשמה קיימת אם יש — שני המצבים הדדיים.
create or replace function decline_game(input_game_id text, input_player_id text)
returns text language plpgsql security definer as $$
declare v_uid uuid;
begin
  v_uid := auth.uid();
  if v_uid is null or not exists (select 1 from players where id=input_player_id and auth_user_id=v_uid) then
    return 'not_authorized';
  end if;
  if exists (select 1 from games where id = input_game_id and registration_closed) then
    return 'registration_closed';
  end if;
  delete from registrations where game_id=input_game_id and player_id=input_player_id;
  insert into game_declines (game_id, player_id, ts) values (input_game_id, input_player_id, (extract(epoch from now())*1000)::bigint)
    on conflict (game_id, player_id) do update set ts = excluded.ts;
  return 'ok';
end; $$;

-- cancel_own_decline: שחקן מבטל את הסימון "לא אגיע" (חוזר למצב "לא ענה").
create or replace function cancel_own_decline(input_game_id text, input_player_id text)
returns boolean language plpgsql security definer as $$
declare v_uid uuid;
begin
  v_uid := auth.uid();
  if v_uid is null or not exists (select 1 from players where id=input_player_id and auth_user_id=v_uid) then
    return false;
  end if;
  if exists (select 1 from games where id = input_game_id and registration_closed) then
    return false;
  end if;
  delete from game_declines where game_id=input_game_id and player_id=input_player_id;
  return found;
end; $$;

-- register_for_game: שחקן נרשם לעצמו למשחק. בודקת בעלות אמיתית
-- (players.auth_user_id = auth.uid()) לפני ההרשמה. מ-migration 0006: מנקה גם
-- סימון "לא אגיע" קיים, כדי ששני המצבים יישארו הדדיים (לא ניתן להיות גם וגם).
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
  return 'ok';
end; $$;


-- ============================================================================
-- חלק ב: פונקציות קיימות מראש (נכתבו לפני הפרויקט הזה) — כאן כהפניה בלבד
-- אלה לא נערכו על ידינו; מתועדות כאן כי הגוף שלהן ידוע.
--
-- יוצא דופן: register_for_game הועברה לחלק א' (למעלה, אחרי decline_game)
-- כי נוספה לה שורה שמנקה סימון "לא אגיע" קיים — מעכשיו נערכת ומתוחזקת
-- כחלק מהפרויקט הזה, בדיוק כמו check_login/update_settings.
-- ============================================================================

-- cancel_own_registration: שחקן מבטל את ההרשמה של עצמו. אותה בדיקת בעלות.
create or replace function cancel_own_registration(input_game_id text, input_player_id text)
returns boolean language plpgsql security definer as $$
declare v_uid uuid;
begin
  v_uid := auth.uid();
  if v_uid is null or not exists (select 1 from players where id=input_player_id and auth_user_id=v_uid) then
    return false;
  end if;
  if exists (select 1 from games where id = input_game_id and registration_closed) then
    return false;
  end if;
  delete from registrations where game_id=input_game_id and player_id=input_player_id;
  return found;
end; $$;

-- הפונקציות הבאות קיימות במערכת אך הגוף שלהן לא תועד כאן (לא הוצג לנו
-- במהלך הפרויקט) — הן קיימות ופועלות, רק שהעתק הקוד שלהן לא נאסף:
--   login_hint(input_phone)
--   create_admin_invite / list_pending_invites / cancel_admin_invite / redeem_admin_invite
--   create_pin_reset / list_pending_resets / cancel_pin_reset / redeem_pin_reset
-- אם ירצו לתעד גם אותן — יש להעתיק את הגוף שלהן מ-Database → Functions
-- ולהוסיף לקובץ הזה.
