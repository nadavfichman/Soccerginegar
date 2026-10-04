-- ============================================================================
-- Migration 0016 — תיעוד תוצאות משחק (2026-10-05)
-- ============================================================================
-- צעד ראשון לקראת שלב C (כימיה/אחוזי-ניצחון, "נקודות פורמה") — אבל לא תלוי
-- בשלב B (ייבוא היסטוריה מ-TeamPicker, עדיין חסום): מתחילים לתעד תוצאות
-- למשחקים מעכשיו והלאה, בתוך Soccerginegar עצמה, ובונים היסטוריה אורגנית.
-- בשלב הזה: תיעוד גולמי בלבד (תוצאה מספרית), בלי תצוגת סטטיסטיקה/"פורמה"
-- עצמה — זה עדיין שלב C/D נפרד (ר' שיחה עם המשתמש).
--
-- game_results נעולה לגמרי (RLS מופעל, בלי policy, בלי grant select) —
-- אותו דפוס בדיוק כמו player_grades/game_teams, כי התוצאה אדמין-בלבד כרגע.
-- ============================================================================

create table if not exists game_results (
  game_id text primary key references games(id) on delete cascade,
  team1_score integer not null check (team1_score >= 0),
  team2_score integer not null check (team2_score >= 0),
  recorded_at timestamptz not null default now()
);
alter table game_results enable row level security;
-- בכוונה בלי שום policy ובלי grant select — נעול לגמרי, כמו game_teams.

-- שומר/מעדכן תוצאה למשחק — דורש שחלוקת קבוצות (game_teams) כבר נשמרה
-- לאותו משחק (אכיפה בצד השרת, לא רק UI). on conflict מאפשר תיקון תוצאה
-- שהוזנה בטעות, לא רק כתיבה ראשונה.
create or replace function admin_set_game_result(input_game_id text, input_team1_score integer, input_team2_score integer, input_pw text, input_phone text, input_pin text)
returns boolean language plpgsql security definer as $$
declare v_role text;
begin
  v_role := require_admin(input_pw, input_phone, input_pin);
  if not exists (select 1 from game_teams where game_id = input_game_id) then raise exception 'teams_not_saved'; end if;
  if input_team1_score < 0 or input_team2_score < 0 then raise exception 'invalid_score'; end if;
  insert into game_results (game_id, team1_score, team2_score, recorded_at) values (input_game_id, input_team1_score, input_team2_score, now())
    on conflict (game_id) do update set team1_score = excluded.team1_score, team2_score = excluded.team2_score, recorded_at = now();
  perform log_admin_action(v_role, coalesce(input_phone,'super'), 'admin_set_game_result', jsonb_build_object('game_id', input_game_id, 'team1_score', input_team1_score, 'team2_score', input_team2_score));
  return true;
end; $$;

-- קריאת תוצאת משחק ספציפי — נטען יחד עם admin_get_game_teams כשפאנל
-- החלוקה נפתח (ר' AdminGameRow, index.html).
create or replace function admin_get_game_result(input_game_id text, input_pw text, input_phone text, input_pin text)
returns table(team1_score integer, team2_score integer) language plpgsql security definer as $$
declare v_role text;
begin
  v_role := require_admin(input_pw, input_phone, input_pin);
  return query select gr.team1_score, gr.team2_score from game_results gr where gr.game_id = input_game_id;
end; $$;

-- כל התוצאות השמורות בעסקה אחת, כולל תאריך המשחק וספירת שחקנים לכל
-- קבוצה — לרשימת "היסטוריית תוצאות" (ר' AdminGames, index.html), בלי
-- round-trip נפרד ללקוח לכל משחק.
create or replace function admin_get_all_game_results(input_pw text, input_phone text, input_pin text)
returns table(game_id text, team1_score integer, team2_score integer, team1_count bigint, team2_count bigint, kickoff bigint)
language plpgsql security definer as $$
declare v_role text;
begin
  v_role := require_admin(input_pw, input_phone, input_pin);
  return query
    select gr.game_id, gr.team1_score, gr.team2_score,
      (select count(*) from game_teams gt where gt.game_id = gr.game_id and gt.team = 1),
      (select count(*) from game_teams gt where gt.game_id = gr.game_id and gt.team = 2),
      g.kickoff
    from game_results gr join games g on g.id = gr.game_id
    order by g.kickoff desc;
end; $$;
