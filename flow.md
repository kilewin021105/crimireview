# CrimiReview System Flow

## App Launch Flow

```
App Start
    │
    ▼
Splash Screen (2s)
    │
    ▼
Check Onboarding Status
    │
    ├── Not Completed ──► Onboarding Screen ──► Auth Screen
    │
    └── Completed ──► Check Auth Status
                          │
                          ├── Logged In ──► Home Screen
                          │
                          └── Not Logged In ──► Auth Screen
```

## Authentication Flow

### Sign Up
```
Auth Screen (Sign Up Mode)
    │
    ▼
Enter Name, Email, Password
    │
    ▼
Validate Input
    │
    ▼
Email Verification Screen
    │
    ▼
Send OTP via Resend API (noreply@crimireview.app)
    │
    ▼
User Enters 6-Digit Code
    │
    ▼
Verify Code with Backend
    │
    ├── Invalid ──► Show Error, Clear Code, Retry
    │
    └── Valid ──► Create Supabase Account
                      │
                      ▼
                  Auto Sign In
                      │
                      ▼
                  Sync Local Progress
                      │
                      ▼
                  Home Screen
```

### Sign In
```
Auth Screen (Sign In Mode)
    │
    ▼
Enter Email, Password
    │
    ▼
Supabase Authentication
    │
    ├── Failed ──► Show Error Message
    │
    └── Success ──► Sync Progress ──► Home Screen
```

### Forgot Password
```
Auth Screen ──► Forgot Password Dialog
    │
    ▼
Enter Email
    │
    ▼
Send Reset Link via Supabase
    │
    ▼
User Clicks Link in Email
    │
    ▼
Reset Password
```

## Main App Flow

### Home Screen
```
Home Screen
    │
    ├── Subject Cards ──► Quiz Screen
    │
    ├── Daily Challenge ──► Daily Challenge Screen
    │
    ├── Flashcards ──► Flashcard Screen
    │
    ├── Achievements ──► Achievements Screen
    │
    ├── Leaderboard ──► Leaderboard Screen
    │
    └── Settings ──► Settings Screen
```

### Quiz Flow
```
Select Subject
    │
    ▼
Select Difficulty (Easy/Medium/Hard)
    │
    ▼
Load Questions from Database
    │
    ▼
Display Question
    │
    ▼
User Selects Answer
    │
    ├── Correct ──► Show Green, +10 Points
    │
    └── Wrong ──► Show Red, Show Correct Answer
    │
    ▼
Next Question (repeat until done)
    │
    ▼
Quiz Results Screen
    │
    ├── Score Summary
    ├── Time Taken
    ├── Accuracy %
    └── Share Results Option
    │
    ▼
Update Progress & Sync to Supabase
```

### Daily Challenge Flow
```
Daily Challenge Screen
    │
    ▼
Check if Already Completed Today
    │
    ├── Yes ──► Show "Come Back Tomorrow"
    │
    └── No ──► Load 10 Random Questions
                   │
                   ▼
               Complete Challenge
                   │
                   ▼
               Award Bonus Points
                   │
                   ▼
               Update Streak
```

### Flashcard Flow
```
Select Subject
    │
    ▼
Load Flashcards
    │
    ▼
Display Front (Question)
    │
    ▼
Tap to Flip ──► Show Back (Answer)
    │
    ▼
Swipe Left/Right for Next/Previous
```

## Data Flow

### Local Storage (SharedPreferences)
```
┌─────────────────────────────────────┐
│         StorageService              │
├─────────────────────────────────────┤
│ • User Progress                     │
│ • Subject Progress                  │
│ • Quiz History                      │
│ • Achievements                      │
│ • Settings (Theme, Sound, etc.)     │
│ • Onboarding Status                 │
│ • User Name                         │
└─────────────────────────────────────┘
```

### Cloud Storage (Supabase)
```
┌─────────────────────────────────────┐
│         Supabase Database           │
├─────────────────────────────────────┤
│ users                               │
│ ├── id                              │
│ ├── email                           │
│ ├── display_name                    │
│ ├── total_points                    │
│ ├── total_quizzes                   │
│ ├── total_correct                   │
│ ├── current_streak                  │
│ ├── best_streak                     │
│ └── created_at                      │
└─────────────────────────────────────┘
```

### Sync Flow
```
Local Action (Quiz Complete, etc.)
    │
    ▼
Save to Local Storage
    │
    ▼
Check Internet Connection
    │
    ├── Offline ──► Queue for Later
    │
    └── Online ──► Sync to Supabase
                       │
                       ▼
                   Update Leaderboard
```

## Email Verification Flow (Resend API)

```
┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│   App        │    │  Supabase    │    │  Resend API  │
│              │    │  Edge Func   │    │              │
└──────┬───────┘    └──────┬───────┘    └──────┬───────┘
       │                   │                   │
       │ Send OTP Request  │                   │
       │──────────────────►│                   │
       │                   │ Send Email        │
       │                   │──────────────────►│
       │                   │                   │
       │                   │   Email Sent      │
       │                   │◄──────────────────│
       │   OTP Stored      │                   │
       │◄──────────────────│                   │
       │                   │                   │
       │ Verify OTP        │                   │
       │──────────────────►│                   │
       │                   │                   │
       │   Result          │                   │
       │◄──────────────────│                   │
       │                   │                   │
```

## Settings Flow

```
Settings Screen
    │
    ├── Profile Section
    │   ├── Edit Name
    │   └── Change Password ──► Change Password Screen
    │
    ├── Preferences
    │   ├── Dark/Light Theme Toggle
    │   ├── Sound Effects Toggle
    │   └── Notifications Toggle
    │
    ├── About
    │   ├── App Version
    │   ├── Privacy Policy
    │   └── Terms of Service
    │
    └── Sign Out ──► Clear Session ──► Auth Screen
```

## Change Password Flow

```
Change Password Screen
    │
    ▼
Enter Current Password
    │
    ▼
Enter New Password
    │
    ▼
Confirm New Password
    │
    ▼
Validate Requirements
    ├── Min 8 characters
    ├── Uppercase letter
    ├── Lowercase letter
    ├── Number
    └── Special character
    │
    ▼
Update via Supabase
    │
    ├── Failed ──► Show Error
    │
    └── Success ──► Show Success ──► Back to Settings
```

## Achievement System

```
User Action
    │
    ▼
Check Achievement Criteria
    │
    ├── First Quiz ──► "First Steps" Badge
    ├── 10 Quizzes ──► "Quiz Enthusiast" Badge
    ├── 100% Score ──► "Perfect Score" Badge
    ├── 7 Day Streak ──► "Week Warrior" Badge
    └── ... more achievements
    │
    ▼
Unlock Achievement
    │
    ▼
Show Notification
    │
    ▼
Save to Progress
```

## Screen Navigation Map

```
                         ┌─────────────┐
                         │   Splash    │
                         └──────┬──────┘
                                │
              ┌─────────────────┼─────────────────┐
              ▼                 ▼                 ▼
       ┌────────────┐    ┌────────────┐    ┌────────────┐
       │ Onboarding │───►│    Auth    │───►│    Home    │
       └────────────┘    └─────┬──────┘    └─────┬──────┘
                               │                 │
                               ▼           ┌─────┼─────┬─────────┬──────────┐
                        ┌────────────┐     │     │     │         │          │
                        │   Email    │     ▼     ▼     ▼         ▼          ▼
                        │   Verify   │  ┌─────┐┌─────┐┌─────┐┌────────┐┌────────┐
                        └────────────┘  │Quiz ││Flash││Daily││Achieve-││Settings│
                                        │     ││cards││Chall││ments   ││        │
                                        └──┬──┘└─────┘└─────┘└────────┘└───┬────┘
                                           │                               │
                                           ▼                               ▼
                                     ┌──────────┐                   ┌──────────┐
                                     │ Results  │                   │ Change   │
                                     │          │                   │ Password │
                                     └──────────┘                   └──────────┘
```
