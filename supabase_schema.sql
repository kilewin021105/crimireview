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
  easy_segments JSONB,
  medium_segments JSONB,
  hard_segments JSONB,
  last_study_date TIMESTAMPTZ,
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id, subject_id)
);

ALTER TABLE public.user_progress ADD COLUMN IF NOT EXISTS easy_segments JSONB;
ALTER TABLE public.user_progress ADD COLUMN IF NOT EXISTS medium_segments JSONB;
ALTER TABLE public.user_progress ADD COLUMN IF NOT EXISTS hard_segments JSONB;

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
TO public
USING (bucket_id = 'avatars');

DROP POLICY IF EXISTS "Users can upload their own avatar" ON storage.objects;
CREATE POLICY "Users can upload their own avatar"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'avatars' 
  AND auth.uid()::text = (storage.foldername(name))[1]
);

DROP POLICY IF EXISTS "Users can update their own avatar" ON storage.objects;
CREATE POLICY "Users can update their own avatar"
ON storage.objects FOR UPDATE
TO authenticated
USING (
  bucket_id = 'avatars' 
  AND auth.uid()::text = (storage.foldername(name))[1]
);

DROP POLICY IF EXISTS "Users can delete their own avatar" ON storage.objects;
CREATE POLICY "Users can delete their own avatar"
ON storage.objects FOR DELETE
TO authenticated
USING (
  bucket_id = 'avatars' 
  AND auth.uid()::text = (storage.foldername(name))[1]
);

-- ============================================
-- 9. PASSWORD RESETS TABLE
-- ============================================
CREATE TABLE IF NOT EXISTS public.password_resets (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email TEXT NOT NULL,
  code TEXT NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL,
  used BOOLEAN DEFAULT FALSE,
  attempts INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE public.password_resets ENABLE ROW LEVEL SECURITY;

-- Allow anyone to insert (for sending reset code)
DROP POLICY IF EXISTS "Anyone can insert password reset" ON public.password_resets;
CREATE POLICY "Anyone can insert password reset" ON public.password_resets
  FOR INSERT WITH CHECK (true);

-- Allow anyone to select their own reset by email
DROP POLICY IF EXISTS "Anyone can view password resets" ON public.password_resets;
CREATE POLICY "Anyone can view password resets" ON public.password_resets
  FOR SELECT USING (true);

-- Allow anyone to update (for incrementing attempts)
DROP POLICY IF EXISTS "Anyone can update password resets" ON public.password_resets;
CREATE POLICY "Anyone can update password resets" ON public.password_resets
  FOR UPDATE USING (true);

-- Allow anyone to delete expired/used resets
DROP POLICY IF EXISTS "Anyone can delete password resets" ON public.password_resets;
CREATE POLICY "Anyone can delete password resets" ON public.password_resets
  FOR DELETE USING (true);

-- Index for faster lookups
CREATE INDEX IF NOT EXISTS idx_password_resets_email ON public.password_resets(email);

-- ============================================
-- 10. RESET PASSWORD FUNCTION (RPC)
-- ============================================
-- This function allows resetting a user's password after code verification
-- SECURITY: Only works if there's a valid used=true record in password_resets

CREATE OR REPLACE FUNCTION public.reset_user_password(user_email TEXT, new_password TEXT)
RETURNS VOID AS $$
DECLARE
  reset_record RECORD;
  target_user_id UUID;
BEGIN
  -- Check for a valid (used) reset record from the last 15 minutes
  SELECT * INTO reset_record
  FROM public.password_resets
  WHERE email = LOWER(user_email)
    AND used = TRUE
    AND created_at > NOW() - INTERVAL '15 minutes'
  ORDER BY created_at DESC
  LIMIT 1;

  IF reset_record IS NULL THEN
    RAISE EXCEPTION 'No valid password reset found. Please request a new code.';
  END IF;

  -- Get the user ID from auth.users
  SELECT id INTO target_user_id
  FROM auth.users
  WHERE email = LOWER(user_email);

  IF target_user_id IS NULL THEN
    RAISE EXCEPTION 'User not found.';
  END IF;

  -- Update the user's password using Supabase auth admin function
  UPDATE auth.users
  SET encrypted_password = crypt(new_password, gen_salt('bf')),
      updated_at = NOW()
  WHERE id = target_user_id;

  -- Delete the reset record after successful password change
  DELETE FROM public.password_resets
  WHERE email = LOWER(user_email);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permission to anon and authenticated users
GRANT EXECUTE ON FUNCTION public.reset_user_password(TEXT, TEXT) TO anon;
GRANT EXECUTE ON FUNCTION public.reset_user_password(TEXT, TEXT) TO authenticated;

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
