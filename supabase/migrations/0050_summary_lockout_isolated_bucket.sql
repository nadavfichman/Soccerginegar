-- ============================================================================
-- Migration 0050 — ניחוש שגוי בדף הסיכום הציבורי (שניידר) כבר לא "שורף"
-- את מכסת הנעילה של אדמין-העל האמיתי
-- ============================================================================
-- המשתמש: "משהו כאן מוזר, לא ניסיתי אפילו פעם אחת. יכול להיות שאם
-- שניידר או מישהו אחר מנסה זה משפיע גם עליי?" — תשובה: כן, וזה בדיוק
-- מה שקרה. migrations/0045 תיקן רק את המקרה של קוד שניידר *נכון*
-- (לא נוגע יותר בנעילת אדמין-העל) — אבל check_summary_access/
-- require_summary_access עדיין נופלים, על כל ניחוש *שגוי* בדף
-- הציבורי הזה (נגיש לכל אחד, בלי שום הזדהות מוקדמת!), ל-
-- check_login(input_pw, ...) עם אותו ערך-ניחוש בדיוק — וזה בודק אותו
-- מול סיסמת-העל האמיתית ורושם ניסיון כושל (kind='super') בכל פעם
-- שהוא לא תואם. אחרי 8 ניחושים שגויים כאלה תוך 10 דקות (לדוגמה: מישהו
-- סקרן שמנסה להקליד משהו בדף הסיכום) — אדמין-העל האמיתי ננעל, למרות
-- שהוא עצמו מעולם לא ניסה כלום.
--
-- התיקון: הבדיקה "אולי זו בעצם סיסמת אדמין-על" ממשיכה להתקיים (כמו
-- שהיה תמיד — גם סיסמת-על צריכה לעבוד בדף הזה), אבל עם מכסת-נעילה
-- *נפרדת לגמרי* (kind='summary_su') — לעולם לא אותה מכסה (kind='super')
-- שמשרתת את מסך הכניסה האמיתי של אדמין-העל. ניחוש טלפון+פין שגוי
-- ממשיך לעבור דרך check_login כרגיל (המכסה שלו ממילא מבודדת לפי
-- טלפון, לא משותפת/גלובלית — לא היה שם באג).

delete from login_attempts where kind = 'super';

create or replace function check_summary_access(input_summary_pw text, input_pw text)
returns boolean language plpgsql security definer as $$
declare s record; fail_count int; window_minutes int := 10; max_attempts int := 8;
begin
  if check_summary_login(input_summary_pw) then return true; end if;
  if input_pw is null then return false; end if;
  select count(*) into fail_count from login_attempts where kind='summary_su' and created_at > now() - (window_minutes||' minutes')::interval;
  if fail_count >= max_attempts then return false; end if;
  select super_pw into s from settings where id = 1;
  if crypt(input_pw, s.super_pw) = s.super_pw then return true; end if;
  insert into login_attempts (kind, key) values ('summary_su','x');
  return false;
end; $$;

create or replace function require_summary_access(input_summary_pw text, input_pw text, input_phone text, input_pin text)
returns text language plpgsql security definer as $$
declare s record; fail_count int; window_minutes int := 10; max_attempts int := 8; v_role text;
begin
  if check_summary_login(input_summary_pw) then return 'schneider'; end if;
  if input_pw is not null then
    select count(*) into fail_count from login_attempts where kind='summary_su' and created_at > now() - (window_minutes||' minutes')::interval;
    if fail_count >= max_attempts then raise exception 'locked'; end if;
    select super_pw into s from settings where id = 1;
    if crypt(input_pw, s.super_pw) = s.super_pw then return 'super'; end if;
    insert into login_attempts (kind, key) values ('summary_su','x');
  end if;
  if input_phone is not null and input_pin is not null then
    v_role := check_login(null, input_phone, input_pin);
    if v_role = 'locked' then raise exception 'locked'; end if;
    if v_role is not null then return v_role; end if;
  end if;
  raise exception 'not_authorized';
end; $$;
