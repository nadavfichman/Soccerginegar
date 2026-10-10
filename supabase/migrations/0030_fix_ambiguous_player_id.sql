-- ============================================================================
-- Migration 0030 — תיקון "column reference player_id is ambiguous"
-- ב-admin_get_all_player_stats (2026-10-10)
-- ============================================================================
-- migrations/0029 נכשלה בפועל בכל קריאה (נתפס רק כי הפסקנו לבלוע שגיאות
-- RPC בשקט, ר' "לקח כללי" ב-CLAUDE.md — יומן השגיאות של הלקוח
-- (log_client_error) הראה בדיוק את השגיאה): RETURNS TABLE(player_id text,
-- ...) ב-PL/pgSQL יוצר באופן משתמע משתנה/פרמטר OUT בשם player_id בתוך
-- גוף הפונקציה — שם שמתנגש עם העמודה player_id שמגיעה מה-CTE
-- (unified.player_id) ב-SELECT הסופי. admin_get_player_stats (מיגרציה
-- 0022/0028) לא נתקלה בבעיה הזו כי ה-RETURNS TABLE שלה לא כוללת עמודה
-- בשם player_id בכלל.
--
-- תיקון: alias מפורש ל-CTE (unified u) ואזכור u.player_id/u.outcome בכל
-- מקום ב-SELECT הסופי — מסיר את העמימות לגמרי, בלי שינוי בלוגיקה עצמה.
-- ============================================================================

create or replace function admin_get_all_player_stats(input_pw text, input_phone text, input_pin text)
returns table(player_id text, games_count integer, wins integer, losses integer, draws integer)
language plpgsql security definer as $$
declare v_role text;
begin
  v_role := require_admin(input_pw, input_phone, input_pin);
  return query
    with unified as (
      select gt.player_id,
        case
          when gt.team = 1 and gr.team1_score > gr.team2_score then 'win'
          when gt.team = 1 and gr.team1_score < gr.team2_score then 'loss'
          when gt.team = 1 then 'draw'
          when gt.team = 2 and gr.team2_score > gr.team1_score then 'win'
          when gt.team = 2 and gr.team2_score < gr.team1_score then 'loss'
          else 'draw'
        end as outcome
      from game_teams gt
      join game_results gr on gr.game_id = gt.game_id
      union all
      select lpg.player_id, lpg.outcome
      from legacy_player_games lpg
      union all
      select r.player_id, null::text as outcome
      from registrations r
      join games g on g.id = r.game_id
      where r.attended = true
        and g.attendance_locked = true
        and not exists (
          select 1 from game_teams gt2
          join game_results gr2 on gr2.game_id = gt2.game_id
          where gt2.game_id = r.game_id and gt2.player_id = r.player_id
        )
    )
  select u.player_id,
    count(*)::integer as games_count,
    coalesce(sum((u.outcome = 'win')::integer), 0)::integer as wins,
    coalesce(sum((u.outcome = 'loss')::integer), 0)::integer as losses,
    coalesce(sum((u.outcome = 'draw')::integer), 0)::integer as draws
  from unified u
  group by u.player_id;
end; $$;
