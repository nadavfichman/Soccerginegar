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
  // כמו fmt, בלי שם היום — לשימוש רק כשdayName כבר מוצג צמוד (אחרת כפילות: "יום שישי" + "יום ו', 18.09")
  const fmtDateTime = (ts) => new Date(ts).toLocaleString("he-IL", { day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit" });
  // שעה בלבד — לשימוש כש-dayName כבר מוצג צמוד וגם התאריך מיותר (לא רק שם היום)
  const fmtTime = (ts) => new Date(ts).toLocaleTimeString("he-IL", { hour: "2-digit", minute: "2-digit" });
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
  // שכבה: גניגרי+ותיק > ותיק > גניגרי > רגיל. בתוך כל שכבה — מספר ההגעות המצטבר
  // בפועל (attended=true) קובע: כל משחק שהשחקן הגיע אליו מוסיף לו עדיפות, בלי
  // תקרה/סף קבוע — לא "מתמיד כן/לא" חד-פעמי אלא דירוג רציף שממשיך להצטבר.
  function tierRank(reg, roster){
    const p = roster.find(r=>r.id===reg.player_id);
    if(!p) return 0;
    if (p.is_ganigari && p.is_vatik) return 3;
    if (p.is_vatik) return 2;
    if (p.is_ganigari) return 1;
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

  // ==== חלוקת כוחות ====
  // בלי פילוח תפקידים (שוער/בלם וכו', לא קיים ב-Soccerginegar) — שלב A בלבד.
  // פתרון מדויק (לא היוריסטי): "לחלק n שחקנים לתת-קבוצה בגודל קבוע עם סכום
  // הכי קרוב לחצי" הוא subset-sum עם מגבלת גודל — פותר בתכנון דינמי, לא
  // ניחוש-אקראי-הכי-טוב. בגבולות האפליקציה (MAX_PLAYERS=22, דירוג 1-99)
  // טבלת ה-DP קטנה (עד כ-11×2178 תאים) ורצה באלפיות שנייה.
  function shuffleArray(arr) {
    const a = [...arr];
    for (let i = a.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1));
      [a[i], a[j]] = [a[j], a[i]];
    }
    return a;
  }
  function sumGrade(players) { return players.reduce((s, p) => s + (p.grade || 0), 0); }
  function splitTeamsByGrade(players) {
    if (!players || players.length === 0) return { team1: [], team2: [] };
    // shuffle לפני ה-DP כדי ש"ערבב מחדש" ימשיך לתת חלוקות-שחקנים שונות
    // כשיש כמה פתרונות אופטימליים שווי-הפרש — אבל הסכום עצמו תמיד אופטימלי.
    const shuffled = shuffleArray(players);
    const n = shuffled.length, size1 = Math.ceil(n / 2);
    const grades = shuffled.map(p => p.grade || 0);
    const total = sumGrade(shuffled);
    // dp[k][s] = האם קיימת תת-קבוצה בגודל k עם סכום s (מבין הפריטים שעובדו עד כה)
    // from[k][s] = אינדקס הפריט שבזכותו הגענו לראשונה ל-(k,s) — לשחזור התת-קבוצה
    const dp = Array.from({ length: size1 + 1 }, () => new Array(total + 1).fill(false));
    const from = Array.from({ length: size1 + 1 }, () => new Array(total + 1).fill(-1));
    dp[0][0] = true;
    for (let i = 0; i < n; i++) {
      const g = grades[i];
      for (let k = Math.min(i + 1, size1); k >= 1; k--) {
        for (let s = total; s >= g; s--) {
          if (!dp[k][s] && dp[k - 1][s - g]) { dp[k][s] = true; from[k][s] = i; }
        }
      }
    }
    let bestS = 0, bestDiff = Infinity;
    for (let s = 0; s <= total; s++) {
      if (dp[size1][s]) { const diff = Math.abs(total - 2 * s); if (diff < bestDiff) { bestDiff = diff; bestS = s; } }
    }
    const idx1 = new Set();
    let k = size1, s = bestS;
    while (k > 0) { const i = from[k][s]; idx1.add(i); s -= grades[i]; k--; }
    const team1 = shuffled.filter((_, i) => idx1.has(i));
    const team2 = shuffled.filter((_, i) => !idx1.has(i));
    return { team1, team2 };
  }

  return {
    fmt, fmtDateTime, fmtTime, dateOnly, dayName, countdown,
    normPhone, validName, normName, validPhone, normEmail, validEmail, sameEmail,
    findDuplicate, tierRank, sortRegs, splitTeamsByGrade,
  };
}));
