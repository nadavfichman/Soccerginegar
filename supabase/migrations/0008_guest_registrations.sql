-- ============================================================================
-- Migration 0008 — Guest registrations (2026-09-21)
-- ============================================================================
-- מאפשר לאדמין להוסיף "אורח" (חבר של חבר, לא חלק מהקבוצה) להרשמה של משחק
-- ספציפי בלבד, בלי ליצור עבורו שורה קבועה ב-players ובלי שישפיע על שום
-- דבר מעבר לאותו משחק. ר' שיחה עם המשתמש (21.09).
--
-- player_id ב-registrations הוא text חופשי, בלי FK ל-players (כך תוכנן
-- מלכתחילה) — כל אורח מקבל player_id סינתטי וייחודי (guest_<uuid ללא
-- מקפים>) שמאוחסן ב-player_id הרגיל, יחד עם השם האמיתי ב-guest_name
-- החדשה. בזכות זה כל שאר הלוגיקה הקיימת (סימון נוכחות, סידור עדיפות
-- בתוך הרשימה, הסרה, ייצוא לוואטסאפ, ה-unique(game_id, player_id))
-- ממשיכה לעבוד בדיוק כמו על שחקן רגיל, בלי שום שינוי ב-RPCs הקיימים —
-- היא לא יודעת ולא צריכה לדעת שזה לא "שחקן אמיתי". tierRank/sortRegs
-- (logic.js) כבר מתמודדים בחן עם player_id שלא קיים ב-roster (מחזיר
-- tierRank 0, "רגיל") — אין צורך בשינוי שם.
--
-- אורח לא מצטבר לזהות קבועה בין משחקים (אין players.id אמיתי) — זה
-- מכוון: אורח הוא חד-פעמי, "לא לשום מטרה נוספת" חוץ מהמשחק הזה.
-- ============================================================================

alter table registrations add column if not exists guest_name text;

create or replace function admin_add_guest_registration(
  input_game_id text, input_guest_name text,
  input_pw text default null, input_phone text default null, input_pin text default null
) returns text language plpgsql security definer as $$
declare v_role text; v_name text; v_guest_id text;
begin
  v_role := require_admin(input_pw, input_phone, input_pin);
  v_name := trim(input_guest_name);
  if v_name = '' then raise exception 'empty_guest_name'; end if;
  v_guest_id := 'guest_' || replace(gen_random_uuid()::text, '-', '');
  insert into registrations (game_id, player_id, guest_name, ts)
    values (input_game_id, v_guest_id, v_name, (extract(epoch from now())*1000)::bigint);
  perform log_admin_action(v_role, coalesce(input_phone,'super'), 'admin_add_guest_registration', jsonb_build_object('game_id', input_game_id, 'guest_name', v_name, 'player_id', v_guest_id));
  return v_guest_id;
end; $$;
