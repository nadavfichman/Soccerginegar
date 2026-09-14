# SQL — כדורגל גניגרי ושות'

תיעוד גרסה של הצד השרתי (Supabase/Postgres), שעד כה חי רק בדשבורד של Supabase.

## קבצים

- **`functions.sql`** — כל פונקציות ה-RPC: חלק א' נכתב/נערך במהלך הפרויקט הזה (מתועד במלואו ומעודכן); חלק ב' הן פונקציות שהיו קיימות מראש ולא נערכו, מתועדות כאן רק כהפניה כי גופן ידוע.
- **`policies.sql`** — מדיניות ה-RLS הנוכחית (SELECT בלבד לכל הטבלאות הציבוריות; כל כתיבה עוברת דרך RPC).
- **`schema_additions.sql`** — עמודות שנוספו לטבלאות קיימות (`attended`, `attendance_locked`).

## מגבלה חשובה

**לא נאספה כאן הגדרת הטבלאות המקורית** (`CREATE TABLE` עם הטיפוסים/האילוצים/ברירות המחדל של `players`, `games`, `registrations`, `player_requests`, `admins`, `admin_requests`, `settings`, `login_attempts`, `admin_invites`, `admin_pin_resets`) — כי היא נוצרה לפני תחילת העבודה הזו ומעולם לא הועברה. הקבצים כאן מתעדים רק את מה שהשתנה/נוסף.

**מומלץ:** לייצא את הסכימה המלאה ישירות מ-Supabase (Database → Backups, או `select table_name, column_name, data_type, column_default from information_schema.columns where table_schema='public' order by table_name;` ב-SQL Editor) ולהוסיף כקובץ נפרד, כדי שיהיה תיעוד מלא של המסד כולו — לא רק של מה שהשתנה כאן.

## איך להריץ

כל הקבצים משתמשים ב-`create or replace` / `if not exists`, כך שאפשר להריץ אותם מחדש בבטחה (idempotent) — לדוגמה כדי לשחזר את המצב על פרויקט Supabase חדש, אחרי שהטבלאות הבסיסיות כבר קיימות.
