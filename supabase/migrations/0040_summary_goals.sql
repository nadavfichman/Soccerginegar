-- ============================================================================
-- Migration 0040 — גולים לכל שחקן בסיכום שניידר (-5 עד 10)
-- ============================================================================
-- המשתמש: "אני רוצה להוסיף בסיכום ליד כל שחקן שתהיה אפשרות לרשום
-- כמה גולים הבקיע, מספרים שלמים, שתהיה מגבלה בין -5 ל-10 (כי יש
-- גם גול עצמי)." טווח שלילי מאפשר לתעד גול עצמי כ"גולים שליליים"
-- לאותו שחקן. אכיפה בצד השרת (check constraint), לא רק ב-UI —
-- אותו עיקרון בדיוק כמו טווח הציונים (migrations/0039).
--
-- goals הוא עמודה נפרדת מ-rating על אותה שורה (game_id, player_id) —
-- שחקן יכול לקבל ציון בלי גולים (רוב השחקנים) או (לכאורה) גם גולים
-- בלי ציון, ולכן rating הופך מ-not null לניתן ל-null.
-- ============================================================================

alter table game_round_summary_ratings alter column rating drop not null;
alter table game_round_summary_ratings add column if not exists goals integer;

alter table game_round_summary_ratings drop constraint if exists game_round_summary_ratings_rating_check;
alter table game_round_summary_ratings add constraint game_round_summary_ratings_rating_check
  check (rating is null or (rating >= 0 and rating <= 10 and rating*2 = floor(rating*2)));

alter table game_round_summary_ratings drop constraint if exists game_round_summary_ratings_goals_check;
alter table game_round_summary_ratings add constraint game_round_summary_ratings_goals_check
  check (goals is null or (goals >= -5 and goals <= 10));

-- שינוי טיפוס ההחזרה (הוספת goals) — דורש drop+create.
drop function if exists summary_get_draft(text, text, text, text, text);
create or replace function summary_get_draft(input_summary_pw text, input_game_id text, input_pw text default null, input_phone text default null, input_pin text default null)
returns table(player_id text, team smallint, guest_name text, rating numeric, goals integer, narrative text, published boolean, team1_score integer, team2_score integer)
language plpgsql security definer as $$
begin
  perform require_summary_access(input_summary_pw, input_pw, input_phone, input_pin);
  return query
    select gt.player_id, gt.team, reg.guest_name, rt.rating, rt.goals,
      coalesce(grs.narrative, ''), coalesce(grs.published, false),
      grs.team1_score, grs.team2_score
    from game_teams gt
    left join game_round_summary_ratings rt on rt.game_id = gt.game_id and rt.player_id = gt.player_id
    left join registrations reg on reg.game_id = gt.game_id and reg.player_id = gt.player_id
    left join game_round_summary grs on grs.game_id = gt.game_id
    where gt.game_id = input_game_id;
end; $$;

-- אותה חתימה (עדיין jsonb אחד לרשימת הציונים/גולים) — רק הגוף משתנה,
-- create or replace רגיל בלי drop.
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
    insert into game_round_summary_ratings (game_id, player_id, rating, goals)
      values (input_game_id, r->>'player_id', (r->>'rating')::numeric, (r->>'goals')::integer);
  end loop;
  return true;
end; $$;

-- טאב האדמין "סיכומי שניידר" — מציג גם גולים לצד הציון לכל שחקן.
drop function if exists admin_get_round_summaries(text, text, text);
create or replace function admin_get_round_summaries(input_pw text, input_phone text, input_pin text)
returns table(game_id text, kickoff bigint, team1_score integer, team2_score integer, narrative text, published boolean, player_id text, team smallint, guest_name text, rating numeric, goals integer)
language plpgsql security definer as $$
declare v_role text;
begin
  v_role := require_admin(input_pw, input_phone, input_pin);
  return query
    select grs.game_id, g.kickoff, grs.team1_score, grs.team2_score, grs.narrative, grs.published,
      gt.player_id, gt.team, reg.guest_name, rt.rating, rt.goals
    from game_round_summary grs
    join games g on g.id = grs.game_id
    join game_teams gt on gt.game_id = grs.game_id
    left join game_round_summary_ratings rt on rt.game_id = grs.game_id and rt.player_id = gt.player_id
    left join registrations reg on reg.game_id = grs.game_id and reg.player_id = gt.player_id
    order by g.kickoff desc;
end; $$;
