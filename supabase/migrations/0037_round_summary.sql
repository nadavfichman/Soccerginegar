-- ============================================================================
-- Migration 0037 — דף הסיכום של שניידר (ציונים 1-10 + סיכום מחזור)
-- ============================================================================
-- המשתמש: "רוצה להוסיף דף של סיכום המחזור... שהוא יוכל למלא רשימה של
-- כל השחקנים ציון בין אחד לעשר עם חצאים גם, לפי הרשימה של השחקנים
-- של הכוחות... ושיהיה מקום למטה לרשום... סיכום של המשחק המצטיין
-- המאכזב המהלך וכדומה."
--
-- שלוש החלטות מפורשות עם המשתמש (AskUserQuestion):
-- 1. שניידר אינו אדמין במערכת — הרשאה נפרדת לגמרי (settings.summary_pw,
--    לא קשור ל-super_pw/PIN-מנהל), לא להפוך אותו לאדמין.
-- 2. הדף הסופי מוצג לכל השחקנים באפליקציה (לא רק אדמין).
-- 3. טקסט חופשי בתיבה אחת, לא שדות נפרדים.
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
  select summary_pw into s from settings where id = 1;
  if s.summary_pw is null then return false; end if;
  return crypt(input_pw, s.summary_pw) = s.summary_pw;
end; $$;
grant execute on function check_summary_login(text) to anon, authenticated;

create or replace function admin_set_summary_pw(new_pw text, input_pw text, input_phone text, input_pin text)
returns boolean language plpgsql security definer as $$
declare v_role text;
begin
  v_role := require_admin(input_pw, input_phone, input_pin);
  update settings set summary_pw = crypt(new_pw, gen_salt('bf')) where id = 1;
  perform log_admin_action(v_role, coalesce(input_phone,'super'), 'admin_set_summary_pw', '{}'::jsonb);
  return true;
end; $$;

create or replace function summary_get_recent_games(input_summary_pw text)
returns table(game_id text, kickoff bigint, team1_score integer, team2_score integer, published boolean)
language plpgsql security definer as $$
begin
  if not check_summary_login(input_summary_pw) then raise exception 'invalid_summary_password'; end if;
  return query
    select g.id, g.kickoff, gr.team1_score, gr.team2_score, coalesce(grs.published, false)
    from games g
    join game_results gr on gr.game_id = g.id
    left join game_round_summary grs on grs.game_id = g.id
    order by g.kickoff desc
    limit 10;
end; $$;

create or replace function summary_get_draft(input_summary_pw text, input_game_id text)
returns table(player_id text, team smallint, guest_name text, rating numeric, narrative text, published boolean, team1_score integer, team2_score integer)
language plpgsql security definer as $$
begin
  if not check_summary_login(input_summary_pw) then raise exception 'invalid_summary_password'; end if;
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

create or replace function summary_save(input_summary_pw text, input_game_id text, input_narrative text, input_published boolean, input_ratings jsonb)
returns boolean language plpgsql security definer as $$
declare r jsonb;
begin
  if not check_summary_login(input_summary_pw) then raise exception 'invalid_summary_password'; end if;
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
