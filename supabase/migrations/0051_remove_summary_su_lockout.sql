-- ============================================================================
-- Migration 0051 — ביטול הנעילה המשותפת לגמרי בדף הסיכום הציבורי
-- ============================================================================
-- migrations/0050 בידד את ניחושי הסיסמה בדף הסיכום הציבורי לדלי-נעילה
-- נפרד (kind='summary_su') — כדי שלא ישרפו את מכסת אדמין-העל האמיתי.
-- זה פתר את הבעיה ההיא, אבל ה-דלי החדש עדיין *משותף לכל המנחשים*
-- (אין שום זיהוי-משתמש בדף הציבורי הזה) — ומה שראינו ביומן השגיאות
-- (20.11, 16:52-16:59): כמה ניסיונות שגויים רצופים (כנראה מישהו
-- שמנסה לנחש את קוד שניידר) נעלו את התכונה כולה ל-10 דקות — כולל
-- לאדמין עצמו, שנכנס עם קיצור-הדרך (cred, בלי להקליד כלום) ועדיין
-- קיבל 'locked' מ-summary_get_recent_games.
--
-- התיקון: מבטלים את מנגנון הנעילה על הבדיקה "אולי זו בעצם סיסמת
-- אדמין-על" בדף הזה *לגמרי* — לא רק מבודד, אלא בלי ספירה/חסימה
-- בכלל. הסיבה שזה בטוח: (1) מסך הכניסה *האמיתי* של אדמין-העל
-- (kind='super') נשאר עם ההגנה המלאה שלו, לא נוגעים בו. (2) הבדיקה
-- כאן היא רק נתיב-כניסה נוסף/נוח (לא היחיד) לדף הציבורי, מול סוד
-- מוצפן (bcrypt) — הגנה דרך קצב (כל crypt() איטי מכוונת) ולא דרך
-- ספירת-כישלונות משותפת, שהוכיחה את עצמה כ"כלי DoS עצמי" נגד
-- משפחה/קבוצה שלמה. (3) קוד שניידר עצמו (check_summary_login) מעולם
-- לא היה עם הגבלת-קצב כלשהי — אותו עיקרון בדיוק. (4) טלפון+פין נשאר
-- עם ההגנה המקורית שלו (kind='admin_pin', מבודדת-לפי-טלפון ממילא —
-- לא היה שם באג מעולם).

delete from login_attempts where kind = 'summary_su';

create or replace function check_summary_access(input_summary_pw text, input_pw text)
returns boolean language plpgsql security definer as $$
declare s record;
begin
  if check_summary_login(input_summary_pw) then return true; end if;
  if input_pw is null then return false; end if;
  select super_pw into s from settings where id = 1;
  return crypt(input_pw, s.super_pw) = s.super_pw;
end; $$;

create or replace function require_summary_access(input_summary_pw text, input_pw text, input_phone text, input_pin text)
returns text language plpgsql security definer as $$
declare s record; v_role text;
begin
  if check_summary_login(input_summary_pw) then return 'schneider'; end if;
  if input_pw is not null then
    select super_pw into s from settings where id = 1;
    if crypt(input_pw, s.super_pw) = s.super_pw then return 'super'; end if;
  end if;
  if input_phone is not null and input_pin is not null then
    v_role := check_login(null, input_phone, input_pin);
    if v_role = 'locked' then raise exception 'locked'; end if;
    if v_role is not null then return v_role; end if;
  end if;
  raise exception 'not_authorized';
end; $$;
