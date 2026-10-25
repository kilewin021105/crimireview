INSERT INTO zz.chk
SELECT 21, 'Running both files again changes no other question or mastery row',
  zz.q_fp((SELECT v FROM zz.fp WHERE k = 'reactivated')) = (SELECT v FROM zz.fp WHERE k = 'q_first_run')
  AND zz.m_fp() = (SELECT v FROM zz.fp WHERE k = 'm_first_run'), ''
UNION ALL SELECT 22, 'A question that faculty switched back on stays on', is_active, id
  FROM public.questions WHERE id = (SELECT v FROM zz.fp WHERE k = 'reactivated')
UNION ALL SELECT 23, 'Running the bank file again adds no copies (600)', COUNT(*) = 600, COUNT(*)::TEXT
  FROM public.questions WHERE template_id = 'tos_2024';
