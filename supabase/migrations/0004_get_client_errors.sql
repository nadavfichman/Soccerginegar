-- ============================================================================
-- Migration 0004 — get_client_errors RPC (2026-09-14)
-- ============================================================================
-- מאפשרת לאדמין-על לקרוא את client_errors (חסומה ל-SELECT ישיר) מתוך
-- האפליקציה עצמה — כפתור "יומן שגיאות" חדש ב-SuperAdminPanel (ר' index.html,
-- ClientErrorLog), במקום שהדרך היחידה תהיה שאילתה ידנית ב-Supabase Dashboard.
-- ============================================================================

create or replace function get_client_errors(input_pw text, input_limit int default 200)
returns table(id bigint, created_at timestamptz, message text, stack text, user_agent text, url text, context text)
language plpgsql security definer as $$
declare v_role text;
begin
  v_role := require_admin(input_pw, null, null);
  if v_role <> 'super' then raise exception 'not_authorized'; end if;
  return query
    select e.id, e.created_at, e.message, e.stack, e.user_agent, e.url, e.context
    from client_errors e
    order by e.created_at desc
    limit greatest(coalesce(input_limit, 200), 1);
end; $$;
