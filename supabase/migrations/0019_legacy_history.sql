-- ============================================================================
-- Migration 0019 — היסטוריה מיובאת מ-TeamPicker (שלב B, 2026-10-05)
-- ============================================================================
-- דרור שלח ייצוא Firebase אמיתי (416 משחקים, 2016-2026). אחרי התאמת שמות
-- (ר' שיחה עם המשתמש) מיובאים 4,230 רשומות היסטוריה עבור 43 שחקנים
-- שהותאמו בביטחון מול רשימת Soccerginegar.
--
-- טבלה נפרדת לגמרי מ-games/game_teams/game_results — אלה מייצגים משחקי
-- Soccerginegar אמיתיים (קיקאוף/opens_at/הרשמה/וכו'), וערבוב 416 "משחקים"
-- מדומים מ-2016 לתוכם יזהם את רשימת המשחקים של האדמין ואת attendanceCounts
-- ("מתמיד"). legacy_player_games היא רק נתון גולמי להצגת "פורמה", לא
-- קשורה למחזור החיים של משחק אמיתי.
--
-- נעולה לגמרי (RLS מופעל, בלי policy, בלי grant select) — אותו דפוס בדיוק
-- כמו game_results/game_teams/player_grades, אדמין בלבד.
-- ============================================================================

create table if not exists legacy_player_games (
  id bigint generated always as identity primary key,
  player_id text not null,
  source text not null default 'teampicker',
  source_game_id text not null,
  game_date date not null,
  team smallint not null check (team in (1, 2)),
  own_score integer not null check (own_score >= 0),
  opp_score integer not null check (opp_score >= 0),
  outcome text not null check (outcome in ('win', 'loss', 'draw')),
  unique (source, source_game_id, player_id)
);
alter table legacy_player_games enable row level security;

-- admin_get_player_form (migrations/0017) מתעדכנת לאחד (UNION) היסטוריה
-- חיה (game_teams+game_results) עם היסטוריה מיובאת — "פורמה" עשירה מיד
-- לכל שחקן עם היסטוריה אצל דרור, לא מתחילה מאפס. legacy_player_games.game_date
-- (date) מומר ל-bigint (אפוקים במילישניות) לעקביות עם kickoff החי.
create or replace function admin_get_player_form(input_player_ids text[], input_pw text, input_phone text, input_pin text)
returns table(player_id text, kickoff bigint, outcome text)
language plpgsql security definer as $$
declare v_role text;
begin
  v_role := require_admin(input_pw, input_phone, input_pin);
  return query
    select x.player_id, x.kickoff, x.outcome from (
      select combined.player_id, combined.kickoff, combined.outcome,
        row_number() over (partition by combined.player_id order by combined.kickoff desc) as rn
      from (
        select gt.player_id, g.kickoff,
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
        join games g on g.id = gt.game_id
        where gt.player_id = any(input_player_ids)
        union all
        select lpg.player_id, floor(extract(epoch from lpg.game_date) * 1000)::bigint as kickoff, lpg.outcome
        from legacy_player_games lpg
        where lpg.player_id = any(input_player_ids)
      ) combined
    ) x
    where x.rn <= 5
    order by x.player_id, x.kickoff desc;
end; $$;
