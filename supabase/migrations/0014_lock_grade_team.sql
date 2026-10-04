-- ============================================================================
-- Migration 0014 — נעילת grade/team מגישה ציבורית (2026-10-04)
-- ============================================================================
-- migration 0013 הוסיפה players.grade ו-registrations.team לתוך טבלאות
-- שכבר פתוחות לגמרי ל-SELECT ציבורי (RLS "using (true)", ר' policies.sql).
-- מפתח ה-anon של Supabase חשוף בקוד הלקוח (index.html) — כל מי שפותח
-- קונסולת דפדפן יכול לשלוח שאילתה ישירה ולקרוא את שני השדות, בניגוד מוחלט
-- לדרישה המפורשת "אסור ששחקן יראה ציונים, גלוי רק לאדמין" (ר' שיחה עם
-- המשתמש). ה-UI הסתיר את השדות אבל הנתון עצמו היה גלוי.
--
-- התיקון: אותו דפוס בדיוק כמו settings/login_attempts/client_errors/
-- admin_audit_log (ר' policies.sql) — טבלה נפרדת, RLS מופעל, בלי אף
-- policy ובלי grant select ל-anon/authenticated. קריאה אפשרית אך ורק דרך
-- RPC של אדמין (SECURITY DEFINER, עוקף RLS אחרי אימות הרשאה). גם שאילתת
-- REST ישירה עם מפתח ה-anon הציבורי תיכשל עם permission denied, בדיוק
-- כמו ניסיון לקרוא settings היום.
-- ============================================================================

create table if not exists player_grades (
  player_id text primary key references players(id) on delete cascade,
  grade integer not null default 50 check (grade between 1 and 99)
);
alter table player_grades enable row level security;
-- בכוונה בלי שום policy ובלי grant select — נעול לגמרי, כמו settings.

insert into player_grades (player_id, grade)
select id, grade from players
on conflict (player_id) do update set grade = excluded.grade;

alter table players drop column if exists grade;

create table if not exists game_teams (
  game_id text not null references games(id) on delete cascade,
  player_id text not null,
  team smallint not null check (team in (1, 2)),
  primary key (game_id, player_id)
);
alter table game_teams enable row level security;
-- גם כאן: בלי policy, בלי grant select — נעול לגמרי.

insert into game_teams (game_id, player_id, team)
select game_id, player_id, team from registrations where team is not null;

alter table registrations drop column if exists team;

-- ---- RPCs של migration 0013, מעודכנים לכתוב לטבלאות הנעולות החדשות ----

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

-- ---- RPCs חדשים לקריאה — תמיד דרך אדמין מאומת, לעולם לא SELECT ציבורי ----
-- שתי הרמות (admin/super) יכולות לקרוא — איזון כוחות הוא "ניהול משחק",
-- אותה רמה בדיוק כמו admin_set_game_teams עצמו, לא "ניהול שחקן" (שם
-- super-בלבד, כמו is_ganigari/is_vatik/player_group).

create or replace function admin_get_player_grades(input_pw text, input_phone text, input_pin text)
returns table(player_id text, grade integer) language plpgsql security definer as $$
declare v_role text;
begin
  v_role := require_admin(input_pw, input_phone, input_pin);
  return query select pg.player_id, pg.grade from player_grades pg;
end; $$;

create or replace function admin_get_game_teams(input_game_id text, input_pw text, input_phone text, input_pin text)
returns table(player_id text, team smallint) language plpgsql security definer as $$
declare v_role text;
begin
  v_role := require_admin(input_pw, input_phone, input_pin);
  return query select gt.player_id, gt.team from game_teams gt where gt.game_id = input_game_id;
end; $$;
