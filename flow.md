# CrimiReview System Flow (Current)

Last updated: May 31, 2026

## App Launch Flow

```text
App Start
    |
    +--> Initialize core services
    |      - StorageService
    |      - SupabaseService
    |      - NotificationService
    |      - FeedbackService
    |      - AdaptiveMLService
    |      - ConnectivityService
    |      - OfflineSyncService
    |
    +--> Splash Screen (about 2.5s)
            |
            +--> Check onboarding flag
                    |
                    +--> Not completed --> Onboarding Screen (4 pages) --> Auth Screen
                    |
                    +--> Completed --> Check auth status
                                   |
                                   +--> Logged in --> Home Screen
                                   |
                                   +--> Not logged in --> Auth Screen
```

## Authentication Flow

### Sign Up (Current)

```text
Auth Screen (Sign Up mode)
    |
    +--> Enter First Name, Last Name, Email, Password
    |
    +--> Validate input
    |      - Email must be valid
    |      - Password: 8-16 chars, uppercase, lowercase, number
    |
    +--> Open Email Verification Screen
            |
            +--> Send OTP using Resend API
            |      - Store code in email_verifications table
            |
            +--> User enters 6-digit code
            |
            +--> Verify code in Supabase table
                    |
                    +--> Invalid/expired --> Show error, clear code, retry
                    |
                    +--> Valid --> Create Supabase account
                                  |
                                  +--> Ensure profile exists
                                  +--> Handle account switch if needed
                                  +--> Sync local totals to cloud
                                  +--> Navigate to Home Screen
```

### Sign In (Current)

```text
Auth Screen (Sign In mode)
    |
    +--> Enter Email + Password
    |
    +--> Supabase signIn
            |
            +--> Failed --> Show friendly error message
            |
            +--> Success --> Handle account switch if needed
                            - Sync pending offline queue
                            - Clear previous user's local quiz progress
                            |
                            +--> Load cloud profile/progress/achievements
                            +--> Merge with local data (max/union strategy)
                            +--> Save merged local data
                            +--> Sync highest totals back to cloud
                            +--> Navigate to Home Screen
```

### Forgot Password (Current)

```text
Auth Screen --> Forgot Password Screen
    |
    +--> Step 1: Enter Email
    |      - Send OTP via Resend
    |      - Store code in password_resets table
    |
    +--> Step 2: Enter 6-digit code
    |      - Verify code in password_resets table
    |
    +--> Step 3: Enter New Password + Confirm Password
           - Validate strength (8-16 chars, uppercase, lowercase, number)
           - Call Supabase RPC reset_user_password
           - Cleanup reset records
           - Return to login
```

## Main App Flow

### Home Container (Bottom Navigation)

```text
Home Screen (container)
    |
    +--> Tab 1: Home
    +--> Tab 2: Quiz (Subjects)
    +--> Tab 3: Progress
    +--> Tab 4: Settings

Home header shortcuts:
    +--> Profile icon --> Profile Screen
    +--> Leaderboard icon --> Leaderboard Screen
```

### Quiz Flow (Current)

```text
Home/Quiz Tab --> Subjects Screen
    |
    +--> Select Subject
    |
    +--> Difficulty Sheet
    |      - Easy: unlocked
    |      - Medium: unlocks after Easy passed
    |      - Hard: unlocks after Medium passed
    |
    +--> Load 10 questions for chosen difficulty
    |
    +--> Study Notes Screen
    |
    +--> Start Quiz --> Quiz Screen
            |
            +--> For each question:
            |      - Select answer
            |      - Check
            |      - Next
            |
            +--> Finish quiz
                   |
                   +--> AdaptiveLearningService.recordQuizResult
                   |      - Update local progress, streak, achievements
                   |      - Save subject progress to cloud if logged in
                   |
                   +--> Results Screen
                          - Mark level passed when score >= 75%
                          - Record ML learning signal
                          - Save quiz result:
                                online  -> Supabase saveQuizResult
                                offline -> queue in OfflineSyncService
                          - Done/Try Again -> back to main app
```

### Daily Challenge Flow (Current)

```text
Home Tab --> Daily Challenge Card --> DailyChallengeScreen
    |
    +--> Check local last_daily_challenge date
            |
            +--> Already done today
            |      - Show completion screen + countdown to next day
            |
            +--> Not done today
                   - Load 10 seeded random questions
                   - 20-second timer per question
                   - Time-out counts as unanswered
                   |
                   +--> Compute score
                          base score = correct * 10
                          total score includes 1.5x bonus
                   |
                   +--> Save local challenge date + local cumulative challenge score
                   +--> Sync challenge score:
                          online  -> Supabase saveDailyChallengeScore
                          offline -> queue in OfflineSyncService
                   +--> Show detailed results + review answers
                   +--> Done -> back to Home
```

### Study Modules Flow (Current)

```text
Home Tab --> Study Modules grid --> Modules Screen
    |
    +--> Load assets/modules/<subject_id>_module.json
    |
    +--> Choose:
           - Read Full Module
           - Open Chapter
    |
    +--> ModuleReaderScreen
           - Navigate chapter by chapter
           - Finish -> back
```

Note: module reader is currently a study path only (no direct quiz launch inside module reader).

### Progress and Achievements Flow

```text
Bottom Nav --> Progress Tab
    |
    +--> View overall stats, streak, subject breakdown
    |
    +--> Tap Achievements card --> Achievements Screen
```

### Settings and Account Flow (Current)

```text
Bottom Nav --> Settings Tab
    |
    +--> Profile tile --> Profile Screen
    |      - Edit name, school, email
    |      - Update profile photo (local and cloud when logged in)
    |
    +--> Appearance
    |      - Dark mode toggle
    |
    +--> Notifications & Feedback
    |      - Notifications toggle
    |      - Sound effects toggle
    |      - Haptic feedback toggle
    |
    +--> Account (if logged in)
    |      - Change Password Screen (new + confirm)
    |      - Sign Out
    |           - Supabase signOut
    |           - clearAuthData (keeps local quiz progress)
    |           - go to Auth Screen
    |
    +--> Account (if logged out)
    |      - Sign In tile -> Auth Screen
    |
    +--> Support
           - Share app
           - Rate app (placeholder)
           - Send feedback (mailto)
```

## Data Flow

### Local Storage (SharedPreferences)

```text
StorageService keys include:
    - user_progress (full serialized progress)
    - onboarding_completed
    - user profile fields (name, email, school, avatar)
    - settings (theme, notifications, sound, haptics, quiz prefs)
    - daily challenge state (date + score)
    - last_user_id (account switch handling)
    - offline_sync_queue (pending cloud writes)
```

### Cloud Storage (Supabase)

```text
Primary tables currently used:
    - user_profiles
    - quiz_results
    - user_progress
    - daily_challenge_scores
    - user_achievements
    - email_verifications
    - password_resets

Storage bucket:
    - avatars
```

### Offline-First Sync Flow

```text
Action requiring cloud write
    |
    +--> Check connectivity (ConnectivityService)
            |
            +--> Online  --> write to Supabase immediately
            |
            +--> Offline --> queue operation in OfflineSyncService
                            (persisted in SharedPreferences)
                            |
                            +--> On reconnect: auto-sync pending queue
```

Current queue producers in active app flow:
- Quiz result writes from Results Screen
- Daily challenge score writes from DailyChallengeScreen

Queue supports additional operation types:
- subjectProgress
- achievement
- profileUpdate

## Email Verification Integration Flow (Current)

```text
App --> Supabase table (email_verifications)
App --> Resend API (send message)
App --> verify code in Supabase table
App --> proceed to Supabase signUp/signIn
```

## Password Reset Integration Flow (Current)

```text
App --> Supabase table (password_resets)
App --> Resend API (send OTP)
App --> verify code in Supabase table
App --> Supabase RPC reset_user_password
```

## Screen Navigation Map (Current)

```text
Splash
  |
  +--> Onboarding (if first run)
  |      +--> Auth
  |
  +--> Auth (if not logged in)
  |
  +--> Home Container (if logged in)
         |
         +--> Home Tab
         |     +--> Daily Challenge
         |     +--> Study Modules -> Module Reader
         |     +--> Leaderboard (header)
         |     +--> Profile (header)
         |
         +--> Quiz Tab (Subjects)
         |     +--> Difficulty Picker
         |     +--> Study Notes
         |     +--> Quiz
         |     +--> Results
         |
         +--> Progress Tab
         |     +--> Achievements
         |
         +--> Settings Tab
               +--> Profile
               +--> Change Password
               +--> Sign Out
```

## Current Notes

- FlashcardScreen exists in code, but there is currently no navigation entry to it from active screens.
- Change Password flow currently asks for new password and confirmation only (no current password field).
- Daily challenge completion check is based on local stored date for the current device.