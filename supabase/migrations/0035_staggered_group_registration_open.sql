-- ============================================================================
-- Migration 0035 — פתיחת הרשמה בשעה נפרדת לכל קבוצה (ראשית/משנית)
-- (2026-10-12)
-- ============================================================================
-- המשתמש: "המטרה שלי שקודם ירשמו הקבוצה הראשית, ורק אחר כך הקבוצה
-- המשנית... שחקן קבוצה ראשית יראה שהרשמה נפתחת ב-21:00, שחקן קבוצה
-- משנית ב-22:00, וכך גם אכן יקרה." אושר במפורש (AskUserQuestion) גם
-- אכיפה אמיתית בצד השרת, לא רק תצוגה — אחרת היתרון היה רק ויזואלי,
-- ניתן לעקיפה ע"י קריאת RPC ישירה.
--
-- games.opens_at (קיים) ממשיך לייצג את שעת הפתיחה לקבוצה הראשית, בלי
-- שינוי משמעות. עמודה חדשה, opens_at_secondary — ברירת מחדל = opens_at
-- (אין שינוי התנהגות למשחקים קיימים/משחקים שלא הוגדרה להם שעה נפרדת
-- במפורש — שתי הקבוצות נפתחות יחד, בדיוק כמו היום).
-- ============================================================================

alter table games add column if not exists opens_at_secondary bigint;
update games set opens_at_secondary = opens_at where opens_at_secondary is null;
alter table games alter column opens_at_secondary set not null;

do $$ begin
  if not exists (
    select 1 from pg_constraint where conname = 'games_opens_at_secondary_not_before_primary'
  ) then
    alter table games add constraint games_opens_at_secondary_not_before_primary
      check (opens_at_secondary >= opens_at);
  end if;
end $$;

-- admin_create_game: פרמטר נוסף אופציונלי (ברירת מחדל null → זהה ל-opens_at,
-- כלומר בלי הפרדה אם לא צויין). חתימה חדשה (8 פרמטרים, היתה 7) — דורש drop
-- כדי לא להשאיר גרסה ישנה כפולה (אותה קונבנציה כמו migrations/0009).
drop function if exists admin_create_game(bigint, bigint, text, text, text);
drop function if exists admin_create_game(bigint, bigint, boolean, boolean, text, text, text);
create or replace function admin_create_game(
  input_kickoff bigint, input_opens_at bigint,
  input_visible_to_primary boolean, input_visible_to_secondary boolean,
  input_pw text, input_phone text, input_pin text,
  input_opens_at_secondary bigint default null
) returns text language plpgsql security definer as $$
declare v_role text; v_game_id text; v_opens_secondary bigint;
begin
  v_role := require_admin(input_pw, input_phone, input_pin);
  v_game_id := 'g'||floor(extract(epoch from now())*1000)::text;
  v_opens_secondary := coalesce(input_opens_at_secondary, input_opens_at);
  if v_opens_secondary < input_opens_at then
    raise exception 'opens_at_secondary_before_primary';
  end if;
  insert into games (id, kickoff, opens_at, opens_at_secondary, published, roster_published, visible_to_primary, visible_to_secondary)
    values (v_game_id, input_kickoff, input_opens_at, v_opens_secondary, false, false, input_visible_to_primary, input_visible_to_secondary);
  perform log_admin_action(v_role, coalesce(input_phone,'super'), 'admin_create_game', jsonb_build_object('game_id', v_game_id, 'kickoff', input_kickoff, 'opens_at', input_opens_at, 'opens_at_secondary', v_opens_secondary, 'visible_to_primary', input_visible_to_primary, 'visible_to_secondary', input_visible_to_secondary));
  return 'ok';
end; $$;

-- register_for_game: אכיפה אמיתית בצד השרת, לפי קבוצת השחקן (לא רק isOpen
-- בצד הלקוח, שהיה ונשאר גם קיים כקו-הגנה ראשון/UX). שם+חתימה זהים — create
-- or replace רגיל, לא unconditional-on-load (נקרא רק בלחיצה על "מגיע ✓"),
-- אז אין סיכון deploy-ordering.
create or replace function register_for_game(input_game_id text, input_player_id text)
returns text language plpgsql security definer as $$
declare v_uid uuid; already_registered boolean; v_group text; v_opens_at bigint; v_now bigint;
begin
  v_uid := auth.uid();
  if v_uid is null or not exists (select 1 from players where id=input_player_id and auth_user_id=v_uid) then
    return 'not_authorized';
  end if;
  if exists (select 1 from games where id = input_game_id and registration_closed) then
    return 'registration_closed';
  end if;
  select player_group into v_group from players where id = input_player_id;
  select (case when v_group = 'secondary' then opens_at_secondary else opens_at end) into v_opens_at
    from games where id = input_game_id;
  v_now := (extract(epoch from now())*1000)::bigint;
  if v_opens_at is not null and v_now < v_opens_at then
    return 'not_open_yet';
  end if;
  select exists(select 1 from registrations where game_id=input_game_id and player_id=input_player_id) into already_registered;
  if already_registered then return 'already_registered'; end if;
  delete from game_declines where game_id=input_game_id and player_id=input_player_id;
  insert into registrations (game_id, player_id, ts) values (input_game_id, input_player_id, (extract(epoch from now())*1000)::bigint);
  perform close_registration_if_full(input_game_id);
  return 'ok';
end; $$;
