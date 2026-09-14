#!/usr/bin/env node
// אוטומציה לחלק מ-CHECKLIST.md (סעיפים 1/2/5) — רץ ב-CI על כל push, כדי
// שבדיקה שנשכחה ידנית לא תגיע ל-main. סעיפים 3/4/6/7 נשארים ידניים במכוון
// (שיפוט אנושי, או דורשים גישה בפועל ל-Supabase/לאתר החי).
const fs = require("fs");
let failed = false;

function fail(msg) { console.error("FAIL: " + msg); failed = true; }
function ok(msg) { console.log("OK: " + msg); }

// 1. תחביר JSX תקין — index.html מתקומפל בדפדפן בזמן ריצה (Babel Standalone),
// אז שגיאת תחביר לא נתפסת עד שמישהו פותח את הדף ורואה מסך לבן.
try {
  const babel = require("@babel/standalone");
  const html = fs.readFileSync("index.html", "utf8");
  const match = html.match(/<script type="text\/babel"[^>]*>([\s\S]*?)<\/script>/);
  if (!match) throw new Error('לא נמצאה תגית <script type="text/babel"> ב-index.html');
  babel.transform(match[1], { presets: ["react"] });
  ok("תחביר JSX תקין (index.html)");
} catch (e) {
  fail("שגיאת תחביר ב-index.html: " + e.message);
}

// 2. אין כתיבה ישירה לטבלה שעוקפת RPC/RLS (db.from(...).insert/update/delete —
// מותר רק .select(...), ר' CLAUDE.md "באגים משמעותיים" #3).
try {
  const html = fs.readFileSync("index.html", "utf8");
  const badCalls = html.match(/db\.from\([^)]*\)\.(insert|update|delete)\(/g) || [];
  if (badCalls.length > 0) {
    fail("נמצאה כתיבה ישירה לטבלה שעוקפת RPC/RLS: " + badCalls.join(", "));
  } else {
    ok("אין כתיבה ישירה לטבלה (db.from(...).insert/update/delete)");
  }
} catch (e) {
  fail("בדיקת db.from נכשלה: " + e.message);
}

// 5. manifest.json תקין
try {
  JSON.parse(fs.readFileSync("manifest.json", "utf8"));
  ok("manifest.json תקין");
} catch (e) {
  fail("manifest.json לא תקין: " + e.message);
}

if (failed) {
  console.error("\nכשל בבדיקות CHECKLIST.md האוטומטיות — ר' CHECKLIST.md לפרטים.");
  process.exit(1);
} else {
  console.log("\nכל בדיקות ה-CHECKLIST האוטומטיות עברו.");
}
