-- ============================================================================
-- Migration 0027 — נקודות "פורמה" (5 משחקים אחרונים) בתצוגה הציבורית
-- (2026-10-09)
-- ============================================================================
-- המשתמש: "כאשר אני מצרף תמונה בוואטסאפ כקישור או מציג באפליקציה אני
-- רוצה שגם יראו את כל החמש משחקים האחרונים, את כל הנקודות שהכנת.
-- כמובן מדגיש אסור להראות ציונים." תמונת השיתוף לוואטסאפ כבר נפתרת
-- בלי SQL חדש (playerForm/formDots כבר קיימים וטעונים אצל האדמין) —
-- אבל "הצגת הכוחות" הציבורית לשחקן (TeamsDisplay, get_published_teams
-- הקיימת) לא מציגה נקודות כי admin_get_player_form דורש require_admin.
--
-- RPC ציבורי חדש, מראה-כמעט-זהה ל-admin_get_player_form (אותה לוגיקת
-- UNION חי+מיובא, אותו חלון 5 אחרונים), אבל:
-- - בלי require_admin/פרמטרי אישורים בכלל.
-- - אותו שער בדיוק כמו get_published_teams (migrations/0020) — מחזיר
--   ריק אם games.teams_published != true.
-- - מקבל input_game_id וגוזר את קבוצת השחקנים רק ממי שבאמת ב-game_teams
--   של המשחק הזה — לא פותח גישה כללית ל"פורמה של כל שחקן", אותו היקף
--   חשיפה בדיוק כמו get_published_teams עצמה. בלי דירוג/ציון בחתימה.
-- ============================================================================

create or replace function get_published_teams_form(input_game_id text)
returns table(player_id text, kickoff bigint, outcome text)
language plpgsql security definer as $$
begin
  if not exists (select 1 from games where id = input_game_id and teams_published = true) then
    return;
  end if;
  return query
    select x.player_id, x.kickoff, x.outcome from (
      select combined.player_id, combined.kickoff, combined.outcome,
        row_number() over (partition by combined.player_id order by combined.kickoff desc) as rn
      from (
        select gt2.player_id, g2.kickoff,
          case
            when gt2.team = 1 and gr.team1_score > gr.team2_score then 'win'
            when gt2.team = 1 and gr.team1_score < gr.team2_score then 'loss'
            when gt2.team = 1 then 'draw'
            when gt2.team = 2 and gr.team2_score > gr.team1_score then 'win'
            when gt2.team = 2 and gr.team2_score < gr.team1_score then 'loss'
            else 'draw'
          end as outcome
        from game_teams gt2
        join game_results gr on gr.game_id = gt2.game_id
        join games g2 on g2.id = gt2.game_id
        where gt2.player_id in (select gt.player_id from game_teams gt where gt.game_id = input_game_id)
        union all
        select lpg.player_id, floor(extract(epoch from lpg.game_date) * 1000)::bigint as kickoff, lpg.outcome
        from legacy_player_games lpg
        where lpg.player_id in (select gt.player_id from game_teams gt where gt.game_id = input_game_id)
      ) combined
    ) x
    where x.rn <= 5
    order by x.player_id, x.kickoff desc;
end; $$;

grant execute on function get_published_teams_form(text) to anon, authenticated;
