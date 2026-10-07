-- ================================================================
-- CrimiReview -- Remove the "Generate from Document" (PDF -> AI) path
-- ================================================================
-- The app no longer generates questions from uploaded PDFs; only the
-- template method (supabase_template_generation.sql) remains. This file
-- removes the database objects the old PDF path created.
--
-- NOT touched: public.questions. Any questions the PDF path already
-- generated stay in the bank (source = 'generated') -- review, keep or
-- delete them from Admin Panel -> Questions -> "Generated only" like any
-- other item.
--
-- Two leftovers SQL can't remove -- do these by hand in the Dashboard:
--   1. Storage -> bucket "document-uploads" -> Empty bucket, then Delete
--      bucket. (Supabase blocks deleting storage rows directly from SQL.)
--   2. Edge Functions -> "generate-questions-from-document" -> Delete.
--      Or CLI: supabase functions delete generate-questions-from-document
--              --project-ref wbhobbehgqlzfborscvx
--   Optionally also remove the ANTHROPIC_API_KEY secret
--   (Edge Functions -> Secrets) if nothing else uses it.
--
-- HOW TO RUN: Supabase SQL Editor, paste, Run. Safe to re-run.
-- ================================================================

DROP POLICY IF EXISTS "Admins can upload documents" ON storage.objects;
DROP POLICY IF EXISTS "Admins can read documents"   ON storage.objects;
DROP POLICY IF EXISTS "Admins can delete documents" ON storage.objects;

DROP TABLE IF EXISTS public.document_uploads;
