-- ================================================================
-- CrimiReview Admin Management
-- ================================================================
-- Lets an existing admin promote/demote a user from INSIDE the app
-- (Admin Panel -> Students -> per-row action) instead of requiring
-- someone to run raw SQL in the Supabase dashboard every time.
--
-- This does not change WHO can become an admin -- it just gives the
-- people who already are admins a UI for the exact same operation the
-- SQL Editor already does. The actual security is unchanged and lives
-- in two places that already existed before this file:
--   1. public.protect_user_role() trigger (supabase_schema_v2.sql
--      section 1) -- silently reverts any role change attempted by a
--      caller who is not already an admin. This function is an
--      additional, explicit guard on TOP of that trigger, not a
--      replacement for it.
--   2. public.is_admin() (supabase_schema_v2.sql section 2).
--
-- HOW TO RUN: Supabase SQL Editor, paste, Run. Safe to re-run.
-- ================================================================

create or replace function public.admin_set_user_role(p_email text, p_role text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_email     text := lower(trim(p_email));
  v_target_id uuid;
  v_old_role  text;
begin
  -- Explicit check here (not just relying on the trigger) so the caller
  -- gets a clear message instead of a silent no-op.
  if not public.is_admin() then
    return jsonb_build_object('success', false, 'error', 'Only admins can change roles.');
  end if;

  if p_role not in ('student', 'admin') then
    return jsonb_build_object('success', false, 'error', 'Role must be ''student'' or ''admin''.');
  end if;

  select id, role into v_target_id, v_old_role
  from public.user_profiles
  where lower(email) = v_email;

  if v_target_id is null then
    return jsonb_build_object('success', false, 'error', 'No account found with that email.');
  end if;

  -- An admin can't demote themselves out of the only admin seat by
  -- accident from inside the app -- do that from the SQL Editor if you
  -- really mean to.
  if v_target_id = auth.uid() and p_role <> 'admin' then
    return jsonb_build_object('success', false, 'error', 'You cannot demote your own account from here.');
  end if;

  if v_old_role = p_role then
    return jsonb_build_object('success', true, 'unchanged', true);
  end if;

  update public.user_profiles set role = p_role where id = v_target_id;

  perform public.log_admin_action(
    case when p_role = 'admin' then 'promote' else 'demote' end,
    'user_profiles',
    v_target_id::text,
    jsonb_build_object('email', v_email, 'old_role', v_old_role, 'new_role', p_role)
  );

  return jsonb_build_object('success', true);
end;
$$;

revoke all on function public.admin_set_user_role(text, text) from public, anon;
grant execute on function public.admin_set_user_role(text, text) to authenticated;
