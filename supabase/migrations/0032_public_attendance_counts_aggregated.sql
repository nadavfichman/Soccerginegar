-- ============================================================================
-- Migration 0032 — ספירת "הגעות" ציבורית: מצטברת בשרת, לא שורה-לכל-משחק
-- (2026-10-10)
-- ============================================================================
-- המשתמש דיווח אחרי migrations/0031 (מקור אמת יחיד): "צבי אמיר מראה 43
-- הגעות, בסטטיסטיקה מראה 153 משחקים" — עדיין פער, למרות ששני המקומות
-- כבר קוראים מאותה פונקציה SQL בדיוק (get_counted_results_players).
--
-- הסיבה האמיתית: attendanceCounts (index.html) קורא ל-get_counted_results_players
-- *ישירות מהלקוח* וסופר כל שורה (שורה אחת לכל משחק-ושחקן — אלפי שורות
-- בסה"כ, עם עשור של היסטוריה מיובאת × ~56 שחקנים). ל-Supabase המתארח
-- יש הגבלת שורות ברירת מחדל ל-RPC שחוצה את גבול ה-HTTP (db-max-rows,
-- בד"כ 1000) — נחתך בשקט, בלי שגיאה, ובלי ORDER BY החיתוך שרירותי
-- לכל שחקן. admin_get_all_player_stats לא נפגעת כי היא קוראת לאותה
-- פונקציה *מבפנים* (SQL-ל-SQL, לא חוצה HTTP) ומחזירה רק שורה אחת
-- לכל שחקן (~56 שורות סה"כ) — רחוק מכל הגבלה.
--
-- הפתרון: RPC ציבורי חדש שמצטבר *בשרת* (כמו admin_get_all_player_stats
-- כבר עושה) ומחזיר רק (player_id, games_count) — שורה אחת לשחקן, אף
-- פעם לא קרוב להגבלת שורות כלשהי. index.html קורא לזה במקום לספור
-- שורות גולמיות בעצמו.
-- ============================================================================

create or replace function get_player_attendance_counts()
returns table(player_id text, games_count integer)
language sql security definer as $$
  select gc.player_id, count(*)::integer as games_count
  from get_counted_results_players() gc
  group by gc.player_id;
$$;

grant execute on function get_player_attendance_counts() to anon, authenticated;
