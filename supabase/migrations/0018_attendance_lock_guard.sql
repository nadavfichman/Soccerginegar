-- ============================================================================
-- Migration 0018 — מניעת נעילת נוכחות למשחק שעוד לא התקיים (2026-10-05)
-- ============================================================================
-- המשתמש נעל בטעות נוכחות למשחק עתידי (לפני שהוא בכלל שוחק) — לא הגיוני:
-- "נוכחות נעולה" אמורה לסמן שהנוכחות הסופית נקבעה אחרי שהמשחק קרה, לא
-- "אף אחד לא הגיע" למשחק שטרם התקיים (ר' שיחה עם המשתמש).
--
-- אותו דפוס בדיוק כמו admin_set_game_kickoff (migration 0011 — "game
-- already happened" guard) — אכיפה בצד השרת, לא רק UI. פתיחה מחדש
-- (input_locked=false) תמיד מותרת, בלי מגבלה.
-- ============================================================================

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
