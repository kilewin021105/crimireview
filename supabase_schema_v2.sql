-- ================================================================
-- CrimiReview Supabase Schema  --  V2 MIGRATION
-- Adaptive Learning / Admin Question Bank / Automatic Item Generation
-- ================================================================
--
-- WHAT THIS FILE IS
--   An ADDITIVE, IDEMPOTENT migration that runs ON TOP OF the existing
--   supabase_schema.sql. It does NOT drop, rename or modify any existing
--   table. You may paste it into Supabase SQL Editor and run it as many
--   times as you like -- every statement is CREATE ... IF NOT EXISTS,
--   DROP POLICY IF EXISTS + CREATE POLICY, ALTER TABLE ... ADD COLUMN
--   IF NOT EXISTS, or CREATE OR REPLACE.
--
-- HOW TO RUN
--   1. Supabase Dashboard > SQL Editor > New query
--   2. Paste this whole file, press RUN.
--   3. Scroll to SECTION 13 and make yourself an admin.
--   4. Scroll to SECTION 14 and run the verification queries.
--
-- WHY IT EXISTS (panel notes it answers)
--   Note 1  Questions must be generated AUTOMATICALLY
--             -> SECTION 5 question_templates + SECTION 6 concept_bank
--                (Automatic Item Generation, Gierl & Lai)
--   Note 2  ML must MONITOR STUDENT PROGRESS
--             -> SECTION 7 topic_mastery (Bayesian Knowledge Tracing state)
--                SECTION 9 question_attempts (the training / audit trail)
--   Note 3  Repeat the TOPIC but NOT THE SAME QUESTION
--             -> SECTION 8 question_exposure (per-learner exposure ledger)
--   Note 4  Adaptive learning must have a citable BASIS
--             -> BKT (Corbett & Anderson, 1995) is stored explicitly as
--                p_known, not as a hardcoded if/else accuracy ladder
--   Note 5  The app must explain WHY MY ANSWER IS WRONG
--             -> questions.options JSONB carries a per-option `rationale`,
--                plus legal_basis and remediation_hint
--   Note 7  NO questions inside the code; there must be an ADMIN
--             -> SECTION 4 public.questions is the single source of truth,
--                SECTION 1 role column, SECTION 2 is_admin(),
--                SECTION 10 admin_audit_log
--
-- NAMING CONVENTIONS (inherited from supabase_schema.sql)
--   * snake_case columns, TEXT ids for content, UUID ids for rows
--   * subject_id values MUST match lib/models/subject.dart:
--       criminal_jurisprudence, law_enforcement, criminalistics,
--       crime_detection, criminology, corrections
--   * difficulty values MUST match Dart enum Difficulty: easy | medium | hard
--   * source values MUST match Dart enum QuestionSource: admin | generated | imported
-- ================================================================


-- ================================================================
-- 1. PREREQUISITE: ADMIN ROLE ON user_profiles
-- ================================================================
-- Panel note 7: "It should have an ADMIN to add questions."
-- We do NOT create a second users table. We add one role column to the
-- profile table that already exists, so handle_new_user() keeps working
-- untouched (new signups fall to the DEFAULT 'student').

ALTER TABLE public.user_profiles
  ADD COLUMN IF NOT EXISTS role TEXT DEFAULT 'student';

-- Backfill any pre-existing rows created before this migration.
UPDATE public.user_profiles SET role = 'student' WHERE role IS NULL;

-- Named CHECK constraint added defensively: ADD CONSTRAINT has no
-- IF NOT EXISTS form, so we look it up in the catalog first.
DO $role_check$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'user_profiles_role_check'
      AND conrelid = 'public.user_profiles'::regclass
  ) THEN
    ALTER TABLE public.user_profiles
      ADD CONSTRAINT user_profiles_role_check
      CHECK (role IN ('student', 'admin'));
  END IF;
END
$role_check$;

CREATE INDEX IF NOT EXISTS idx_user_profiles_role
  ON public.user_profiles(role);

-- IMPORTANT: a student must never be able to promote themselves.
-- The existing "Users can update own profile" policy is FOR UPDATE
-- USING (auth.uid() = id) with no WITH CHECK, so a student could PATCH
-- their own role to 'admin'. This trigger closes that hole at the DB
-- level without editing the original schema file.
CREATE OR REPLACE FUNCTION public.protect_user_role()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $protect_role$
BEGIN
  -- Role may only change when the CALLER is already an admin.
  -- auth.uid() is NULL for service_role / SQL Editor, which is allowed
  -- so that SECTION 13 (bootstrap your first admin) still works.
  IF NEW.role IS DISTINCT FROM OLD.role THEN
    IF auth.uid() IS NOT NULL AND NOT public.is_admin() THEN
      NEW.role := OLD.role;   -- silently ignore the escalation attempt
    END IF;
  END IF;
  RETURN NEW;
END;
$protect_role$;


-- ================================================================
-- 2. ADMIN HELPER: public.is_admin()
-- ================================================================
-- Used by nearly every policy below, and by AdminService.isAdmin().
--
-- SECURITY DEFINER + a pinned search_path is deliberate:
--   * SECURITY DEFINER makes the function run as its owner (postgres,
--     the owner of user_profiles). A table owner bypasses RLS unless
--     FORCE ROW LEVEL SECURITY is set, so this CANNOT recurse into the
--     RLS policies of user_profiles -- no infinite policy recursion,
--     which is the classic Supabase "stack depth exceeded" bug.
--   * SET search_path = public, pg_temp stops a malicious temp-schema
--     object from shadowing user_profiles inside a definer function.
--   * STABLE lets the planner cache it per statement instead of
--     re-running it once per row in a policy.

CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $is_admin$
  SELECT EXISTS (
    SELECT 1
    FROM public.user_profiles
    WHERE id = auth.uid()
      AND role = 'admin'
  );
$is_admin$;

REVOKE ALL ON FUNCTION public.is_admin() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_admin() TO anon, authenticated, service_role;

-- Now that is_admin() exists, arm the role-escalation guard from SECTION 1.
DROP TRIGGER IF EXISTS protect_user_role_trigger ON public.user_profiles;
CREATE TRIGGER protect_user_role_trigger
  BEFORE UPDATE OF role ON public.user_profiles
  FOR EACH ROW EXECUTE FUNCTION public.protect_user_role();


-- ================================================================
-- 3. SHARED TRIGGER FUNCTIONS
-- ================================================================

-- 3a. Generic updated_at touch. Reused by several tables below.
CREATE OR REPLACE FUNCTION public.touch_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $touch$
BEGIN
  NEW.updated_at := NOW();
  RETURN NEW;
END;
$touch$;

-- 3b. Keep questions.correct_answer_index in sync with the is_correct
--     flag inside the options JSONB. This is the single most important
--     data-integrity rule in the whole app: if these two ever disagree,
--     the quiz marks a right answer wrong and the explanation engine
--     shows the wrong rationale.
--
--     Behaviour:
--       * If exactly one option has "is_correct": true -> the index is
--         recomputed from the JSONB (JSONB wins).
--       * If NO option is flagged -> we trust correct_answer_index and
--         stamp the flags back into the JSONB (index wins). This makes
--         plain bulk imports that only supply an index work fine.
--       * Rejects malformed payloads (not an array, fewer than 2
--         options, more than one correct option, blank option text).
CREATE OR REPLACE FUNCTION public.sync_question_correct_index()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $sync_idx$
DECLARE
  opt_count   INT;
  flag_count  INT;
  found_idx   INT;
BEGIN
  IF NEW.options IS NULL OR jsonb_typeof(NEW.options) <> 'array' THEN
    RAISE EXCEPTION 'questions.options must be a JSON array of {text, is_correct, rationale}';
  END IF;

  SELECT COUNT(*) INTO opt_count FROM jsonb_array_elements(NEW.options);
  IF opt_count < 2 THEN
    RAISE EXCEPTION 'questions.options must contain at least 2 options (got %)', opt_count;
  END IF;

  IF EXISTS (
    SELECT 1 FROM jsonb_array_elements(NEW.options) AS o(opt)
    WHERE COALESCE(TRIM(opt->>'text'), '') = ''
  ) THEN
    RAISE EXCEPTION 'every entry in questions.options needs a non-empty "text"';
  END IF;

  SELECT COUNT(*) INTO flag_count
  FROM jsonb_array_elements(NEW.options) AS o(opt)
  WHERE COALESCE((opt->>'is_correct')::BOOLEAN, FALSE);

  IF flag_count > 1 THEN
    RAISE EXCEPTION 'exactly one option may have is_correct = true (got %)', flag_count;
  END IF;

  IF flag_count = 1 THEN
    -- JSONB is authoritative: recompute the index.
    SELECT (ord - 1) INTO found_idx
    FROM jsonb_array_elements(NEW.options) WITH ORDINALITY AS t(opt, ord)
    WHERE COALESCE((opt->>'is_correct')::BOOLEAN, FALSE)
    LIMIT 1;

    NEW.correct_answer_index := found_idx;
  ELSE
    -- Nothing flagged: the index is authoritative, write the flags back.
    NEW.correct_answer_index := COALESCE(NEW.correct_answer_index, 0);

    IF NEW.correct_answer_index < 0 OR NEW.correct_answer_index >= opt_count THEN
      RAISE EXCEPTION 'correct_answer_index % is out of range for % options',
        NEW.correct_answer_index, opt_count;
    END IF;

    SELECT jsonb_agg(
             CASE
               WHEN (ord - 1) = NEW.correct_answer_index
                 THEN opt || '{"is_correct": true}'::JSONB
               ELSE opt || '{"is_correct": false}'::JSONB
             END
             ORDER BY ord)
      INTO NEW.options
      FROM jsonb_array_elements(NEW.options) WITH ORDINALITY AS t(opt, ord);
  END IF;

  RETURN NEW;
END;
$sync_idx$;


-- ================================================================
-- 4. public.questions  --  THE SINGLE SOURCE OF TRUTH
-- ================================================================
-- Panel note 7: "Do NOT put your questions in your code."
-- After this migration, lib/data/questions_database.dart and
-- lib/data/question_bank.dart are dead. QuestionRepository reads this
-- table only (plus a SharedPreferences snapshot for offline use).
--
-- options JSONB shape -- ONE array element per choice:
--   [
--     {"text": "Unlawful aggression", "is_correct": true,
--      "rationale": "Correct. Unlawful aggression is the indispensable
--                    requisite; without it there is no self-defense."},
--     {"text": "Sufficient provocation", "is_correct": false,
--      "rationale": "Wrong. Lack of sufficient provocation is the THIRD
--                    requisite, not the indispensable one."}
--   ]
-- The per-option `rationale` is what makes panel note 5 possible:
-- the app can say why the option the STUDENT picked is wrong, not just
-- why the key is right.

CREATE TABLE IF NOT EXISTS public.questions (
  id                   TEXT PRIMARY KEY,
  subject_id           TEXT NOT NULL,
  topic                TEXT NOT NULL,
  question_text        TEXT NOT NULL,
  options              JSONB NOT NULL,
  correct_answer_index INTEGER NOT NULL DEFAULT 0,
  explanation          TEXT DEFAULT '',
  legal_basis          TEXT,
  remediation_hint     TEXT,
  difficulty           TEXT NOT NULL DEFAULT 'medium'
                         CHECK (difficulty IN ('easy', 'medium', 'hard')),
  source               TEXT NOT NULL DEFAULT 'admin'
                         CHECK (source IN ('admin', 'generated', 'imported')),
  template_id          TEXT,
  version              INTEGER NOT NULL DEFAULT 1,
  is_active            BOOLEAN NOT NULL DEFAULT TRUE,
  created_by           UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at           TIMESTAMPTZ DEFAULT NOW(),
  updated_at           TIMESTAMPTZ DEFAULT NOW()
);

-- Self-healing: if a partial `questions` table already existed (an early
-- build of question_service.dart queried one), top it up column by column.
ALTER TABLE public.questions ADD COLUMN IF NOT EXISTS subject_id           TEXT;
ALTER TABLE public.questions ADD COLUMN IF NOT EXISTS topic                TEXT;
ALTER TABLE public.questions ADD COLUMN IF NOT EXISTS question_text        TEXT;
ALTER TABLE public.questions ADD COLUMN IF NOT EXISTS options              JSONB;
ALTER TABLE public.questions ADD COLUMN IF NOT EXISTS correct_answer_index INTEGER DEFAULT 0;
ALTER TABLE public.questions ADD COLUMN IF NOT EXISTS explanation          TEXT DEFAULT '';
ALTER TABLE public.questions ADD COLUMN IF NOT EXISTS legal_basis          TEXT;
ALTER TABLE public.questions ADD COLUMN IF NOT EXISTS remediation_hint     TEXT;
ALTER TABLE public.questions ADD COLUMN IF NOT EXISTS difficulty           TEXT DEFAULT 'medium';
ALTER TABLE public.questions ADD COLUMN IF NOT EXISTS source               TEXT DEFAULT 'admin';
ALTER TABLE public.questions ADD COLUMN IF NOT EXISTS template_id          TEXT;
ALTER TABLE public.questions ADD COLUMN IF NOT EXISTS version              INTEGER DEFAULT 1;
ALTER TABLE public.questions ADD COLUMN IF NOT EXISTS is_active            BOOLEAN DEFAULT TRUE;
ALTER TABLE public.questions ADD COLUMN IF NOT EXISTS created_by           UUID;
ALTER TABLE public.questions ADD COLUMN IF NOT EXISTS created_at           TIMESTAMPTZ DEFAULT NOW();
ALTER TABLE public.questions ADD COLUMN IF NOT EXISTS updated_at           TIMESTAMPTZ DEFAULT NOW();

-- Indexes: the three access paths QuestionRepository actually uses.
CREATE INDEX IF NOT EXISTS idx_questions_subject_difficulty
  ON public.questions(subject_id, difficulty);
CREATE INDEX IF NOT EXISTS idx_questions_topic
  ON public.questions(topic);
CREATE INDEX IF NOT EXISTS idx_questions_is_active
  ON public.questions(is_active);
-- Covering index for the hot path: "active questions for this subject".
CREATE INDEX IF NOT EXISTS idx_questions_active_subject
  ON public.questions(subject_id, difficulty) WHERE is_active;
-- Lets QuestionGenerationService find and dedupe what a template produced.
CREATE INDEX IF NOT EXISTS idx_questions_template
  ON public.questions(template_id) WHERE template_id IS NOT NULL;
-- Cheap duplicate guard for auto-generation: the same stem can never be
-- published twice for the same subject. Wrapped so that a pre-existing
-- table that already holds duplicates warns instead of aborting the
-- whole migration.
DO $stem_uq$
BEGIN
  CREATE UNIQUE INDEX IF NOT EXISTS uq_questions_subject_stem
    ON public.questions(subject_id, md5(lower(question_text)));
EXCEPTION WHEN unique_violation OR duplicate_table THEN
  RAISE NOTICE 'Skipped uq_questions_subject_stem: duplicate question stems already exist. Clean them up, then re-run.';
END
$stem_uq$;

-- Triggers
DROP TRIGGER IF EXISTS questions_touch_updated_at ON public.questions;
CREATE TRIGGER questions_touch_updated_at
  BEFORE UPDATE ON public.questions
  FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

DROP TRIGGER IF EXISTS questions_sync_correct_index ON public.questions;
CREATE TRIGGER questions_sync_correct_index
  BEFORE INSERT OR UPDATE OF options, correct_answer_index ON public.questions
  FOR EACH ROW EXECUTE FUNCTION public.sync_question_correct_index();

-- RLS
ALTER TABLE public.questions ENABLE ROW LEVEL SECURITY;

-- Read: everyone (including anon, so the app can warm its cache before
-- login) may read ACTIVE questions only.
DROP POLICY IF EXISTS "Anyone can read active questions" ON public.questions;
CREATE POLICY "Anyone can read active questions" ON public.questions
  FOR SELECT TO anon, authenticated
  USING (is_active = TRUE);

-- Read: admins additionally see soft-deleted rows
-- (AdminService.listQuestions(includeInactive: true)).
DROP POLICY IF EXISTS "Admins can read all questions" ON public.questions;
CREATE POLICY "Admins can read all questions" ON public.questions
  FOR SELECT TO authenticated
  USING (public.is_admin());

DROP POLICY IF EXISTS "Admins can insert questions" ON public.questions;
CREATE POLICY "Admins can insert questions" ON public.questions
  FOR INSERT TO authenticated
  WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS "Admins can update questions" ON public.questions;
CREATE POLICY "Admins can update questions" ON public.questions
  FOR UPDATE TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS "Admins can delete questions" ON public.questions;
CREATE POLICY "Admins can delete questions" ON public.questions
  FOR DELETE TO authenticated
  USING (public.is_admin());

GRANT SELECT ON public.questions TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.questions TO authenticated;


-- ================================================================
-- 5. public.question_templates  --  AUTOMATIC ITEM GENERATION (part 1)
-- ================================================================
-- Panel note 1: "Should generate a question Automatically."
--
-- Theoretical basis: Gierl & Lai's Automatic Item Generation. An ITEM
-- MODEL is a stem template with SLOTS; the slots are filled from a
-- structured content store (SECTION 6). This is not "random questions",
-- it is a documented psychometric method you can cite in the RRL.
--
-- Placeholders understood by QuestionGenerationService:
--   {{term}}        -> concept_bank.term
--   {{definition}}  -> concept_bank.definition        (used as the KEY)
--   {{legal_basis}} -> concept_bank.legal_basis
--   {{topic}}       -> concept_bank.topic
-- rationale_template additionally understands:
--   {{option_term}}, {{option_definition}}  -> the SIBLING concept whose
--   definition became this distractor, so every wrong choice ships with
--   a real, specific reason (panel note 5).

CREATE TABLE IF NOT EXISTS public.question_templates (
  id                   TEXT PRIMARY KEY,
  subject_id           TEXT NOT NULL,
  topic                TEXT NOT NULL,
  stem_template        TEXT NOT NULL,     -- MUST contain a {{term}} slot
  difficulty           TEXT NOT NULL DEFAULT 'medium'
                         CHECK (difficulty IN ('easy', 'medium', 'hard')),
  distractor_strategy  TEXT NOT NULL DEFAULT 'sibling_definitions',
  rationale_template   TEXT,
  explanation_template TEXT,
  is_active            BOOLEAN NOT NULL DEFAULT TRUE,
  created_at           TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.question_templates ADD COLUMN IF NOT EXISTS rationale_template   TEXT;
ALTER TABLE public.question_templates ADD COLUMN IF NOT EXISTS explanation_template TEXT;
ALTER TABLE public.question_templates ADD COLUMN IF NOT EXISTS distractor_strategy  TEXT DEFAULT 'sibling_definitions';
ALTER TABLE public.question_templates ADD COLUMN IF NOT EXISTS is_active            BOOLEAN DEFAULT TRUE;

CREATE INDEX IF NOT EXISTS idx_question_templates_subject
  ON public.question_templates(subject_id, topic);
CREATE INDEX IF NOT EXISTS idx_question_templates_active
  ON public.question_templates(is_active);

ALTER TABLE public.question_templates ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated can read templates" ON public.question_templates;
CREATE POLICY "Authenticated can read templates" ON public.question_templates
  FOR SELECT TO authenticated
  USING (is_active = TRUE OR public.is_admin());

DROP POLICY IF EXISTS "Admins can write templates" ON public.question_templates;
CREATE POLICY "Admins can write templates" ON public.question_templates
  FOR ALL TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

GRANT SELECT, INSERT, UPDATE, DELETE ON public.question_templates TO authenticated;


-- ================================================================
-- 6. public.concept_bank  --  AUTOMATIC ITEM GENERATION (part 2)
-- ================================================================
-- The structured content the templates draw from.
--
-- sibling_group is the clever bit. Concepts that share a sibling_group
-- are MUTUALLY PLAUSIBLE distractors: the six justifying circumstances
-- of RPC Art. 11 all belong to 'rpc_art11_justifying', so a question
-- keyed on "self-defense" gets its wrong answers from defense of a
-- relative, state of necessity, fulfillment of duty... These are
-- plausible-but-wrong (a good distractor), and because each sibling
-- carries its own definition and legal_basis, the generator gets a
-- REAL per-distractor rationale for free -- no LLM, no guessing.

CREATE TABLE IF NOT EXISTS public.concept_bank (
  id            TEXT PRIMARY KEY,
  subject_id    TEXT NOT NULL,
  topic         TEXT NOT NULL,
  term          TEXT NOT NULL,
  definition    TEXT NOT NULL,
  legal_basis   TEXT,
  sibling_group TEXT NOT NULL,
  is_active     BOOLEAN NOT NULL DEFAULT TRUE,
  created_at    TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.concept_bank ADD COLUMN IF NOT EXISTS legal_basis   TEXT;
ALTER TABLE public.concept_bank ADD COLUMN IF NOT EXISTS sibling_group TEXT;
ALTER TABLE public.concept_bank ADD COLUMN IF NOT EXISTS is_active     BOOLEAN DEFAULT TRUE;

CREATE INDEX IF NOT EXISTS idx_concept_bank_subject
  ON public.concept_bank(subject_id, topic);
-- The generator's hot path: "give me the siblings of this concept".
CREATE INDEX IF NOT EXISTS idx_concept_bank_sibling_group
  ON public.concept_bank(sibling_group) WHERE is_active;

ALTER TABLE public.concept_bank ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated can read concepts" ON public.concept_bank;
CREATE POLICY "Authenticated can read concepts" ON public.concept_bank
  FOR SELECT TO authenticated
  USING (is_active = TRUE OR public.is_admin());

DROP POLICY IF EXISTS "Admins can write concepts" ON public.concept_bank;
CREATE POLICY "Admins can write concepts" ON public.concept_bank
  FOR ALL TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

GRANT SELECT, INSERT, UPDATE, DELETE ON public.concept_bank TO authenticated;


-- ================================================================
-- 7. public.topic_mastery  --  BAYESIAN KNOWLEDGE TRACING STATE
-- ================================================================
-- Panel note 2 ("ML to monitor progress") and note 4 ("state your basis").
--
-- p_known is P(L_n), the posterior probability that the learner has
-- LEARNED this topic, updated after every single answer using Bayesian
-- Knowledge Tracing (Corbett & Anderson, 1995, "Knowledge tracing:
-- Modeling the acquisition of procedural knowledge", UMUAI 4(4)).
--
--   MasteryService parameters (documented here so the DB, the RRL and
--   the code all agree):
--     p_init    = 0.20   prior that the topic is already known
--     p_transit = 0.20   chance of learning it on any given attempt
--     p_slip    = 0.10   knows it but answers wrong
--     p_guess   = 0.25   does not know it but guesses right (4-option MCQ)
--
--   is_mastered  := p_known >= 0.90 AND attempts >= 4
--   remediation  := p_known <  0.60 AND attempts >= 3   -> repeat the topic
--
-- This row is the DB mirror of the local 'topic_mastery_v1' cache, so a
-- student keeps their model across devices and after a reinstall.

CREATE TABLE IF NOT EXISTS public.topic_mastery (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id             UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  subject_id          TEXT NOT NULL,
  topic               TEXT NOT NULL,
  p_known             NUMERIC(6,5) NOT NULL DEFAULT 0.20
                        CHECK (p_known >= 0 AND p_known <= 1),
  attempts            INTEGER NOT NULL DEFAULT 0,
  correct             INTEGER NOT NULL DEFAULT 0,
  consecutive_correct INTEGER NOT NULL DEFAULT 0,
  is_mastered         BOOLEAN NOT NULL DEFAULT FALSE,
  last_practiced      TIMESTAMPTZ,
  updated_at          TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (user_id, subject_id, topic)
);

ALTER TABLE public.topic_mastery ADD COLUMN IF NOT EXISTS consecutive_correct INTEGER DEFAULT 0;
ALTER TABLE public.topic_mastery ADD COLUMN IF NOT EXISTS is_mastered         BOOLEAN DEFAULT FALSE;
ALTER TABLE public.topic_mastery ADD COLUMN IF NOT EXISTS last_practiced      TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_topic_mastery_user
  ON public.topic_mastery(user_id);
CREATE INDEX IF NOT EXISTS idx_topic_mastery_user_subject
  ON public.topic_mastery(user_id, subject_id);
-- Powers weakTopics(): lowest p_known first.
CREATE INDEX IF NOT EXISTS idx_topic_mastery_weak
  ON public.topic_mastery(user_id, subject_id, p_known);

DROP TRIGGER IF EXISTS topic_mastery_touch_updated_at ON public.topic_mastery;
CREATE TRIGGER topic_mastery_touch_updated_at
  BEFORE UPDATE ON public.topic_mastery
  FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

ALTER TABLE public.topic_mastery ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users manage own mastery" ON public.topic_mastery;
CREATE POLICY "Users manage own mastery" ON public.topic_mastery
  FOR ALL TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- Admins may READ every student's mastery (panel note 2: the system
-- monitors progress) but may NOT write it -- a teacher must not be able
-- to fake a student's model.
DROP POLICY IF EXISTS "Admins can read all mastery" ON public.topic_mastery;
CREATE POLICY "Admins can read all mastery" ON public.topic_mastery
  FOR SELECT TO authenticated
  USING (public.is_admin());

GRANT SELECT, INSERT, UPDATE, DELETE ON public.topic_mastery TO authenticated;


-- ================================================================
-- 8. public.question_exposure  --  "REPEAT THE TOPIC, NOT THE QUESTION"
-- ================================================================
-- Panel note 3, verbatim: "if the student is good at that topic advance;
-- if not, it will REPEAT the topic but NOT THE SAME QUESTION."
--
-- QuestionSelectionService rules this table enforces:
--   R1  Never serve a question already in here while ANY unseen question
--       remains in the pool for that subject + difficulty.
--   R2  Once the unseen pool is exhausted, recycle least-seen and
--       least-recently-seen first  -> ORDER BY times_seen, last_seen.
--   R3  Remediation targets the SAME weak topic but strictly DIFFERENT
--       question ids.
-- times_correct is kept alongside so a recycled item the learner has
-- always missed can be prioritised over one they have always nailed.

CREATE TABLE IF NOT EXISTS public.question_exposure (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  question_id   TEXT NOT NULL REFERENCES public.questions(id) ON DELETE CASCADE,
  times_seen    INTEGER NOT NULL DEFAULT 1,
  times_correct INTEGER NOT NULL DEFAULT 0,
  last_seen     TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (user_id, question_id)
);

ALTER TABLE public.question_exposure ADD COLUMN IF NOT EXISTS times_correct INTEGER DEFAULT 0;
ALTER TABLE public.question_exposure ADD COLUMN IF NOT EXISTS last_seen     TIMESTAMPTZ DEFAULT NOW();

CREATE INDEX IF NOT EXISTS idx_question_exposure_user
  ON public.question_exposure(user_id);
-- Powers R2 recycling order directly.
CREATE INDEX IF NOT EXISTS idx_question_exposure_recycle
  ON public.question_exposure(user_id, times_seen, last_seen);

ALTER TABLE public.question_exposure ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users manage own exposure" ON public.question_exposure;
CREATE POLICY "Users manage own exposure" ON public.question_exposure
  FOR ALL TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Admins can read all exposure" ON public.question_exposure;
CREATE POLICY "Admins can read all exposure" ON public.question_exposure
  FOR SELECT TO authenticated
  USING (public.is_admin());

GRANT SELECT, INSERT, UPDATE, DELETE ON public.question_exposure TO authenticated;


-- ================================================================
-- 9. public.question_attempts  --  ML TRAINING / AUDIT TRAIL
-- ================================================================
-- Panel note 2: this is the EVIDENCE that the model is learning, and the
-- dataset any future retraining runs on. One immutable row per answered
-- question, capturing the BKT posterior before and after the update, so
-- the whole knowledge trajectory can be replayed and defended.
--
-- Deliberate design notes:
--   * subject_id / topic / difficulty are DENORMALISED. If a question is
--     later edited or hard-deleted, the training data stays valid.
--   * question_id has NO foreign key on purpose -- an attempt on a
--     locally cached or freshly generated item must never be rejected,
--     and the audit trail must outlive the question row.
--   * There is no UPDATE or DELETE policy. Attempts are append-only.

CREATE TABLE IF NOT EXISTS public.question_attempts (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  question_id      TEXT NOT NULL,
  subject_id       TEXT NOT NULL,
  topic            TEXT NOT NULL,
  difficulty       TEXT CHECK (difficulty IN ('easy', 'medium', 'hard')),
  selected_index   INTEGER,
  is_correct       BOOLEAN NOT NULL,
  response_time_ms INTEGER DEFAULT 0,
  p_known_before   NUMERIC(6,5),
  p_known_after    NUMERIC(6,5),
  created_at       TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.question_attempts ADD COLUMN IF NOT EXISTS response_time_ms INTEGER DEFAULT 0;
ALTER TABLE public.question_attempts ADD COLUMN IF NOT EXISTS p_known_before   NUMERIC(6,5);
ALTER TABLE public.question_attempts ADD COLUMN IF NOT EXISTS p_known_after    NUMERIC(6,5);

CREATE INDEX IF NOT EXISTS idx_question_attempts_user_created
  ON public.question_attempts(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_question_attempts_question
  ON public.question_attempts(question_id);
-- Item analysis: how hard is this item really, per topic?
CREATE INDEX IF NOT EXISTS idx_question_attempts_subject_topic
  ON public.question_attempts(subject_id, topic);

ALTER TABLE public.question_attempts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can read own attempts" ON public.question_attempts;
CREATE POLICY "Users can read own attempts" ON public.question_attempts
  FOR SELECT TO authenticated
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert own attempts" ON public.question_attempts;
CREATE POLICY "Users can insert own attempts" ON public.question_attempts
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Admins can read all attempts" ON public.question_attempts;
CREATE POLICY "Admins can read all attempts" ON public.question_attempts
  FOR SELECT TO authenticated
  USING (public.is_admin());

GRANT SELECT, INSERT ON public.question_attempts TO authenticated;


-- ================================================================
-- 10. public.admin_audit_log
-- ================================================================
-- Every admin content change is logged. This is what turns "an admin can
-- add questions" into a defensible system: you can show the panel who
-- added or edited which item, and when.

CREATE TABLE IF NOT EXISTS public.admin_audit_log (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_id     UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  action       TEXT NOT NULL,        -- create | update | delete | restore | bulk_import | generate
  target_table TEXT,                 -- e.g. 'questions'
  target_id    TEXT,
  details      JSONB,
  created_at   TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_admin_audit_log_admin
  ON public.admin_audit_log(admin_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_admin_audit_log_target
  ON public.admin_audit_log(target_table, target_id);

ALTER TABLE public.admin_audit_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admins can read audit log" ON public.admin_audit_log;
CREATE POLICY "Admins can read audit log" ON public.admin_audit_log
  FOR SELECT TO authenticated
  USING (public.is_admin());

DROP POLICY IF EXISTS "Admins can write audit log" ON public.admin_audit_log;
CREATE POLICY "Admins can write audit log" ON public.admin_audit_log
  FOR INSERT TO authenticated
  WITH CHECK (public.is_admin() AND admin_id = auth.uid());

GRANT SELECT, INSERT ON public.admin_audit_log TO authenticated;

-- Convenience RPC so AdminService does not have to pass admin_id by hand.
-- Silently no-ops for non-admins rather than throwing, so a failed audit
-- write can never roll back a legitimate content edit.
CREATE OR REPLACE FUNCTION public.log_admin_action(
  p_action       TEXT,
  p_target_table TEXT DEFAULT 'questions',
  p_target_id    TEXT DEFAULT NULL,
  p_details      JSONB DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $log_admin$
BEGIN
  IF public.is_admin() THEN
    INSERT INTO public.admin_audit_log (admin_id, action, target_table, target_id, details)
    VALUES (auth.uid(), p_action, p_target_table, p_target_id, p_details);
  END IF;
END;
$log_admin$;

GRANT EXECUTE ON FUNCTION public.log_admin_action(TEXT, TEXT, TEXT, JSONB) TO authenticated;


-- ================================================================
-- 11. VIEW: public.student_progress_overview  --  ADMIN DASHBOARD
-- ================================================================
-- Backs AdminService.studentProgressOverview(). One row per student with
-- their BKT rollup, so an instructor can see at a glance who is stuck and
-- on what -- panel note 2, "monitor the progress of the students".
--
-- Two independent guards:
--   1. security_invoker = on  -> the view runs with the CALLER's rights,
--      so the RLS on topic_mastery still applies (a leaky SECURITY
--      DEFINER view is the #1 way people accidentally expose all rows).
--   2. WHERE public.is_admin() -> non-admins get zero rows, full stop.
-- Requires PostgreSQL 15+, which every current Supabase project runs.

DROP VIEW IF EXISTS public.student_progress_overview;
CREATE VIEW public.student_progress_overview
WITH (security_invoker = on) AS
SELECT
  p.id                                        AS user_id,
  p.email,
  p.display_name,
  p.school,
  p.rank,
  p.role,
  p.total_points,
  p.total_quizzes,
  p.total_correct,
  p.current_streak,
  p.best_streak,
  COUNT(m.id)                                 AS topics_tracked,
  COUNT(m.id) FILTER (WHERE m.is_mastered)    AS topics_mastered,
  COUNT(m.id) FILTER (WHERE m.p_known < 0.60
                        AND m.attempts >= 3)  AS topics_needing_remediation,
  ROUND(COALESCE(AVG(m.p_known), 0), 4)       AS avg_p_known,
  COALESCE(SUM(m.attempts), 0)                AS total_topic_attempts,
  COALESCE(SUM(m.correct), 0)                 AS total_topic_correct,
  MAX(m.last_practiced)                       AS last_practiced,
  p.created_at                                AS joined_at
FROM public.user_profiles p
LEFT JOIN public.topic_mastery m ON m.user_id = p.id
WHERE public.is_admin()
GROUP BY p.id, p.email, p.display_name, p.school, p.rank, p.role,
         p.total_points, p.total_quizzes, p.total_correct,
         p.current_streak, p.best_streak, p.created_at;

GRANT SELECT ON public.student_progress_overview TO authenticated;


-- ================================================================
-- 12. SEED DATA  --  WORKED EXAMPLES FOR AUTO-GENERATION
-- ================================================================
-- Real Philippine criminology content so QuestionGenerationService has
-- something to run against on day one. ON CONFLICT DO UPDATE keeps this
-- block re-runnable and lets you fix a typo by just re-running the file.
--
-- Four item models, one per major topic area:
--   tmpl_rpc_art11_def   Justifying circumstances (RPC Art. 11)
--   tmpl_rpc_art12_def   Exempting circumstances  (RPC Art. 12)
--   tmpl_ra9344_def      Juvenile justice         (RA 9344)
--   tmpl_pnp_org_def     PNP / DILG organisation  (RA 6975, RA 8551)

INSERT INTO public.question_templates
  (id, subject_id, topic, stem_template, difficulty, distractor_strategy,
   rationale_template, explanation_template, is_active)
VALUES
  ('tmpl_rpc_art11_def',
   'criminal_jurisprudence',
   'Justifying Circumstances',
   'Under the Revised Penal Code, which of the following BEST describes the justifying circumstance of {{term}}?',
   'medium',
   'sibling_definitions',
   'That statement defines {{option_term}}, not {{term}}. {{option_term}} is a different justifying circumstance under Article 11, so it cannot be the answer here.',
   '{{term}} is defined as: {{definition}} (Basis: {{legal_basis}}). All six justifying circumstances appear in Article 11 of the Revised Penal Code, so read them side by side -- they are easy to swap under exam pressure.',
   TRUE),

  ('tmpl_rpc_art12_def',
   'criminal_jurisprudence',
   'Exempting Circumstances',
   'Which of the following BEST describes the exempting circumstance of {{term}}?',
   'medium',
   'sibling_definitions',
   'That is the definition of {{option_term}}. {{option_term}} and {{term}} are both exempting circumstances under Article 12, but they are not interchangeable.',
   '{{term}} means: {{definition}} (Basis: {{legal_basis}}). Remember the distinction the board loves to test: a JUSTIFYING circumstance means no crime was committed at all, while an EXEMPTING circumstance means a crime exists but the actor incurs no criminal liability.',
   TRUE),

  ('tmpl_ra9344_def',
   'criminology',
   'Juvenile Delinquency and Juvenile Justice',
   'Under RA 9344, as amended by RA 10630, what does {{term}} mean?',
   'easy',
   'sibling_definitions',
   'That is the statutory meaning of {{option_term}}, not {{term}}. RA 9344 defines these terms separately, and mixing them up changes which programme the child is entitled to.',
   '{{term}}: {{definition}} (Basis: {{legal_basis}}). RA 9344 is the Juvenile Justice and Welfare Act; its definitions in Section 4 are frequently asked verbatim.',
   TRUE),

  ('tmpl_pnp_org_def',
   'law_enforcement',
   'Police Organization and Administration',
   'In the organization of the Philippine national law enforcement system, what is the primary mandate of the {{term}}?',
   'easy',
   'sibling_definitions',
   'That is the mandate of the {{option_term}}. The {{option_term}} and the {{term}} are separate agencies under the DILG with distinct functions.',
   'The {{term}}: {{definition}} (Basis: {{legal_basis}}). RA 6975 reorganized the DILG and created these bureaus; RA 8551 later reformed and professionalized the PNP.',
   TRUE)
ON CONFLICT (id) DO UPDATE SET
  subject_id           = EXCLUDED.subject_id,
  topic                = EXCLUDED.topic,
  stem_template        = EXCLUDED.stem_template,
  difficulty           = EXCLUDED.difficulty,
  distractor_strategy  = EXCLUDED.distractor_strategy,
  rationale_template   = EXCLUDED.rationale_template,
  explanation_template = EXCLUDED.explanation_template,
  is_active            = EXCLUDED.is_active;


-- ---- CONCEPT BANK -----------------------------------------------
-- Group A: rpc_art11_justifying  (RPC Art. 11 -- six justifying circumstances)
-- Group B: rpc_art12_exempting   (RPC Art. 12 -- exempting circumstances)
-- Group C: ra9344_juvenile       (RA 9344 Sec. 4 definitions)
-- Group D: dilg_law_enforcement  (RA 6975 / RA 8551 bureaus)
-- Every member of a group is a plausible distractor for every other
-- member of the same group -- that is the whole trick.

INSERT INTO public.concept_bank
  (id, subject_id, topic, term, definition, legal_basis, sibling_group, is_active)
VALUES
  -- Group A -- Justifying circumstances, RPC Article 11
  ('cb_art11_self_defense',
   'criminal_jurisprudence', 'Justifying Circumstances',
   'Self-Defense',
   'Acting in defense of one''s own person or rights, provided there is unlawful aggression, reasonable necessity of the means employed to prevent or repel it, and lack of sufficient provocation on the part of the person defending himself.',
   'RPC Art. 11(1)', 'rpc_art11_justifying', TRUE),

  ('cb_art11_defense_relative',
   'criminal_jurisprudence', 'Justifying Circumstances',
   'Defense of a Relative',
   'Acting in defense of the person or rights of a spouse, ascendant, descendant, legitimate, natural or adopted brother or sister, or relative by affinity in the same degree, or by consanguinity within the fourth civil degree, provided the first two requisites of self-defense are present and, in case provocation was given by the person attacked, the one defending had no part therein.',
   'RPC Art. 11(2)', 'rpc_art11_justifying', TRUE),

  ('cb_art11_defense_stranger',
   'criminal_jurisprudence', 'Justifying Circumstances',
   'Defense of a Stranger',
   'Acting in defense of the person or rights of a person who is not a relative, provided there is unlawful aggression and reasonable necessity of the means employed, and the person defending is not induced by revenge, resentment, or other evil motive.',
   'RPC Art. 11(3)', 'rpc_art11_justifying', TRUE),

  ('cb_art11_state_of_necessity',
   'criminal_jurisprudence', 'Justifying Circumstances',
   'Avoidance of Greater Evil or Injury',
   'Causing damage to another in order to avoid an evil or injury, provided the evil sought to be avoided actually exists, the injury feared is greater than that done to avoid it, and there is no other practical and less harmful means of preventing it. Also called a state of necessity.',
   'RPC Art. 11(4)', 'rpc_art11_justifying', TRUE),

  ('cb_art11_fulfillment_of_duty',
   'criminal_jurisprudence', 'Justifying Circumstances',
   'Fulfillment of Duty or Lawful Exercise of a Right or Office',
   'Acting in the fulfillment of a duty or in the lawful exercise of a right or office, provided the accused acted in the performance of that duty and the injury caused was the necessary consequence of its due performance.',
   'RPC Art. 11(5)', 'rpc_art11_justifying', TRUE),

  ('cb_art11_obedience_order',
   'criminal_jurisprudence', 'Justifying Circumstances',
   'Obedience to a Lawful Order of a Superior',
   'Acting in obedience to an order issued by a superior for some lawful purpose, provided the order is lawful both in itself and in the means used to carry it out.',
   'RPC Art. 11(6)', 'rpc_art11_justifying', TRUE),

  -- Group B -- Exempting circumstances, RPC Article 12
  ('cb_art12_insanity',
   'criminal_jurisprudence', 'Exempting Circumstances',
   'Insanity or Imbecility',
   'Exemption from criminal liability where the offender is an imbecile or insane at the time of the commission of the act, and therefore acts without the freedom and intelligence the law requires, unless he acted during a lucid interval.',
   'RPC Art. 12(1)', 'rpc_art12_exempting', TRUE),

  ('cb_art12_accident',
   'criminal_jurisprudence', 'Exempting Circumstances',
   'Accident Without Fault or Intention',
   'Exemption where a person, while performing a lawful act with due care, causes an injury by mere accident without fault or intention of causing it.',
   'RPC Art. 12(4)', 'rpc_art12_exempting', TRUE),

  ('cb_art12_irresistible_force',
   'criminal_jurisprudence', 'Exempting Circumstances',
   'Irresistible Force',
   'Exemption where a person acts under the compulsion of an irresistible physical force originating from a third person, so that the actor is reduced to a mere instrument and acts without freedom.',
   'RPC Art. 12(5)', 'rpc_art12_exempting', TRUE),

  ('cb_art12_uncontrollable_fear',
   'criminal_jurisprudence', 'Exempting Circumstances',
   'Uncontrollable Fear of an Equal or Greater Injury',
   'Exemption where a person acts under the impulse of an uncontrollable fear of an evil equal to or greater than that which he is compelled to commit, the threat being real, imminent and grave.',
   'RPC Art. 12(6)', 'rpc_art12_exempting', TRUE),

  ('cb_art12_insuperable_cause',
   'criminal_jurisprudence', 'Exempting Circumstances',
   'Lawful or Insuperable Cause',
   'Exemption where a person fails to perform an act required by law because of some lawful or insuperable cause, so that the omission is not attributable to his own will.',
   'RPC Art. 12(7)', 'rpc_art12_exempting', TRUE),

  -- Group C -- RA 9344, Juvenile Justice and Welfare Act
  ('cb_ra9344_cicl',
   'criminology', 'Juvenile Delinquency and Juvenile Justice',
   'Child in Conflict with the Law (CICL)',
   'A child who is alleged as, accused of, or adjudged as having committed an offense under Philippine laws.',
   'RA 9344, Sec. 4(e)', 'ra9344_juvenile', TRUE),

  ('cb_ra9344_child_at_risk',
   'criminology', 'Juvenile Delinquency and Juvenile Justice',
   'Child at Risk (CAR)',
   'A child who is vulnerable to and at risk of committing criminal offenses because of personal, family or social circumstances, such as being abused, out of school, a street child, or living with a parent engaged in illegal activities.',
   'RA 9344, Sec. 4(d)', 'ra9344_juvenile', TRUE),

  ('cb_ra9344_diversion',
   'criminology', 'Juvenile Delinquency and Juvenile Justice',
   'Diversion',
   'An alternative, child-appropriate process of determining the responsibility and treatment of a child in conflict with the law on the basis of his or her social, cultural, economic, psychological or educational background, WITHOUT resorting to formal court proceedings.',
   'RA 9344, Sec. 4(i)', 'ra9344_juvenile', TRUE),

  ('cb_ra9344_intervention',
   'criminology', 'Juvenile Delinquency and Juvenile Justice',
   'Intervention',
   'A series of activities designed to address issues that caused the child to commit an offense, such as counseling, skills training and education, which may be done on an individual basis or through group activities.',
   'RA 9344, Sec. 4(l)', 'ra9344_juvenile', TRUE),

  ('cb_ra9344_min_age',
   'criminology', 'Juvenile Delinquency and Juvenile Justice',
   'Minimum Age of Criminal Responsibility',
   'The rule that a child fifteen (15) years of age or under at the time of the commission of the offense is exempt from criminal liability, while a child above 15 but below 18 is likewise exempt unless he or she acted with discernment; in both cases the child is subjected to an intervention programme.',
   'RA 9344, Sec. 6 as amended by RA 10630', 'ra9344_juvenile', TRUE),

  -- Group D -- Law enforcement organisation, RA 6975 / RA 8551
  ('cb_le_pnp',
   'law_enforcement', 'Police Organization and Administration',
   'Philippine National Police (PNP)',
   'The national police force, civilian in character and national in scope, mandated to enforce the law, prevent and control crimes, maintain peace and order, and ensure public safety and internal security with the active support of the community.',
   'RA 6975, as amended by RA 8551', 'dilg_law_enforcement', TRUE),

  ('cb_le_napolcom',
   'law_enforcement', 'Police Organization and Administration',
   'National Police Commission (NAPOLCOM)',
   'The agency attached to the DILG that exercises administrative control and operational supervision over the PNP, sets policies and standards on recruitment, promotion and retirement, and exercises appellate disciplinary jurisdiction over police personnel.',
   'RA 6975, as amended by RA 8551', 'dilg_law_enforcement', TRUE),

  ('cb_le_bjmp',
   'law_enforcement', 'Police Organization and Administration',
   'Bureau of Jail Management and Penology (BJMP)',
   'The bureau under the DILG that exercises supervision and control over all district, city and municipal jails, taking custody of detainees awaiting trial and prisoners serving sentences of three (3) years or less.',
   'RA 6975, Sec. 60', 'dilg_law_enforcement', TRUE),

  ('cb_le_bfp',
   'law_enforcement', 'Police Organization and Administration',
   'Bureau of Fire Protection (BFP)',
   'The bureau under the DILG responsible for preventing and suppressing all destructive fires, enforcing the Fire Code, and investigating the causes of fires, as well as responding to other emergencies and rescue operations.',
   'RA 6975, Sec. 53; RA 9514 Fire Code', 'dilg_law_enforcement', TRUE),

  ('cb_le_ppsc',
   'law_enforcement', 'Police Organization and Administration',
   'Philippine Public Safety College (PPSC)',
   'The premier educational institution for the training, human resource development and continuing education of all personnel of the PNP, BFP and BJMP.',
   'RA 6975, Sec. 66', 'dilg_law_enforcement', TRUE)
ON CONFLICT (id) DO UPDATE SET
  subject_id    = EXCLUDED.subject_id,
  topic         = EXCLUDED.topic,
  term          = EXCLUDED.term,
  definition    = EXCLUDED.definition,
  legal_basis   = EXCLUDED.legal_basis,
  sibling_group = EXCLUDED.sibling_group,
  is_active     = EXCLUDED.is_active;


-- ================================================================
-- 13. HOW TO MAKE YOURSELF ADMIN   <<< READ THIS >>>
-- ================================================================
--
-- STEP 1. Sign up inside the CrimiReview app FIRST, using the email you
--         want to be the admin. Signing up creates the user_profiles row
--         (via the handle_new_user trigger). You cannot promote an
--         account that does not exist yet.
--
-- STEP 2. Come back to the Supabase SQL Editor, put YOUR email below,
--         un-comment the line, and RUN it:
--
--   UPDATE public.user_profiles SET role = 'admin' WHERE email = 'your@email.com';
--
-- STEP 3. Confirm it worked:
--
--   SELECT id, email, display_name, role FROM public.user_profiles WHERE role = 'admin';
--
-- STEP 4. Sign OUT and back IN inside the app so AdminService refreshes
--         its cached role. The Admin tab then appears.
--
-- TO DEMOTE SOMEONE:
--   UPDATE public.user_profiles SET role = 'student' WHERE email = 'someone@email.com';
--
-- SECURITY NOTE: students CANNOT promote themselves from the app. The
-- protect_user_role trigger in SECTION 1 silently reverts any role change
-- attempted by a non-admin. The SQL Editor runs as the service role
-- (auth.uid() IS NULL), which is why STEP 2 above still works.
-- ================================================================


-- ================================================================
-- 14. VERIFICATION -- run these after the migration to prove it worked
-- ================================================================
-- All eight objects should be listed:
--   SELECT table_name FROM information_schema.tables
--   WHERE table_schema = 'public'
--     AND table_name IN ('questions','question_templates','concept_bank',
--                        'topic_mastery','question_exposure',
--                        'question_attempts','admin_audit_log')
--   ORDER BY table_name;
--
-- RLS must be ON for every one of them:
--   SELECT relname, relrowsecurity FROM pg_class
--   WHERE relname IN ('questions','question_templates','concept_bank',
--                     'topic_mastery','question_exposure',
--                     'question_attempts','admin_audit_log');
--
-- Seed data sanity check (expect 4 templates, 21 concepts, 4 groups):
--   SELECT (SELECT COUNT(*) FROM public.question_templates) AS templates,
--          (SELECT COUNT(*) FROM public.concept_bank)       AS concepts,
--          (SELECT COUNT(DISTINCT sibling_group) FROM public.concept_bank) AS groups;
--
-- Preview what auto-generation will produce -- the key plus its
-- plausible sibling distractors, exactly as the generator sees them:
--   SELECT c.term AS key_term, s.term AS distractor_term
--   FROM public.concept_bank c
--   JOIN public.concept_bank s
--     ON s.sibling_group = c.sibling_group AND s.id <> c.id
--   WHERE c.id = 'cb_art11_self_defense';
--
-- Prove the correct-index trigger works (insert options with only flags,
-- no index -- the trigger should compute 1):
--   INSERT INTO public.questions (id, subject_id, topic, question_text, options, difficulty)
--   VALUES ('smoke_test_1','criminology','Introduction to Criminology','Smoke test?',
--     '[{"text":"Wrong","is_correct":false,"rationale":"No."},
--       {"text":"Right","is_correct":true,"rationale":"Yes."}]'::JSONB,'easy');
--   SELECT correct_answer_index FROM public.questions WHERE id = 'smoke_test_1';  -- expect 1
--   DELETE FROM public.questions WHERE id = 'smoke_test_1';
--   (Note: run these as the SQL Editor / service role, or after SECTION 13.)
--
-- The question bank starts EMPTY on purpose. There are no hardcoded
-- questions anywhere any more (panel note 7). Fill it either from the
-- Admin screen, from a bulk import, or by running auto-generation
-- against the seeded templates in SECTION 12.
--
-- ================================================================
-- END OF V2 MIGRATION
-- ================================================================
