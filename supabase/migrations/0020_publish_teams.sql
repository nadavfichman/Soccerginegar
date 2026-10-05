-- ============================================================================
-- Migration 0020 — פרסום חלוקת הכוחות לשחקנים בתוך האפליקציה (2026-10-05)
-- ============================================================================
-- עד כה חלוקת הכוחות הייתה גלויה רק לאדמין (פאנל החלוקה) ולמי שקיבל את
-- תמונת הוואטסאפ המשותפת. המשתמש רוצה שהיא תוצג גם בתוך Soccerginegar עצמה
-- לשחקנים, באותו מקום שבו TeamPicker מציג זאת (ר' שיחה עם המשתמש).
--
-- נראות לפי קבוצה (ראשית/משנית) כבר נאכפת ברמת כל המשחק (PlayerView מסנן
-- לפי visible_to_primary/visible_to_secondary) — GameCard כולו לא מרונדר
-- למשחק שהשחקן לא אמור לראות, אז כל מה שמוסיפים בתוכו (כולל הצגת כוחות)
-- יורש את אותה הגבלה בלי קוד נוסף.
--
-- דפוס זהה בדיוק ל-roster_published/admin_set_roster_published: שליטת
-- אדמין מפורשת (לא אוטומטי ברגע שומרים חלוקה, כדי לא לחשוף בזמן עריכה).
--
-- game_teams עצמה נשארת נעולה לגמרי (בלי policy, בלי grant select) —
-- get_published_teams הוא הנתיב הציבורי היחיד, ובודק teams_published
-- בפנים לפני שמחזיר שורות (אחרת ריק). בלי דירוג/ציון בחתימה — game_teams
-- לא מכילה את זה בכלל, אותה רמת חשיפה כמו תמונת הוואטסאפ היום.
-- ============================================================================

alter table games add column if not exists teams_published boolean not null default false;

create or replace function admin_set_teams_published(input_game_id text, input_value boolean, input_pw text, input_phone text, input_pin text)
returns boolean language plpgsql security definer as $$
declare v_role text;
begin
  v_role := require_admin(input_pw, input_phone, input_pin);
  update games set teams_published = input_value where id = input_game_id;
  perform log_admin_action(v_role, coalesce(input_phone,'super'), 'admin_set_teams_published', jsonb_build_object('game_id', input_game_id, 'value', input_value));
  return true;
end; $$;

-- קריאה ציבורית (anon/authenticated, בלי אישורי אדמין) — בכוונה, כדי
-- שכל שחקן שרואה את המשחק (דרך הסינון הקיים) יוכל לראות את הכוחות בלי
-- להזדקק לאישורי ניהול. require_admin לא נקרא כאן בכוונה.
create or replace function get_published_teams(input_game_id text)
returns table(player_id text, team smallint)
language plpgsql security definer as $$
begin
  if not exists (select 1 from games where id = input_game_id and teams_published = true) then
    return;
  end if;
  return query select gt.player_id, gt.team from game_teams gt where gt.game_id = input_game_id;
end; $$;

grant execute on function get_published_teams(text) to anon, authenticated;
