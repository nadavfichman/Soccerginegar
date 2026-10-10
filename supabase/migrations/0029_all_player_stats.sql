-- ============================================================================
-- Migration 0029 — RPC לטבלת סטטיסטיקה לכל השחקנים (2026-10-10)
-- ============================================================================
-- המשתמש: "רוצה להוסיף גם שדה של סטטיסטיקה (ליד משחקים, היסטוריה),
-- יופיעו בו כל שחקנים מאושרים, ויהיה ניתן גם לפלטר וגם לחפש שחקן."
-- admin_get_player_stats (migrations/0022, עודכנה ב-0028) מחזירה
-- סטטיסטיקה לשחקן בודד בלבד — לא מתאים לטבלה עם ~70 שחקנים (70
-- round-trips). RPC חדש, אותו היגיון "unified" המדויק ממיגרציה 0028
-- (חי + legacy + נוכחות-נעולה-בלי-תוצאה, אותה דה-דופליקציה), רק
-- group by player_id במקום סינון לשחקן יחיד — כך שהמספרים בטבלה
-- תמיד זהים למסך "שנה מידע" הבודד של כל שחקן.
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
  select player_id,
    count(*)::integer as games_count,
    coalesce(sum((outcome = 'win')::integer), 0)::integer as wins,
    coalesce(sum((outcome = 'loss')::integer), 0)::integer as losses,
    coalesce(sum((outcome = 'draw')::integer), 0)::integer as draws
  from unified
  group by player_id;
end; $$;
