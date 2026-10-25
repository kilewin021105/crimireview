-- Fingerprints of the untouched database, and the results table.
CREATE SCHEMA zz;
CREATE TABLE zz.chk (n INT PRIMARY KEY, name TEXT, ok BOOLEAN, detail TEXT);
CREATE TABLE zz.fp (k TEXT PRIMARY KEY, v TEXT);
GRANT USAGE ON SCHEMA zz TO anon, authenticated;
GRANT INSERT, SELECT ON zz.chk TO anon, authenticated;
CREATE FUNCTION zz.q_fp(skip TEXT DEFAULT '') RETURNS TEXT LANGUAGE sql AS $$
  SELECT md5(string_agg(id || '|' || COALESCE(subject_id, '') || '|' || topic || '|' || COALESCE(is_active::TEXT, ''), ',' ORDER BY id))
    FROM public.questions WHERE template_id IS DISTINCT FROM 'tos_2024' AND id <> skip $$;
CREATE FUNCTION zz.m_fp() RETURNS TEXT LANGUAGE sql AS $$
  SELECT md5(string_agg(user_id || '|' || subject_id || '|' || topic || '|' || p_known || '|' || attempts || '|' || correct
                        || '|' || consecutive_correct || '|' || is_mastered, ',' ORDER BY user_id, subject_id, topic))
    FROM public.topic_mastery $$;
INSERT INTO zz.fp VALUES ('q_before', zz.q_fp()), ('m_before', zz.m_fp()),
  ('attempts_before', (SELECT SUM(attempts)::TEXT FROM public.topic_mastery)),
  ('questions_before', (SELECT COUNT(*)::TEXT FROM public.questions)),
  ('active_before', (SELECT COUNT(*)::TEXT FROM public.questions WHERE is_active));
