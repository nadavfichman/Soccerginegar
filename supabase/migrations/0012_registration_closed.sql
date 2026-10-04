-- ============================================================================
-- Migration 0012 — Admin "close registration" toggle per game (2026-10-04)
-- ============================================================================
-- כפתור אדמין נפרד מ-roster_published/attendance_locked: "סגור הרשמה"
-- מקפיא ידנית את רשימת הנרשמים למשחק ספציפי, בלי קשר לזמן (opens_at),
-- וניתן לפתיחה מחדש בכל רגע (toggle, לא חד-כיווני). אכיפה בצד השרת בכל
-- פעולות השחקן עצמו (לא רק הסתרת כפתורים ב-UI) — לפי הלקח שכבר תועד
-- ב-CLAUDE.md "באגים משמעותיים", ר' גם migration 0011.
-- ============================================================================

alter table games add column if not exists registration_closed boolean not null default false;

create or replace function admin_set_registration_closed(input_game_id text, input_value boolean, input_pw text, input_phone text, input_pin text)
returns boolean language plpgsql security definer as $$
declare v_role text;
begin
  v_role := require_admin(input_pw, input_phone, input_pin);
  update games set registration_closed = input_value where id = input_game_id;
  perform log_admin_action(v_role, coalesce(input_phone,'super'), 'admin_set_registration_closed', jsonb_build_object('game_id', input_game_id, 'value', input_value));
  return true;
end; $$;

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
