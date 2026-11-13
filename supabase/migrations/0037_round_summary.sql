-- ============================================================================
-- Migration 0037 — דף הסיכום של שניידר (ציונים 1-10 + סיכום מחזור)
-- ============================================================================
-- המשתמש: "רוצה להוסיף דף של סיכום המחזור... שהוא יוכל למלא רשימה של
-- כל השחקנים ציון בין אחד לעשר עם חצאים גם, לפי הרשימה של השחקנים
-- של הכוחות... ושיהיה מקום למטה לרשום... סיכום של המשחק המצטיין
-- המאכזב המהלך וכדומה." הציונים האלה נפרדים לגמרי מ-players.grade
-- (המשמש לחלוקת כוחות) — לתצוגה/פרסום בלבד, לא משפיעים על שום חישוב.
--
-- החלטות מפורשות עם המשתמש (AskUserQuestion + המשך שיחה):
-- 1. שניידר אינו אדמין במערכת — הרשאה נפרדת לגמרי (settings.summary_pw),
--    לא להפוך אותו לאדמין. אבל גם המשתמש (אדמין-על) צריך גישה לאותו
--    מסך בדיוק, עם האישורים הרגילים שלו — לא עם קוד שניידר. לכן
--    require_summary_access מקבל את שני המסלולים ומקבל אם אחד מהם
--    תקין (לא "גם וגם").
-- 2. הדף הסופי מוצג לכל השחקנים באפליקציה (לא רק אדמין).
-- 3. טקסט חופשי בתיבה אחת, לא שדות נפרדים.
-- 4. גם אפשרות מחיקה של סיכום קיים (לא רק שמירה/עריכה).
-- ============================================================================

alter table settings add column if not exists summary_pw text;

create table if not exists game_round_summary (
  game_id text primary key references games(id) on delete cascade,
  narrative text not null default '',
  published boolean not null default false,
  updated_at timestamptz not null default now()
);
alter table game_round_summary enable row level security;

create table if not exists game_round_summary_ratings (
  game_id text not null references games(id) on delete cascade,
  player_id text not null,
  rating numeric(3,1) not null check (rating >= 1 and rating <= 10 and rating*2 = floor(rating*2)),
  primary key (game_id, player_id)
);
alter table game_round_summary_ratings enable row level security;
-- בלי policy/grant select ישיר על אף טבלה — אותו דפוס כמו player_grades/
-- game_teams/game_results. גישה רק דרך ה-RPCs למטה.

create or replace function check_summary_login(input_pw text)
returns boolean language plpgsql security definer as $$
declare s record;
begin
  if input_pw is null then return false; end if;
  select summary_pw into s from settings where id = 1;
  if s.summary_pw is null then return false; end if;
  return crypt(input_pw, s.summary_pw) = s.summary_pw;
end; $$;
grant execute on function check_summary_login(text) to anon, authenticated;

-- קביעת/איפוס הסיסמה של שניידר — דרך require_admin הרגיל (אדמין-על
-- או מנהל רגיל קובעים אותה, לא שניידר בעצמו).
create or replace function admin_set_summary_pw(new_pw text, input_pw text, input_phone text, input_pin text)
returns boolean language plpgsql security definer as $$
declare v_role text;
begin
  v_role := require_admin(input_pw, input_phone, input_pin);
  update settings set summary_pw = crypt(new_pw, gen_salt('bf')) where id = 1;
  perform log_admin_action(v_role, coalesce(input_phone,'super'), 'admin_set_summary_pw', '{}'::jsonb);
  return true;
end; $$;

-- בדיקה ציבורית נקייה (בלי raise) למסך הכניסה בלבד — מנסה קודם את
-- check_login הרגיל (סיסמת אדמין-על/PIN מנהל) ואם לא, את קוד שניידר.
-- check_login(null,null,null) חסר-תופעות-לוואי (לא רושם ניסיון כושל),
-- אז שניידר שלא שולח input_pw בכלל לא "נתקע" בלוגיקת הנעילה של אדמין.
create or replace function check_summary_access(input_summary_pw text, input_pw text)
returns boolean language plpgsql security definer as $$
declare v_role text;
begin
  v_role := check_login(input_pw, null, null);
  if v_role is not null and v_role <> 'locked' then return true; end if;
  return check_summary_login(input_summary_pw);
end; $$;
grant execute on function check_summary_access(text, text) to anon, authenticated;

-- עזר פנימי (לא נקרא ישירות מהלקוח) לשאר ה-RPCs של דף הסיכום — מקבל
-- אם האישורים הרגילים (אדמין-על/מנהל) תקינים, או אם קוד שניידר תקין.
-- raise בכישלון, אותו עיקרון כמו require_admin.
create or replace function require_summary_access(input_summary_pw text, input_pw text, input_phone text, input_pin text)
returns text language plpgsql security definer as $$
declare v_role text;
begin
  v_role := check_login(input_pw, input_phone, input_pin);
  if v_role = 'locked' then raise exception 'locked'; end if;
  if v_role is not null then return v_role; end if;
  if check_summary_login(input_summary_pw) then return 'schneider'; end if;
  raise exception 'not_authorized';
end; $$;
revoke all on function require_summary_access(text, text, text, text) from public;

create or replace function summary_get_recent_games(input_summary_pw text, input_pw text default null, input_phone text default null, input_pin text default null)
returns table(game_id text, kickoff bigint, team1_score integer, team2_score integer, published boolean)
language plpgsql security definer as $$
begin
  perform require_summary_access(input_summary_pw, input_pw, input_phone, input_pin);
  return query
    select g.id, g.kickoff, gr.team1_score, gr.team2_score, coalesce(grs.published, false)
    from games g
    join game_results gr on gr.game_id = g.id
    left join game_round_summary grs on grs.game_id = g.id
    order by g.kickoff desc
    limit 10;
end; $$;

create or replace function summary_get_draft(input_summary_pw text, input_game_id text, input_pw text default null, input_phone text default null, input_pin text default null)
returns table(player_id text, team smallint, guest_name text, rating numeric, narrative text, published boolean, team1_score integer, team2_score integer)
language plpgsql security definer as $$
begin
  perform require_summary_access(input_summary_pw, input_pw, input_phone, input_pin);
  return query
    select gt.player_id, gt.team, reg.guest_name, rt.rating,
      coalesce(grs.narrative, ''), coalesce(grs.published, false),
      gr.team1_score, gr.team2_score
    from game_teams gt
    left join game_round_summary_ratings rt on rt.game_id = gt.game_id and rt.player_id = gt.player_id
    left join registrations reg on reg.game_id = gt.game_id and reg.player_id = gt.player_id
    left join game_round_summary grs on grs.game_id = gt.game_id
    left join game_results gr on gr.game_id = gt.game_id
    where gt.game_id = input_game_id;
end; $$;

create or replace function summary_save(input_summary_pw text, input_game_id text, input_narrative text, input_published boolean, input_ratings jsonb, input_pw text default null, input_phone text default null, input_pin text default null)
returns boolean language plpgsql security definer as $$
declare r jsonb;
begin
  perform require_summary_access(input_summary_pw, input_pw, input_phone, input_pin);
  insert into game_round_summary (game_id, narrative, published, updated_at)
    values (input_game_id, input_narrative, input_published, now())
    on conflict (game_id) do update set narrative = excluded.narrative, published = excluded.published, updated_at = now();
  delete from game_round_summary_ratings where game_id = input_game_id;
  for r in select * from jsonb_array_elements(input_ratings) loop
    insert into game_round_summary_ratings (game_id, player_id, rating)
      values (input_game_id, r->>'player_id', (r->>'rating')::numeric);
  end loop;
  return true;
end; $$;

-- מחיקה מלאה של סיכום קיים (לא רק "שמור ריק") — מסיר גם את הטיוטה/
-- פרסום וגם את כל הציונים לאותו משחק.
create or replace function summary_delete(input_summary_pw text, input_game_id text, input_pw text default null, input_phone text default null, input_pin text default null)
returns boolean language plpgsql security definer as $$
begin
  perform require_summary_access(input_summary_pw, input_pw, input_phone, input_pin);
  delete from game_round_summary_ratings where game_id = input_game_id;
  delete from game_round_summary where game_id = input_game_id;
  return true;
end; $$;

-- ציבורי לגמרי, בלי סיסמה — "נראות" נשלטת ע"י published, אותו דפוס
-- בדיוק כמו get_published_teams/get_published_teams_form.
create or replace function get_round_summary_latest()
returns table(game_id text, kickoff bigint, narrative text, player_id text, team smallint, guest_name text, rating numeric)
language plpgsql security definer as $$
declare v_game_id text;
begin
  select grs.game_id into v_game_id
  from game_round_summary grs
  join games g on g.id = grs.game_id
  where grs.published = true
  order by g.kickoff desc
  limit 1;
  if v_game_id is null then return; end if;
  return query
    select grs.game_id, g.kickoff, grs.narrative, gt.player_id, gt.team, reg.guest_name, rt.rating
    from game_round_summary grs
    join games g on g.id = grs.game_id
    join game_teams gt on gt.game_id = grs.game_id
    left join game_round_summary_ratings rt on rt.game_id = grs.game_id and rt.player_id = gt.player_id
    left join registrations reg on reg.game_id = grs.game_id and reg.player_id = gt.player_id
    where grs.game_id = v_game_id;
end; $$;
grant execute on function get_round_summary_latest() to anon, authenticated;

-- טאב אדמין חדש ("📋 סיכומי שניידר") — רשימת כל המחזורים עם סיכום
-- (טיוטה או מפורסם, לא רק הפרסום האחרון כמו get_round_summary_latest),
-- לצפייה בלבד. require_admin רגיל (אותו cred כבר מאומת ב-AdminView),
-- לא קשור לקוד שניידר/require_summary_access.
create or replace function admin_get_round_summaries(input_pw text, input_phone text, input_pin text)
returns table(game_id text, kickoff bigint, team1_score integer, team2_score integer, narrative text, published boolean, player_id text, team smallint, guest_name text, rating numeric)
language plpgsql security definer as $$
declare v_role text;
begin
  v_role := require_admin(input_pw, input_phone, input_pin);
  return query
    select grs.game_id, g.kickoff, gr.team1_score, gr.team2_score, grs.narrative, grs.published,
      gt.player_id, gt.team, reg.guest_name, rt.rating
    from game_round_summary grs
    join games g on g.id = grs.game_id
    left join game_results gr on gr.game_id = grs.game_id
    join game_teams gt on gt.game_id = grs.game_id
    left join game_round_summary_ratings rt on rt.game_id = grs.game_id and rt.player_id = gt.player_id
    left join registrations reg on reg.game_id = grs.game_id and reg.player_id = gt.player_id
    order by g.kickoff desc;
end; $$;
