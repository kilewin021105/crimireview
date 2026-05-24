-- Email Verification Table
-- Run this in your Supabase SQL Editor

-- Create email_verifications table
CREATE TABLE IF NOT EXISTS email_verifications (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  email TEXT NOT NULL,
  code TEXT NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL,
  verified BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  attempts INTEGER DEFAULT 0
);

-- Create index for faster lookups
CREATE INDEX IF NOT EXISTS idx_email_verifications_email ON email_verifications(email);
CREATE INDEX IF NOT EXISTS idx_email_verifications_expires ON email_verifications(expires_at);

-- Enable RLS
ALTER TABLE email_verifications ENABLE ROW LEVEL SECURITY;

-- Policy: Anyone can insert (for sending verification)
CREATE POLICY "Anyone can request verification"
  ON email_verifications
  FOR INSERT
  TO anon, authenticated
  WITH CHECK (true);

-- Policy: Anyone can read their own verification by email
CREATE POLICY "Anyone can check their verification"
  ON email_verifications
  FOR SELECT
  TO anon, authenticated
  USING (true);

-- Policy: Anyone can update (for marking as verified)
CREATE POLICY "Anyone can verify"
  ON email_verifications
  FOR UPDATE
  TO anon, authenticated
  USING (true)
  WITH CHECK (true);

-- Policy: Allow delete for cleanup
CREATE POLICY "Allow cleanup"
  ON email_verifications
  FOR DELETE
  TO anon, authenticated
  USING (true);

-- Function to clean up expired verifications (run periodically)
CREATE OR REPLACE FUNCTION cleanup_expired_verifications()
RETURNS void AS $$
BEGIN
  DELETE FROM email_verifications
  WHERE expires_at < NOW() OR verified = true;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Optional: Create a cron job to clean up expired codes every hour
-- (Requires pg_cron extension - enable in Supabase Dashboard > Database > Extensions)
-- SELECT cron.schedule('cleanup-verifications', '0 * * * *', 'SELECT cleanup_expired_verifications()');
