-- ============================================================================
-- Migration 0038 — לשניידר תוצאה משלו, לא תלוי בתוצאה שהאדמין מזין
-- ============================================================================
-- המשתמש: "הבעיה היא ששניידר לפעמים רושם את הסיכום לפני שאני רושם
-- את התוצאה... מבקש שיהיה אפשרות לשניידר למעלה לרשום תוצאת המשחק,
-- כחולים כתומים... לא להסתמך על התוצאה שלי, אנחנו לא עושים את זה
-- באותו זמן, וגם לא חשוב שזה יהיה מתאים."
--
-- עד עכשיו summary_get_recent_games/summary_get_draft/admin_get_round_summaries
-- שאבו את התוצאה מ-game_results (התוצאה הרשמית של האדמין) — מה שיצר
-- תלות-סדר לא רצויה. עכשיו ל-game_round_summary יש עמודות תוצאה
-- משלה, שניידר קובע אותן בעצמו, לגמרי בלי קשר ל-game_results — אותו
-- עיקרון בדיוק כמו הציונים (לתצוגה/פרסום בלבד, לא "רשמי"). הרשימה
-- לבחירת משחק גם לא דורשת יותר תוצאה רשמית קיימת — רק חלוקה לקבוצות
-- שמורה (game_teams), כדי ששניידר יוכל לכתוב אפילו לפני שהאדמין הזין
-- משהו.
-- ============================================================================

alter table game_round_summary add column if not exists team1_score integer;
alter table game_round_summary add column if not exists team2_score integer;

-- רשימת המשחקים לבחירה: לפי חלוקה שמורה (game_teams), לא לפי תוצאה
-- רשמית קיימת (game_results) — כדי שניידר יוכל לבחור משחק גם לפני
-- שהאדמין הזין תוצאה.
create or replace function summary_get_recent_games(input_summary_pw text, input_pw text default null, input_phone text default null, input_pin text default null)
returns table(game_id text, kickoff bigint, team1_score integer, team2_score integer, published boolean)
language plpgsql security definer as $$
begin
  perform require_summary_access(input_summary_pw, input_pw, input_phone, input_pin);
  return query
    select distinct g.id, g.kickoff, grs.team1_score, grs.team2_score, coalesce(grs.published, false)
    from games g
    join game_teams gt on gt.game_id = g.id
    left join game_round_summary grs on grs.game_id = g.id
    order by g.kickoff desc
    limit 10;
end; $$;

-- התוצאה חוזרת עכשיו מ-game_round_summary (התוצאה של שניידר עצמו),
-- לא מ-game_results.
create or replace function summary_get_draft(input_summary_pw text, input_game_id text, input_pw text default null, input_phone text default null, input_pin text default null)
returns table(player_id text, team smallint, guest_name text, rating numeric, narrative text, published boolean, team1_score integer, team2_score integer)
language plpgsql security definer as $$
begin
  perform require_summary_access(input_summary_pw, input_pw, input_phone, input_pin);
  return query
    select gt.player_id, gt.team, reg.guest_name, rt.rating,
      coalesce(grs.narrative, ''), coalesce(grs.published, false),
      grs.team1_score, grs.team2_score
    from game_teams gt
    left join game_round_summary_ratings rt on rt.game_id = gt.game_id and rt.player_id = gt.player_id
    left join registrations reg on reg.game_id = gt.game_id and reg.player_id = gt.player_id
    left join game_round_summary grs on grs.game_id = gt.game_id
    where gt.game_id = input_game_id;
end; $$;

-- input_team1_score/input_team2_score חדשים — חתימה שונה (10 פרמטרים
-- במקום 8), אז דרוש drop לגרסה הישנה קודם (אותה קונבנציה כמו migrations/0035
-- על admin_create_game) כדי לא להשאיר שתי גרסאות-עומס מתנגשות.
drop function if exists summary_save(text, text, text, boolean, jsonb, text, text, text);
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
    insert into game_round_summary_ratings (game_id, player_id, rating)
      values (input_game_id, r->>'player_id', (r->>'rating')::numeric);
  end loop;
  return true;
end; $$;

-- שינוי טיפוס החזרה (הוספת team1_score/team2_score) — דורש drop+create,
-- לא create or replace בלבד. נקראת רק בלחיצה על הרחבת הבאנר לשחקן
-- (lazy, לא unconditional-on-load) — בטוח לפרוס קוד+SQL יחד.
drop function if exists get_round_summary_latest();
create or replace function get_round_summary_latest()
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
      gt.player_id, gt.team, reg.guest_name, rt.rating
    from game_round_summary grs
    join games g on g.id = grs.game_id
    join game_teams gt on gt.game_id = grs.game_id
    left join game_round_summary_ratings rt on rt.game_id = grs.game_id and rt.player_id = gt.player_id
    left join registrations reg on reg.game_id = grs.game_id and reg.player_id = gt.player_id
    where grs.game_id = v_game_id;
end; $$;
grant execute on function get_round_summary_latest() to anon, authenticated;

-- התוצאה בטאב האדמין גם היא מ-game_round_summary עכשיו, לא מ-game_results.
create or replace function admin_get_round_summaries(input_pw text, input_phone text, input_pin text)
returns table(game_id text, kickoff bigint, team1_score integer, team2_score integer, narrative text, published boolean, player_id text, team smallint, guest_name text, rating numeric)
language plpgsql security definer as $$
declare v_role text;
begin
  v_role := require_admin(input_pw, input_phone, input_pin);
  return query
    select grs.game_id, g.kickoff, grs.team1_score, grs.team2_score, grs.narrative, grs.published,
      gt.player_id, gt.team, reg.guest_name, rt.rating
    from game_round_summary grs
    join games g on g.id = grs.game_id
    join game_teams gt on gt.game_id = grs.game_id
    left join game_round_summary_ratings rt on rt.game_id = grs.game_id and rt.player_id = gt.player_id
    left join registrations reg on reg.game_id = grs.game_id and reg.player_id = gt.player_id
    order by g.kickoff desc;
end; $$;
