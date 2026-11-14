-- ============================================================================
-- Migration 0047 — מלך שערים + ממוצע ציונים (שניידר), לפי תקופה
-- ============================================================================
-- המשתמש: "אני רוצה שתהיה לי אפשרות להשיג טבלת מלך שערים, לפי תקופה,
-- לסדר מגבוה לנמוך. אני רוצה שיהיה גם ממוצע ציון לשחקן לפי ציוני
-- שניידר, גם זה לפי תקופה." והדגיש שוב: "אין לציוני שניידר שום
-- השפעה על הכוחות או על ציון שחקן בחלוקה" — RPC זה קורא בלבד
-- מ-game_round_summary_ratings/games, לא נוגע ב-players.grade או
-- בשום דבר שמשפיע על logic.js.
--
-- input_from_ts/input_to_ts (אופציונליים, אותה יחידה כמו games.kickoff)
-- מסננים לפי תקופה. total_goals/avg_rating מחושבים ב-SQL (sum/avg
-- מתעלמים אוטומטית מ-NULL) — הלקוח ממיין את התוצאה לפי כל עמודה
-- שירצה (גולים/ציון), בלי קריאה נוספת לשרת.
-- ============================================================================

create or replace function admin_get_summary_stats(input_pw text, input_phone text, input_pin text, input_from_ts bigint default null, input_to_ts bigint default null)
returns table(player_id text, guest_name text, games_count bigint, total_goals bigint, avg_rating numeric)
language plpgsql security definer as $$
declare v_role text;
begin
  v_role := require_admin(input_pw, input_phone, input_pin);
  return query
    select rt.player_id,
      max(reg.guest_name) as guest_name,
      count(distinct rt.game_id) as games_count,
      coalesce(sum(rt.goals), 0) as total_goals,
      avg(rt.rating) as avg_rating
    from game_round_summary_ratings rt
    join games g on g.id = rt.game_id
    left join registrations reg on reg.game_id = rt.game_id and reg.player_id = rt.player_id
    where (input_from_ts is null or g.kickoff >= input_from_ts)
      and (input_to_ts is null or g.kickoff <= input_to_ts)
    group by rt.player_id
    order by total_goals desc;
end; $$;
