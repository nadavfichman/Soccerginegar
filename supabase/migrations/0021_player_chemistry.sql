-- ============================================================================
-- Migration 0021 — שלב C: נתוני "כימיה" לאיזון כוחות כמו אצל דרור (2026-10-05)
-- ============================================================================
-- אימוץ מדויק (לא ניחוש) של אלגוריתם האיזון של TeamPicker (DivideCollaboration):
-- במקום חישוב DP מדויק של הפרש דירוגים בלבד, חיפוש Monte Carlo (200 ניסיונות
-- אקראיים, ר' logic.js) שבוחר את הניסיון עם ציון-איזון משוקלל הכי טוב, לפי
-- שלושה גורמים: דירוג, "כימיה" (win-rate אישי ספציפית במשחקים שבהם כל שחקן
-- אחר בקבוצה היה חבר-קבוצה שלו בעבר), ו-win-rate אישי כללי. ר' שיחה עם
-- המשתמש ו"עדכון 6" ב-plan — נקרא קוד המקור הציבורי של TeamPicker במפורש
-- (GitHub, DrorFichman/PeamTicker) כדי לא לנחש את הנוסחה.
--
-- בלי טבלה חדשה — כל הנתונים הגולמיים כבר קיימים (game_teams+game_results
-- למשחקים חיים, legacy_player_games למשחקים מיובאים מ-TeamPicker, ר'
-- migrations/0019). RPC חדש מחזיר שורות גולמיות (לא ציון מחושב מראש) כדי
-- שחיפוש ה-200-ניסיונות ירוץ בצד הלקוח על נתונים שנשלפו פעם אחת בפתיחת
-- הפאנל — בדיוק כמו admin_get_player_grades/admin_get_game_teams הקיימים.
--
-- חלון היסטוריה: 50 המשחקים האחרונים של כל שחקן (RECENT_GAMES אצל דרור).
-- שורת "עצמי" (teammate_id = player_id) מקודדת את הסטטיסטיקה האישית
-- הכוללת של השחקן — טריק קטן שחוסך RPC נפרד לזה.
-- ============================================================================

create or replace function admin_get_player_chemistry(input_player_ids text[], input_pw text, input_phone text, input_pin text)
returns table(player_id text, teammate_id text, games_with integer, wins_with integer, decisive_with integer)
language plpgsql security definer as $$
declare v_role text;
begin
  v_role := require_admin(input_pw, input_phone, input_pin);
  return query
    with unified as (
      select gt.player_id, ('live:'||gt.game_id) as gkey, gt.team, g.kickoff as sort_ts,
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
      union all
      select lpg.player_id, ('legacy:'||lpg.source_game_id) as gkey, lpg.team,
        floor(extract(epoch from lpg.game_date) * 1000)::bigint as sort_ts, lpg.outcome
      from legacy_player_games lpg
    ),
    recent as (
      select x.player_id, x.gkey, x.team, x.outcome from (
        select u.player_id, u.gkey, u.team, u.outcome,
          row_number() over (partition by u.player_id order by u.sort_ts desc) as rn
        from unified u
        where u.player_id = any(input_player_ids)
      ) x
      where x.rn <= 50
    )
  select r.player_id, r.player_id as teammate_id, count(*)::integer as games_with,
    sum((r.outcome = 'win')::integer)::integer as wins_with,
    sum((r.outcome in ('win','loss'))::integer)::integer as decisive_with
  from recent r
  group by r.player_id
  union all
  select a.player_id, b.player_id, count(*)::integer,
    sum((a.outcome = 'win')::integer)::integer,
    sum((a.outcome in ('win','loss'))::integer)::integer
  from recent a
  join unified b on b.gkey = a.gkey and b.team = a.team and b.player_id <> a.player_id
  where b.player_id = any(input_player_ids)
  group by a.player_id, b.player_id;
end; $$;
