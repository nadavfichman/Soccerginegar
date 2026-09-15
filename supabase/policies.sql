-- ============================================================================
-- כדורגל גניגרי ושות' — מדיניות RLS (Row Level Security)
-- ============================================================================
-- מצב היסטורי: כל שש הטבלאות האלה נוצרו במקור עם מדיניות "allow all"
-- (USING true, WITH CHECK true, לכל פעולה — SELECT/INSERT/UPDATE/DELETE —
-- לתפקיד public) — כלומר כל מי שיש לו את ה-anon key הציבורי (חשוף ממילא
-- בקוד המקור של האתר) יכול היה לקרוא/לכתוב/למחוק כל שורה בכל טבלה, ישירות
-- מקונסולת הדפדפן, בלי לעבור דרך שום בדיקת הרשאה של האפליקציה.
--
-- התיקון: הוחלפה המדיניות הישנה במדיניות SELECT-בלבד. כל כתיבה (INSERT/
-- UPDATE/DELETE) עוברת אך ורק דרך פונקציות RPC מסוג SECURITY DEFINER
-- (ר' functions.sql) שמאמתות הרשאת אדמין/אדמין-על בצד השרת, ומכיוון שהן
-- SECURITY DEFINER הן עוקפות RLS מבחינה טכנית (רצות בהרשאת הבעלים).
--
-- SELECT נשאר פתוח לכולם בכוונה — האפליקציה מציגה רשימת שחקנים/משחקים גם
-- למבקרים לא-מחוברים (למשל בדיקת כפילות שם/טלפון בטופס ההרשמה).
--
-- טבלאות settings, login_attempts (שם שמורה סיסמת האדמין-על), client_errors
-- (לוג שגיאות קליינט) ו-admin_audit_log (לוג פעולות ניהול, ר'
-- schema_additions.sql/functions.sql) יש להן RLS מופעל בלי אף מדיניות
-- בכלל — כלומר חסומות לגמרי מגישה ציבורית, גם לקריאה. זה תקין ומכוון, לא
-- צריך לשנות.
-- ============================================================================

drop policy if exists "allow all players" on players;
create policy "players select" on players for select to public using (true);

drop policy if exists "allow all games" on games;
create policy "games select" on games for select to public using (true);

drop policy if exists "allow all registrations" on registrations;
create policy "registrations select" on registrations for select to public using (true);

drop policy if exists "allow all player_requests" on player_requests;
create policy "player_requests select" on player_requests for select to public using (true);

drop policy if exists "allow all admins" on admins;
create policy "admins select" on admins for select to public using (true);

drop policy if exists "allow all admin_requests" on admin_requests;
create policy "admin_requests select" on admin_requests for select to public using (true);

-- game_declines (ר' schema_additions.sql) — אותה מדיניות כמו registrations:
-- SELECT פתוח לכולם, כל כתיבה רק דרך RPC (decline_game/cancel_own_decline).
drop policy if exists "game_declines select" on game_declines;
create policy "game_declines select" on game_declines for select to public using (true);
