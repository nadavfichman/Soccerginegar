// כדורגל גניגרי ושות' — פונקציות עזר "טהורות" (בלי React/DOM/רשת).
// מקור אמת יחיד: גם index.html (בדפדפן, דרך תגית <script> רגילה לפני
// ה-script של Babel) וגם tests/logic.spec.js (ב-Node, דרך require) טוענים
// את הקובץ הזה — כדי שהבדיקות תמיד יבדקו בדיוק את הקוד שרץ בפועל, לא עותק
// נפרד שעלול לסטות ממנו.
(function (root, factory) {
  if (typeof module === "object" && module.exports) {
    module.exports = factory();
  } else {
    root.AppLogic = factory();
  }
}(typeof self !== "undefined" ? self : this, function () {

  // ==== עזרי זמן ====
  const fmt = (ts) => new Date(ts).toLocaleString("he-IL", { weekday: "short", day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit" });
  const dateOnly = (ts) => new Date(ts).toLocaleDateString("he-IL", { day: "2-digit", month: "2-digit", year: "numeric" });
  const dayName = (ts) => new Date(ts).toLocaleDateString("he-IL", { weekday: "long" });
  function countdown(ms) {
    if (ms <= 0) return "פתוח";
    const d = Math.floor(ms/86400000), h = Math.floor((ms%86400000)/3600000), m = Math.floor((ms%3600000)/60000), s = Math.floor((ms%60000)/1000);
    if (d>0) return d+" ימים "+h+" שע׳";
    if (h>0) return h+":"+String(m).padStart(2,"0")+":"+String(s).padStart(2,"0");
    return m+":"+String(s).padStart(2,"0");
  }

  // ==== טלפון/שם/מייל ====
  function normPhone(raw){ let d=(raw||"").replace(/\D/g,""); if(d.startsWith("972")) d="0"+d.slice(3); return d; }
  function validName(name){ const parts=(name||"").trim().split(/\s+/).filter(Boolean); return parts.length>=2; }
  function normName(name){ return (name||"").trim().replace(/\s+/g," ").toLowerCase(); }
  const validPhone = (raw)=>{ const d=normPhone(raw); return d.length===10 && d.startsWith("05"); };
  const normEmail = (e)=>(e||"").trim().toLowerCase();
  const validEmail = (raw)=>/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test((raw||"").trim());
  const sameEmail = (a,b) => { const na=normEmail(a), nb=normEmail(b); return na!=="" && na===nb; };

  // בודק כפילות שם/טלפון/מייל מול שחקנים מאושרים ומול בקשות ממתינות (לא כולל בקשות שנדחו).
  // אם השם/טלפון תואמים לרשומה שכבר משויכת לאותו מייל — זה לא כפילות, זו התחברות חוזרת
  // לגיטימית (למשל אחרי ניקוי נתונים בדפדפן) — ולכן לא נחסם.
  // excludeReqId משמש כדי לא להתנגש עם הבקשה עצמה בעת אישורה.
  function findDuplicate(name, phone, email, roster, pending, excludeReqId){
    const nn = normName(name), np = normPhone(phone), ne = normEmail(email);
    const activePending = (pending||[]).filter(r=>r.status!=="rejected" && r.id!==excludeReqId);
    const allRecords = [...roster, ...activePending];

    const nameMatch = allRecords.find(r=>normName(r.name)===nn);
    if (nameMatch && nameMatch.email && !sameEmail(nameMatch.email, email)) return "השם הזה כבר קיים במערכת עם כתובת מייל אחרת. פנה למנהל.";

    const phoneMatch = allRecords.find(r=>r.phone===np);
    if (phoneMatch && phoneMatch.email && !sameEmail(phoneMatch.email, email)) return "מספר הטלפון הזה כבר קיים במערכת עם כתובת מייל אחרת. פנה למנהל.";

    if (ne) {
      const emailMatch = allRecords.find(r=>sameEmail(r.email, email));
      if (emailMatch && normName(emailMatch.name)!==nn) return "כתובת המייל הזו כבר משויכת לשחקן אחר במערכת. פנה למנהל.";
    }
    return null;
  }

  // ==== מיון עדיפות ====
  // שכבה: גניגרי+ותיק > גניגרי > ותיק > רגיל. בתוך כל שכבה — מספר ההגעות המצטבר
  // בפועל (attended=true) קובע: כל משחק שהשחקן הגיע אליו מוסיף לו עדיפות, בלי
  // תקרה/סף קבוע — לא "מתמיד כן/לא" חד-פעמי אלא דירוג רציף שממשיך להצטבר.
  function tierRank(reg, roster){
    const p = roster.find(r=>r.id===reg.player_id);
    if(!p) return 0;
    if (p.is_ganigari && p.is_vatik) return 3;
    if (p.is_ganigari) return 2;
    if (p.is_vatik) return 1;
    return 0;
  }
  function sortRegs(regs, roster, attendanceCounts){
    return [...regs].sort((a,b) => {
      const ra=tierRank(a,roster), rb=tierRank(b,roster);
      if (ra!==rb) return rb-ra;
      const ca=(attendanceCounts && attendanceCounts[a.player_id]) || 0;
      const cb=(attendanceCounts && attendanceCounts[b.player_id]) || 0;
      if (ca!==cb) return cb-ca;
      return a.ts-b.ts;
    });
  }

  return {
    fmt, dateOnly, dayName, countdown,
    normPhone, validName, normName, validPhone, normEmail, validEmail, sameEmail,
    findDuplicate, tierRank, sortRegs,
  };
}));
