-- ================================================================
-- CrimiReview -- Require the 6-digit email code before an account exists
-- ================================================================
-- Problem: the app checks the emailed code and only then calls Supabase
-- sign-up, but Supabase's sign-up API is public. Anyone can call it
-- directly and create an account for an email address they don't own,
-- skipping the code entirely.
--
-- Fix: the database itself refuses to create an account unless that
-- email passed confirm_verification_code() in the last 30 minutes.
--
-- RUN AFTER supabase_security_fixes_v2.sql. Then IMMEDIATELY test: sign
-- up a brand-new account in the app. If sign-up fails with "Database
-- error saving new user", run the ROLLBACK line at the bottom and tell
-- your developer.
--
-- ADDING A USER BY HAND (Dashboard -> Authentication -> Add user) now
-- needs one line in the SQL Editor first, replacing the email:
--   INSERT INTO public.email_verifications (email, code, expires_at, verified)
--   VALUES (lower('person@example.com'), 'manual', now() + interval '10 minutes', true);
-- ================================================================

CREATE OR REPLACE FUNCTION public.require_verified_email()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $require$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.email_verifications
    WHERE email = lower(btrim(NEW.email))
      AND verified = true
      AND created_at > now() - interval '30 minutes'
  ) THEN
    RAISE EXCEPTION 'Email address has not been verified'
      USING ERRCODE = 'check_violation';
  END IF;

  -- One verification creates one account.
  DELETE FROM public.email_verifications WHERE email = lower(btrim(NEW.email));
  RETURN NEW;
END;
$require$;

REVOKE ALL ON FUNCTION public.require_verified_email() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS require_verified_email_before_signup ON auth.users;
CREATE TRIGGER require_verified_email_before_signup
  BEFORE INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.require_verified_email();

-- ROLLBACK:
--   DROP TRIGGER IF EXISTS require_verified_email_before_signup ON auth.users;
