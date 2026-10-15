-- ================================================================
-- CrimiReview -- Google and Facebook sign-in
-- ================================================================
-- Run once in the SQL Editor (safe to run again). It does not switch
-- Google or Facebook on by itself; that is done in the dashboard, see
-- README "Google and Facebook sign-in".
--
-- What it changes:
--   handle_new_user() creates the user_profiles row for every new
--   account. Before, it only knew the `display_name` the app sends at
--   email sign-up, so a Google or Facebook account would have been named
--   after its email address ("juan.delacruz") with no photo. Now it also
--   reads the name and photo that Google / Facebook send.
--
-- Email sign-ups are unchanged: the app always sends `display_name`,
-- and it is still used first.
--
-- Pair with supabase_enforce_email_verification.sql: that file makes the
-- database refuse an email sign-up that skipped the emailed code, and it
-- already lets Google and Facebook accounts through.
-- ================================================================

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $handle$
DECLARE
  meta     jsonb := COALESCE(NEW.raw_user_meta_data, '{}'::jsonb);
  -- Written by Supabase Auth itself, never by the app, so it can be trusted.
  provider text  := COALESCE(NEW.raw_app_meta_data->>'provider', 'email');
  name     text;
  photo    text;
BEGIN
  name := COALESCE(
    NULLIF(btrim(meta->>'display_name'), ''),  -- email sign-up (from the app)
    NULLIF(btrim(meta->>'full_name'), ''),     -- Google / Facebook
    NULLIF(btrim(meta->>'name'), ''),
    NULLIF(split_part(COALESCE(NEW.email, ''), '@', 1), ''),
    'Student'
  );

  -- A photo is only taken from Google / Facebook, and only over https.
  IF provider IN ('google', 'facebook') THEN
    photo := NULLIF(btrim(COALESCE(meta->>'avatar_url', meta->>'picture', '')), '');
    IF photo IS NOT NULL AND (photo !~* '^https://' OR char_length(photo) > 1000) THEN
      photo := NULL;
    END IF;
  END IF;

  INSERT INTO public.user_profiles (id, email, display_name, avatar_url)
  VALUES (NEW.id, NEW.email, left(name, 80), photo);  -- 80 = display_name limit
  RETURN NEW;
END;
$handle$;

-- ROLLBACK (the previous version):
--   CREATE OR REPLACE FUNCTION public.handle_new_user()
--   RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
--   BEGIN
--     INSERT INTO public.user_profiles (id, email, display_name)
--     VALUES (NEW.id, NEW.email,
--       COALESCE(NEW.raw_user_meta_data->>'display_name', split_part(NEW.email, '@', 1)));
--     RETURN NEW;
--   END; $$;
