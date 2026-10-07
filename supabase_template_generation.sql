-- ================================================================
-- CrimiReview -- Template-Based Automatic Item Generation (free path)
-- ================================================================
-- The slot-filling counterpart to supabase_document_generation.sql's LLM
-- path. Both are Automatic Item Generation (panel note 1); this one is the
-- method already documented in supabase_schema_v2.sql sections 5-6 as
-- "no LLM, no guessing" (Gierl & Lai) -- but nothing was ever built to
-- actually RUN it. This file is that missing piece: one function that turns
-- public.question_templates + public.concept_bank into real rows in
-- public.questions. No API key, no network call, no per-question cost --
-- pure SQL string substitution over data already sitting in your database.
--
-- Algorithm, per generated question:
--   1. Pick one "key" concept from concept_bank (matched to the template by
--      subject_id + topic).
--   2. Its `definition` becomes the CORRECT answer option's text.
--   3. Up to 3 "sibling" concepts (same sibling_group) become the WRONG
--      answer options -- their own `definition`, each with its own
--      already-written reason it's wrong (rationale_template filled with
--      that sibling's term).
--   4. stem_template's {{term}} becomes the key concept's term.
--   5. Inserted as source = 'generated', is_active = FALSE -- the exact
--      same review gate the LLM path uses; AdminService.setActive() is
--      "approve", exactly as documented in supabase_document_generation.sql.
--
-- Ceiling, and this matters for what you tell an admin to expect: a
-- question's stem is deterministic from its key concept (same {{term}}
-- every time), so uq_questions_subject_stem rejects a re-generated
-- duplicate. Each concept can ever produce exactly ONE question. With the
-- 4 seeded templates / 21 concepts, the true maximum is 21 questions,
-- ever, until someone adds more rows to concept_bank by hand.
--
-- HOW TO RUN: Supabase SQL Editor, paste, Run. Safe to re-run.
-- ================================================================

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
  v_template    RECORD;
  v_key         RECORD;
  v_siblings    JSONB;
  v_options     JSONB;
  v_stem        TEXT;
  v_explanation TEXT;
  v_new_id      TEXT;
  v_inserted    INTEGER := 0;
  v_skipped     INTEGER := 0;
  v_considered  INTEGER := 0;
BEGIN
  IF NOT public.is_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Only admins can generate questions.');
  END IF;

  IF p_count IS NULL OR p_count < 1 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Count must be at least 1.');
  END IF;

  SELECT * INTO v_template FROM public.question_templates
  WHERE id = p_template_id AND is_active = TRUE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Template not found or inactive.');
  END IF;

  -- One question per key concept, at most p_count, in random order so
  -- repeated runs eventually cover the whole topic rather than always
  -- landing on the same handful.
  FOR v_key IN
    SELECT * FROM public.concept_bank
    WHERE topic = v_template.topic
      AND subject_id = v_template.subject_id
      AND is_active = TRUE
    ORDER BY random()
    LIMIT p_count
  LOOP
    v_considered := v_considered + 1;

    -- Distractors: up to 3 siblings, randomly chosen so re-running doesn't
    -- always produce the same wrong-answer set for the same key concept.
    SELECT jsonb_agg(jsonb_build_object(
             'text', s.definition,
             'is_correct', false,
             'rationale', regexp_replace(
                            regexp_replace(
                              COALESCE(v_template.rationale_template, ''),
                              '\{\{option_term\}\}', s.term, 'g'
                            ),
                            '\{\{term\}\}', v_key.term, 'g'
                          )
           ))
    INTO v_siblings
    FROM (
      SELECT * FROM public.concept_bank
      WHERE sibling_group = v_key.sibling_group
        AND id <> v_key.id
        AND is_active = TRUE
      ORDER BY random()
      LIMIT 3
    ) s;

    IF v_siblings IS NULL OR jsonb_array_length(v_siblings) < 1 THEN
      -- Fewer than 2 total options possible -- can't make a valid MCQ from
      -- a sibling group this small.
      v_skipped := v_skipped + 1;
      CONTINUE;
    END IF;

    v_explanation := regexp_replace(
                        regexp_replace(
                          regexp_replace(
                            COALESCE(v_template.explanation_template, ''),
                            '\{\{term\}\}', v_key.term, 'g'
                          ),
                          '\{\{definition\}\}', v_key.definition, 'g'
                        ),
                        '\{\{legal_basis\}\}', COALESCE(v_key.legal_basis, ''), 'g'
                      );

    v_options := jsonb_build_array(jsonb_build_object(
                   'text', v_key.definition,
                   'is_correct', true,
                   'rationale', 'Correct. ' || v_key.definition ||
                     CASE WHEN v_key.legal_basis IS NOT NULL
                          THEN ' (Basis: ' || v_key.legal_basis || ')' ELSE '' END
                 )) || v_siblings;

    -- Shuffle option order -- sync_question_correct_index (schema_v2)
    -- recomputes correct_answer_index from the is_correct flag regardless
    -- of position, so this is safe.
    SELECT jsonb_agg(opt ORDER BY random())
    INTO v_options
    FROM jsonb_array_elements(v_options) AS opt;

    v_stem   := regexp_replace(v_template.stem_template, '\{\{term\}\}', v_key.term, 'g');
    v_new_id := 'gen_tpl_' || replace(gen_random_uuid()::text, '-', '');

    BEGIN
      INSERT INTO public.questions (
        id, subject_id, topic, question_text, options, difficulty,
        explanation, legal_basis, remediation_hint, source, template_id,
        version, is_active, created_by
      ) VALUES (
        v_new_id, v_template.subject_id, v_template.topic, v_stem, v_options,
        v_template.difficulty, v_explanation, v_key.legal_basis, NULL,
        'generated', v_template.id, 1, FALSE, auth.uid()
      );
      v_inserted := v_inserted + 1;
    EXCEPTION WHEN unique_violation THEN
      -- This key concept already has a generated question from an earlier
      -- run -- not an error, just nothing new for this one.
      v_skipped := v_skipped + 1;
    END;
  END LOOP;

  IF v_considered = 0 THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'No active concepts found for this template''s topic.'
    );
  END IF;

  PERFORM public.log_admin_action(
    'generate', 'questions', v_template.id,
    jsonb_build_object('method', 'template', 'inserted', v_inserted, 'skipped', v_skipped)
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


-- ================================================================
-- Read model for the admin picker: which templates exist, and how many
-- concepts are left to turn into a question (so the UI can show "6
-- available" instead of an admin discovering the 21-question ceiling by
-- trial and error).
-- ================================================================

DROP VIEW IF EXISTS public.template_generation_status;
CREATE VIEW public.template_generation_status
WITH (security_invoker = on) AS
SELECT
  t.id, t.subject_id, t.topic, t.difficulty, t.is_active,
  COUNT(c.id) FILTER (WHERE c.is_active) AS total_concepts,
  COUNT(c.id) FILTER (
    WHERE c.is_active AND NOT EXISTS (
      SELECT 1 FROM public.questions q
      WHERE q.template_id = t.id
        AND q.question_text = regexp_replace(t.stem_template, '\{\{term\}\}', c.term, 'g')
    )
  ) AS concepts_remaining
FROM public.question_templates t
LEFT JOIN public.concept_bank c
  ON c.topic = t.topic AND c.subject_id = t.subject_id
WHERE t.is_active
GROUP BY t.id, t.subject_id, t.topic, t.difficulty, t.is_active;

GRANT SELECT ON public.template_generation_status TO authenticated;
