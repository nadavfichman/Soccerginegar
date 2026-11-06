-- ============================================================================
-- Migration 0036 — ביטול משחק (cancelled) + הודעת ביטול לשחקנים
-- ============================================================================
-- המשתמש: "לעיתים אין משחק מכל מיני סיבות למרות שפורסמה רשימת כוחות,
-- רוצה שתהיה אפשרות להקפיץ הודעה המשחק שנקבע ליום... בשעה... לא
-- יתקיים. כמובן עם אפשרות לביטול ההודעה וחזרה למסך קודם. שיהיה גם
-- אפשרות לשליחה בוואטסאפ."
--
-- games.cancelled — דגל בוליאני נפרד לגמרי מ-registration_closed/
-- teams_published/roster_published (לא נוגע בהם, לא נגרר מהם). כש-true,
-- GameCard (index.html) מציג רק הודעת ביטול בולטת במקום UI ההרשמה
-- הרגיל — "להקפיץ הודעה" לשחקנים בתוך האפליקציה עצמה. הפיך (toggle,
-- "בטל ביטול") כמו שאר דגלי המשחק.
--
-- "אפשרות לביטול ההודעה וחזרה למסך קודם" ממומשת בצד הלקוח בלבד —
-- window.confirm() לפני שמסמנים cancelled=true; לחיצה על "ביטול"
-- בדיאלוג לא משנה כלום ומחזירה בדיוק לאותו מסך. אין צורך בתמיכה
-- בצד השרת לזה.
--
-- הודעת ביטול לוואטסאפ — אותו דפוס בדיוק כמו הודעת "נפתחה ההרשמה"
-- הקיימת (buildOpenMsg/shareOpenMsg לקבוצה ראשית, שליחה בודדת/העתקה
-- לרשימת תפוצה לקבוצה משנית) — טקסט בלבד, בלי RPC/טבלה נוספת.
-- ============================================================================

alter table games add column if not exists cancelled boolean not null default false;

create or replace function admin_set_game_cancelled(input_game_id text, input_value boolean, input_pw text, input_phone text, input_pin text)
returns boolean language plpgsql security definer as $$
declare v_role text;
begin
  v_role := require_admin(input_pw, input_phone, input_pin);
  update games set cancelled = input_value where id = input_game_id;
  perform log_admin_action(v_role, coalesce(input_phone,'super'), 'admin_set_game_cancelled', jsonb_build_object('game_id', input_game_id, 'value', input_value));
  return true;
end; $$;
