-- ============================================================================
-- Migration 0005 — Hash the super-admin password (2026-09-15)
-- ============================================================================
-- עד עכשיו settings.super_pw היה שמור כטקסט גלוי. משתמש ב-pgcrypto (כבר
-- מותקן בפרויקט — ר' schema_snapshot_2026-09-15.sql) כדי לעבור להאש bcrypt.
--
-- שלושה חלקים, מומלץ להריץ בסדר הזה:
--   1. עדכון check_login — משווה עכשיו דרך crypt() במקום ==.
--   2. עדכון update_settings — שומר סיסמה חדשה מוצפנת (bcrypt) במקום גלויה.
--   3. הצפנה חד-פעמית של הערך הקיים בטבלה עצמה — לא צריך להקליד את הסיסמה
--      הנוכחית לשום מקום; השאילתה קוראת אותה מהטבלה ומחליפה במקום. הביטוי
--      `super_pw !~ '^\$2[aby]\$'` הוא שומר-אידמפוטנטיות: אם ירוץ פעמיים
--      בטעות, לא יצפין האש קיים בתוך עצמו (זה יהפוך אותו לבלתי-שמיש).
--
-- אחרי שזה רץ: סיסמת האדמין-על הישנה עדיין עובדת בדיוק כמו קודם (check_login
-- משווה נכון מול ההאש) — אין צורך לשנות סיסמה, רק המבנה הפנימי השתנה.
-- ============================================================================

create or replace function check_login(input_pw text default null, input_phone text default null, input_pin text default null)
returns text language plpgsql security definer as $$
declare s record; fail_count int; window_minutes int := 10; max_attempts int := 8;
begin
  if input_pw is not null then
    select count(*) into fail_count from login_attempts where kind='super' and created_at > now() - (window_minutes||' minutes')::interval;
    if fail_count >= max_attempts then return 'locked'; end if;
    select super_pw into s from settings where id = 1;
    if crypt(input_pw, s.super_pw) = s.super_pw then
      delete from login_attempts where kind='super';
      return 'super';
    else
      insert into login_attempts (kind, key) values ('super','x');
      return null;
    end if;
  end if;

  if input_phone is not null and input_pin is not null then
    select count(*) into fail_count from login_attempts where kind='admin_pin' and key=input_phone and created_at > now() - (window_minutes||' minutes')::interval;
    if fail_count >= max_attempts then return 'locked'; end if;
    if exists(select 1 from admins where phone=input_phone and pin=input_pin) then
      delete from login_attempts where kind='admin_pin' and key=input_phone;
      return 'admin';
    else
      insert into login_attempts (kind, key) values ('admin_pin', input_phone);
      return null;
    end if;
  end if;
  return null;
end; $$;

create or replace function update_settings(current_super_pw text, new_super_pw text, new_super_phone text)
returns boolean language plpgsql security definer
set search_path to 'public' as $$
begin
  if not exists (select 1 from settings where id = 1 and crypt(current_super_pw, super_pw) = super_pw) then return false; end if;
  update settings set super_pw = crypt(new_super_pw, gen_salt('bf')), super_phone = new_super_phone where id = 1;
  return true;
end; $$;

-- הצפנה חד-פעמית של הסיסמה הקיימת. בטוח להריץ שוב בטעות (לא יצפין פעמיים).
update settings set super_pw = crypt(super_pw, gen_salt('bf'))
where id = 1 and super_pw !~ '^\$2[aby]\$';
