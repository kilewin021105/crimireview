-- ============================================
-- CrimiReview Supabase Schema (COMPLETE)
-- ============================================
-- Run this in Supabase SQL Editor (Database > SQL Editor)
-- This will set up all tables, policies, triggers, and storage

-- ============================================
-- 1. USER PROFILES TABLE
-- ============================================
CREATE TABLE IF NOT EXISTS public.user_profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email TEXT,
  display_name TEXT,
  avatar_url TEXT,
  school TEXT,
  total_points INTEGER DEFAULT 0,
  total_quizzes INTEGER DEFAULT 0,
  total_correct INTEGER DEFAULT 0,
  current_streak INTEGER DEFAULT 0,
  best_streak INTEGER DEFAULT 0,
  rank TEXT DEFAULT 'Rookie',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Add school column if table already exists
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS school TEXT;

-- Enable RLS
ALTER TABLE public.user_profiles ENABLE ROW LEVEL SECURITY;

-- Policies for user_profiles
DROP POLICY IF EXISTS "Users can view all profiles" ON public.user_profiles;
CREATE POLICY "Users can view all profiles" ON public.user_profiles
  FOR SELECT USING (true);

DROP POLICY IF EXISTS "Users can update own profile" ON public.user_profiles;
CREATE POLICY "Users can update own profile" ON public.user_profiles
  FOR UPDATE USING (auth.uid() = id);

DROP POLICY IF EXISTS "Users can insert own profile" ON public.user_profiles;
CREATE POLICY "Users can insert own profile" ON public.user_profiles
  FOR INSERT WITH CHECK (auth.uid() = id);

-- ============================================
-- 2. QUIZ RESULTS TABLE
-- ============================================
CREATE TABLE IF NOT EXISTS public.quiz_results (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  subject_id TEXT NOT NULL,
  difficulty TEXT NOT NULL,
  score INTEGER NOT NULL,
  total_questions INTEGER NOT NULL,
  correct_answers INTEGER NOT NULL,
  time_taken_seconds INTEGER,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE public.quiz_results ENABLE ROW LEVEL SECURITY;

-- Policies
DROP POLICY IF EXISTS "Users can view own quiz results" ON public.quiz_results;
CREATE POLICY "Users can view own quiz results" ON public.quiz_results
  FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert own quiz results" ON public.quiz_results;
CREATE POLICY "Users can insert own quiz results" ON public.quiz_results
  FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_quiz_results_user_id ON public.quiz_results(user_id);
CREATE INDEX IF NOT EXISTS idx_quiz_results_subject ON public.quiz_results(subject_id);

-- ============================================
-- 3. USER PROGRESS TABLE
-- ============================================
CREATE TABLE IF NOT EXISTS public.user_progress (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  subject_id TEXT NOT NULL,
  questions_answered INTEGER DEFAULT 0,
  correct_answers INTEGER DEFAULT 0,
  easy_correct INTEGER DEFAULT 0,
  easy_total INTEGER DEFAULT 0,
  medium_correct INTEGER DEFAULT 0,
  medium_total INTEGER DEFAULT 0,
  hard_correct INTEGER DEFAULT 0,
  hard_total INTEGER DEFAULT 0,
  last_study_date TIMESTAMPTZ,
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id, subject_id)
);

-- Enable RLS
ALTER TABLE public.user_progress ENABLE ROW LEVEL SECURITY;

-- Policies
DROP POLICY IF EXISTS "Users can view own progress" ON public.user_progress;
CREATE POLICY "Users can view own progress" ON public.user_progress
  FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert own progress" ON public.user_progress;
CREATE POLICY "Users can insert own progress" ON public.user_progress
  FOR INSERT WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update own progress" ON public.user_progress;
CREATE POLICY "Users can update own progress" ON public.user_progress
  FOR UPDATE USING (auth.uid() = user_id);

-- Index
CREATE INDEX IF NOT EXISTS idx_user_progress_user_id ON public.user_progress(user_id);

-- ============================================
-- 4. DAILY CHALLENGE SCORES TABLE
-- ============================================
CREATE TABLE IF NOT EXISTS public.daily_challenge_scores (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  challenge_date DATE NOT NULL,
  score INTEGER NOT NULL,
  correct_answers INTEGER NOT NULL,
  total_questions INTEGER DEFAULT 10,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id, challenge_date)
);

-- Enable RLS
ALTER TABLE public.daily_challenge_scores ENABLE ROW LEVEL SECURITY;

-- Policies
DROP POLICY IF EXISTS "Users can view all challenge scores" ON public.daily_challenge_scores;
CREATE POLICY "Users can view all challenge scores" ON public.daily_challenge_scores
  FOR SELECT USING (true);

DROP POLICY IF EXISTS "Users can insert own challenge scores" ON public.daily_challenge_scores;
CREATE POLICY "Users can insert own challenge scores" ON public.daily_challenge_scores
  FOR INSERT WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update own challenge scores" ON public.daily_challenge_scores;
CREATE POLICY "Users can update own challenge scores" ON public.daily_challenge_scores
  FOR UPDATE USING (auth.uid() = user_id);

-- Index
CREATE INDEX IF NOT EXISTS idx_daily_challenge_user_date ON public.daily_challenge_scores(user_id, challenge_date);

-- ============================================
-- 5. USER ACHIEVEMENTS TABLE
-- ============================================
CREATE TABLE IF NOT EXISTS public.user_achievements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  achievement_id TEXT NOT NULL,
  unlocked_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id, achievement_id)
);

-- Enable RLS
ALTER TABLE public.user_achievements ENABLE ROW LEVEL SECURITY;

-- Policies
DROP POLICY IF EXISTS "Users can view own achievements" ON public.user_achievements;
CREATE POLICY "Users can view own achievements" ON public.user_achievements
  FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert own achievements" ON public.user_achievements;
CREATE POLICY "Users can insert own achievements" ON public.user_achievements
  FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Index
CREATE INDEX IF NOT EXISTS idx_user_achievements_user_id ON public.user_achievements(user_id);

-- ============================================
-- 6. AUTO-CREATE PROFILE ON SIGNUP
-- ============================================
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.user_profiles (id, email, display_name)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'display_name', split_part(NEW.email, '@', 1))
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ============================================
-- 7. AUTO-UPDATE RANK ON POINTS CHANGE
-- ============================================
CREATE OR REPLACE FUNCTION public.update_user_rank()
RETURNS TRIGGER AS $$
BEGIN
  NEW.rank := CASE
    WHEN NEW.total_points >= 10000 THEN 'Legend'
    WHEN NEW.total_points >= 5000 THEN 'Master'
    WHEN NEW.total_points >= 2500 THEN 'Expert'
    WHEN NEW.total_points >= 1000 THEN 'Scholar'
    WHEN NEW.total_points >= 500 THEN 'Student'
    WHEN NEW.total_points >= 100 THEN 'Beginner'
    ELSE 'Rookie'
  END;
  NEW.updated_at := NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS update_rank_trigger ON public.user_profiles;
CREATE TRIGGER update_rank_trigger
  BEFORE UPDATE OF total_points ON public.user_profiles
  FOR EACH ROW EXECUTE FUNCTION public.update_user_rank();

-- ============================================
-- 8. STORAGE BUCKET FOR AVATARS
-- ============================================
INSERT INTO storage.buckets (id, name, public)
VALUES ('avatars', 'avatars', true)
ON CONFLICT (id) DO UPDATE SET public = true;

-- Storage policies for avatars
DROP POLICY IF EXISTS "Avatar images are publicly accessible" ON storage.objects;
CREATE POLICY "Avatar images are publicly accessible"
ON storage.objects FOR SELECT
USING (bucket_id = 'avatars');

DROP POLICY IF EXISTS "Users can upload their own avatar" ON storage.objects;
CREATE POLICY "Users can upload their own avatar"
ON storage.objects FOR INSERT
WITH CHECK (
  bucket_id = 'avatars' 
  AND auth.uid()::text = (storage.foldername(name))[1]
);

DROP POLICY IF EXISTS "Users can update their own avatar" ON storage.objects;
CREATE POLICY "Users can update their own avatar"
ON storage.objects FOR UPDATE
USING (
  bucket_id = 'avatars' 
  AND auth.uid()::text = (storage.foldername(name))[1]
);

DROP POLICY IF EXISTS "Users can delete their own avatar" ON storage.objects;
CREATE POLICY "Users can delete their own avatar"
ON storage.objects FOR DELETE
USING (
  bucket_id = 'avatars' 
  AND auth.uid()::text = (storage.foldername(name))[1]
);

-- ============================================
-- DONE! Schema is ready.
-- ============================================

-- IMPORTANT MANUAL STEPS IN SUPABASE DASHBOARD:
-- 
-- 1. Authentication > Providers > Email
--    - Disable "Confirm email" for instant login (optional)
--
-- 2. If storage bucket fails to create via SQL:
--    - Go to Storage > New Bucket
--    - Name: avatars
--    - Public: ON
--
-- 3. Test signup in your app!
