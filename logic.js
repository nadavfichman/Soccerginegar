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
  // אימוץ מדויק (לא ניחוש) של אלגוריתם האיזון של TeamPicker (אפליקציית
  // האח, DivideCollaboration) — נקרא קוד המקור הציבורי במפורש (ר' "עדכון 6"
  // ב-plan). לא DP — חיפוש Monte Carlo: 200 ניסיונות אקראיים של חלוקה
  // ל-2 קבוצות, ובכל ניסיון ציון-איזון משוקלל משלושה גורמים (דירוג/כימיה/
  // win-rate אישי), נבחר הניסיון עם הציון הכי נמוך (הכי קרוב ל-50% סיכוי
  // ניצחון לכל קבוצה). בלי פילוח תפקידים (שוער/בלם וכו') — לא קיים
  // ב-Soccerginegar, הבאקט "אחרים" של דרור מתנוון ממילא לערבוב-אקראי-ואז-slice.
  function shuffleArray(arr) {
    const a = [...arr];
    for (let i = a.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1));
      [a[i], a[j]] = [a[j], a[i]];
    }
    return a;
  }
  function sumGrade(players) { return players.reduce((s, p) => s + (p.grade || 0), 0); }

  // rows: [{player_id, teammate_id, games_with, wins_with, decisive_with}]
  // (מ-admin_get_player_chemistry) — שורת "עצמי" (teammate_id===player_id)
  // מקודדת win-rate אישי כללי, שאר השורות הן win-rate "ביחד עם" שותף ספציפי.
  function buildChemistryMap(rows) {
    const map = {};
    (rows || []).forEach(r => {
      if (!map[r.player_id]) map[r.player_id] = { ownWins: 0, ownDecisive: 0, with: {} };
      if (r.teammate_id === r.player_id) {
        map[r.player_id].ownWins = r.wins_with;
        map[r.player_id].ownDecisive = r.decisive_with;
      } else {
        map[r.player_id].with[r.teammate_id] = { wins: r.wins_with, decisive: r.decisive_with };
      }
    });
    return map;
  }
  function rate(wins, decisive) { return decisive > 0 ? Math.round(wins * 100 / decisive) : 0; }
  // "כימיה" קבוצתית: סכום win-rate האישי של כל שחקן ספציפית במשחקים שבהם
  // כל אחד מחבריו הנוכחיים לקבוצה היה חבר-קבוצה שלו בעבר (לא משנה נגד מי —
  // יחסי "נגד" קיימים אצל דרור אבל לא בשימוש בפועל בציון האיזון, אז גם כאן לא).
  function teamChemistry(chem, ids) {
    let wins = 0, decisive = 0;
    ids.forEach(id => {
      const p = chem[id]; if (!p) return;
      ids.forEach(other => {
        if (other === id) return;
        const w = p.with[other];
        if (w) { wins += w.wins; decisive += w.decisive; }
      });
    });
    return rate(wins, decisive);
  }
  function teamWinRate(chem, ids) {
    let wins = 0, decisive = 0;
    ids.forEach(id => { const p = chem[id]; if (p) { wins += p.ownWins; decisive += p.ownDecisive; } });
    return rate(wins, decisive);
  }
  // יחס שווה בין שלושת הגורמים (לפי בקשת המשתמש — לא ברירת המחדל 20/40/40 של דרור)
  const CHEM_WEIGHTS = { grade: 1 / 3, chemistry: 1 / 3, winRate: 1 / 3 };
  function balanceScore(chem, players, ids1, ids2) {
    const g1 = sumGrade(players.filter(p => ids1.includes(p.id)));
    const g2 = sumGrade(players.filter(p => ids2.includes(p.id)));
    // בלי נתונים (0 משחקים רלוונטיים) → ניטרלי 50%, לא 0 — כדי לא להטות
    const c1 = teamChemistry(chem, ids1) || 50, c2 = teamChemistry(chem, ids2) || 50;
    const w1 = teamWinRate(chem, ids1) || 50, w2 = teamWinRate(chem, ids2) || 50;
    const totalGrade = g1 + g2;
    const gradeAdv = totalGrade > 0 ? (g1 * 100 / totalGrade - 50) : 0;
    const weighted = (c1 - c2) * CHEM_WEIGHTS.chemistry + (w1 - w2) * CHEM_WEIGHTS.winRate + gradeAdv * CHEM_WEIGHTS.grade;
    const prob = Math.max(20, Math.min(80, Math.round(50 + weighted)));
    return Math.abs(prob - 50);
  }
  function splitTeamsByChemistry(players, chemistry, attempts) {
    if (!players || players.length === 0) return { team1: [], team2: [] };
    const chem = chemistry || {};
    const n = attempts || 200;
    let best = null, bestScore = Infinity;
    for (let i = 0; i < n; i++) {
      const shuffled = shuffleArray(players);
      const half = Math.ceil(shuffled.length / 2);
      const team1 = shuffled.slice(0, half), team2 = shuffled.slice(half);
      const score = balanceScore(chem, players, team1.map(p => p.id), team2.map(p => p.id));
      if (score < bestScore) { bestScore = score; best = { team1, team2 }; }
    }
    return best;
  }

  return {
    fmt, fmtDateTime, fmtTime, dateOnly, dayName, countdown,
    normPhone, validName, normName, validPhone, normEmail, validEmail, sameEmail,
    findDuplicate, tierRank, sortRegs, buildChemistryMap, splitTeamsByChemistry,
  };
}));
