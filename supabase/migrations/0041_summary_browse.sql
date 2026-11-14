-- ============================================================================
-- Migration 0041 — שחקן יכול לבחור ולצפות בכל סיכום מפורסם (לא רק האחרון)
-- ============================================================================
-- המשתמש: "רוצה ששחקן יוכל לבחור סיכום ולהסתכל עליו. כמובן לצפייה
-- בלבד." עד עכשיו get_round_summary_latest החזיר רק את המחזור
-- האחרון שפורסם. שתי פונקציות חדשות, ציבוריות לגמרי (בלי סיסמה —
-- אותו עיקרון בדיוק כמו get_round_summary_latest: "נראות" נשלטת
-- ע"י published, לא ע"י cred):
--   get_published_round_summaries() — רשימת כל המחזורים שפורסמו
--     (עד 20 אחרונים), לבחירה מתוך <select>.
--   get_round_summary_by_game(input_game_id) — פרטי סיכום מלאים
--     למשחק ספציפי, רק אם published=true לאותו משחק (לא ניתן "לנחש"
--     game_id של טיוטה לא-מפורסמת ולראות אותה).
-- ============================================================================

create or replace function get_published_round_summaries()
returns table(game_id text, kickoff bigint, team1_score integer, team2_score integer)
language plpgsql security definer as $$
begin
  return query
    select grs.game_id, g.kickoff, grs.team1_score, grs.team2_score
    from game_round_summary grs
    join games g on g.id = grs.game_id
    where grs.published = true
    order by g.kickoff desc
    limit 20;
end; $$;
grant execute on function get_published_round_summaries() to anon, authenticated;

create or replace function get_round_summary_by_game(input_game_id text)
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
