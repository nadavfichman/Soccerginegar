-- ============================================================================
-- Migration 0045 — תיקון שורש: קוד שניידר נרשם כניסיון כושל לאדמין-על
-- ============================================================================
-- "השמירה נכשלה" (ושאר הכישלונות ב-20 הדקות האחרונות) לא היו קשורים
-- לבקרת הגולים בכלל. הקוד "1478" של שניידר נשלח בכל קריאה גם כ-
-- input_pw (require_summary_access מנסה קודם את check_login, המסלול
-- של אדמין-על). check_login לא יודע שזה ניסיון-שניידר ולא ניסיון-
-- אדמין אמיתי — הוא משווה "1478" מול סיסמת האדמין-על, נכשל, ורושם
-- את זה כניסיון כושל אמיתי ל-login_attempts (kind='super'). אחרי 8
-- כישלונות כאלה תוך 10 דקות (בדיוק מה שקרה תוך כדי הבדיקות שלנו),
-- check_login מחזיר 'locked' — ו-require_summary_access אז זורק
-- exception גם אם קוד שניידר עצמו תקין לגמרי, כי הבדיקה הראשונה
-- (check_login) כבר נכשלה/ננעלה לפני שבכלל הגענו ל-check_summary_login.
--
-- התיקון: מחליפים את סדר הבדיקה ב-check_summary_access/
-- require_summary_access — קודם check_summary_login (קוד שניידר,
-- בלי שום תופעת-לוואי/נעילה), ורק אם הוא נכשל עוברים ל-check_login
-- (האדמין). כך קוד שניידר תקין אף פעם לא "נוגע" בלוגיקת הנעילה של
-- האדמין. גם מנקים עכשיו את הנעילה שכבר נצברה, כדי שהאדמין האמיתי
-- לא יישאר נעול.
-- ============================================================================

delete from login_attempts where kind = 'super';

create or replace function check_summary_access(input_summary_pw text, input_pw text)
returns boolean language plpgsql security definer as $$
declare v_role text;
begin
  if check_summary_login(input_summary_pw) then return true; end if;
  v_role := check_login(input_pw, null, null);
  return v_role is not null and v_role <> 'locked';
end; $$;

create or replace function require_summary_access(input_summary_pw text, input_pw text, input_phone text, input_pin text)
returns text language plpgsql security definer as $$
declare v_role text;
begin
  if check_summary_login(input_summary_pw) then return 'schneider'; end if;
  v_role := check_login(input_pw, input_phone, input_pin);
  if v_role = 'locked' then raise exception 'locked'; end if;
  if v_role is not null then return v_role; end if;
  raise exception 'not_authorized';
end; $$;
