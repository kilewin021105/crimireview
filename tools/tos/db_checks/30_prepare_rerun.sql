-- Faculty switch one switched-off question back on before the files run again.
INSERT INTO zz.fp VALUES ('reactivated',
  (SELECT b.question_id FROM public.tos_alignment_backup b JOIN public.questions q ON q.id = b.question_id
    WHERE NOT q.is_active ORDER BY 1 LIMIT 1));
UPDATE public.questions SET is_active = TRUE WHERE id = (SELECT v FROM zz.fp WHERE k = 'reactivated');
INSERT INTO zz.fp VALUES ('q_first_run', zz.q_fp((SELECT v FROM zz.fp WHERE k = 'reactivated'))),
                         ('m_first_run', zz.m_fp());
