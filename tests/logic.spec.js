// בדיקות יחידה ללוגיקה העסקית הטהורה (logic.js) — רצות ישירות ב-Node,
// בלי דפדפן, כי אין תלות ב-React/DOM. זה בדיוק המקום שבו באג שקט הכי יקר:
// סדר עדיפות שגוי או זיהוי כפילות שגוי לא "קורס" את האתר (ה-smoke test
// לא יתפוס את זה), אבל גורם למחלוקות אמיתיות עם שחקנים.
const { test } = require("node:test");
const assert = require("node:assert/strict");
const {
  normPhone, validName, normName, validPhone, normEmail, validEmail, sameEmail,
  findDuplicate, tierRank, sortRegs, splitTeamsByGrade,
} = require("../logic.js");

// ---- טלפון/שם/מייל ----

test("normPhone: ממיר קידומת בינלאומית לפורמט מקומי", () => {
  assert.equal(normPhone("972501234567"), "0501234567");
  assert.equal(normPhone("0501234567"), "0501234567");
  assert.equal(normPhone("050-123-4567"), "0501234567");
  assert.equal(normPhone(""), "");
});

test("validPhone: מקבל רק מספרי 05X בני 10 ספרות", () => {
  assert.equal(validPhone("0501234567"), true);
  assert.equal(validPhone("972501234567"), true); // מנורמל לפני הבדיקה
  assert.equal(validPhone("0261234567"), false); // לא מתחיל ב-05
  assert.equal(validPhone("050123456"), false); // קצר מדי
  assert.equal(validPhone(""), false);
});

test("validName: דורש לפחות שם פרטי ושם משפחה", () => {
  assert.equal(validName("ישראל ישראלי"), true);
  assert.equal(validName("  ישראל   ישראלי  "), true);
  assert.equal(validName("ישראל"), false);
  assert.equal(validName(""), false);
});

test("normName: מנרמל רווחים וגודל אותיות", () => {
  assert.equal(normName("  ישראל   ישראלי "), "ישראל ישראלי");
});

test("validEmail / sameEmail", () => {
  assert.equal(validEmail("a@b.com"), true);
  assert.equal(validEmail("not-an-email"), false);
  assert.equal(sameEmail("A@B.com", "a@b.com "), true);
  assert.equal(sameEmail("a@b.com", "c@d.com"), false);
  assert.equal(sameEmail("", ""), false); // מייל ריק לעולם לא "אותו מייל"
});

// ---- findDuplicate ----

test("findDuplicate: חוסם שם זהה עם מייל שונה", () => {
  const roster = [{ name: "דני כהן", phone: "0501111111", email: "dani@x.com" }];
  const err = findDuplicate("דני כהן", "0502222222", "other@x.com", roster, [], null);
  assert.match(err, /השם הזה כבר קיים/);
});

test("findDuplicate: חוסם טלפון זהה עם מייל שונה", () => {
  const roster = [{ name: "דני כהן", phone: "0501111111", email: "dani@x.com" }];
  const err = findDuplicate("מישהו אחר", "0501111111", "other@x.com", roster, [], null);
  assert.match(err, /מספר הטלפון הזה כבר קיים/);
});

test("findDuplicate: חוסם מייל זהה עם שם שונה", () => {
  const roster = [{ name: "דני כהן", phone: "0501111111", email: "dani@x.com" }];
  const err = findDuplicate("מישהו אחר", "0509999999", "dani@x.com", roster, [], null);
  assert.match(err, /כתובת המייל הזו כבר משויכת/);
});

test("findDuplicate: לא חוסם כשזה אותו אדם ממש (שם+טלפון+מייל תואמים) — התחברות חוזרת", () => {
  const roster = [{ name: "דני כהן", phone: "0501111111", email: "dani@x.com" }];
  const err = findDuplicate("דני כהן", "0501111111", "dani@x.com", roster, [], null);
  assert.equal(err, null);
});

test("findDuplicate: לא חוסם שחקן שהוזן ידנית בלי מייל מקושר (מאפשר קישור אוטומטי)", () => {
  const roster = [{ name: "דני כהן", phone: "0501111111", email: null }];
  const err = findDuplicate("דני כהן", "0501111111", "dani@x.com", roster, [], null);
  assert.equal(err, null);
});

// ---- tierRank / sortRegs ----

const roster = [
  { id: "p1", name: "רגיל",        is_ganigari: false, is_vatik: false },
  { id: "p2", name: "ותיק",        is_ganigari: false, is_vatik: true  },
  { id: "p3", name: "גניגרי",      is_ganigari: true,  is_vatik: false },
  { id: "p4", name: "גניגרי+ותיק", is_ganigari: true,  is_vatik: true  },
];

test("tierRank: גניגרי+ותיק > ותיק > גניגרי > רגיל", () => {
  const rank = (id) => tierRank({ player_id: id }, roster);
  assert.ok(rank("p4") > rank("p2"));
  assert.ok(rank("p2") > rank("p3"));
  assert.ok(rank("p3") > rank("p1"));
});

test("sortRegs: ממיין לפי שכבה קודם, בלי קשר לזמן הרשמה", () => {
  const regs = [
    { player_id: "p1", ts: 1 },  // רגיל, נרשם ראשון
    { player_id: "p4", ts: 100 }, // גניגרי+ותיק, נרשם אחרון
  ];
  const sorted = sortRegs(regs, roster);
  assert.equal(sorted[0].player_id, "p4", "גניגרי+ותיק צריך להיות ראשון למרות שנרשם מאוחר יותר");
});

test("sortRegs: בתוך אותה שכבה, יותר הגעות מנצח, בלי תלות בזמן הרשמה", () => {
  const regs = [
    { player_id: "p1", ts: 1 },   // רגיל, נרשם ראשון, 0 הגעות
    { player_id: "p2", ts: 100 }, // ותיק, נרשם מאוחר — אבל שכבה גבוהה יותר ממילא
  ];
  const roster2 = [
    { id: "p1", name: "א", is_ganigari: false, is_vatik: false },
    { id: "p5", name: "ב", is_ganigari: false, is_vatik: false },
  ];
  const sameTierRegs = [
    { player_id: "p1", ts: 1 },  // 0 הגעות, נרשם ראשון
    { player_id: "p5", ts: 2 },  // 5 הגעות, נרשם שני
  ];
  const sorted = sortRegs(sameTierRegs, roster2, { p5: 5, p1: 0 });
  assert.equal(sorted[0].player_id, "p5", "מי שהגיע יותר פעמים צריך לנצח בתוך אותה שכבה, למרות שנרשם מאוחר יותר");
});

test("sortRegs: בלי attendanceCounts, זמן הרשמה שובר שוויון בתוך אותה שכבה", () => {
  const roster2 = [
    { id: "a", name: "א", is_ganigari: false, is_vatik: false },
    { id: "b", name: "ב", is_ganigari: false, is_vatik: false },
  ];
  const regs = [
    { player_id: "b", ts: 50 },
    { player_id: "a", ts: 10 },
  ];
  const sorted = sortRegs(regs, roster2);
  assert.deepEqual(sorted.map(r=>r.player_id), ["a", "b"]);
});

// ---- splitTeamsByGrade ----

test("splitTeamsByGrade: גדלי הקבוצות תקינים (זוגי)", () => {
  const players = [1,2,3,4,5,6].map(i => ({ id: "p"+i, grade: 50 }));
  const { team1, team2 } = splitTeamsByGrade(players);
  assert.equal(team1.length, 3);
  assert.equal(team2.length, 3);
});

test("splitTeamsByGrade: גדלי הקבוצות תקינים (אי-זוגי — העודף לקבוצה 1)", () => {
  const players = [1,2,3,4,5].map(i => ({ id: "p"+i, grade: 50 }));
  const { team1, team2 } = splitTeamsByGrade(players);
  assert.equal(team1.length, 3);
  assert.equal(team2.length, 2);
});

test("splitTeamsByGrade: מוצא חלוקה מאוזנת מושלמת כשהיא קיימת", () => {
  // 10+40=50 מול 20+30=50 — הפרש 0 אמור להימצא כמעט תמיד תוך 200 ניסיונות
  const players = [
    { id: "a", grade: 10 }, { id: "b", grade: 20 },
    { id: "c", grade: 30 }, { id: "d", grade: 40 },
  ];
  const { team1, team2 } = splitTeamsByGrade(players, 200);
  const sum = (t) => t.reduce((s,p)=>s+p.grade, 0);
  assert.equal(Math.abs(sum(team1) - sum(team2)), 0);
});

test("splitTeamsByGrade: לא מאבד ולא משכפל שחקנים", () => {
  const players = [1,2,3,4,5,6,7].map(i => ({ id: "p"+i, grade: 40+i }));
  const { team1, team2 } = splitTeamsByGrade(players);
  const ids = [...team1, ...team2].map(p=>p.id).sort();
  assert.deepEqual(ids, players.map(p=>p.id).sort());
});

test("splitTeamsByGrade: רשימה ריקה לא קורסת", () => {
  const { team1, team2 } = splitTeamsByGrade([]);
  assert.deepEqual(team1, []);
  assert.deepEqual(team2, []);
});
