# CrimiReview

Criminology Board Exam Review App built with Flutter.

## Setup on New Laptop (Windows)

### 1. Install Flutter SDK

```bash
# Download Flutter SDK
https://docs.flutter.dev/get-started/install/windows

# Extract to C:\flutter

# Add to System PATH:
C:\flutter\bin
```

### 2. Install Android SDK (Command Line Only)

```bash
# Download Command Line Tools from:
https://developer.android.com/studio#command-line-tools-only

# Extract to C:\Android\cmdline-tools\latest

# Add to System PATH:
C:\Android\cmdline-tools\latest\bin
C:\Android\platform-tools

# Install required SDK components:
sdkmanager "platform-tools" "platforms;android-34" "build-tools;34.0.0"

# Accept licenses:
flutter doctor --android-licenses
```

### 3. Set Environment Variables

```bash
# Add these to System Environment Variables:
ANDROID_HOME = C:\Android
ANDROID_SDK_ROOT = C:\Android
```

### 4. Verify Setup

```bash
flutter doctor
```

All checks should pass.

### 5. Get Dependencies

```bash
cd crimireview
flutter pub get
```

### 6. Run App

```bash
# Connect Android device via USB (enable USB debugging)
flutter run

# Or run in release mode
flutter run --release
```

### 7. Build APK

```bash
flutter build apk --release
```

APK output: `build/app/outputs/flutter-apk/app-release.apk`

## Project Structure

```
lib/
├── main.dart              # App entry point
├── data/                  # Question database
├── models/                # Data models
├── screens/               # UI screens
├── services/              # Business logic
├── utils/                 # Utilities
└── widgets/               # Reusable widgets
```

## Supabase Setup

Project URL: `https://wbhobbehgqlzfborscvx.supabase.co`

Tables required:
- user_profiles
- quiz_results
- user_progress
- daily_challenge_scores
- user_achievements

See `supabase/schema.sql` for full schema.

## Build Commands

```bash
# Debug APK
flutter build apk --debug

# Release APK
flutter build apk --release

# App Bundle (for Play Store)
flutter build appbundle --release

# Clean build
flutter clean && flutter pub get && flutter build apk --release
```
