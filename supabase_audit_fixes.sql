-- ================================================================
-- CrimiReview -- Security fixes from the pre-release audit (2026-10-17)
-- ================================================================
-- Run once in Supabase -> SQL Editor (whole file). Safe to run again.
-- It changes rules and functions only; no student data is deleted.
--
-- 1. Profile email can no longer be changed by a student.
--    The "Make admin" function found its target by user_profiles.email,
--    which each student could edit on their own row. A student who put a
--    teacher's email on their own profile could have been promoted
--    instead of the teacher. Now (a) a profile's email is always copied
--    from the real sign-in email, and (b) "Make admin" looks the account
--    up by its sign-in email in auth.users.
--
-- 2. Profile photos can only point at the student's own uploaded photo
--    (or the Google/Facebook photo set at sign-up). Before, any web
--    address could be saved and would load on every student's
--    leaderboard, letting that website log their phones' addresses or
--    show anything.
--
-- 3. Resetting a password now signs that account out on every device.
--
-- 4. The internal email functions (schema "private") can only be run by
--    the database itself. They were not reachable from the app before
--    either (no access to the schema); this removes the leftover
--    default permission.
--
-- ROLLBACK (only if something breaks):
--   DROP TRIGGER IF EXISTS guard_user_profile_trigger ON public.user_profiles;
--   and re-run the earlier admin_set_user_role / reset_user_password
--   from supabase_admin_management.sql / supabase_security_fixes_v2.sql.
-- ================================================================


-- 1 + 2. Guard on every profile insert and update ---------------------
CREATE OR REPLACE FUNCTION public.guard_user_profile()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $guard$
DECLARE
  v_email       text;
  v_old_avatar  text;
  v_own_folder  text := 'https://wbhobbehgqlzfborscvx.supabase.co/storage/v1/object/public/avatars/'
                        || NEW.id::text || '/';
BEGIN
  -- The email in a profile is always the account's sign-in email.
  SELECT u.email INTO v_email FROM auth.users u WHERE u.id = NEW.id;
  IF v_email IS NOT NULL THEN
    NEW.email := v_email;
  END IF;

  -- Photo address: checked only when a signed-in user (not Supabase Auth
  -- itself, which sets the Google/Facebook photo at sign-up) changes it.
  IF TG_OP = 'UPDATE' THEN
    v_old_avatar := OLD.avatar_url;
  END IF;

  IF auth.uid() IS NOT NULL
     AND NEW.avatar_url IS DISTINCT FROM v_old_avatar
     AND NULLIF(btrim(NEW.avatar_url), '') IS NOT NULL
     AND left(NEW.avatar_url, length(v_own_folder)) <> v_own_folder
     AND NEW.avatar_url !~ '^https://lh[0-9]+\.googleusercontent\.com/'
     AND NEW.avatar_url !~ '^https://(platform-lookaside\.fbsbx\.com|graph\.facebook\.com)/'
  THEN
    RAISE EXCEPTION 'Profile photo must be uploaded through the app.'
      USING ERRCODE = 'check_violation';
  END IF;

  RETURN NEW;
END;
$guard$;

REVOKE ALL ON FUNCTION public.guard_user_profile() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS guard_user_profile_trigger ON public.user_profiles;
CREATE TRIGGER guard_user_profile_trigger
  BEFORE INSERT OR UPDATE ON public.user_profiles
  FOR EACH ROW EXECUTE FUNCTION public.guard_user_profile();

-- Bring any existing profile email in line with its sign-in email
-- (0 rows differed on 2026-10-17; kept for anyone running this later).
UPDATE public.user_profiles p
SET email = u.email
FROM auth.users u
WHERE u.id = p.id AND p.email IS DISTINCT FROM u.email;


-- 1. "Make admin" finds the account by its real sign-in email ---------
CREATE OR REPLACE FUNCTION public.admin_set_user_role(p_email text, p_role text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
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

  -- The sign-in email (auth.users), which only Supabase Auth can change --
  -- never the editable profile row.
  select u.id into v_target_id
  from auth.users u
  where lower(u.email) = v_email
  limit 1;

  if v_target_id is null then
    return jsonb_build_object('success', false, 'error', 'No account found with that email.');
  end if;

  select role into v_old_role from public.user_profiles where id = v_target_id;
  if not found then
    return jsonb_build_object('success', false, 'error',
      'That account has not opened the app yet. Ask them to sign in once, then try again.');
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
$function$;


-- 3. A password reset signs the account out everywhere ---------------
CREATE OR REPLACE FUNCTION public.reset_user_password(p_email text, p_code text, p_new_password text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $function$
DECLARE
  v_email   text := lower(btrim(p_email));
  v_expired constant text := 'This reset session has expired. Please request a new code.';
  rec       record;
  v_user_id uuid;
BEGIN
  IF p_new_password IS NULL OR length(p_new_password) < 8 OR length(p_new_password) > 72 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Password must be 8 to 72 characters.');
  END IF;

  -- The row confirm_password_reset_code() marked used = true.
  SELECT * INTO rec
  FROM public.password_resets
  WHERE email = v_email
    AND used = true
    AND created_at > now() - interval '15 minutes'
  ORDER BY created_at DESC
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', v_expired);
  END IF;

  IF rec.code IS DISTINCT FROM btrim(p_code) THEN
    -- Count wrong guesses on the verified row too; 5 strikes ends it.
    IF rec.attempts + 1 >= 5 THEN
      DELETE FROM public.password_resets WHERE id = rec.id;
    ELSE
      UPDATE public.password_resets SET attempts = attempts + 1 WHERE id = rec.id;
    END IF;
    RETURN jsonb_build_object('success', false, 'error', v_expired);
  END IF;

  SELECT id INTO v_user_id FROM auth.users WHERE lower(email) = v_email LIMIT 1;
  IF v_user_id IS NULL THEN
    DELETE FROM public.password_resets WHERE email = v_email;
    RETURN jsonb_build_object('success', false, 'error', v_expired);
  END IF;

  UPDATE auth.users
  SET encrypted_password = crypt(p_new_password, gen_salt('bf')),
      updated_at = now()
  WHERE id = v_user_id;

  -- Sign the account out on every phone that was signed in, so whoever
  -- knew the old password (or holds an old session) loses access.
  DELETE FROM auth.refresh_tokens WHERE user_id = v_user_id::text;
  DELETE FROM auth.sessions WHERE user_id = v_user_id;

  DELETE FROM public.password_resets WHERE email = v_email;
  RETURN jsonb_build_object('success', true);
END;
$function$;


-- 4. Internal email functions: database only --------------------------
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA private FROM PUBLIC, anon, authenticated;
