-- ============================================================================
-- Migration 0048 — הגדרה-מחדש כפויה (drop+create) של ה-RPCs הציבוריים
-- ============================================================================
-- אימתנו ישירות במסד הנתונים שהנתונים תקינים לגמרי (teams_count=23,
-- ratings_count=22, published=true לאותו game_id) — אין שום בעיית
-- נתונים. בכל זאת get_round_summary_by_game ממשיכה להחזיר 0 שורות,
-- גם אחרי NOTIFY pgrst ורענון מלא של הדף בצד הלקוח. "create or
-- replace" אמור להספיק, אבל כדי לשלול לגמרי אפשרות של overload ישן/
-- תקוע או הגדרה חלקית שלא השתכללה כמו שצריך בפעם הראשונה, מפילים
-- במפורש ובונים מחדש את כל ה-RPCs הציבוריים (ללא סיסמה) שמעורבים
-- בתצוגת השחקן, ואת admin_get_summary_stats (שגם היא החזירה ריק).
-- ============================================================================

drop function if exists get_published_round_summaries();
create function get_published_round_summaries()
returns table(game_id text, kickoff bigint, team1_score integer, team2_score integer)
language plpgsql security definer as $$
begin
  return query
    select distinct grs.game_id, g.kickoff, grs.team1_score, grs.team2_score
    from game_round_summary grs
    join games g on g.id = grs.game_id
    join game_teams gt on gt.game_id = grs.game_id
    where grs.published = true
    order by g.kickoff desc;
end; $$;
grant execute on function get_published_round_summaries() to anon, authenticated;

drop function if exists get_round_summary_by_game(text);
create function get_round_summary_by_game(input_game_id text)
returns table(game_id text, kickoff bigint, narrative text, team1_score integer, team2_score integer, player_id text, team smallint, guest_name text, rating numeric, goals integer)
language plpgsql security definer as $$
begin
  return query
    select grs.game_id, g.kickoff, grs.narrative, grs.team1_score, grs.team2_score,
      gt.player_id, gt.team, reg.guest_name, rt.rating, rt.goals
    from game_round_summary grs
    join games g on g.id = grs.game_id
    join game_teams gt on gt.game_id = grs.game_id
    left join game_round_summary_ratings rt on rt.game_id = grs.game_id and rt.player_id = gt.player_id
    left join registrations reg on reg.game_id = grs.game_id and reg.player_id = gt.player_id
    where grs.game_id = input_game_id and grs.published = true;
end; $$;
grant execute on function get_round_summary_by_game(text) to anon, authenticated;

drop function if exists admin_get_summary_stats(text, text, text, bigint, bigint);
create function admin_get_summary_stats(input_pw text, input_phone text, input_pin text, input_from_ts bigint default null, input_to_ts bigint default null)
returns table(player_id text, guest_name text, games_count bigint, total_goals bigint, avg_rating numeric)
language plpgsql security definer as $$
declare v_role text;
begin
  v_role := require_admin(input_pw, input_phone, input_pin);
  return query
    select rt.player_id,
      max(reg.guest_name) as guest_name,
      count(distinct rt.game_id) as games_count,
      coalesce(sum(rt.goals), 0) as total_goals,
      avg(rt.rating) as avg_rating
    from game_round_summary_ratings rt
    join games g on g.id = rt.game_id
    left join registrations reg on reg.game_id = rt.game_id and reg.player_id = rt.player_id
    where (input_from_ts is null or g.kickoff >= input_from_ts)
      and (input_to_ts is null or g.kickoff <= input_to_ts)
    group by rt.player_id
    order by total_goals desc;
end; $$;

-- לוודא שגם ה-cache של PostgREST מתעדכן מיד אחרי ה-drop+create הזה,
-- לא רק אחרי ה-DDL הרגיל.
notify pgrst, 'reload schema';
