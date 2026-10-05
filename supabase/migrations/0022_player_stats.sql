-- ============================================================================
-- Migration 0022 — מסך "מידע על שחקן" (ר' שיחה עם המשתמש: "כאשר לוחצים על
-- שחקן כלשהו ייפתח מידע רלוונטי כמו אצל דרור — אחוזי הצלחה, כמויות
-- משחקים, ניצחונות, הפסדים") (2026-10-05)
-- ============================================================================
-- בניגוד ל-admin_get_player_chemistry (migrations/0021), שמוגבל בכוונה
-- ל-50 המשחקים האחרונים (RECENT_GAMES, תואם את אלגוריתם האיזון של דרור) —
-- כאן אלה נתוני קריירה מצטברים, בלי חלון זמן. אותו מקור נתונים בדיוק
-- (game_teams+game_results למשחקים חיים, legacy_player_games למיובאים
-- מ-TeamPicker) כמו admin_get_player_form/admin_get_player_chemistry.
-- ============================================================================

create or replace function admin_get_player_stats(input_player_id text, input_pw text, input_phone text, input_pin text)
returns table(games_count integer, wins integer, losses integer, draws integer)
language plpgsql security definer as $$
declare v_role text;
begin
  v_role := require_admin(input_pw, input_phone, input_pin);
  return query
    with unified as (
      select
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
      where gt.player_id = input_player_id
      union all
      select lpg.outcome
      from legacy_player_games lpg
      where lpg.player_id = input_player_id
    )
  select count(*)::integer as games_count,
    coalesce(sum((outcome = 'win')::integer), 0)::integer as wins,
    coalesce(sum((outcome = 'loss')::integer), 0)::integer as losses,
    coalesce(sum((outcome = 'draw')::integer), 0)::integer as draws
  from unified;
end; $$;
