-- ============================================================================
-- Migration 0010 — Edit a published game's kickoff time (2026-10-02)
-- ============================================================================
-- מאפשר לאדמין לשנות את שעת/תאריך המשחק אחרי שהמשחק כבר פורסם (למשל
-- להזיז מ-15:15 ל-15:00), כל עוד המשחק עוד לא קרה. אין צורך בשינוי
-- בשום מקום אחר — כל התצוגות לשחקנים (כרטיס, באנר, הודעות וואטסאפ)
-- קוראות ישירות מ-games.kickoff, אז השינוי מתעדכן בכל מקום אוטומטית.
-- ר' שיחה עם המשתמש.
-- ============================================================================

create or replace function admin_set_game_kickoff(input_game_id text, input_kickoff bigint, input_pw text, input_phone text, input_pin text)
returns boolean language plpgsql security definer as $$
declare v_role text;
begin
  v_role := require_admin(input_pw, input_phone, input_pin);
  update games set kickoff = input_kickoff where id = input_game_id;
  perform log_admin_action(v_role, coalesce(input_phone,'super'), 'admin_set_game_kickoff', jsonb_build_object('game_id', input_game_id, 'kickoff', input_kickoff));
  return true;
end; $$;
