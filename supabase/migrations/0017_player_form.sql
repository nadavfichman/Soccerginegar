-- ============================================================================
-- Migration 0017 — "פורמה" (5 תוצאות אחרונות לכל שחקן) בפאנל חלוקת הכוחות (2026-10-05)
-- ============================================================================
-- המשך ישיר של migration 0016 (game_results) — עכשיו שיש לנו תוצאות אמיתיות
-- נצברות בתוך Soccerginegar עצמה (לא תלוי בייבוא חסום מ-TeamPicker, שלב B),
-- אפשר לגזור "ניצחון/הפסד/תיקו" לכל שחקן בכל משחק שהוא השתתף בו ושיש לו
-- תוצאה, ולהציג את 5 התוצאות האחרונות — בדיוק נקודות ה"פורמה" הירוקות/
-- אדומות שראינו ב-TeamPicker (ר' שיחה עם המשתמש: ניצחון=ירוק, הפסד=אדום,
-- תיקו=כחול).
--
-- בלי טבלה חדשה — הכל נגזר (JOIN+window function) מ-game_teams+game_results
-- הקיימים, אין מידע חדש לאחסן.
-- ============================================================================

create or replace function admin_get_player_form(input_player_ids text[], input_pw text, input_phone text, input_pin text)
returns table(player_id text, kickoff bigint, outcome text)
language plpgsql security definer as $$
declare v_role text;
begin
  v_role := require_admin(input_pw, input_phone, input_pin);
  return query
    select x.player_id, x.kickoff, x.outcome from (
      select gt.player_id, g.kickoff,
        case
          when gt.team = 1 and gr.team1_score > gr.team2_score then 'win'
          when gt.team = 1 and gr.team1_score < gr.team2_score then 'loss'
          when gt.team = 1 then 'draw'
          when gt.team = 2 and gr.team2_score > gr.team1_score then 'win'
          when gt.team = 2 and gr.team2_score < gr.team1_score then 'loss'
          else 'draw'
        end as outcome,
        row_number() over (partition by gt.player_id order by g.kickoff desc) as rn
      from game_teams gt
      join game_results gr on gr.game_id = gt.game_id
      join games g on g.id = gt.game_id
      where gt.player_id = any(input_player_ids)
    ) x
    where x.rn <= 5
    order by x.player_id, x.kickoff desc;
end; $$;
