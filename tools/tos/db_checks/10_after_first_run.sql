INSERT INTO zz.chk
SELECT 1, 'TOS topics loaded (37)', COUNT(*) = 37, COUNT(*)::TEXT FROM public.tos_topics
UNION ALL SELECT 2, 'TOS competencies loaded (146)', COUNT(*) = 146, COUNT(*)::TEXT FROM public.tos_competencies
UNION ALL SELECT 3, 'Each subject''s competencies total 100 items',
  bool_and(s = 100), string_agg(subject_id || '=' || s, ' ' ORDER BY subject_id)
  FROM (SELECT subject_id, SUM(items) s FROM public.tos_competencies GROUP BY 1) x
UNION ALL SELECT 4, 'Each topic''s items equal the sum of its competencies',
  NOT EXISTS (SELECT 1 FROM public.tos_topics t
               WHERE t.items <> (SELECT SUM(c.items) FROM public.tos_competencies c WHERE c.topic_code = t.code)), ''
UNION ALL SELECT 5, 'TOS bank: 600 questions, all inactive',
  COUNT(*) = 600 AND NOT bool_or(is_active), COUNT(*) || ' total, ' || COUNT(*) FILTER (WHERE is_active) || ' active'
  FROM public.questions WHERE template_id = 'tos_2024'
UNION ALL SELECT 6, 'Each TOS question names a competency of its own subject and a Bloom level',
  NOT EXISTS (SELECT 1 FROM public.questions q LEFT JOIN public.tos_competencies c ON c.code = q.tos_code
               WHERE q.template_id = 'tos_2024' AND (c.code IS NULL OR c.subject_id <> q.subject_id OR q.bloom_level IS NULL)), ''
UNION ALL SELECT 7, 'TOS bank matches the TOS items per competency and Bloom level',
  NOT EXISTS (SELECT 1 FROM public.tos_competencies c CROSS JOIN LATERAL jsonb_each_text(c.bloom) b(level, n)
               WHERE (SELECT COUNT(*) FROM public.questions q
                       WHERE q.template_id = 'tos_2024' AND q.tos_code = c.code AND q.bloom_level = b.level) <> b.n::INT), ''
UNION ALL SELECT 8, 'Imported questions linked to a TOS topic (742)', COUNT(*) = 742, COUNT(*)::TEXT
  FROM public.questions WHERE tos_code IS NOT NULL AND template_id IS DISTINCT FROM 'tos_2024'
UNION ALL SELECT 9, 'Questions moved to the subject the TOS gives them (49)', COUNT(*) = 49, COUNT(*)::TEXT
  FROM public.tos_alignment_backup b JOIN public.questions q ON q.id = b.question_id WHERE q.subject_id <> b.old_subject_id
UNION ALL SELECT 10, 'Questions switched off, not deleted (33)', COUNT(*) = 33, COUNT(*)::TEXT
  FROM public.tos_alignment_backup b JOIN public.questions q ON q.id = b.question_id WHERE b.old_is_active AND NOT q.is_active
UNION ALL SELECT 11, 'No question deleted (759 + 600)',
  COUNT(*) = (SELECT v::INT FROM zz.fp WHERE k = 'questions_before') + 600, COUNT(*)::TEXT FROM public.questions
UNION ALL SELECT 12, 'Every changed question has a backup row (759)', COUNT(*) = 759, COUNT(*)::TEXT FROM public.tos_alignment_backup
UNION ALL SELECT 13, 'Topic mastery renamed to TOS topics without losing attempts; a dropped topic''s row is kept',
  SUM(attempts)::TEXT = (SELECT v FROM zz.fp WHERE k = 'attempts_before')
  AND (SELECT COUNT(*) FROM public.tos_alignment_mastery_backup) = 3
  AND EXISTS (SELECT 1 FROM public.topic_mastery WHERE topic = 'Police Communication System' AND attempts = 3),
  SUM(attempts) || ' attempts; ' || (SELECT COUNT(*) FROM public.tos_alignment_mastery_backup) || ' renamed rows backed up'
  FROM public.topic_mastery;

-- 14-15: the trigger on questions.tos_code
DO $t$
DECLARE ok14 BOOLEAN := FALSE; ok15 BOOLEAN := FALSE;
BEGIN
  BEGIN
    UPDATE public.questions SET tos_code = 'CLJ-99' WHERE id = (SELECT id FROM public.questions WHERE tos_code LIKE 'CLJ-%' LIMIT 1);
  EXCEPTION WHEN OTHERS THEN ok14 := SQLERRM LIKE '%not a TOS topic or competency%';
  END;
  BEGIN
    UPDATE public.questions SET tos_code = 'CA-1' WHERE id = (SELECT id FROM public.questions WHERE tos_code LIKE 'CLJ-%' LIMIT 1);
  EXCEPTION WHEN OTHERS THEN ok15 := SQLERRM LIKE '%belongs to subject%';
  END;
  INSERT INTO zz.chk VALUES (14, 'Trigger refuses an unknown TOS code', ok14, ''),
                            (15, 'Trigger refuses a TOS code of another subject', ok15, '');
END
$t$;
