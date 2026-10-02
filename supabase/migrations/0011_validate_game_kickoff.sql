-- ============================================================================
-- Migration 0011 — Validate admin_set_game_kickoff server-side (2026-10-02)
-- ============================================================================
-- admin_set_game_kickoff (migration 0010) לא אימתה כלום בצד השרת — ה-UI
-- חוסם עריכת שעה למשחק שכבר קרה (hasHappened), אבל זו בדיקת לקוח בלבד.
-- קריאה ישירה ל-RPC (למשל אם מישהו יודע את אישורי האדמין) הייתה יכולה
-- לעקוף אותה, או להזיז קיקאוף למועד שהוא לפני opens_at (פותח הרשמה
-- אחרי שהמשחק כבר התחיל). מוסיף שתי בדיקות בצד השרת, עקבי עם מודל
-- "האדמין מאומת אבל הקלט עדיין נבדק" של שאר ה-RPCs.
-- ============================================================================

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
