-- ================================================================
-- CrimiReview Supabase Security Fixes
-- ================================================================
--
-- WHAT THIS FILE FIXES
--   1. `email_verifications` and `password_resets` had RLS policies of
--      `USING (true)` for SELECT -- meaning ANY anonymous request (just
--      the public anon key, which ships inside the app) could run
--      `SELECT * FROM password_resets` and read every pending
--      verification/reset code for every email address in the system.
--      That is a real account-takeover path: request a password reset
--      for someone else's email, read their code straight from the
--      table via the REST API, finish the reset yourself.
--
--      Root cause: the OLD Dart code (`EmailVerificationService`)
--      fetched the row with a plain `.select()` and compared the code
--      client-side, so the client HAD to be able to read the row for
--      the feature to work at all.
--
--   2. The Resend API key was hardcoded in `lib/services/
--      email_verification_service.dart` -- extractable from the
--      compiled app by anyone (Flutter apps decompile trivially into
--      readable strings). Whoever has it can send email as
--      noreply@crimireview.app through your account.
--
-- THE FIX, IN ONE SENTENCE
--   Move code generation, code comparison, AND the Resend HTTP call
--   entirely server-side into SECURITY DEFINER functions; the client
--   never sees a stored code and never holds the Resend key. The two
--   tables get zero direct client access -- only these functions may
--   touch them.
--
-- HOW TO RUN
--   1. Supabase Dashboard > SQL Editor.
--   2. FIRST, rotate your Resend key (the old one is already
--      compromised -- it has been sitting in this repo's Dart source):
--        a. https://resend.com/api-keys -> revoke the old key, create
--           a new one.
--        b. Store the NEW key in Supabase Vault by running, as its own
--           statement, BEFORE the rest of this file:
--
--              select vault.create_secret(
--                'PASTE_YOUR_NEW_RESEND_KEY_HERE',
--                'resend_api_key',
--                'CrimiReview transactional email (Resend)'
--              );
--
--           (Vault encrypts the value at rest. This create_secret call
--           itself will appear in your SQL Editor query history in
--           plaintext -- that is a Supabase Dashboard limitation, not
--           this file's; the key is still off the CLIENT, which is the
--           actual attack surface being closed here.)
--   3. Then paste and run the rest of this whole file.
--   4. Section 6 has verification queries -- run those to confirm.
--
-- PREREQUISITE EXTENSIONS
--   `http`   -- lets a Postgres function make an outbound HTTPS call
--              (to Resend). Ships with Supabase; enabled below.
--   `vault`  -- Supabase's encrypted secret store, backed by pgsodium.
--              Ships with every Supabase project; enabled below.
-- ================================================================


-- ================================================================
-- 1. EXTENSIONS
-- ================================================================
create extension if not exists http with schema extensions;
create extension if not exists supabase_vault;


-- ================================================================
-- 2. PRIVATE SCHEMA -- internal helpers, never exposed to PostgREST
-- ================================================================
-- A brand-new schema grants nothing to PUBLIC by default in modern
-- Postgres, so `anon`/`authenticated` have no USAGE on it unless we
-- explicitly grant it -- which we never do. Only SECURITY DEFINER
-- functions owned by the same role that created this schema (you, via
-- the SQL Editor) can reach inside it.

create schema if not exists private;

-- Fetches the Resend key out of Vault. Never granted EXECUTE to any
-- client role -- only called from inside the SECURITY DEFINER
-- functions in section 4, which run with the privileges to read it.
create or replace function private.get_resend_api_key()
returns text
language sql
stable
security definer
set search_path = vault, pg_temp
as $$
  select decrypted_secret
  from vault.decrypted_secrets
  where name = 'resend_api_key'
  limit 1;
$$;

create or replace function private.verification_email_html(p_code text)
returns text
language sql
immutable
set search_path = pg_temp
as $$
  select
    '<!DOCTYPE html><html><head><meta charset="utf-8">'
    '<meta name="viewport" content="width=device-width, initial-scale=1.0"></head>'
    '<body style="margin:0;padding:0;background-color:#0A0F1A;font-family:-apple-system,BlinkMacSystemFont,''Segoe UI'',Roboto,sans-serif;">'
    '<table width="100%" cellpadding="0" cellspacing="0" style="background-color:#0A0F1A;padding:40px 20px;"><tr><td align="center">'
    '<table width="100%" cellpadding="0" cellspacing="0" style="max-width:480px;background-color:#141B2D;border-radius:16px;overflow:hidden;">'
    '<tr><td style="padding:40px 32px;text-align:center;">'
    '<h1 style="margin:0 0 8px;font-size:28px;font-weight:700;color:#F5F5F5;">CrimiReview</h1>'
    '<p style="margin:0;font-size:14px;color:#9CA3AF;">Criminology Board Exam Reviewer</p>'
    '</td></tr>'
    '<tr><td style="padding:0 32px 32px;text-align:center;">'
    '<p style="margin:0 0 24px;font-size:16px;color:#F5F5F5;line-height:1.5;">Enter this code to verify your email:</p>'
    '<div style="background:linear-gradient(135deg,#8B5CF6 0%,#7C3AED 100%);border-radius:12px;padding:24px;margin-bottom:24px;">'
    '<span style="font-size:36px;font-weight:700;color:#FFFFFF;letter-spacing:8px;">' || p_code || '</span></div>'
    '<p style="margin:0;font-size:14px;color:#9CA3AF;line-height:1.5;">This code expires in 10 minutes.<br>If you didn''t request this, please ignore this email.</p>'
    '</td></tr>'
    '<tr><td style="padding:24px 32px;background-color:#0A0F1A;text-align:center;border-top:1px solid rgba(255,255,255,0.08);">'
    '<p style="margin:0;font-size:12px;color:#6B7280;">&copy; 2026 CrimiReview. All rights reserved.</p>'
    '</td></tr></table></td></tr></table></body></html>';
$$;

create or replace function private.password_reset_email_html(p_code text)
returns text
language sql
immutable
set search_path = pg_temp
as $$
  select
    '<!DOCTYPE html><html><head><meta charset="utf-8">'
    '<meta name="viewport" content="width=device-width, initial-scale=1.0"></head>'
    '<body style="margin:0;padding:0;background-color:#0A0F1A;font-family:-apple-system,BlinkMacSystemFont,''Segoe UI'',Roboto,sans-serif;">'
    '<table width="100%" cellpadding="0" cellspacing="0" style="background-color:#0A0F1A;padding:40px 20px;"><tr><td align="center">'
    '<table width="100%" cellpadding="0" cellspacing="0" style="max-width:480px;background-color:#141B2D;border-radius:16px;overflow:hidden;">'
    '<tr><td style="padding:40px 32px;text-align:center;">'
    '<h1 style="margin:0 0 8px;font-size:28px;font-weight:700;color:#F5F5F5;">CrimiReview</h1>'
    '<p style="margin:0;font-size:14px;color:#9CA3AF;">Password Reset Request</p>'
    '</td></tr>'
    '<tr><td style="padding:0 32px 32px;text-align:center;">'
    '<p style="margin:0 0 24px;font-size:16px;color:#F5F5F5;line-height:1.5;">Enter this code to reset your password:</p>'
    '<div style="background:linear-gradient(135deg,#EF4444 0%,#DC2626 100%);border-radius:12px;padding:24px;margin-bottom:24px;">'
    '<span style="font-size:36px;font-weight:700;color:#FFFFFF;letter-spacing:8px;">' || p_code || '</span></div>'
    '<p style="margin:0;font-size:14px;color:#9CA3AF;line-height:1.5;">This code expires in 10 minutes.<br>If you didn''t request this, please ignore this email.</p>'
    '</td></tr>'
    '<tr><td style="padding:24px 32px;background-color:#0A0F1A;text-align:center;border-top:1px solid rgba(255,255,255,0.08);">'
    '<p style="margin:0;font-size:12px;color:#6B7280;">&copy; 2026 CrimiReview. All rights reserved.</p>'
    '</td></tr></table></td></tr></table></body></html>';
$$;

-- Shared by both request_* functions -- fires the actual Resend call
-- and reports whether it succeeded. Never returns response BODY to the
-- caller (which could leak provider error detail); only true/false.
create or replace function private.send_transactional_email(
  p_to text,
  p_subject text,
  p_html text
)
returns boolean
language plpgsql
security definer
set search_path = extensions, private, pg_temp
as $$
declare
  v_api_key text;
  v_response extensions.http_response;
begin
  v_api_key := private.get_resend_api_key();
  if v_api_key is null or v_api_key = '' then
    raise warning 'resend_api_key not set in Vault -- see supabase_security_fixes.sql section 0';
    return false;
  end if;

  select * into v_response from extensions.http((
    'POST',
    'https://api.resend.com/emails',
    array[
      extensions.http_header('Authorization', 'Bearer ' || v_api_key),
      extensions.http_header('Content-Type', 'application/json')
    ],
    'application/json',
    jsonb_build_object(
      'from', 'CrimiReview <noreply@crimireview.app>',
      'to', jsonb_build_array(p_to),
      'subject', p_subject,
      'html', p_html
    )::text
  )::extensions.http_request);

  return v_response.status between 200 and 299;
exception when others then
  raise warning 'send_transactional_email failed: %', sqlerrm;
  return false;
end;
$$;


-- ================================================================
-- 3. LOCK DOWN THE TABLES -- this is the actual vulnerability fix
-- ================================================================
-- Drop every wide-open policy from both original SQL files, then
-- revoke direct table privileges from the client roles entirely. RLS
-- was already ON for both tables; with no policies AND no grants, a
-- direct REST call against either table now returns nothing / fails,
-- regardless of role. Only the SECURITY DEFINER functions below (owned
-- by the table owner, which bypasses RLS the normal Postgres way) can
-- still read/write them.

drop policy if exists "Anyone can request verification" on public.email_verifications;
drop policy if exists "Anyone can check their verification" on public.email_verifications;
drop policy if exists "Anyone can verify" on public.email_verifications;
drop policy if exists "Allow cleanup" on public.email_verifications;
revoke all on public.email_verifications from anon, authenticated;

drop policy if exists "Anyone can insert password reset" on public.password_resets;
drop policy if exists "Anyone can view password resets" on public.password_resets;
drop policy if exists "Anyone can update password resets" on public.password_resets;
drop policy if exists "Anyone can delete password resets" on public.password_resets;
revoke all on public.password_resets from anon, authenticated;


-- ================================================================
-- 4. PUBLIC RPCs -- the only door left into either table
-- ================================================================
-- Mirrors the exact methods lib/services/email_verification_service.dart
-- calls, so the Dart rewrite is a thin `.rpc(...)` wrapper per method,
-- nothing more. Every one of these returns jsonb {success, error?} --
-- consistent with what the old Dart maps already looked like.

-- ---- Email verification (signup) -------------------------------

create or replace function public.request_verification_code(p_email text)
returns jsonb
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_email text := lower(trim(p_email));
  v_code text;
  v_sent boolean;
begin
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    return jsonb_build_object('success', false, 'error', 'Enter a valid email address.');
  end if;

  v_code := lpad(floor(random() * 900000 + 100000)::int::text, 6, '0');

  delete from public.email_verifications
  where email = v_email and verified = false;

  insert into public.email_verifications (email, code, expires_at, verified, attempts)
  values (v_email, v_code, now() + interval '10 minutes', false, 0);

  v_sent := private.send_transactional_email(
    v_email,
    'CrimiReview - Verify Your Email',
    private.verification_email_html(v_code)
  );

  if not v_sent then
    delete from public.email_verifications where email = v_email and code = v_code;
    return jsonb_build_object('success', false, 'error', 'Failed to send email. Please try again.');
  end if;

  return jsonb_build_object('success', true);
end;
$$;

create or replace function public.confirm_verification_code(p_email text, p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_email text := lower(trim(p_email));
  rec record;
begin
  select * into rec from public.email_verifications
  where email = v_email and verified = false
  order by created_at desc
  limit 1;

  if not found then
    return jsonb_build_object('success', false, 'error', 'No pending verification found.');
  end if;

  if now() > rec.expires_at then
    delete from public.email_verifications where id = rec.id;
    return jsonb_build_object('success', false, 'error', 'Code has expired. Please request a new one.');
  end if;

  if rec.attempts >= 5 then
    delete from public.email_verifications where id = rec.id;
    return jsonb_build_object('success', false, 'error', 'Too many attempts. Please request a new code.');
  end if;

  if rec.code <> p_code then
    update public.email_verifications set attempts = attempts + 1 where id = rec.id;
    return jsonb_build_object(
      'success', false,
      'error', format('Invalid code. %s attempts remaining.', 5 - rec.attempts - 1)
    );
  end if;

  update public.email_verifications set verified = true where id = rec.id;
  return jsonb_build_object('success', true);
end;
$$;

-- ---- Password reset ----------------------------------------------

create or replace function public.request_password_reset(p_email text)
returns jsonb
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_email text := lower(trim(p_email));
  v_code text;
  v_sent boolean;
begin
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    return jsonb_build_object('success', false, 'error', 'Enter a valid email address.');
  end if;

  v_code := lpad(floor(random() * 900000 + 100000)::int::text, 6, '0');

  delete from public.password_resets
  where email = v_email and used = false;

  insert into public.password_resets (email, code, expires_at, used, attempts)
  values (v_email, v_code, now() + interval '10 minutes', false, 0);

  v_sent := private.send_transactional_email(
    v_email,
    'CrimiReview - Reset Your Password',
    private.password_reset_email_html(v_code)
  );

  if not v_sent then
    delete from public.password_resets where email = v_email and code = v_code;
    return jsonb_build_object('success', false, 'error', 'Failed to send email. Please try again.');
  end if;

  return jsonb_build_object('success', true);
end;
$$;

create or replace function public.confirm_password_reset_code(p_email text, p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_email text := lower(trim(p_email));
  rec record;
begin
  select * into rec from public.password_resets
  where email = v_email and used = false
  order by created_at desc
  limit 1;

  if not found then
    return jsonb_build_object('success', false, 'error', 'No pending reset found. Please request a new code.');
  end if;

  if now() > rec.expires_at then
    delete from public.password_resets where id = rec.id;
    return jsonb_build_object('success', false, 'error', 'Code has expired. Please request a new one.');
  end if;

  if rec.attempts >= 5 then
    delete from public.password_resets where id = rec.id;
    return jsonb_build_object('success', false, 'error', 'Too many attempts. Please request a new code.');
  end if;

  if rec.code <> p_code then
    update public.password_resets set attempts = attempts + 1 where id = rec.id;
    return jsonb_build_object(
      'success', false,
      'error', format('Invalid code. %s attempts remaining.', 5 - rec.attempts - 1)
    );
  end if;

  -- Marking used=true here is what public.reset_user_password() (see
  -- supabase_schema.sql section 10) checks for before it will touch
  -- auth.users -- this function is that gate.
  update public.password_resets set used = true where id = rec.id;
  return jsonb_build_object('success', true);
end;
$$;

-- Thin wrapper so the Dart client's post-reset cleanup call keeps
-- working. Actually redundant now -- reset_user_password() already
-- deletes matching rows on success -- kept as a harmless no-op safety
-- net rather than editing forgot_password_screen.dart's call site.
create or replace function public.cleanup_password_resets(p_email text)
returns void
language sql
security definer
set search_path = public, pg_temp
as $$
  delete from public.password_resets where email = lower(trim(p_email));
$$;

-- ---- Grants --------------------------------------------------------
-- These four (well, five) run for users who are NOT signed in yet
-- (mid-signup, mid-password-reset), so `anon` needs EXECUTE too.

revoke all on function public.request_verification_code(text) from public;
revoke all on function public.confirm_verification_code(text, text) from public;
revoke all on function public.request_password_reset(text) from public;
revoke all on function public.confirm_password_reset_code(text, text) from public;
revoke all on function public.cleanup_password_resets(text) from public;

grant execute on function public.request_verification_code(text) to anon, authenticated;
grant execute on function public.confirm_verification_code(text, text) to anon, authenticated;
grant execute on function public.request_password_reset(text) to anon, authenticated;
grant execute on function public.confirm_password_reset_code(text, text) to anon, authenticated;
grant execute on function public.cleanup_password_resets(text) to anon, authenticated;


-- ================================================================
-- 5. AUTH DASHBOARD SETTING -- cannot be done from SQL, do it manually
-- ================================================================
-- Authentication > Providers > Email > turn OFF "Confirm email".
--
-- This app's flow signs the user in immediately after the CUSTOM code
-- verification above succeeds -- it does not also wait for Supabase's
-- own separate confirmation email. If "Confirm email" is left ON,
-- `signUp()` will succeed but the immediate `signIn()` right after will
-- fail with "Email not confirmed", even though everything in this file
-- is working correctly.


-- ================================================================
-- 6. VERIFICATION -- run these after the migration to prove it worked
-- ================================================================
--
-- 6a. Direct table access must now be BLOCKED for anon/authenticated.
--     Run this as the anon role (i.e. via the app or a REST call with
--     just the anon key, not from the SQL Editor which runs as
--     postgres/service_role and bypasses RLS by design):
--       select * from email_verifications limit 1;
--     Expected: permission denied, or an empty result -- never actual
--     rows.
--
-- 6b. The Vault secret is set:
--       select name, created_at from vault.decrypted_secrets
--       where name = 'resend_api_key';
--     Expected: one row. If empty, go back to the top of this file.
--
-- 6c. Functions exist and are owned correctly:
--       select proname, prosecdef from pg_proc
--       where pronamespace = 'public'::regnamespace
--         and proname in (
--           'request_verification_code', 'confirm_verification_code',
--           'request_password_reset', 'confirm_password_reset_code'
--         );
--     Expected: 4 rows, prosecdef = true (SECURITY DEFINER) on all.
--
-- 6d. Smoke test the whole path from the SQL Editor (uses a real send,
--     so use an email you can check):
--       select public.request_verification_code('you@example.com');
--       -- check your inbox / spam, then:
--       select public.confirm_verification_code('you@example.com', '123456'); -- wrong code on purpose
--       -- expect {"success": false, "error": "Invalid code. 4 attempts remaining."}
--
-- ================================================================
-- END OF SECURITY FIXES
-- ================================================================
