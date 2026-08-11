# CrimiReview — Change Log

This file is a complete, chronological record of every change made to this system since Claude began working on it, in plain language: what was found, what was changed, and why. It exists so you (and your panel, if it comes up) can trace any behavior in the app back to a reason, not just a commit.

Entries are grouped by working session. Within a session, changes are listed in the order they happened.

---

## 2026-08-06 — Session 1: Building the Admin Panel

**Starting point:** the codebase already had substantial backend groundwork sitting uncommitted — `supabase_schema_v2.sql` (question bank, admin role, Bayesian Knowledge Tracing tables), `QuestionRepository`, `MasteryService`, `QuestionSelectionService`, `ExplanationService`, and the `Question`/`AnswerFeedback`/`TopicMastery` models — but no Flutter UI to use any of it, and the whole app failed to compile.

- Fixed a pre-existing compile-breaking bug unrelated to the admin panel: two leftover methods in `adaptive_learning_service.dart` referenced a hardcoded question file (`QuestionsDatabase`) that had already been deleted mid-migration by earlier work, and an undefined `_random` field. Replaced both with one async method (`getQuestionsForSegment`) that goes through `QuestionSelectionService` instead. Updated `subjects_screen.dart`'s difficulty-selection flow to match (made it async, added a loading overlay, fixed a BuildContext-across-async-gap risk by routing navigation through the screen's own context instead of a bottom sheet's transient one).
- Built **`lib/services/admin_service.dart`** — role check (via the `is_admin()` Postgres function, the same one the database's own security rules use), question CRUD, student progress reads, audit log reads.
- Built **`lib/screens/admin/`**: `admin_dashboard_screen.dart` (stats), `admin_questions_screen.dart` (search/filter/edit/delete), `admin_question_editor_screen.dart` (create/edit form with a rationale field per answer option), `admin_students_screen.dart` (read-only mastery monitor).
- Wired the entry point: an "Admin Panel" tile in Settings → Account, shown only when `AdminService.isAdmin` is true.
- Registered `AdminService.instance.init()` in `main.dart` startup.
- Verified with `flutter analyze` (0 errors) and by actually launching the app (`flutter run -d windows`) and taking a real screenshot of it running.

## 2026-08-06 — Session 2: Signup was failing

You reported "Failed to verify code" / "Failed to create account" errors. Traced the real code path (`auth_screen.dart`, `email_verification_service.dart`) rather than guessing. Diagnosed that the configured Supabase project (`wbhobbehgqlzfborscvx`) wasn't reachable — first misread this as a sandbox network restriction, then corrected that once direct testing from your machine confirmed the project itself was the issue (a paused free-tier project, as it turned out once inspected further in Session 4).

## 2026-08-06 — Session 3: Full project inspection (you asked "inspect everything")

- **Dead code found:** `lib/data/question_bank.dart` (968 lines) — nothing imported it.
- **Incomplete migration found:** `daily_challenge_screen.dart` and `flashcard_screen.dart` were still reading from the old hardcoded `lib/data/questions_database.dart` (6,045 lines), bypassing the database entirely — meaning admin edits to a question wouldn't show up in Daily Challenge or Flashcards.
- **Security hole found:** `email_verifications` and `password_resets` tables had RLS policies of `USING (true)` for `SELECT` — meaning anyone with the app's public anon key could read every pending verification/reset code for every account. Real account-takeover path: request a reset for someone else's email, read their code straight from the table.
- **Hardcoded secret found:** the Resend email API key was a literal string in `lib/services/email_verification_service.dart` — extractable from the compiled app.
- **Documentation drift found:** `README.md` referenced only the original two SQL files and didn't mention `supabase_schema_v2.sql`, the admin panel, or the new architecture at all.
- Reported all of this, ranked by severity, without changing anything yet.

## 2026-08-06 — Session 4: Fixing what Session 3 found

- Wrote **`supabase_security_fixes.sql`**: moved verification-code generation, comparison, and the actual email send entirely server-side into Postgres `SECURITY DEFINER` functions (`request_verification_code`, `confirm_verification_code`, `request_password_reset`, `confirm_password_reset_code`). The client never sees a stored code again. Locked `email_verifications` and `password_resets` down to zero direct client access — only those functions may touch them now. The Resend API key moves into Supabase Vault (encrypted secret storage), never into Dart source.
- Rewrote **`lib/services/email_verification_service.dart`** from ~480 lines (direct DB reads + direct Resend calls with a hardcoded key) down to ~110 lines of thin wrappers around the new server-side functions.
- Migrated **`daily_challenge_screen.dart`** and **`flashcard_screen.dart`** off the hardcoded file onto `QuestionRepository` (Supabase-backed). Added proper loading/empty states since a live database can legitimately return nothing, unlike a compiled-in file.
- **Deleted** `lib/data/question_bank.dart` and `lib/data/questions_database.dart` — 7,013 lines of hardcoded content removed. There is no question content anywhere in the Dart source anymore.
- Rewrote **`README.md`**: current architecture, correct SQL run order (now 5 files), the admin panel, a security-notes section.
- Verified with `flutter analyze` (0 errors).

*(Note: this session designed the fix but could not run the SQL files yet — that required direct database access, which came in Session 6.)*

## 2026-08-06 — Session 5: Flashcards as its own tab

- Built **`lib/screens/flashcards_home_screen.dart`** — a subject picker, the same role `SubjectsScreen` plays for the Quiz tab.
- Wired it into `home_screen.dart`'s bottom navigation as a 5th tab ("Cards"), between Quiz and Progress.

## 2026-08-06 — Session 6: Getting the database itself up to date

You gave direct Postgres access so the SQL files sitting in the repo could actually be applied (they never had been — everything up to this point was designed but unexecuted).

- Worked through several connection issues in order: a connection string for the wrong Supabase project; the "direct connection" hostname resolving to IPv6-only (unreachable from this environment, fixed by switching to Supabase's connection *pooler*, which is IPv4); a freshly-reset database password needing a short propagation delay before it worked.
- Ran **`supabase_security_fixes.sql`** and **`supabase_schema_v2.sql`** against the live database for the first time — both had existed only as files until this point.
- Found and fixed a **live schema mismatch**: the `questions` table already existed from an earlier, separate draft, with a legacy `subject` column marked `NOT NULL` that nothing in the current app ever writes to (the app uses `subject_id`). This blocked every insert, including the question seed file. Confirmed the table was empty, then dropped the column (required your explicit permission — schema-altering commands are gated behind a safety check in this environment, and I stopped and asked rather than routing around it).
- Promoted your account (`hongoyarwinkile004@gmail.com`) to `role = 'admin'`.
- Diagnosed the "Failed to send email" error down to its exact cause: the Resend API key had never actually been stored in Vault (confirmed by querying `vault.decrypted_secrets` directly — zero rows). You rotated your Resend key; stored the new one in Vault directly through the database connection.
- Verified the entire signup path end-to-end for real — called `request_verification_code` against your real email and confirmed Resend actually sent it.
- Ran **`supabase_seed_questions.sql`** (759 questions) — hit the same legacy `subject`-column issue, which was already fixed by that point, then re-ran successfully. Verified: 759 rows, all active, spread across all 6 subjects, readable through the app's own anon-key path (not just as the database owner).

## 2026-08-06 — Session 7: Letting admins manage other admins

You asked how to restrict admin access to specific people — the mechanism already existed (the `role` column + `is_admin()` + the `protect_user_role` trigger blocking self-promotion), but the only way to grant it was raw SQL.

- Wrote **`supabase_admin_management.sql`**: new `admin_set_user_role(email, role)` function — admin-gated (checked twice, independently: by the function itself and by the pre-existing trigger), blocks an admin from demoting their own account by accident, logs every promote/demote to the audit log. Applied directly to the database.
- Added `AdminService.setUserRole()`.
- Added a "⋮" menu to each row in `AdminStudentsScreen` — "Make admin" / "Remove admin access," with a confirmation dialog.

## 2026-08-06 — Session 8: Separating the admin and student experiences

You pointed out that being an admin didn't actually change the app experience — an admin still landed on the same student Home/Quiz/Cards/Progress tabs, with the Admin Panel buried inside Settings.

- Built **`lib/screens/admin/admin_shell_screen.dart`** — a root screen for admin accounts, parallel to `HomeScreen` but for admins: its own bottom nav (Dashboard / Questions / Students), no student-facing tabs at all. Includes "View as Student" (pushes the normal student app on top; back returns here) and Sign Out.
- Modified `AdminDashboardScreen`, `AdminQuestionsScreen`, `AdminStudentsScreen` to work both as a tab root (no back button) and pushed on top of something else (the original Settings → Admin Panel path still works, e.g. from inside "View as Student").
- Updated **`splash_screen.dart`** (cold app start) and **`auth_screen.dart`** (right after sign-in) to route an admin account to `AdminShellScreen` instead of `HomeScreen`. The `auth_screen.dart` path explicitly re-checks the role right before deciding, rather than trusting a background listener's timing, to close a small but real race condition.
- Verified with `flutter analyze` (0 errors, same pre-existing lint count as before).

---

## 2026-08-07 — Session 9: The adaptive learning system had never actually run

You asked me to inspect the app specifically against two of your panel's points: that the adaptive learning must be accurate, and that the app must explain why an answer is wrong. This inspection found the single most serious functional gap in the whole project.

**What was found, with proof, not assumption:**

- `MasteryService.recordAttempt()` — the *only* place in the codebase that updates the Bayesian Knowledge Tracing model — was never called by any screen. Confirmed against the live database: `topic_mastery` and `question_attempts` had **zero rows**, despite `quiz_results` showing **45 real completed quizzes**. The BKT model, the citable basis your panel asked for, had never received a single piece of evidence.
- What was actually deciding quiz difficulty instead: a plain hardcoded rule in `adaptive_learning_service.dart` (`_adjustTopicDifficulty`) — 4-of-last-5-correct levels up, 1-or-fewer-of-5 levels down. This is the exact kind of ungrounded ladder the BKT system's own code comments claimed had already been replaced. It hadn't been; it was the only thing actually running.
- `QuestionSelectionService.markServed()` — which records that a question was shown to a student, the mechanism behind "repeat the topic but not the same question" — was also never called. Confirmed: `question_exposure` had zero rows too.
- `quiz_screen.dart` (the screen used for the main Subjects → Quiz practice flow) still had the exact bug `ExplanationService` was built to fix: the explanation text was wrapped in `if (isCorrect) [...]`, so a wrong answer showed only "Not quite!" and nothing else. `ExplanationService` existed, worked correctly in isolation, and was never called from this file.

**What was fixed:**

- `lib/screens/quiz_screen.dart`: on every answered question, now calls `MasteryService.instance.recordAttempt(...)` (updates the BKT model for that topic — this is what makes `topic_mastery` and `question_attempts` start populating), and `ExplanationService.instance.build(...)` to construct the feedback shown to the student. The explanation card no longer gates its reason behind `if (isCorrect)` — a wrong answer now always shows the specific reason that option is wrong, plus (when the question has one) its legal citation, plus the topic's mastery percentage and how much it just moved. Also added `QuestionSelectionService.instance.markServed(widget.questions)` when the quiz set is first shown, so the exposure ledger finally records what a student has seen.
- Had to track the shuffle permutation itself (`_shuffledIndexMap`), not just the shuffled display order, because `ExplanationService` and `MasteryService` both need the option's *original* index (matching how it's stored), and that mapping didn't exist anywhere before.
- `lib/main.dart`: added startup initialization for `MasteryService` and `QuestionSelectionService`, so both are warm before the first question renders instead of paying their (fast, local) setup cost inline on the first answer.
- Verified with `flutter analyze` (0 errors) and a careful manual trace of the logic (confirmed the shuffled-index math and the mastery-before/after sequencing are both race-free).
- **Live-verified, not just reasoned about.** Baseline captured immediately before the fix: `topic_mastery: 0, question_attempts: 0, question_exposure: 0`. Your first live test after the fix reused an old build (still showed the pre-fix "Not quite!" with nothing after it) — confirmed by the exact wording (the old hardcoded string has an exclamation mark; the new code's `AnswerFeedback.headline` doesn't) and by the database still reading 0/0/0 after your test. Rebuilt fresh (`flutter run -d windows`) and drove it through a real quiz question myself: the explanation card showed a full, specific reason plus a legal-basis line for a wrong answer — impossible under the old code, which had no body text at all on that branch. Confirmed against the database immediately after:
  - `topic_mastery`: 0 → 3 rows, `question_attempts`: 0 → 3 rows, `question_exposure`: 0 → 10 rows (the whole 10-question set marked served in one call, as designed).
  - The actual BKT numbers behave exactly as the model should: a correct answer moved p(known) from the 0.20 prior to 0.583 (a big jump for first evidence, matching the algorithm's documented worked example); a wrong answer still ticked up slightly, 0.200 → 0.221, because the model treats seeing the explanation as partial learning even on a miss (the "transit" term) rather than moving nothing at all.
- Created this file.

## 2026-08-07 — Session 10: Strict admin/student separation, no crossover at all

Session 8 gave admin accounts their own shell but still let them step into the student app on purpose via a "View as Student" button. You asked for full separation instead — admin login only ever reaches the admin dashboard, student login only ever reaches the student dashboard, no exceptions — matching a diagram you sent showing the two paths never crossing (with the one intentional link being that an admin's edits still reach students *through the database*, not through navigation).

- **`lib/screens/admin/admin_shell_screen.dart`**: removed the "View as Student" button, its handler, and the now-unused `home_screen.dart` import. An admin session can no longer reach `HomeScreen`/Quiz/Cards/Progress under any circumstance.
- **`lib/screens/settings_screen.dart`**: removed the conditional "Admin Panel" tile and all its supporting state (`_isAdmin`, the `AdminService` listener wiring) — this tile could only ever have been reached via "View as Student," so once that path was gone, the tile was permanently dead code. Removed rather than left behind, so the code doesn't imply a crossover that no longer exists.
- Confirmed granting admin access to *other* people was already fully built (Session 7): Admin Panel → Students → "⋮" → "Make admin," no SQL needed.
- Verified with `flutter analyze` (0 errors, project-wide).

**Net result:** the two roles now share exactly one thing — the database (`public.questions`, written by admins, read by students via `QuestionRepository`) — and nothing else. No shared screens, no shared navigation, no toggle between them from either side.

---

## 2026-08-09 — Session 11: Chapter 3 diagrams (System Framework, Use Case, Activity) — no app code touched

You were in a long OJT meeting and asked for the System Framework, Use Case Diagram, and Activity Diagram due for capstone class, in proper Philippine capstone thesis format, while you couldn't attend.

- Re-derived the actual actor/use-case/process picture from the live codebase rather than guessing: `main.dart` startup sequence, every screen under `lib/screens/` and `lib/screens/admin/`, `lib/models/question.dart`, `lib/models/mastery.dart`, `lib/models/subject.dart` (confirmed the six real 2026 PRC board-exam subjects and their real weights), and the exact Supabase RPC names in `admin_service.dart` (`is_admin`, `admin_set_user_role`, `log_admin_action`).
- Ran a 4-agent review workflow: three parallel reviewers (technical accuracy against the codebase, UML notation correctness, Philippine capstone formatting convention) drafted and corrected each figure independently, then a fourth agent cross-checked all three for consistent terminology. It caught a real sequencing bug (a draft had "mark question set as served" happening *before* the quiz was answered, contradicting the verified `markServed()` call order), an unsupported claim (an on-screen "mastery-percentage delta" that isn't actually confirmed in the UI), and six actor/term naming mismatches across the three figures (e.g. "Admin" vs. "administrator," "CrimiReview Application" vs. "CrimiReview System," "generates" vs. "compiles" for `ExplanationService.build()`, which only assembles pre-authored rationale text rather than generating new content).
- Deliberately preserved, rather than "fixed," two known real gaps in both diagrams: Daily Challenge is not connected to Record Answer & Update Mastery (it doesn't call `MasteryService.recordAttempt()`), and the closed adaptive feedback loop in the System Framework is scoped to Quiz mode only — both stated in-diagram so they hold up under panel questioning instead of looking like an oversight.
- Published an interactive artifact (`docs/chapter3_system_design.md` is the Word-paste-friendly twin) containing all three figures as hand-authored inline SVG (an IPO box-and-feedback-loop diagram; a 27-use-case UML diagram grouped into shaded thematic regions with correct `<<include>>`/`<<extend>>` semantics; a two-swimlane UML activity diagram for the adaptive quiz-taking flow), full academic narrative for each, and five detailed Use Case Description tables (Sign Up, Take Quiz, Track Progress/Mastery, Manage Questions, Manage Admin Roles).
- No Dart/SQL files were modified this session — this was documentation/diagramming work only, added under `docs/`.
- **Rebuilt after you shared your actual instructor's guide** (Buenavista Community College Research Development Center template, sections 4.3–4.6): the first pass had used generic textbook formats (IPO box diagram, boundary-framed UML use case diagram, Actor(s)/Description/Preconditions/Postconditions table) that didn't match what was actually required. Redid all three to the real spec: System Framework as a hub-and-spoke icon diagram (CrimiReview App at center; Student, Admin, Adaptive Learning/BKT, Database, Connectivity, Question Bank, Progress Reports, Notifications around it) with no boundary frame; Use Case Diagram with no boundary frame and the guide's two-column actor-fanout layout; a new "4.5 Use Case Narrative" section replacing the old table format, using the instructor's exact fields (Use Case Name, Primary Actor, Goal on Context, Trigger, Pre-Condition, Flow of Events as paired Actor Action/System Response, Exception, Post-Condition), horizontal rules only; Activity Diagram kept in a bordered lane-table matching the guide's "Log In" example style. Same underlying facts, verified codebase grounding, and honestly-documented limitations carried over unchanged — only the presentation format changed.

## 2026-08-11 — Session 12: Automatic Item Generation from an uploaded PDF (LLM path)

You asked for a feature where an admin/instructor uploads a document or PDF and the system generates questions and quizzes from it automatically — a second, LLM-driven path alongside the slot-filling `question_templates`/`concept_bank` Automatic Item Generation design already scaffolded (but never implemented) in `supabase_schema_v2.sql` SECTION 5/6.

- Discovered the review workflow this needed mostly already existed: `AdminService.setActive()` (the existing soft delete/restore toggle) is now literally the "approve" action for a generated question, `deleteQuestionPermanently()` is "reject," and `AdminQuestionEditorScreen` already lets an admin fix content before approving. No separate review screen was built — generated items just insert as `is_active = false`, the same flag every other deactivated question already uses.
- Built **`supabase_document_generation.sql`**: `public.document_uploads` table (tracks each upload through pending → processing → completed/failed, admin-only RLS via the existing `is_admin()`), and a private `document-uploads` Storage bucket (PDF-only, 32MB cap, admin-only policies).
- Built **`supabase/functions/generate-questions-from-document/index.ts`** (new Supabase Edge Function, Deno): downloads the PDF from Storage, sends it to Claude as a native PDF document block with a JSON-schema-constrained structured-output request (so the response comes back already shaped like a `questions` row — no text-parsing), and inserts each generated item with `source: 'generated'`, `template_id: <upload id>`, `is_active: false`. Never leaves an upload stuck at "processing" — any failure (bad PDF, API error, refusal) resolves the row to `status: 'failed'` with a message. Duplicate/malformed items are skipped individually rather than failing the whole batch, because `public.questions` already has a `(subject_id, stem)` uniqueness guard from the original schema.
- Built **`lib/services/document_generation_service.dart`**: file-picker → Storage upload → `document_uploads` row → fire-and-forget Edge Function invoke (per your "upload and check back later" preference, not a blocking wait), plus `watchUploads()` on Supabase Realtime so the admin's queue list updates live with no manual polling.
- Built **`lib/screens/admin/admin_document_generation_screen.dart`**: subject/topic/difficulty/count form, "Choose PDF & Generate," and a live upload history list with status badges and a "Review N questions" button once a batch completes.
- Extended `AdminService.listQuestions()` and `AdminQuestionsScreen` with `source`/`templateId` filters (plus a "Generated only" filter chip) instead of writing a new review screen — "Review N questions" just opens the existing question list pre-filtered to that one upload's batch. The "generated" badge on each question card already existed (`q.source != QuestionSource.admin`) from before this session.
- Added `file_picker` to `pubspec.yaml`; ran `flutter pub get` (resolved cleanly) and `flutter analyze` (0 new errors/warnings — the only pre-existing lint hits are unrelated files untouched this session).
- **Deliberately scoped to PDF only.** Claude reads PDFs natively; a `.docx` would need a text-extraction step first — flagged as a fast-follow, not built.
- **Deliberately did not auto-publish.** Per your answer, every generated item requires admin review before a student can see it — there is no code path that flips `is_active` to `true` except the admin's own approve action.

---

## Known gaps — not fixed yet, worth knowing about

- **Session 12's Edge Function is not deployed yet** — I wrote the code, but only you can run `supabase functions deploy generate-questions-from-document`, set the `ANTHROPIC_API_KEY` secret, and run `supabase_document_generation.sql` in the SQL Editor. Until all three are done, "Generate from Document" will accept an upload but the row will sit at `pending`/`processing` forever.
- **Document generation is PDF-only.** A `.docx` upload isn't handled — the file picker restricts to `.pdf`.

- **Daily Challenge** shows an explanation either way (better than the old Quiz screen was), but still uses the plain overall `explanation` field, not the richer per-option "why THIS specific wrong choice fails" rationale, and does not call `MasteryService.recordAttempt()`. Only the main Quiz flow does, as of Session 9.
- **The quiz Results screen** has no per-question answer review at all (Daily Challenge's own separate results screen does have one). A student who wants to see *why* they missed something after finishing has to remember it from the quiz itself.
- **Supabase Authentication → "Confirm email" setting** — the app's own custom code-verification flow assumes this dashboard toggle is off. This was flagged early on but never independently re-verified after the security fixes; worth a quick check in the dashboard if login-right-after-signup ever behaves oddly.

## Files this project gained that didn't exist before Session 1

`lib/services/admin_service.dart`, `lib/screens/admin/` (now 7 files as of Session 12), `lib/screens/flashcards_home_screen.dart`, `supabase_security_fixes.sql`, `supabase_admin_management.sql`, `supabase_document_generation.sql` (Session 12), `supabase/functions/generate-questions-from-document/` (Session 12), `lib/services/document_generation_service.dart` (Session 12), this file. (`supabase_schema_v2.sql`, `question_repository.dart`, `mastery_service.dart`, `question_selection_service.dart`, `explanation_service.dart`, and the `Question`/`AnswerFeedback`/`TopicMastery` models already existed, unused, before Session 1 — see that section for what "unused" meant in practice.)

## Files this project lost

`lib/data/question_bank.dart`, `lib/data/questions_database.dart` — 7,013 lines of hardcoded quiz content, deleted in Session 4 once nothing referenced them anymore.
