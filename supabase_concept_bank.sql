-- ================================================================
-- CrimiReview -- Concept bank screen + four question forms per concept
-- ================================================================
-- WHY THIS FILE EXISTS
--   Template generation (supabase_template_generation.sql) had two
--   problems for Faculty:
--     1. Concepts could only be added with SQL, so Faculty could not feed it.
--     2. Each concept produced exactly ONE question, so 21 concepts meant
--        21 questions, ever.
--
--   This file fixes both, without touching the app's other tables:
--     * Faculty can add, edit, deactivate and bulk-import concepts from the
--       admin panel (RPCs below; every one checks is_admin() and is audited).
--     * A concept can now produce up to FOUR different questions, one per
--       "form" (a form is a kind of template):
--           term_to_definition   shows the term,        options are definitions
--           definition_to_term   shows the definition,  options are terms
--           basis_to_term        shows a legal basis,   options are terms
--           term_to_basis        shows the term,        options are legal bases
--     * The generator and the "N available" count now share ONE definition
--       of "which concepts can still make a question", so they cannot
--       disagree. (The old generator picked concepts at random without
--       skipping used ones, so "3 available" could create 0.)
--     * A Faculty-selected batch of generated questions can be approved in
--       one step (admin_approve_generated).
--
-- SAFETY RULES BUILT INTO THE GENERATOR
--   * A question needs at least 2 wrong options (3 options in total).
--   * Wrong options never repeat the correct option's text.
--   * The two legal-basis forms are only used for a sibling group in which
--     EVERY active concept has a legal basis, and no basis is equal to or
--     contained in another. Otherwise two answers could both be right
--     (for example "RA 6975, Sec. 60" is inside "RA 6975").
--   * Generated questions are still saved INACTIVE. Students never see one
--     until Faculty approve it.
--
-- HOW TO RUN
--   Supabase Dashboard > SQL Editor > New query > paste this whole file > Run.
--   Safe to run more than once. Run supabase_schema_v2.sql and
--   supabase_template_generation.sql first (they already ran on your project).
--
-- HOW TO UNDO
--   See the ROLLBACK block at the very end of this file.
-- ================================================================


-- ----------------------------------------------------------------
-- 1. question_templates.form
-- ----------------------------------------------------------------
-- Existing rows become 'term_to_definition', which is exactly how they
-- behaved before.

ALTER TABLE public.question_templates
  ADD COLUMN IF NOT EXISTS form TEXT NOT NULL DEFAULT 'term_to_definition';

DO $form_check$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'question_templates_form_check'
      AND conrelid = 'public.question_templates'::regclass
  ) THEN
    ALTER TABLE public.question_templates
      ADD CONSTRAINT question_templates_form_check
      CHECK (form IN ('term_to_definition', 'definition_to_term',
                      'basis_to_term', 'term_to_basis'));
  END IF;
END
$form_check$;


-- ----------------------------------------------------------------
-- 2. Small pure helpers
-- ----------------------------------------------------------------

-- The slot a template's question text MUST contain for each form. Without
-- it every concept would produce the same text and only the first would be
-- saved.
CREATE OR REPLACE FUNCTION public.template_required_slot(p_form TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
  SELECT CASE p_form
           WHEN 'definition_to_term' THEN '{{definition}}'
           WHEN 'basis_to_term'      THEN '{{legal_basis}}'
           ELSE '{{term}}'
         END
$$;

-- Fills {{term}}, {{definition}}, {{legal_basis}} and {{topic}}.
-- Uses replace(), not regexp_replace(): a backslash or "&" typed into a
-- definition must stay literal. When the concept has no legal basis, the
-- text " (Basis: {{legal_basis}})" is removed instead of leaving "(Basis: )".
CREATE OR REPLACE FUNCTION public.fill_slots(
  p_text        TEXT,
  p_term        TEXT,
  p_definition  TEXT,
  p_legal_basis TEXT,
  p_topic       TEXT
)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
  SELECT replace(replace(replace(replace(
           CASE WHEN nullif(btrim(p_legal_basis), '') IS NULL
                THEN replace(COALESCE(p_text, ''), ' (Basis: {{legal_basis}})', '')
                ELSE COALESCE(p_text, '')
           END,
           '{{term}}',        COALESCE(p_term, '')),
           '{{definition}}',  COALESCE(p_definition, '')),
           '{{legal_basis}}', COALESCE(p_legal_basis, '')),
           '{{topic}}',       COALESCE(p_topic, ''))
$$;

-- Fills a wrong option's reason: the key concept's slots plus the
-- {{option_term}}, {{option_definition}} and {{option_basis}} of the concept
-- that became the wrong option.
CREATE OR REPLACE FUNCTION public.fill_distractor_rationale(
  p_text          TEXT,
  p_key_term      TEXT,
  p_key_definition TEXT,
  p_key_basis     TEXT,
  p_topic         TEXT,
  p_opt_term      TEXT,
  p_opt_definition TEXT,
  p_opt_basis     TEXT
)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
  SELECT public.fill_slots(
           replace(replace(replace(
             COALESCE(p_text, ''),
             '{{option_term}}',       COALESCE(p_opt_term, '')),
             '{{option_definition}}', COALESCE(p_opt_definition, '')),
             '{{option_basis}}',      COALESCE(nullif(btrim(p_opt_basis), ''), 'another provision')),
           p_key_term, p_key_definition, p_key_basis, p_topic)
$$;


-- ----------------------------------------------------------------
-- 3. Which concepts can make a question? (ONE definition, used by both
--    the generator and the status view)
-- ----------------------------------------------------------------

-- True when every ACTIVE concept in the group has a legal basis, and no
-- basis is equal to, or contained in, another basis of the same group.
-- Required before a legal-basis form may be used for that group.
CREATE OR REPLACE FUNCTION public.group_bases_distinct(p_group TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT NOT EXISTS (
    SELECT 1
    FROM public.concept_bank a
    WHERE a.sibling_group = p_group
      AND a.is_active
      AND (
        nullif(btrim(a.legal_basis), '') IS NULL
        OR EXISTS (
          SELECT 1
          FROM public.concept_bank b
          WHERE b.sibling_group = p_group
            AND b.is_active
            AND b.id <> a.id
            AND strpos(lower(btrim(b.legal_basis)), lower(btrim(a.legal_basis))) > 0
        )
      )
  )
$$;

-- The concepts that can be WRONG options for one key concept in one
-- template: active siblings whose option text differs from the key's.
CREATE OR REPLACE FUNCTION public.template_distractors(
  p_template_id TEXT,
  p_concept_id  TEXT
)
RETURNS SETOF public.concept_bank
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT s.*
  FROM public.question_templates t
  JOIN public.concept_bank k ON k.id = p_concept_id
  JOIN public.concept_bank s
    ON s.sibling_group = k.sibling_group
   AND s.id <> k.id
   AND s.is_active
  WHERE t.id = p_template_id
    AND CASE t.form
          WHEN 'term_to_definition' THEN
            nullif(btrim(s.definition), '') IS NOT NULL
            AND lower(btrim(s.definition)) <> lower(btrim(k.definition))
          WHEN 'term_to_basis' THEN
            nullif(btrim(s.legal_basis), '') IS NOT NULL
            AND lower(btrim(s.legal_basis)) <> lower(btrim(k.legal_basis))
          ELSE
            nullif(btrim(s.term), '') IS NOT NULL
            AND lower(btrim(s.term)) <> lower(btrim(k.term))
        END
$$;

-- Every concept this template COULD make a question from, whether or not it
-- already has one. This is the "total" in the admin screen.
CREATE OR REPLACE FUNCTION public.template_eligible(p_template_id TEXT)
RETURNS SETOF public.concept_bank
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT c.*
  FROM public.question_templates t
  JOIN public.concept_bank c
    ON c.subject_id = t.subject_id
   AND c.topic      = t.topic
   AND c.is_active
  WHERE t.id = p_template_id
    AND t.is_active
    AND position(public.template_required_slot(t.form) IN t.stem_template) > 0
    AND nullif(btrim(c.term), '')       IS NOT NULL
    AND nullif(btrim(c.definition), '') IS NOT NULL
    AND (
      t.form IN ('term_to_definition', 'definition_to_term')
      OR (
        nullif(btrim(c.legal_basis), '') IS NOT NULL
        AND public.group_bases_distinct(c.sibling_group)
      )
    )
    -- at least 2 wrong options, so a question has 3 options or more
    AND (SELECT count(*) FROM public.template_distractors(t.id, c.id)) >= 2
$$;

-- The eligible concepts that do NOT yet have a question. The comparison is
-- the same one the database uses to refuse duplicate questions
-- (uq_questions_subject_stem: same subject, same text ignoring case), so a
-- question typed by hand also counts as "already has one".
CREATE OR REPLACE FUNCTION public.template_candidates(p_template_id TEXT)
RETURNS SETOF public.concept_bank
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT e.*
  FROM public.question_templates t
  CROSS JOIN LATERAL public.template_eligible(t.id) e
  WHERE t.id = p_template_id
    AND t.is_active
    AND NOT EXISTS (
      SELECT 1
      FROM public.questions q
      WHERE q.subject_id = t.subject_id
        AND lower(q.question_text) = lower(
              public.fill_slots(t.stem_template, e.term, e.definition,
                                e.legal_basis, e.topic))
    )
$$;


-- ----------------------------------------------------------------
-- 4. The generator (same name and result shape as before, so the app's
--    call does not change)
-- ----------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.generate_questions_from_template(
  p_template_id TEXT,
  p_count       INTEGER DEFAULT 5
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_template     RECORD;
  v_key          RECORD;
  v_wrong        JSONB;
  v_options      JSONB;
  v_stem         TEXT;
  v_explanation  TEXT;
  v_correct_text TEXT;
  v_correct_why  TEXT;
  v_basis_note   TEXT;
  v_new_id       TEXT;
  v_inserted     INTEGER := 0;
  v_skipped      INTEGER := 0;
  v_considered   INTEGER := 0;
BEGIN
  IF NOT public.is_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Only admins can generate questions.');
  END IF;

  IF p_count IS NULL OR p_count < 1 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Count must be at least 1.');
  END IF;
  IF p_count > 200 THEN
    p_count := 200;
  END IF;

  SELECT * INTO v_template FROM public.question_templates
  WHERE id = p_template_id AND is_active = TRUE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Template not found or inactive.');
  END IF;

  IF position(public.template_required_slot(v_template.form) IN v_template.stem_template) = 0 THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'This template''s question text must contain ' ||
               public.template_required_slot(v_template.form) || '.'
    );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.concept_bank
    WHERE topic = v_template.topic
      AND subject_id = v_template.subject_id
      AND is_active = TRUE
  ) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'No active concepts found for this template''s topic.'
    );
  END IF;

  -- Random order, so repeated runs do not always pick the same concepts.
  FOR v_key IN
    SELECT * FROM public.template_candidates(p_template_id)
    ORDER BY random()
    LIMIT p_count
  LOOP
    v_considered := v_considered + 1;

    -- Up to 3 wrong options, chosen at random, each with its own reason.
    SELECT jsonb_agg(jsonb_build_object(
             'text', CASE v_template.form
                       WHEN 'term_to_definition' THEN s.definition
                       WHEN 'term_to_basis'      THEN btrim(s.legal_basis)
                       ELSE s.term
                     END,
             'is_correct', false,
             'rationale', public.fill_distractor_rationale(
                            v_template.rationale_template,
                            v_key.term, v_key.definition, v_key.legal_basis, v_key.topic,
                            s.term, s.definition, s.legal_basis)
           ))
    INTO v_wrong
    FROM (
      SELECT * FROM public.template_distractors(v_template.id, v_key.id)
      ORDER BY random()
      LIMIT 3
    ) s;

    IF v_wrong IS NULL OR jsonb_array_length(v_wrong) < 2 THEN
      v_skipped := v_skipped + 1;
      CONTINUE;
    END IF;

    v_basis_note := CASE WHEN nullif(btrim(v_key.legal_basis), '') IS NOT NULL
                         THEN ' (Basis: ' || btrim(v_key.legal_basis) || ')'
                         ELSE '' END;

    v_correct_text := CASE v_template.form
                        WHEN 'term_to_definition' THEN v_key.definition
                        WHEN 'term_to_basis'      THEN btrim(v_key.legal_basis)
                        ELSE v_key.term
                      END;

    v_correct_why := CASE v_template.form
                       WHEN 'term_to_definition' THEN
                         'Correct. ' || v_key.definition || v_basis_note
                       WHEN 'definition_to_term' THEN
                         'Correct. ' || v_key.term ||
                         ' is the term described in the question.' || v_basis_note
                       ELSE
                         'Correct. ' || v_key.term || ' is covered by ' ||
                         btrim(v_key.legal_basis) || '.'
                     END;

    v_options := jsonb_build_array(jsonb_build_object(
                   'text', v_correct_text,
                   'is_correct', true,
                   'rationale', v_correct_why
                 )) || v_wrong;

    -- Shuffle the option order. sync_question_correct_index (schema v2)
    -- recomputes correct_answer_index from the is_correct flag.
    SELECT jsonb_agg(opt ORDER BY random())
    INTO v_options
    FROM jsonb_array_elements(v_options) AS opt;

    v_stem := public.fill_slots(v_template.stem_template, v_key.term,
                                v_key.definition, v_key.legal_basis, v_key.topic);
    v_explanation := public.fill_slots(v_template.explanation_template, v_key.term,
                                       v_key.definition, v_key.legal_basis, v_key.topic);
    v_new_id := 'gen_tpl_' || replace(gen_random_uuid()::text, '-', '');

    BEGIN
      INSERT INTO public.questions (
        id, subject_id, topic, question_text, options, difficulty,
        explanation, legal_basis, remediation_hint, source, template_id,
        version, is_active, created_by
      ) VALUES (
        v_new_id, v_template.subject_id, v_template.topic, v_stem, v_options,
        v_template.difficulty, v_explanation, nullif(btrim(v_key.legal_basis), ''), NULL,
        'generated', v_template.id, 1, FALSE, auth.uid()
      );
      v_inserted := v_inserted + 1;
    EXCEPTION WHEN unique_violation THEN
      -- Someone saved the same question text between the check and now.
      v_skipped := v_skipped + 1;
    END;
  END LOOP;

  PERFORM public.log_admin_action(
    'generate', 'questions', v_template.id,
    jsonb_build_object('method', 'template', 'form', v_template.form,
                       'inserted', v_inserted, 'skipped', v_skipped)
  );

  RETURN jsonb_build_object(
    'success', true,
    'inserted', v_inserted,
    'skipped', v_skipped,
    'considered', v_considered
  );
END;
$$;

REVOKE ALL ON FUNCTION public.generate_questions_from_template(TEXT, INTEGER) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.generate_questions_from_template(TEXT, INTEGER) TO authenticated;


-- ----------------------------------------------------------------
-- 5. The status view the admin screen reads
-- ----------------------------------------------------------------
-- total_concepts      = concepts this template could ever make a question from
-- concepts_remaining  = how many of those still have no question
-- The columns the app already read are unchanged; "form" is new.

DROP VIEW IF EXISTS public.template_generation_status;
CREATE VIEW public.template_generation_status
WITH (security_invoker = on) AS
SELECT
  t.id,
  t.subject_id,
  t.topic,
  t.difficulty,
  t.form,
  t.is_active,
  (SELECT count(*) FROM public.template_eligible(t.id))   AS total_concepts,
  (SELECT count(*) FROM public.template_candidates(t.id)) AS concepts_remaining
FROM public.question_templates t
WHERE t.is_active;

GRANT SELECT ON public.template_generation_status TO authenticated;


-- ----------------------------------------------------------------
-- 6. Standard templates for a topic
-- ----------------------------------------------------------------
-- Creates the four forms for a (subject, topic) that do not exist yet, using
-- the topic name in the question text. A form that already has a template
-- (even a deactivated one) is left alone, so hand-written templates are
-- never replaced and a template Faculty switched off stays off.

CREATE OR REPLACE FUNCTION public.ensure_standard_templates(
  p_subject_id TEXT,
  p_topic      TEXT
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_form    TEXT;
  v_code    TEXT;
  v_stem    TEXT;
  v_diff    TEXT;
  v_rat     TEXT;
  v_exp     TEXT;
  v_made    INTEGER := 0;
BEGIN
  FOREACH v_form IN ARRAY ARRAY['term_to_definition', 'definition_to_term',
                                'basis_to_term', 'term_to_basis']
  LOOP
    IF EXISTS (
      SELECT 1 FROM public.question_templates
      WHERE subject_id = p_subject_id AND topic = p_topic AND form = v_form
    ) THEN
      CONTINUE;
    END IF;

    IF v_form = 'term_to_definition' THEN
      v_code := 't2d'; v_diff := 'easy';
      v_stem := format('Under "%s", which of the following BEST describes {{term}}?', p_topic);
      v_rat  := 'That statement defines {{option_term}}, not {{term}}. Both belong to "{{topic}}", but they are different concepts.';
      v_exp  := '{{term}} is defined as: "{{definition}}" (Basis: {{legal_basis}}).';
    ELSIF v_form = 'definition_to_term' THEN
      v_code := 'd2t'; v_diff := 'medium';
      v_stem := format('Which term under "%s" matches the following description: {{definition}}', p_topic);
      v_rat  := '{{option_term}} is a different concept ("{{option_definition}}"), so it does not match the description in the question, which defines {{term}}.';
      v_exp  := 'The description matches {{term}}: "{{definition}}" (Basis: {{legal_basis}}).';
    ELSIF v_form = 'basis_to_term' THEN
      v_code := 'b2t'; v_diff := 'hard';
      v_stem := format('Under "%s", which of the following is covered by {{legal_basis}}?', p_topic);
      v_rat  := '{{option_term}} is covered by {{option_basis}}, not by {{legal_basis}}.';
      v_exp  := '{{legal_basis}} covers {{term}}: "{{definition}}"';
    ELSE
      v_code := 't2b'; v_diff := 'hard';
      v_stem := format('Under "%s", which provision is the legal basis of {{term}}?', p_topic);
      v_rat  := '{{option_basis}} is the legal basis of {{option_term}}, not of {{term}}.';
      v_exp  := '{{term}} is covered by {{legal_basis}}: "{{definition}}"';
    END IF;

    INSERT INTO public.question_templates
      (id, subject_id, topic, stem_template, difficulty, distractor_strategy,
       rationale_template, explanation_template, is_active, form)
    VALUES
      ('tpl_' || v_code || '_' || substr(md5(p_subject_id || '|' || p_topic), 1, 10),
       p_subject_id, p_topic, v_stem, v_diff, 'sibling_definitions',
       v_rat, v_exp, TRUE, v_form)
    ON CONFLICT (id) DO NOTHING;

    IF FOUND THEN
      v_made := v_made + 1;
    END IF;
  END LOOP;

  RETURN v_made;
END;
$$;

REVOKE ALL ON FUNCTION public.ensure_standard_templates(TEXT, TEXT) FROM PUBLIC, anon, authenticated;


-- ----------------------------------------------------------------
-- 7. Faculty tools for the concept bank
-- ----------------------------------------------------------------

-- Returns NULL when the fields are acceptable, otherwise a plain message.
CREATE OR REPLACE FUNCTION public.validate_concept_fields(
  p_term        TEXT,
  p_definition  TEXT,
  p_legal_basis TEXT
)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
BEGIN
  IF nullif(btrim(p_term), '') IS NULL THEN
    RETURN 'The term is required.';
  END IF;
  IF nullif(btrim(p_definition), '') IS NULL THEN
    RETURN 'The definition is required.';
  END IF;
  IF char_length(btrim(p_term)) < 2 THEN
    RETURN 'The term is too short.';
  END IF;
  IF char_length(btrim(p_term)) > 200 THEN
    RETURN 'The term is too long (200 characters at most).';
  END IF;
  IF char_length(btrim(p_definition)) < 10 THEN
    RETURN 'The definition is too short. Write the full meaning (at least 10 characters).';
  END IF;
  IF char_length(btrim(p_definition)) > 1500 THEN
    RETURN 'The definition is too long (1500 characters at most).';
  END IF;
  IF p_legal_basis IS NOT NULL AND char_length(btrim(p_legal_basis)) > 200 THEN
    RETURN 'The legal basis is too long (200 characters at most).';
  END IF;
  IF position('{{' IN COALESCE(p_term, '') || COALESCE(p_definition, '') || COALESCE(p_legal_basis, '')) > 0
     OR position('}}' IN COALESCE(p_term, '') || COALESCE(p_definition, '') || COALESCE(p_legal_basis, '')) > 0 THEN
    RETURN 'Text cannot contain {{ or }}.';
  END IF;
  RETURN NULL;
END;
$$;

REVOKE ALL ON FUNCTION public.validate_concept_fields(TEXT, TEXT, TEXT) FROM PUBLIC, anon, authenticated;

-- Works out the exact topic spelling and the sibling group for a new
-- concept. An existing topic keeps its spelling (matched ignoring case), so
-- "justifying circumstances" cannot create a second, empty topic.
CREATE OR REPLACE FUNCTION public.resolve_concept_target(
  p_subject_id TEXT,
  p_topic      TEXT,
  p_group      TEXT,
  OUT o_topic  TEXT,
  OUT o_group  TEXT,
  OUT o_error  TEXT
)
LANGUAGE plpgsql
STABLE
SET search_path = public, pg_temp
AS $$
DECLARE
  v_topic  TEXT;
  v_groups TEXT[];
  v_slug   TEXT;
BEGIN
  IF p_subject_id IS NULL OR p_subject_id NOT IN
     ('criminal_jurisprudence', 'law_enforcement', 'criminalistics',
      'crime_detection', 'criminology', 'corrections') THEN
    o_error := 'Choose a subject.';
    RETURN;
  END IF;

  v_topic := btrim(regexp_replace(COALESCE(p_topic, ''), '\s+', ' ', 'g'));
  IF v_topic = '' THEN
    o_error := 'Choose or type a topic.';
    RETURN;
  END IF;
  IF char_length(v_topic) > 120 THEN
    o_error := 'The topic name is too long (120 characters at most).';
    RETURN;
  END IF;
  IF position('{{' IN v_topic) > 0 OR position('}}' IN v_topic) > 0 THEN
    o_error := 'Text cannot contain {{ or }}.';
    RETURN;
  END IF;

  SELECT c.topic INTO o_topic
  FROM public.concept_bank c
  WHERE c.subject_id = p_subject_id AND lower(c.topic) = lower(v_topic)
  ORDER BY c.created_at NULLS LAST, c.id
  LIMIT 1;
  IF o_topic IS NULL THEN
    o_topic := v_topic;
  END IF;

  SELECT array_agg(DISTINCT c.sibling_group) INTO v_groups
  FROM public.concept_bank c
  WHERE c.subject_id = p_subject_id AND c.topic = o_topic;

  IF nullif(btrim(COALESCE(p_group, '')), '') IS NOT NULL THEN
    o_group := lower(btrim(p_group));
    IF o_group !~ '^[a-z0-9_]{3,80}$' THEN
      o_error := 'The group name may use only letters, numbers and underscores (3 to 80 characters).';
    END IF;
    RETURN;
  END IF;

  IF v_groups IS NULL OR cardinality(v_groups) = 0 THEN
    v_slug := btrim(lower(regexp_replace(p_subject_id || '_' || o_topic, '[^a-zA-Z0-9]+', '_', 'g')), '_');
    o_group := left(v_slug, 80);
  ELSIF cardinality(v_groups) = 1 THEN
    o_group := v_groups[1];
  ELSE
    o_error := 'This topic has more than one group. Choose which group the concept belongs to.';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.resolve_concept_target(TEXT, TEXT, TEXT) FROM PUBLIC, anon, authenticated;

-- Add (p_id NULL) or edit (p_id given) one concept. Editing changes only the
-- term, definition and legal basis; to move a concept to another topic,
-- deactivate it and add it again.
CREATE OR REPLACE FUNCTION public.admin_save_concept(
  p_id            TEXT,
  p_subject_id    TEXT,
  p_topic         TEXT,
  p_term          TEXT,
  p_definition    TEXT,
  p_legal_basis   TEXT,
  p_sibling_group TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_err      TEXT;
  v_term     TEXT;
  v_def      TEXT;
  v_basis    TEXT;
  v_existing public.concept_bank%ROWTYPE;
  v_topic    TEXT;
  v_group    TEXT;
  v_subject  TEXT;
  v_new_id   TEXT;
BEGIN
  IF NOT public.is_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Only admins can change concepts.');
  END IF;

  v_err := public.validate_concept_fields(p_term, p_definition, p_legal_basis);
  IF v_err IS NOT NULL THEN
    RETURN jsonb_build_object('success', false, 'error', v_err);
  END IF;

  v_term  := btrim(p_term);
  v_def   := btrim(p_definition);
  v_basis := nullif(btrim(COALESCE(p_legal_basis, '')), '');

  IF p_id IS NULL THEN
    SELECT t.o_topic, t.o_group, t.o_error INTO v_topic, v_group, v_err
    FROM public.resolve_concept_target(p_subject_id, p_topic, p_sibling_group) t;
    IF v_err IS NOT NULL THEN
      RETURN jsonb_build_object('success', false, 'error', v_err);
    END IF;
    v_subject := p_subject_id;
  ELSE
    SELECT * INTO v_existing FROM public.concept_bank WHERE id = p_id;
    IF NOT FOUND THEN
      RETURN jsonb_build_object('success', false, 'error', 'That concept no longer exists.');
    END IF;
    v_subject := v_existing.subject_id;
    v_topic   := v_existing.topic;
    v_group   := v_existing.sibling_group;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.concept_bank c
    WHERE c.subject_id = v_subject
      AND lower(c.topic) = lower(v_topic)
      AND lower(btrim(c.term)) = lower(v_term)
      AND c.id IS DISTINCT FROM p_id
  ) THEN
    RETURN jsonb_build_object('success', false, 'error',
      'This topic already has a concept called "' || v_term || '".');
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.concept_bank c
    WHERE c.sibling_group = v_group
      AND lower(btrim(c.definition)) = lower(v_def)
      AND c.id IS DISTINCT FROM p_id
  ) THEN
    RETURN jsonb_build_object('success', false, 'error',
      'Another concept in this group already has this definition.');
  END IF;

  IF p_id IS NULL THEN
    v_new_id := 'cb_' || replace(gen_random_uuid()::text, '-', '');
    INSERT INTO public.concept_bank
      (id, subject_id, topic, term, definition, legal_basis, sibling_group, is_active)
    VALUES
      (v_new_id, v_subject, v_topic, v_term, v_def, v_basis, v_group, TRUE);

    PERFORM public.ensure_standard_templates(v_subject, v_topic);
    PERFORM public.log_admin_action('create', 'concept_bank', v_new_id,
      jsonb_build_object('subject_id', v_subject, 'topic', v_topic, 'term', v_term));

    RETURN jsonb_build_object('success', true, 'id', v_new_id, 'topic', v_topic);
  END IF;

  UPDATE public.concept_bank
  SET term = v_term, definition = v_def, legal_basis = v_basis
  WHERE id = p_id;

  PERFORM public.log_admin_action('update', 'concept_bank', p_id,
    jsonb_build_object('subject_id', v_subject, 'topic', v_topic, 'term', v_term));

  RETURN jsonb_build_object('success', true, 'id', p_id, 'topic', v_topic);
END;
$$;

REVOKE ALL ON FUNCTION public.admin_save_concept(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_save_concept(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) TO authenticated;

-- Deactivate or restore a concept. Questions already made from it are kept.
CREATE OR REPLACE FUNCTION public.admin_set_concept_active(
  p_id     TEXT,
  p_active BOOLEAN
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_term TEXT;
BEGIN
  IF NOT public.is_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Only admins can change concepts.');
  END IF;
  IF p_active IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Choose active or inactive.');
  END IF;

  UPDATE public.concept_bank SET is_active = p_active WHERE id = p_id
  RETURNING term INTO v_term;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'That concept no longer exists.');
  END IF;

  PERFORM public.log_admin_action(
    CASE WHEN p_active THEN 'restore' ELSE 'delete' END,
    'concept_bank', p_id, jsonb_build_object('term', v_term));

  RETURN jsonb_build_object('success', true);
END;
$$;

REVOKE ALL ON FUNCTION public.admin_set_concept_active(TEXT, BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_set_concept_active(TEXT, BOOLEAN) TO authenticated;

-- Add many concepts to ONE subject and topic at once.
-- p_rows is a JSON array of {"term": "...", "definition": "...", "legal_basis": "..."}.
-- Valid rows are saved; a row that cannot be saved is listed in "rejected"
-- with the reason, and the others still go through.
CREATE OR REPLACE FUNCTION public.admin_import_concepts(
  p_subject_id    TEXT,
  p_topic         TEXT,
  p_sibling_group TEXT,
  p_rows          JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_err      TEXT;
  v_topic    TEXT;
  v_group    TEXT;
  v_item     JSONB;
  v_pos      INTEGER;
  v_term     TEXT;
  v_def      TEXT;
  v_basis    TEXT;
  v_inserted INTEGER := 0;
  v_rejected JSONB := '[]'::jsonb;
BEGIN
  IF NOT public.is_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Only admins can import concepts.');
  END IF;

  IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' OR jsonb_array_length(p_rows) = 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'There are no rows to import.');
  END IF;
  IF jsonb_array_length(p_rows) > 200 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Import at most 200 concepts at a time.');
  END IF;

  SELECT t.o_topic, t.o_group, t.o_error INTO v_topic, v_group, v_err
  FROM public.resolve_concept_target(p_subject_id, p_topic, p_sibling_group) t;
  IF v_err IS NOT NULL THEN
    RETURN jsonb_build_object('success', false, 'error', v_err);
  END IF;

  FOR v_item, v_pos IN
    SELECT e.value, e.ordinality::INTEGER
    FROM jsonb_array_elements(p_rows) WITH ORDINALITY AS e(value, ordinality)
  LOOP
    IF jsonb_typeof(v_item) <> 'object' THEN
      v_rejected := v_rejected || jsonb_build_array(jsonb_build_object(
        'row', v_pos, 'term', '', 'reason', 'This row is not valid.'));
      CONTINUE;
    END IF;

    v_term  := btrim(COALESCE(v_item->>'term', ''));
    v_def   := btrim(COALESCE(v_item->>'definition', ''));
    v_basis := nullif(btrim(COALESCE(v_item->>'legal_basis', '')), '');

    v_err := public.validate_concept_fields(v_term, v_def, v_basis);

    IF v_err IS NULL AND EXISTS (
      SELECT 1 FROM public.concept_bank c
      WHERE c.subject_id = p_subject_id
        AND lower(c.topic) = lower(v_topic)
        AND lower(btrim(c.term)) = lower(v_term)
    ) THEN
      v_err := 'This topic already has this term.';
    END IF;

    IF v_err IS NULL AND EXISTS (
      SELECT 1 FROM public.concept_bank c
      WHERE c.sibling_group = v_group
        AND lower(btrim(c.definition)) = lower(v_def)
    ) THEN
      v_err := 'Another concept in this group already has this definition.';
    END IF;

    IF v_err IS NOT NULL THEN
      v_rejected := v_rejected || jsonb_build_array(jsonb_build_object(
        'row', v_pos, 'term', left(v_term, 80), 'reason', v_err));
      CONTINUE;
    END IF;

    INSERT INTO public.concept_bank
      (id, subject_id, topic, term, definition, legal_basis, sibling_group, is_active)
    VALUES
      ('cb_' || replace(gen_random_uuid()::text, '-', ''),
       p_subject_id, v_topic, v_term, v_def, v_basis, v_group, TRUE);
    v_inserted := v_inserted + 1;
  END LOOP;

  IF v_inserted > 0 THEN
    PERFORM public.ensure_standard_templates(p_subject_id, v_topic);
    PERFORM public.log_admin_action('create', 'concept_bank',
      v_inserted || ' concepts imported',
      jsonb_build_object('bulk', true, 'subject_id', p_subject_id, 'topic', v_topic,
                         'inserted', v_inserted,
                         'rejected', jsonb_array_length(v_rejected)));
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'inserted', v_inserted,
    'rejected', v_rejected,
    'topic', v_topic
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_import_concepts(TEXT, TEXT, TEXT, JSONB) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_import_concepts(TEXT, TEXT, TEXT, JSONB) TO authenticated;


-- ----------------------------------------------------------------
-- 8. Approve the generated questions Faculty selected
-- ----------------------------------------------------------------
-- Only questions that are generated AND still inactive are changed, so this
-- can never switch on a hand-written question by mistake. The caller sends
-- the ids Faculty ticked: a generated question Faculty deactivated on
-- purpose is not approved unless it is in the list.

CREATE OR REPLACE FUNCTION public.admin_approve_generated(p_ids TEXT[])
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_count INTEGER;
BEGIN
  IF NOT public.is_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Only admins can approve questions.');
  END IF;
  IF p_ids IS NULL OR cardinality(p_ids) = 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Select at least one question.');
  END IF;
  IF cardinality(p_ids) > 500 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Approve at most 500 questions at a time.');
  END IF;

  UPDATE public.questions
  SET is_active = TRUE
  WHERE id = ANY(p_ids)
    AND source = 'generated'
    AND is_active = FALSE;
  GET DIAGNOSTICS v_count = ROW_COUNT;

  IF v_count > 0 THEN
    PERFORM public.log_admin_action('restore', 'questions',
      v_count || ' generated questions',
      jsonb_build_object('bulk', true, 'approved', v_count,
                         'ids', to_jsonb(p_ids[1:50])));
  END IF;

  RETURN jsonb_build_object('success', true, 'approved', v_count);
END;
$$;

REVOKE ALL ON FUNCTION public.admin_approve_generated(TEXT[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_approve_generated(TEXT[]) TO authenticated;


-- ----------------------------------------------------------------
-- 9. Permissions for the helpers the status view calls
-- ----------------------------------------------------------------
-- The view runs with the signed-in user's rights, so these need EXECUTE for
-- "authenticated". They read only rows that user can already read.

REVOKE ALL ON FUNCTION public.template_required_slot(TEXT)        FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fill_slots(TEXT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.group_bases_distinct(TEXT)          FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.template_distractors(TEXT, TEXT)    FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.template_eligible(TEXT)             FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.template_candidates(TEXT)           FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.template_required_slot(TEXT)        TO authenticated;
GRANT EXECUTE ON FUNCTION public.fill_slots(TEXT, TEXT, TEXT, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.group_bases_distinct(TEXT)          TO authenticated;
GRANT EXECUTE ON FUNCTION public.template_distractors(TEXT, TEXT)    TO authenticated;
GRANT EXECUTE ON FUNCTION public.template_eligible(TEXT)             TO authenticated;
GRANT EXECUTE ON FUNCTION public.template_candidates(TEXT)           TO authenticated;

-- Only used inside the SECURITY DEFINER functions above.
REVOKE ALL ON FUNCTION public.fill_distractor_rationale(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT)
  FROM PUBLIC, anon, authenticated;


-- ----------------------------------------------------------------
-- 10. Create the missing forms for the topics that already exist
-- ----------------------------------------------------------------
-- The four topics seeded earlier keep their hand-written
-- term_to_definition template and gain the other three forms.

DO $backfill$
DECLARE
  r RECORD;
BEGIN
  FOR r IN SELECT DISTINCT subject_id, topic FROM public.concept_bank LOOP
    PERFORM public.ensure_standard_templates(r.subject_id, r.topic);
  END LOOP;
END
$backfill$;


-- ================================================================
-- ROLLBACK (only if you want to undo this file; run it separately)
-- ================================================================
-- Questions already generated stay in the bank. Remove the new templates and
-- functions, restore the previous view, then re-run
-- supabase_template_generation.sql to bring back the old generator.
--
--   DROP VIEW IF EXISTS public.template_generation_status;
--   DELETE FROM public.question_templates WHERE form <> 'term_to_definition';
--   DELETE FROM public.question_templates WHERE id LIKE 'tpl\_t2d\_%';
--   DROP FUNCTION IF EXISTS public.admin_approve_generated(TEXT[]);
--   DROP FUNCTION IF EXISTS public.admin_import_concepts(TEXT, TEXT, TEXT, JSONB);
--   DROP FUNCTION IF EXISTS public.admin_set_concept_active(TEXT, BOOLEAN);
--   DROP FUNCTION IF EXISTS public.admin_save_concept(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT);
--   DROP FUNCTION IF EXISTS public.resolve_concept_target(TEXT, TEXT, TEXT);
--   DROP FUNCTION IF EXISTS public.validate_concept_fields(TEXT, TEXT, TEXT);
--   DROP FUNCTION IF EXISTS public.ensure_standard_templates(TEXT, TEXT);
--   DROP FUNCTION IF EXISTS public.template_candidates(TEXT);
--   DROP FUNCTION IF EXISTS public.template_eligible(TEXT);
--   DROP FUNCTION IF EXISTS public.template_distractors(TEXT, TEXT);
--   DROP FUNCTION IF EXISTS public.group_bases_distinct(TEXT);
--   DROP FUNCTION IF EXISTS public.fill_distractor_rationale(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT);
--   DROP FUNCTION IF EXISTS public.fill_slots(TEXT, TEXT, TEXT, TEXT, TEXT);
--   DROP FUNCTION IF EXISTS public.template_required_slot(TEXT);
--   ALTER TABLE public.question_templates DROP CONSTRAINT IF EXISTS question_templates_form_check;
--   ALTER TABLE public.question_templates DROP COLUMN IF EXISTS form;
--   -- then run supabase_template_generation.sql again
