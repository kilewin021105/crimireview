-- ================================================================
-- CrimiReview -- Faculty view of one student's full record
-- ================================================================
-- WHY THIS FILE EXISTS
--   Admin Panel > Students showed only the mastery summary. Faculty could
--   not see which level (Easy / Medium / Hard) a student had reached, how
--   far through each level's 4 segments they were, or their quiz history,
--   because user_progress and quiz_results only let a student read their
--   OWN rows.
--
--   This file adds ONE read-only function, admin_student_record(user_id).
--   It returns everything the record screen shows, in one call, and only
--   to an admin. It does not change any table or any existing rule: students
--   still see only their own rows, and nobody can change a student's data
--   through it.
--
-- WHAT IT RETURNS (JSON)
--   profile      name, email, school, role, rank, points, streaks, joined
--   subjects     one row per subject from user_progress: totals, per-level
--                correct/total, and the 4 segments of each level
--   mastery      every topic_mastery row, weakest first
--   quizzes      the 30 most recent quiz_results, newest first
--   quiz_count, daily_challenges, achievements   counts
--
-- HOW TO RUN
--   Supabase Dashboard > SQL Editor > New query > paste this file > Run.
--   Safe to run more than once. If you ran the first version (it failed with
--   "column r.created_at does not exist"), run this file again: it replaces it.
--
-- HOW TO UNDO
--   DROP FUNCTION IF EXISTS public.admin_student_record(UUID);
-- ================================================================

CREATE OR REPLACE FUNCTION public.admin_student_record(p_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_profile JSONB;
BEGIN
  IF NOT public.is_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Only admins can view student records.');
  END IF;

  IF p_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Choose a student.');
  END IF;

  SELECT jsonb_build_object(
           'user_id',        p.id,
           'email',          p.email,
           'display_name',   p.display_name,
           'school',         p.school,
           'role',           p.role,
           'rank',           p.rank,
           'total_points',   p.total_points,
           'total_quizzes',  p.total_quizzes,
           'total_correct',  p.total_correct,
           'current_streak', p.current_streak,
           'best_streak',    p.best_streak,
           'joined_at',      p.created_at
         )
  INTO v_profile
  FROM public.user_profiles p
  WHERE p.id = p_user_id;

  IF v_profile IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'That student no longer exists.');
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'profile', v_profile,

    'subjects', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'subject_id',         up.subject_id,
               'questions_answered', up.questions_answered,
               'correct_answers',    up.correct_answers,
               'easy_correct',       up.easy_correct,
               'easy_total',         up.easy_total,
               'medium_correct',     up.medium_correct,
               'medium_total',       up.medium_total,
               'hard_correct',       up.hard_correct,
               'hard_total',         up.hard_total,
               'easy_segments',      up.easy_segments,
               'medium_segments',    up.medium_segments,
               'hard_segments',      up.hard_segments,
               'last_study_date',    up.last_study_date
             ) ORDER BY up.subject_id)
      FROM public.user_progress up
      WHERE up.user_id = p_user_id
    ), '[]'::jsonb),

    'mastery', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'subject_id',     m.subject_id,
               'topic',          m.topic,
               'p_known',        m.p_known,
               'attempts',       m.attempts,
               'correct',        m.correct,
               'is_mastered',    m.is_mastered,
               'last_practiced', m.last_practiced
             ) ORDER BY m.p_known ASC, m.subject_id, m.topic)
      FROM public.topic_mastery m
      WHERE m.user_id = p_user_id
    ), '[]'::jsonb),

    -- The time a quiz was saved is "completed_at" on projects created from
    -- the first schema (this app's live project) and "created_at" in
    -- supabase_schema.sql. Reading the row as JSON works with either name,
    -- so this function never refers to a column that may not exist. The
    -- result keeps the key "created_at", which the app reads.
    'quizzes', COALESCE((
      SELECT jsonb_agg(q.item ORDER BY q.taken_at DESC NULLS LAST)
      FROM (
        SELECT jsonb_build_object(
                 'subject_id',         r.subject_id,
                 'difficulty',         r.difficulty,
                 'score',              r.score,
                 'total_questions',    r.total_questions,
                 'correct_answers',    r.correct_answers,
                 'time_taken_seconds', r.time_taken_seconds,
                 'created_at',         t.taken_at
               ) AS item,
               t.taken_at
        FROM public.quiz_results r
        CROSS JOIN LATERAL (
          SELECT COALESCE(to_jsonb(r)->>'completed_at',
                          to_jsonb(r)->>'created_at')::timestamptz AS taken_at
        ) t
        WHERE r.user_id = p_user_id
        ORDER BY t.taken_at DESC NULLS LAST
        LIMIT 30
      ) q
    ), '[]'::jsonb),

    'quiz_count',       (SELECT count(*) FROM public.quiz_results r WHERE r.user_id = p_user_id),
    'daily_challenges', (SELECT count(*) FROM public.daily_challenge_scores d WHERE d.user_id = p_user_id),
    'achievements',     (SELECT count(*) FROM public.user_achievements a WHERE a.user_id = p_user_id)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_student_record(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_student_record(UUID) TO authenticated;
