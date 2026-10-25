-- 16-20: who can read and change the TOS data
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000b', true);
DO $s$
DECLARE ok BOOLEAN := FALSE;
BEGIN
  BEGIN PERFORM * FROM public.admin_tos_coverage();
  EXCEPTION WHEN insufficient_privilege THEN ok := TRUE;
  END;
  INSERT INTO zz.chk VALUES (16, 'A student cannot open the TOS coverage', ok, '');
END $s$;
INSERT INTO zz.chk SELECT 18, 'A signed-in student can read the TOS (37 topics, 146 competencies)',
  (SELECT COUNT(*) FROM public.tos_topics) = 37 AND (SELECT COUNT(*) FROM public.tos_competencies) = 146, '';
DO $w$
DECLARE ok BOOLEAN := FALSE;
BEGIN
  BEGIN INSERT INTO public.tos_topics (code, subject_id, topic_no, title, items, sort) VALUES ('X-1', 'criminology', 99, 'x', 1, 99);
  EXCEPTION WHEN insufficient_privilege THEN ok := TRUE;
  END;
  INSERT INTO zz.chk VALUES (20, 'A student cannot change the TOS tables', ok, '');
END $w$;
COMMIT;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000a', true);
INSERT INTO zz.chk SELECT 17, 'A faculty account gets the coverage of 37 topics and 146 competencies',
  COUNT(*) FILTER (WHERE level = 'topic') = 37 AND COUNT(*) FILTER (WHERE level = 'competency') = 146,
  COUNT(*) || ' rows' FROM public.admin_tos_coverage();
COMMIT;

BEGIN;
SET LOCAL ROLE anon;
INSERT INTO zz.chk SELECT 19, 'A visitor who is not signed in can read the TOS',
  (SELECT COUNT(*) FROM public.tos_topics) = 37, '';
COMMIT;
