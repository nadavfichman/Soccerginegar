-- ============================================================================
-- Migration 0042 — תיקון: מחזור מפורסם בלי game_teams הציג עמודות ריקות
-- ============================================================================
-- המשתמש שלח צילום מסך: פתיחת "סיכומי שניידר" במסך שחקן הציגה שתי
-- עמודות צבע (כחול/כתום) לגמרי ריקות — בלי תוצאה, בלי שמות, בלי
-- טקסט. הסיבה: get_published_round_summaries (migrations/0041)
-- הצטרפה רק ל-game_round_summary+games, בלי לדרוש שיש גם game_teams
-- למשחק — אז מחזור שה-game_teams שלו נוקה/שונה אחרי הפרסום (למשל
-- בזמן בדיקות) עדיין הופיע ברשימה. ואז get_round_summary_by_game,
-- שכן דורשת game_teams (inner join), החזירה אפס שורות לאותו משחק —
-- בדיוק מה שיצר את העמודות הריקות. summary_get_recent_games (האדמין,
-- migrations/0038) כבר דרשה game_teams מההתחלה; עכשיו גם הגרסה
-- הציבורית עקבית איתה.
-- ============================================================================

create or replace function get_published_round_summaries()
returns table(game_id text, kickoff bigint, team1_score integer, team2_score integer)
language plpgsql security definer as $$
begin
  return query
    select distinct grs.game_id, g.kickoff, grs.team1_score, grs.team2_score
    from game_round_summary grs
    join games g on g.id = grs.game_id
    join game_teams gt on gt.game_id = grs.game_id
    where grs.published = true
    order by g.kickoff desc
    limit 20;
end; $$;
