// Service Worker מינימלי — קיים רק כדי לעמוד בקריטריון ההתקנה של הדפדפן
// (Chrome/Android דורש SW עם מאזין fetch כדי להציג את "הוסף למסך הבית").
// לא עושה caching בכוונה, כדי לא לעכב עדכונים לאפליקציה.
self.addEventListener("install", () => self.skipWaiting());
self.addEventListener("activate", (event) => event.waitUntil(self.clients.claim()));
self.addEventListener("fetch", () => {});
