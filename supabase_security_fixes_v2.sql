-- ================================================================
-- CrimiReview -- Security fixes v2 (pre-launch audit, 2026-10-09)
-- ================================================================
-- Fixes problems found by testing the LIVE project with only the public
-- anon key (the key shipped inside the APK, i.e. what any outsider has):
--
--   1. Every user_profiles row -- email, name, school, and who is an
--      admin -- was readable by anyone, logged in or not.
--   2. Leaderboard needed (1); it now uses a function that returns only
--      public fields (name, avatar, points, rank) to signed-in users.
--   3. Daily challenge scores were public and could be edited by their
--      owner after the fact.
--   4. reset_user_password(email, new_password) could be called by
--      anyone for 15 minutes after the real owner verified their reset
--      code. It now also requires that code, and limits guesses.
--   5. cleanup_password_resets(email) let anyone cancel anyone's reset.
--   6. Verification / reset codes could be requested without limit for
--      any address (inbox flooding, burning the Resend email quota).
--      Password-reset codes were also emailed to addresses with no
--      account.
--   7. The public avatars bucket accepted files of any type and size.
--   8. Leftover document_uploads table from the removed PDF feature.
--
-- REQUIRES: supabase_schema.sql, supabase_security_fixes.sql and
-- supabase_schema_v2.sql already applied (they are, on the live project).
--
-- APP VERSION: the password-reset change needs the app build that
-- calls reset_user_password(p_email, p_code, p_new_password). Older
-- installs (v1.0.0) will fail at the last step of "Forgot password"
-- until updated; everything else in older installs keeps working,
-- except their leaderboard, which shows only the student's own row.
--
-- HOW TO RUN: Supabase Dashboard -> SQL Editor -> paste all -> Run.
-- Safe to re-run. Rollback notes are at the bottom.
-- ================================================================


-- ================================================================
-- 1. user_profiles: own row only (admins: all rows)
-- ================================================================
DROP POLICY IF EXISTS "Users can view all profiles" ON public.user_profiles;
DROP POLICY IF EXISTS "Users can view own profile; admins view all" ON public.user_profiles;
CREATE POLICY "Users can view own profile; admins view all" ON public.user_profiles
  FOR SELECT TO authenticated
  USING (auth.uid() = id OR public.is_admin());

-- Nobody who is logged out needs profile data at all.
REVOKE ALL ON public.user_profiles FROM anon;


-- ================================================================
-- 2. Leaderboard without exposing private profile fields
-- ================================================================
-- SECURITY DEFINER so it can read every row, but it only ever returns
-- public, leaderboard-safe columns (no email, school or role), and only
-- to signed-in users.
--
-- The live project still has an older get_leaderboard(limit_count) from
-- an early version of the schema (no longer in any .sql file). It is
-- callable WITHOUT logging in and returns other columns, so PostgreSQL
-- can't replace it in place ("cannot change return type of existing
-- function"). No version of the app calls it; it is removed here.
DROP FUNCTION IF EXISTS public.get_leaderboard(integer);

CREATE OR REPLACE FUNCTION public.get_leaderboard(p_limit integer DEFAULT 50)
RETURNS TABLE (
  user_id       uuid,
  display_name  text,
  avatar_url    text,
  total_points  integer,
  total_quizzes integer,
  total_correct integer,
  rank          text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $leaderboard$
  SELECT
    p.id,
    COALESCE(NULLIF(btrim(p.display_name), ''), 'Student'),
    p.avatar_url,
    COALESCE(p.total_points, 0),
    COALESCE(p.total_quizzes, 0),
    COALESCE(p.total_correct, 0),
    COALESCE(p.rank, 'Rookie')
  FROM public.user_profiles p
  WHERE auth.uid() IS NOT NULL
  ORDER BY p.total_points DESC NULLS LAST, p.created_at ASC
  LIMIT LEAST(GREATEST(COALESCE(p_limit, 50), 1), 100);
$leaderboard$;

REVOKE ALL ON FUNCTION public.get_leaderboard(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_leaderboard(integer) TO authenticated;


-- ================================================================
-- 3. daily_challenge_scores: own rows only, insert-only
-- ================================================================
-- The app inserts once per day and never updates; a second attempt is
-- rejected by the UNIQUE (user_id, challenge_date) constraint.
DROP POLICY IF EXISTS "Users can view all challenge scores" ON public.daily_challenge_scores;
DROP POLICY IF EXISTS "Users can view own challenge scores" ON public.daily_challenge_scores;
CREATE POLICY "Users can view own challenge scores" ON public.daily_challenge_scores
  FOR SELECT TO authenticated
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update own challenge scores" ON public.daily_challenge_scores;
REVOKE ALL ON public.daily_challenge_scores FROM anon;


-- ================================================================
-- 4. Password reset must prove it knows the verified code
-- ================================================================
DROP FUNCTION IF EXISTS public.reset_user_password(text, text);

CREATE OR REPLACE FUNCTION public.reset_user_password(
  p_email        text,
  p_code         text,
  p_new_password text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $reset$
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

  DELETE FROM public.password_resets WHERE email = v_email;
  RETURN jsonb_build_object('success', true);
END;
$reset$;

REVOKE ALL ON FUNCTION public.reset_user_password(text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.reset_user_password(text, text, text) TO anon, authenticated;


-- ================================================================
-- 5. Remove the "anyone can cancel anyone's reset" function
-- ================================================================
-- reset_user_password() already deletes the email's reset rows when it
-- succeeds; the app no longer calls this.
DROP FUNCTION IF EXISTS public.cleanup_password_resets(text);


-- ================================================================
-- 6. Rate-limit code emails
-- ================================================================
-- Per email address: at most 1 code per 60 seconds and 5 per hour.
-- Whole project: at most 300 code emails per hour, as a backstop
-- against someone looping through random addresses.
-- NOTE: Resend's own plan limit still applies on top of this (the free
-- plan allows 100 emails per day). Check yours at resend.com/settings.
CREATE TABLE IF NOT EXISTS private.code_requests (
  id           bigserial PRIMARY KEY,
  email        text        NOT NULL,
  kind         text        NOT NULL CHECK (kind IN ('verify', 'reset')),
  requested_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_code_requests_email
  ON private.code_requests (email, kind, requested_at DESC);
CREATE INDEX IF NOT EXISTS idx_code_requests_time
  ON private.code_requests (requested_at);

-- Returns NULL when the request may go ahead (and records it), or a
-- user-facing message when it must be refused.
CREATE OR REPLACE FUNCTION private.check_code_rate_limit(p_email text, p_kind text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = private, pg_temp
AS $ratelimit$
DECLARE
  v_last      timestamptz;
  v_last_hour integer;
  v_global    integer;
BEGIN
  DELETE FROM private.code_requests WHERE requested_at < now() - interval '1 day';

  SELECT max(requested_at), count(*)
    INTO v_last, v_last_hour
  FROM private.code_requests
  WHERE email = p_email
    AND kind = p_kind
    AND requested_at > now() - interval '1 hour';

  IF v_last IS NOT NULL AND v_last > now() - interval '60 seconds' THEN
    RETURN 'Please wait a minute before requesting another code.';
  END IF;

  IF v_last_hour >= 5 THEN
    RETURN 'Too many codes requested for this email. Please try again in an hour.';
  END IF;

  SELECT count(*) INTO v_global
  FROM private.code_requests
  WHERE requested_at > now() - interval '1 hour';

  IF v_global >= 300 THEN
    RETURN 'Too many requests right now. Please try again later.';
  END IF;

  INSERT INTO private.code_requests (email, kind) VALUES (p_email, p_kind);
  RETURN NULL;
END;
$ratelimit$;

REVOKE ALL ON FUNCTION private.check_code_rate_limit(text, text) FROM PUBLIC;

-- Same as supabase_security_fixes.sql, plus the rate limit.
CREATE OR REPLACE FUNCTION public.request_verification_code(p_email text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private, pg_temp
AS $verify$
DECLARE
  v_email   text := lower(btrim(p_email));
  v_code    text;
  v_sent    boolean;
  v_refusal text;
BEGIN
  IF v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' OR length(v_email) > 254 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Enter a valid email address.');
  END IF;

  v_refusal := private.check_code_rate_limit(v_email, 'verify');
  IF v_refusal IS NOT NULL THEN
    RETURN jsonb_build_object('success', false, 'error', v_refusal);
  END IF;

  v_code := lpad(floor(random() * 900000 + 100000)::int::text, 6, '0');

  DELETE FROM public.email_verifications
  WHERE email = v_email AND verified = false;

  INSERT INTO public.email_verifications (email, code, expires_at, verified, attempts)
  VALUES (v_email, v_code, now() + interval '10 minutes', false, 0);

  v_sent := private.send_transactional_email(
    v_email,
    'CrimiReview - Verify Your Email',
    private.verification_email_html(v_code)
  );

  IF NOT v_sent THEN
    DELETE FROM public.email_verifications WHERE email = v_email AND code = v_code;
    RETURN jsonb_build_object('success', false, 'error', 'Failed to send email. Please try again.');
  END IF;

  RETURN jsonb_build_object('success', true);
END;
$verify$;

-- Same as supabase_security_fixes.sql, plus the rate limit, and the
-- email is only actually sent when an account exists. The response is
-- identical either way, so this can't be used to discover who has an
-- account.
CREATE OR REPLACE FUNCTION public.request_password_reset(p_email text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private, pg_temp
AS $reset_request$
DECLARE
  v_email   text := lower(btrim(p_email));
  v_code    text;
  v_sent    boolean;
  v_refusal text;
BEGIN
  IF v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' OR length(v_email) > 254 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Enter a valid email address.');
  END IF;

  v_refusal := private.check_code_rate_limit(v_email, 'reset');
  IF v_refusal IS NOT NULL THEN
    RETURN jsonb_build_object('success', false, 'error', v_refusal);
  END IF;

  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE lower(email) = v_email) THEN
    RETURN jsonb_build_object('success', true);
  END IF;

  v_code := lpad(floor(random() * 900000 + 100000)::int::text, 6, '0');

  DELETE FROM public.password_resets
  WHERE email = v_email;

  INSERT INTO public.password_resets (email, code, expires_at, used, attempts)
  VALUES (v_email, v_code, now() + interval '10 minutes', false, 0);

  v_sent := private.send_transactional_email(
    v_email,
    'CrimiReview - Reset Your Password',
    private.password_reset_email_html(v_code)
  );

  IF NOT v_sent THEN
    DELETE FROM public.password_resets WHERE email = v_email AND code = v_code;
    RETURN jsonb_build_object('success', false, 'error', 'Failed to send email. Please try again.');
  END IF;

  RETURN jsonb_build_object('success', true);
END;
$reset_request$;

REVOKE ALL ON FUNCTION public.request_verification_code(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.request_password_reset(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.request_verification_code(text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.request_password_reset(text) TO anon, authenticated;


-- ================================================================
-- 7. Avatars: images only, 2 MB max
-- ================================================================
-- The app resizes photos to 512 x 512 before upload (well under 1 MB).
-- SVG is deliberately not allowed: it can carry scripts.
UPDATE storage.buckets
SET file_size_limit = 2097152,
    allowed_mime_types = ARRAY['image/jpeg', 'image/png', 'image/webp',
                               'image/gif', 'image/heic', 'image/heif']
WHERE id = 'avatars';


-- ================================================================
-- 8. Remove leftovers of the deleted PDF question generator
-- ================================================================
DROP POLICY IF EXISTS "Admins can upload documents" ON storage.objects;
DROP POLICY IF EXISTS "Admins can read documents"   ON storage.objects;
DROP POLICY IF EXISTS "Admins can delete documents" ON storage.objects;
DROP TABLE IF EXISTS public.document_uploads;


-- ================================================================
-- 9. Length limits on profile text (server-side backstop)
-- ================================================================
-- The app limits names to 30 + 30 characters at sign-up, 60 in the
-- profile, and school to 100. Without a server limit, a huge name sent
-- straight to the API would break the leaderboard for everyone.
-- NOT VALID: applies to every new write without re-checking old rows.
ALTER TABLE public.user_profiles DROP CONSTRAINT IF EXISTS user_profiles_display_name_length;
ALTER TABLE public.user_profiles ADD CONSTRAINT user_profiles_display_name_length
  CHECK (display_name IS NULL OR char_length(display_name) <= 80) NOT VALID;
ALTER TABLE public.user_profiles DROP CONSTRAINT IF EXISTS user_profiles_school_length;
ALTER TABLE public.user_profiles ADD CONSTRAINT user_profiles_school_length
  CHECK (school IS NULL OR char_length(school) <= 150) NOT VALID;


-- ================================================================
-- CHECKS (run after, each should match the comment)
-- ================================================================
-- Logged-out visitors can no longer read profiles (expect: permission denied):
--   SET ROLE anon; SELECT email FROM public.user_profiles LIMIT 1; RESET ROLE;
-- The old two-argument reset function is gone (expect: 0 rows):
--   SELECT 1 FROM pg_proc WHERE proname = 'reset_user_password' AND pronargs = 2;
--
-- ROLLBACK (only if something breaks and you need the old behaviour):
--   Re-run the matching sections of supabase_schema.sql (sections 1, 3
--   and 10) and supabase_security_fixes.sql (section 4).
