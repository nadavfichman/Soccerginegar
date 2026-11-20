-- ============================================================================
-- Migration 0049 — שניידר יכול להחליף שחקנים בין קבוצות ולהוסיף שחקן
-- ============================================================================
-- המשתמש: "שניידר גם רצה שתהיה לו אפשרות להחליף בין שחקנים בכוחות...
-- שתהיה לו אפשרות גם להוסיף שחקן לכל קבוצה שהוא יזין שם. רוצה שתהיה לו
-- גישה מלאה מהבחינה הזאת." שאלנו במפורש אם השינוי צריך לגעת ב-game_teams
-- האמיתי (החלוקה הרשמית שאדמין קבע, שמשפיעה על חישובי כימיה/איזון
-- לעתיד) — המשתמש לא בחר עמדה מפורשת ("[No preference]"), אז הלכנו לפי
-- העיקרון שכבר נקבע מפורשות כמה פעמים בשיחה הזו: "אין שום קשר בין
-- הציונים של שניידר לציונים של הכוחות... אין לציוני שניידר שום השפעה
-- על הכוחות." בהתאם: שינויי שניידר (החלפה/הוספה/הסרה) *לעולם* לא נוגעים
-- ב-game_teams/registrations/player_grades — הם משנים רק את תמונת-המצב
-- העצמאית של הסיכום עצמו.
--
-- game_round_summary_ratings מקבלת שתי עמודות חדשות:
--   team smallint       — 1/2, עצמאי לגמרי מ-game_teams.team.
--   guest_name text     — לשחקן-אורח שהוזן ע"י שניידר/אדמין בתוך הסיכום
--                         בלבד (לא קשור ל-registrations.guest_name).
-- מהרגע שלמשחק יש ולו שורה אחת ב-game_round_summary_ratings, הטבלה הזו
-- היא מקור האמת היחיד למי-שיחק-באיזו-קבוצה באותו סיכום — game_teams
-- משמש רק כברירת מחדל ראשונית כשפותחים משחק שמעולם לא נערך (עדיין
-- אין בו אף שורת דירוג).
--
-- כדי שהמעבר הזה לא "יאבד" שחקנים: עד עכשיו summary_save שמר שורה רק
-- לשחקן עם ציון/גולים בפועל (ר' הפילטר בלקוח) — אחרי המעבר הזה חייבים
-- לשמור שורה לכל שחקן בחלוקה בכל שמירה (גם בלי ציון), אחרת הוא ייעלם
-- מהתצוגה ברגע שהטבלה הזו הופכת למקור היחיד. הסקריפט הזה משלים
-- (backfill) למחזורים קיימים את מה שהיה חסר, לפני שהקריאות עוברות
-- למקור החדש.

alter table game_round_summary_ratings add column if not exists team smallint;
alter table game_round_summary_ratings add column if not exists guest_name text;

-- השלמת team/guest_name על שורות קיימות (שחקן שכבר יש לו ציון/גולים
-- שמורים), לפי game_teams/registrations כפי שהם כרגע.
update game_round_summary_ratings rt
set team = gt.team, guest_name = reg.guest_name
from game_teams gt
left join registrations reg on reg.game_id = gt.game_id and reg.player_id = gt.player_id
where gt.game_id = rt.game_id and gt.player_id = rt.player_id and rt.team is null;

-- הוספת שורות חסרות (שחקנים שהיו בחלוקה אבל לא קיבלו ציון/גולים עד
-- עכשיו ולכן מעולם לא נשמרה להם שורה) — רק למחזורים שכבר יש להם סיכום.
insert into game_round_summary_ratings (game_id, player_id, team, guest_name, rating, goals)
select gt.game_id, gt.player_id, gt.team, reg.guest_name, null, 0
from game_teams gt
join game_round_summary grs on grs.game_id = gt.game_id
left join registrations reg on reg.game_id = gt.game_id and reg.player_id = gt.player_id
where not exists (
  select 1 from game_round_summary_ratings rt2
  where rt2.game_id = gt.game_id and rt2.player_id = gt.player_id
);

-- summary_get_draft: אם כבר יש שורות שמורות לסיכום הזה — הן מקור האמת
-- (כולל שחקנים שהוספו/הוחלפו ע"י שניידר ואינם ב-game_teams בכלל).
-- אחרת (משחק שמעולם לא נערך) — ברירת מחדל מ-game_teams, כמו קודם.
-- drop+create מפורש (לא רק create or replace) — ההרצה הראשונה של
-- המיגרציה הזו נכשלה עם "cannot change return type of existing
-- function / Row type defined by OUT parameters is different", סימן
-- שהחתימה שבאמת פרוסה ב-DB לא תאמה למה שהונח (אותה מחלקת-תקלה בדיוק
-- כמו עמודת goals/migrations 0046-0048) — drop+create שולל את זה לגמרי.
drop function if exists summary_get_draft(text, text, text, text, text);
create function summary_get_draft(input_summary_pw text, input_game_id text, input_pw text default null, input_phone text default null, input_pin text default null)
returns table(player_id text, team smallint, guest_name text, rating numeric, goals integer, narrative text, published boolean, team1_score integer, team2_score integer)
language plpgsql security definer as $$
declare v_has_rows boolean;
begin
  perform require_summary_access(input_summary_pw, input_pw, input_phone, input_pin);
  select exists(select 1 from game_round_summary_ratings where game_id = input_game_id) into v_has_rows;
  if v_has_rows then
    return query
      select rt.player_id, rt.team, rt.guest_name, rt.rating, rt.goals,
        coalesce(grs.narrative, ''), coalesce(grs.published, false),
        grs.team1_score, grs.team2_score
      from game_round_summary_ratings rt
      left join game_round_summary grs on grs.game_id = rt.game_id
      where rt.game_id = input_game_id;
  else
    return query
      select gt.player_id, gt.team, reg.guest_name, null::numeric, null::integer,
        coalesce(grs.narrative, ''), coalesce(grs.published, false),
        grs.team1_score, grs.team2_score
      from game_teams gt
      left join registrations reg on reg.game_id = gt.game_id and reg.player_id = gt.player_id
      left join game_round_summary grs on grs.game_id = gt.game_id
      where gt.game_id = input_game_id;
  end if;
end; $$;

-- summary_save: שומר team/guest_name לכל שורה (נשלחים מהלקוח לפי החלוקה
-- המקומית הנוכחית, אחרי כל החלפה/הוספה/הסרה) — שורה לכל שחקן, גם בלי
-- ציון/גולים (ר' הסבר למעלה — אחרת הוא ייעלם בטעינה הבאה).
create or replace function summary_save(input_summary_pw text, input_game_id text, input_narrative text, input_published boolean, input_ratings jsonb, input_team1_score integer default null, input_team2_score integer default null, input_pw text default null, input_phone text default null, input_pin text default null)
returns boolean language plpgsql security definer as $$
declare r jsonb;
begin
  perform require_summary_access(input_summary_pw, input_pw, input_phone, input_pin);
  insert into game_round_summary (game_id, narrative, published, team1_score, team2_score, updated_at)
    values (input_game_id, input_narrative, input_published, input_team1_score, input_team2_score, now())
    on conflict (game_id) do update set narrative = excluded.narrative, published = excluded.published,
      team1_score = excluded.team1_score, team2_score = excluded.team2_score, updated_at = now();
  delete from game_round_summary_ratings where game_id = input_game_id;
  for r in select * from jsonb_array_elements(input_ratings) loop
    insert into game_round_summary_ratings (game_id, player_id, team, guest_name, rating, goals)
      values (input_game_id, r->>'player_id', (r->>'team')::smallint, nullif(r->>'guest_name',''), (r->>'rating')::numeric, coalesce((r->>'goals')::integer, 0));
  end loop;
  return true;
end; $$;

-- קריאות (ציבוריות/אדמין) — מקור הנתונים עובר מ-game_teams ל-
-- game_round_summary_ratings (מקור האמת החדש לכל מחזור ששמור), כדי
-- שהחלפות/הוספות של שניידר יופיעו גם לשחקנים/אדמין. drop+create מפורש
-- לכל ה-RETURNS TABLE (לא רק create or replace) — ר' ההערה למעלה
-- ב-summary_get_draft: לא לוקחים סיכון עם חתימות שאולי לא תואמות
-- בפועל למה שבקבצי התיעוד.
drop function if exists get_round_summary_by_game(text);
create function get_round_summary_by_game(input_game_id text)
returns table(game_id text, kickoff bigint, narrative text, team1_score integer, team2_score integer, player_id text, team smallint, guest_name text, rating numeric, goals integer)
language plpgsql security definer as $$
begin
  return query
    select grs.game_id, g.kickoff, grs.narrative, grs.team1_score, grs.team2_score,
      rt.player_id, rt.team, rt.guest_name, rt.rating, rt.goals
    from game_round_summary grs
    join games g on g.id = grs.game_id
    join game_round_summary_ratings rt on rt.game_id = grs.game_id
    where grs.game_id = input_game_id and grs.published = true;
end; $$;
grant execute on function get_round_summary_by_game(text) to anon, authenticated;

drop function if exists get_published_round_summaries();
create function get_published_round_summaries()
returns table(game_id text, kickoff bigint, team1_score integer, team2_score integer)
language plpgsql security definer as $$
begin
  return query
    select distinct grs.game_id, g.kickoff, grs.team1_score, grs.team2_score
    from game_round_summary grs
    join games g on g.id = grs.game_id
    join game_round_summary_ratings rt on rt.game_id = grs.game_id
    where grs.published = true
    order by g.kickoff desc;
end; $$;
grant execute on function get_published_round_summaries() to anon, authenticated;

drop function if exists admin_get_round_summaries(text, text, text);
create function admin_get_round_summaries(input_pw text, input_phone text, input_pin text)
returns table(game_id text, kickoff bigint, team1_score integer, team2_score integer, narrative text, published boolean, player_id text, team smallint, guest_name text, rating numeric, goals integer)
language plpgsql security definer as $$
declare v_role text;
begin
  v_role := require_admin(input_pw, input_phone, input_pin);
  return query
    select grs.game_id, g.kickoff, grs.team1_score, grs.team2_score, grs.narrative, grs.published,
      rt.player_id, rt.team, rt.guest_name, rt.rating, rt.goals
    from game_round_summary grs
    join games g on g.id = grs.game_id
    join game_round_summary_ratings rt on rt.game_id = grs.game_id
    order by g.kickoff desc;
end; $$;

drop function if exists get_round_summary_latest();
create function get_round_summary_latest()
returns table(game_id text, kickoff bigint, narrative text, team1_score integer, team2_score integer, player_id text, team smallint, guest_name text, rating numeric)
language plpgsql security definer as $$
declare v_game_id text;
begin
  select grs.game_id into v_game_id
  from game_round_summary grs
  join games g on g.id = grs.game_id
  where grs.published = true
  order by g.kickoff desc
  limit 1;
  if v_game_id is null then return; end if;
  return query
    select grs.game_id, g.kickoff, grs.narrative, grs.team1_score, grs.team2_score,
      rt.player_id, rt.team, rt.guest_name, rt.rating
    from game_round_summary grs
    join games g on g.id = grs.game_id
    join game_round_summary_ratings rt on rt.game_id = grs.game_id
    where grs.game_id = v_game_id;
end; $$;
grant execute on function get_round_summary_latest() to anon, authenticated;

notify pgrst, 'reload schema';
