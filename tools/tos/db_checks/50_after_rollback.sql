INSERT INTO zz.chk
SELECT 24, 'Rollback restores every question''s subject, topic and status, and clears its TOS link',
  zz.q_fp() = (SELECT v FROM zz.fp WHERE k = 'q_before')
  AND NOT EXISTS (SELECT 1 FROM public.questions WHERE tos_code IS NOT NULL), ''
UNION ALL SELECT 25, 'Rollback restores every student''s topic mastery rows',
  zz.m_fp() = (SELECT v FROM zz.fp WHERE k = 'm_before'), '';
