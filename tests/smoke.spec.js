// בדיקת עשן בסיסית — לא מחליפה בדיקה ידנית, רק תופסת קריסות ברורות
// (שגיאת JSX, קריאת RPC שנשברה, קובץ חסר) לפני שמישהו מה-70 נתקל בהן.
// ר' CHECKLIST.md לרשימת הבדיקה המלאה לפני push.
const { test, expect } = require('@playwright/test');

test('האתר נטען בלי שגיאות קונסולה ומציג תוכן אמיתי', async ({ page }) => {
  const errors = [];
  page.on('console', (msg) => { if (msg.type() === 'error') errors.push(msg.text()); });
  page.on('pageerror', (err) => errors.push(String(err)));

  await page.goto('/');

  // Header (עם שם הקבוצה) מוצג רק אחרי ש-loaded && identityLoaded הפכו true —
  // כלומר טעינת הנתונים מ-Supabase הצליחה ו-React רינדר תוכן אמיתי, לא רק "טוען…"
  await expect(page.getByText("כדורגל גניגרי ושות'").first()).toBeVisible({ timeout: 20000 });

  expect(errors, 'שגיאות קונסולה/עמוד בזמן הטעינה:\n' + errors.join('\n')).toEqual([]);
});

test('manifest.json תקין ונגיש', async ({ request, baseURL }) => {
  const res = await request.get(new URL('manifest.json', baseURL).toString());
  expect(res.ok()).toBeTruthy();
  const body = await res.json();
  expect(body.name).toBeTruthy();
  expect(Array.isArray(body.icons) && body.icons.length).toBeTruthy();
});

test('Service Worker נגיש', async ({ request, baseURL }) => {
  const res = await request.get(new URL('sw.js', baseURL).toString());
  expect(res.ok()).toBeTruthy();
});
