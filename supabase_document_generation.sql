-- ================================================================
-- CrimiReview -- Generate questions from a PDF (Google Gemini)
-- ================================================================
-- Lets a faculty member upload a PDF (a reviewer, a new law, a revised
-- syllabus) and have the Edge Function
-- supabase/functions/generate-questions-from-document send it to Google
-- Gemini, which writes multiple-choice questions drawn only from that
-- document. This is how the question bank keeps up when the curriculum
-- or the laws change.
--
-- Review gate: every generated question is inserted with
-- is_active = FALSE, source = 'generated' and template_id = the upload's
-- id. Students never see it until a faculty member approves it in the
-- app (Admin Panel -> Questions -> PDF icon -> Review). Approving is the
-- same AdminService.setActive() call as restoring any question.
--
-- Restores the feature removed on 2026-10-07 (it used the paid Claude
-- API and was never switched on). supabase_security_fixes_v2.sql section
-- 8 dropped the old table and its storage policies; this file recreates
-- them. To remove the feature again run
-- supabase_remove_document_generation.sql.
--
-- HOW TO RUN: Supabase SQL Editor, paste, Run. Safe to re-run.
-- Then deploy the Edge Function and set the GEMINI_API_KEY secret
-- (README, "Generate questions from a PDF").
-- ================================================================


-- ================================================================
-- 1. public.document_uploads -- one row per uploaded PDF
-- ================================================================
-- Lifecycle, written only by the Edge Function after the app inserts the
-- row: pending -> processing -> completed | failed.

CREATE TABLE IF NOT EXISTS public.document_uploads (
  id                TEXT PRIMARY KEY,
  filename          TEXT NOT NULL,
  storage_path      TEXT NOT NULL,
  subject_id        TEXT NOT NULL,
  topic             TEXT,
  target_difficulty TEXT
                      CHECK (target_difficulty IS NULL OR target_difficulty IN ('easy', 'medium', 'hard')),
  requested_count   INTEGER NOT NULL DEFAULT 10 CHECK (requested_count BETWEEN 1 AND 20),
  status            TEXT NOT NULL DEFAULT 'pending'
                      CHECK (status IN ('pending', 'processing', 'completed', 'failed')),
  generated_count   INTEGER NOT NULL DEFAULT 0,
  error_message     TEXT,
  uploaded_by       UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at        TIMESTAMPTZ DEFAULT NOW(),
  completed_at      TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_document_uploads_created
  ON public.document_uploads(created_at DESC);

ALTER TABLE public.document_uploads ENABLE ROW LEVEL SECURITY;

-- Faculty (admins) only. Students and logged-out visitors get nothing.
DROP POLICY IF EXISTS "Admins can manage document uploads" ON public.document_uploads;
DROP POLICY IF EXISTS "Admins can read document uploads"   ON public.document_uploads;
DROP POLICY IF EXISTS "Admins can add document uploads"    ON public.document_uploads;
DROP POLICY IF EXISTS "Admins can delete document uploads" ON public.document_uploads;

CREATE POLICY "Admins can read document uploads" ON public.document_uploads
  FOR SELECT TO authenticated
  USING (public.is_admin());

-- The app may only create a fresh request under its own name. Status,
-- counts and errors are written by the Edge Function (service role), so
-- there is no UPDATE policy for the app at all.
CREATE POLICY "Admins can add document uploads" ON public.document_uploads
  FOR INSERT TO authenticated
  WITH CHECK (public.is_admin()
              AND uploaded_by = auth.uid()
              AND status = 'pending'
              AND generated_count = 0
              AND error_message IS NULL
              AND completed_at IS NULL);

CREATE POLICY "Admins can delete document uploads" ON public.document_uploads
  FOR DELETE TO authenticated
  USING (public.is_admin());

REVOKE ALL ON public.document_uploads FROM anon;
REVOKE ALL ON public.document_uploads FROM authenticated;
GRANT SELECT, INSERT, DELETE ON public.document_uploads TO authenticated;


-- ================================================================
-- 2. Storage bucket: document-uploads (private, PDF only, 20 MB)
-- ================================================================
-- 20 MB keeps the request the Edge Function sends to Gemini well inside
-- Gemini's inline limit once the file is base64-encoded.

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('document-uploads', 'document-uploads', FALSE, 20971520, ARRAY['application/pdf'])
ON CONFLICT (id) DO UPDATE
  SET public = FALSE,
      file_size_limit = EXCLUDED.file_size_limit,
      allowed_mime_types = EXCLUDED.allowed_mime_types;

DROP POLICY IF EXISTS "Admins can upload documents" ON storage.objects;
CREATE POLICY "Admins can upload documents" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'document-uploads'
              AND public.is_admin()
              AND (storage.foldername(name))[1] = auth.uid()::text);

DROP POLICY IF EXISTS "Admins can read documents" ON storage.objects;
CREATE POLICY "Admins can read documents" ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'document-uploads' AND public.is_admin());

DROP POLICY IF EXISTS "Admins can delete documents" ON storage.objects;
CREATE POLICY "Admins can delete documents" ON storage.objects
  FOR DELETE TO authenticated
  USING (bucket_id = 'document-uploads' AND public.is_admin());
-- The Edge Function uses the service role, which bypasses these policies,
-- so it can always download what a faculty member just uploaded.
