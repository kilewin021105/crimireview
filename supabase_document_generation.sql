-- ================================================================
-- CrimiReview -- Document-to-Quiz Automatic Item Generation (LLM path)
-- ================================================================
-- Lets an admin/instructor upload a PDF reviewer document and have the
-- system read it and generate multiple-choice questions from it
-- automatically -- the LLM-driven counterpart to the slot-filling AIG
-- design already scaffolded in supabase_schema_v2.sql SECTION 5/6
-- (public.question_templates / public.concept_bank, Gierl & Lai
-- template method, "no LLM, no guessing"). That design is unchanged and
-- untouched by this file; this is a second, independent generation path
-- for admins who'd rather hand the system a document than build a
-- template + concept bank by hand. Both paths write to the SAME
-- public.questions table, tagged source = 'generated', so
-- QuestionRepository, MasteryService and QuestionSelectionService never
-- need to know which generator produced an item.
--
-- Review gate: generated items are inserted with is_active = FALSE.
-- Nothing new is needed for that gate -- it's the exact same soft
-- delete/restore flag AdminService.setActive() already uses, so
-- "approve" is the existing restore action and "reject" is the existing
-- delete action. See lib/services/document_generation_service.dart and
-- the "Generated" filter on AdminQuestionsScreen.
--
-- HOW TO RUN: Supabase SQL Editor, paste, Run. Safe to re-run.
-- ================================================================


-- ================================================================
-- 1. public.document_uploads
-- ================================================================
-- One row per uploaded document. The Edge Function
-- (supabase/functions/generate-questions-from-document) walks this
-- table's lifecycle: pending -> processing -> completed | failed. The
-- admin app's "Generate from Document" screen watches this table via
-- Supabase Realtime instead of polling.

CREATE TABLE IF NOT EXISTS public.document_uploads (
  id                TEXT PRIMARY KEY,
  filename          TEXT NOT NULL,
  storage_path      TEXT NOT NULL,
  subject_id        TEXT NOT NULL,
  topic             TEXT,
  target_difficulty TEXT
                      CHECK (target_difficulty IS NULL OR target_difficulty IN ('easy', 'medium', 'hard')),
  requested_count   INTEGER NOT NULL DEFAULT 10 CHECK (requested_count BETWEEN 1 AND 30),
  status            TEXT NOT NULL DEFAULT 'pending'
                      CHECK (status IN ('pending', 'processing', 'completed', 'failed')),
  generated_count   INTEGER NOT NULL DEFAULT 0,
  error_message     TEXT,
  uploaded_by       UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at        TIMESTAMPTZ DEFAULT NOW(),
  completed_at      TIMESTAMPTZ
);

-- Self-healing, same convention as every other table in supabase_schema_v2.sql.
ALTER TABLE public.document_uploads ADD COLUMN IF NOT EXISTS filename          TEXT;
ALTER TABLE public.document_uploads ADD COLUMN IF NOT EXISTS storage_path      TEXT;
ALTER TABLE public.document_uploads ADD COLUMN IF NOT EXISTS subject_id        TEXT;
ALTER TABLE public.document_uploads ADD COLUMN IF NOT EXISTS topic             TEXT;
ALTER TABLE public.document_uploads ADD COLUMN IF NOT EXISTS target_difficulty TEXT;
ALTER TABLE public.document_uploads ADD COLUMN IF NOT EXISTS requested_count   INTEGER DEFAULT 10;
ALTER TABLE public.document_uploads ADD COLUMN IF NOT EXISTS status            TEXT DEFAULT 'pending';
ALTER TABLE public.document_uploads ADD COLUMN IF NOT EXISTS generated_count   INTEGER DEFAULT 0;
ALTER TABLE public.document_uploads ADD COLUMN IF NOT EXISTS error_message     TEXT;
ALTER TABLE public.document_uploads ADD COLUMN IF NOT EXISTS uploaded_by       UUID;
ALTER TABLE public.document_uploads ADD COLUMN IF NOT EXISTS created_at        TIMESTAMPTZ DEFAULT NOW();
ALTER TABLE public.document_uploads ADD COLUMN IF NOT EXISTS completed_at      TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_document_uploads_status
  ON public.document_uploads(status);
CREATE INDEX IF NOT EXISTS idx_document_uploads_created
  ON public.document_uploads(created_at DESC);

ALTER TABLE public.document_uploads ENABLE ROW LEVEL SECURITY;

-- Admin-only end to end: this screen never appears to a student, and the
-- source PDF may contain a whole reviewer's worth of proprietary content.
DROP POLICY IF EXISTS "Admins can manage document uploads" ON public.document_uploads;
CREATE POLICY "Admins can manage document uploads" ON public.document_uploads
  FOR ALL TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

GRANT SELECT, INSERT, UPDATE, DELETE ON public.document_uploads TO authenticated;
-- The Edge Function runs as service_role, which already bypasses RLS by
-- default -- no extra grant needed for it.


-- ================================================================
-- 2. Storage bucket: document-uploads
-- ================================================================
-- Holds the raw PDFs admins upload. Private (not public), admin-only,
-- same shape as the existing `avatars` bucket
-- (SupabaseService.uploadAvatar) but locked to admins instead of
-- self-service by the owning user.

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('document-uploads', 'document-uploads', FALSE, 33554432, ARRAY['application/pdf'])
ON CONFLICT (id) DO UPDATE
  SET file_size_limit = EXCLUDED.file_size_limit,
      allowed_mime_types = EXCLUDED.allowed_mime_types;

DROP POLICY IF EXISTS "Admins can upload documents" ON storage.objects;
CREATE POLICY "Admins can upload documents" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'document-uploads' AND public.is_admin());

DROP POLICY IF EXISTS "Admins can read documents" ON storage.objects;
CREATE POLICY "Admins can read documents" ON storage.objects
  FOR SELECT TO authenticated
  USING (bucket_id = 'document-uploads' AND public.is_admin());

DROP POLICY IF EXISTS "Admins can delete documents" ON storage.objects;
CREATE POLICY "Admins can delete documents" ON storage.objects
  FOR DELETE TO authenticated
  USING (bucket_id = 'document-uploads' AND public.is_admin());
-- service_role (the Edge Function) bypasses storage RLS too, so it can
-- always download what an admin just uploaded.
