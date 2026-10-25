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

## 2026-08-24 — Session 12: Manuscript revision patches for Chapters 1–3 — no app code touched

You shared the actual submitted manuscript PDF (`crimiReview-Edited-6-3-2026-1.pdf`, Chapters 1–3) and asked for it to be enhanced with what's actually changed in the system, without breaking its existing structure/format.

- Compared the manuscript's Chapter 1 (Introduction), Chapter 2 (Literature Review), and Chapter 3 (Technical Background) against the current codebase and found the Admin Panel — question bank management with per-choice rationale/legal-citation fields, read-only student mastery monitoring, role promotion/demotion, and server-side audit logging — is not mentioned anywhere in the manuscript at all, despite being a substantial, real part of the system.
- Found and flagged (did not silently fix) a real contradiction: Chapter 1's Scope bullet ("displays only the final quiz score... without revealing the correct answers during the session") contradicts both the actual `quiz_screen.dart` behavior (an explanation is shown after every question, not withheld) and the manuscript's own Chapter 2 claim that the system lets students "reflect on incorrect answers." Proposed a replacement bullet but left the decision to you, since it's a promise made to the panel.
- Drafted surgical, quote-and-replace patches (not a rewrite) for: Project Context's capability list, Objective 2's feature bullets, the Purpose and Description capability list (new "Administrative Content Management" bullet; enhanced "Adaptive Learning" bullet to name Bayesian Knowledge Tracing, citing Corbett & Anderson 1995 — the same reference the codebase's own `MasteryService`/`TopicMastery` comments already cite internally), the Scope's subjects bullet (named the six real 2026 PRC board-exam subjects instead of "selected major subjects"), Chapter 2's Adaptive Learning Theory paragraph (one sentence tying the theory to the BKT implementation), and Chapter 3's Supabase and Faculty Members/Instructors entries (server-side security architecture; the Admin Panel's read-only scope).
- Published both `docs/manuscript_revisions_ch1-3.md` (this file, copy-paste-friendly) and a companion artifact rendering the same patches as original/proposed diff cards.
- Explicitly listed what was left unchanged and why (10-questions-per-session, Android-only scope, the "admins can't directly edit scores" limitation, the "no advanced AI/ML" disclaimer — all already accurate) so nothing gets touched without a reason.
- No Dart/SQL files were modified this session — manuscript-text patches only.

---

## 2026-08-24 — Session 13: Full Chapters 1–3 rebuild with verified Chapter 2 literature — no app code touched

Follow-up to Session 12: you asked for a complete integrated document (not a patch list) and specifically for Chapter 2's theoretical framework to be rebuilt on real, verifiable local and foreign literature rather than left as-is.

- Independently web-searched and checked all 9 existing references. Found 7 were real but cited with wrong venue names/years/details (e.g. Albina et al. was attributed to the wrong journal; Mayne & Green's year and venue were both wrong). Found reference [4] ("Gerard, M., et al. (2022)... *European Journal of Criminology Education*") could not be located anywhere and that journal does not appear to exist — flagged as likely fabricated/duplicated from reference [2], and replaced with a genuinely different, verified 2022 paper (Gehring & Marshall, "Ready Player One: Gamification of a Criminal Justice Course," *Journal of Criminal Justice Education*).
- Found and verified 8 new sources: foundational citations for all three theories the manuscript claims (Corbett & Anderson 1995 for Bayesian Knowledge Tracing — the exact paper the codebase's own comments already reference; Deterding et al. 2011, the canonical gamification definition; Vygotsky 1978 and Piaget 1970 for constructivism, neither of which the original draft cited despite naming the theory), plus two recent foreign adaptive-learning sources and two local Philippine sources (a 2024 Philippine study on AI-personalized learning outcomes; a 2021 Philippine mobile-reviewer-app study for the PhilNITS certification exam — the closest local precedent found for CrimiReview's own product category).
- Explicitly noted where verification failed rather than filling the gap: one existing in-text citation ("Prado") could not be traced to a real source, and no published local academic study specifically about a mobile app for Criminologist Licensure Examination review could be found (only commercial Play Store apps exist) — both are called out inline rather than silently resolved.
- Reorganized Chapter 2 into Theoretical Framework / Foreign Literature / Local Literature / Synthesis subsections (standard Philippine RRL convention), reusing your original sentences wherever unchanged.
- Rebuilt Chapters 1 and 3 as a single integrated document (not separate patches) folding in Session 12's Admin Panel, BKT-naming, six-subjects, and security-architecture additions, plus the previously-flagged Scope correction (applied since it wasn't reverted).
- Published `docs/manuscript_ch1-3_full_revised.md` (plain-text, Word-paste-ready) and a companion artifact with new/changed text visually highlighted against the original.
- No Dart/SQL files were modified this session — manuscript-text work only.

---

## 2026-08-24 — Session 14: Removed references that didn't reflect the actual app, replaced with better-matched real ones

Follow-up to Session 13: you asked to remove any reference that doesn't actually belong/reflect the system, not just ones that fail to verify.

- Re-examined every Chapter 2 reference for fit, not just for existence. Found three real, verifiable papers ([2] CrimOPS, [5] Mayne & Green, [6] Espenocilla) all describe **VR/3D simulation tools for practicing crime-scene investigation** — a fundamentally different kind of system from CrimiReview, which is a gamified quiz/review app with no simulation or VR component. Citing them argued for the wrong kind of system, even though they were individually real.
- Searched for and verified direct replacements that actually match CrimiReview's mechanism: Zainuddin et al. (2020, *Computers & Education*) on gamified e-quizzes as formative assessment (the closest foreign match to CrimiReview's actual quiz feature); James, Oates & Schonfeldt (2025, *Accounting Education*) on a standalone gamified mobile app's effect on retention/engagement (matches CrimiReview's product category directly); Duterte (2024, *IJRISS*) — a Philippine quasi-experimental study using the exact points/badges/leaderboard combination CrimiReview implements, with 133 undergraduates across three Manila universities.
- Removed the "Prado" citation from the running text outright (previously left in with a "could not verify" flag) — two rounds of searching turned up nothing real, so it no longer sits in the document unresolved.
- Updated the Foreign Literature, Local Literature, and Synthesis paragraphs to match the new citations' actual findings rather than just swapping citation numbers.
- Updated both `docs/manuscript_ch1-3_full_revised.md` and the companion artifact.
- No Dart/SQL files were modified this session.

---

## 2026-08-24 — Session 15: Chapter 2 restructured with per-reference Synthesis statements

Follow-up to Session 14: you shared your actual final manuscript (with all prior revisions already integrated) and asked for the Foreign/Local Literature sections to carry a synthesis statement immediately after each theory and each cited work, instead of one combined Synthesis section at the end of the chapter.

- Split every theory paragraph (Adaptive Learning, Constructivist, Gamification) and every one of the 13 non-theory citations into two parts: a description of the source, then a clearly labeled **Synthesis.** sentence tying it explicitly to CrimiReview — matching the Philippine RRL convention of a synthesis per cited work rather than one closing paragraph.
- Replaced the single end-of-chapter "Synthesis" section with a much shorter, unlabeled "Chapter Summary" so the word "Synthesis" isn't overloaded — every individual synthesis now does that job in place.
- No content or citations were added or removed this round — same 17 references, same claims, just recut into the requested structure.
- Updated both `docs/manuscript_ch1-3_full_revised.md` and the companion artifact.
- No Dart/SQL files were modified this session.

---

## 2026-08-24 — Session 16: Shortened Chapter 1's Project Context

You said the Introduction was too long. Condensed "Project Context" from six paragraphs down to two, keeping every required beat: the broader mobile/adaptive-learning context, the cited problem (Albina et al. [1]) and the gap in existing tools, and the proposed CrimiReview solution with its core capabilities (BKT-driven adaptive quizzing, gamification, offline sync, the Admin Panel) and stated purpose. Objectives of the Study, Purpose and Description, and Scope and Limitations were left untouched, since those are structured requirement lists a panel expects to see in full rather than narrative to trim. Updated both `docs/manuscript_ch1-3_full_revised.md` and the companion artifact. No Dart/SQL files were modified this session.

---

## 2026-08-24 — Session 17: Chapter 2 rebuilt to a stricter APA 7 "Body of the Review" guide

You shared your program's formal Body-of-the-Review guideline document — a stricter, more specific spec than the earlier template, requiring APA 7 author-date citations (not the numbered `[N]` style used until now), no subheadings inside the literature body (Theoretical Framework, Legal Bases, and Related Literature/Studies seamlessly integrated as one discussion), an explicit Legal Bases section, SDG alignment, and a Related Literature (books/reports, excluding theses and journal studies) vs. Related Studies (journal articles/theses/empirical research) distinction with a minimum of 4 local + 4 foreign studies published within the last 5 years.

- **Switched the entire manuscript's citation style** from numbered IEEE-style `[N]` to true APA 7 `(Author, Year)`, including fixing Chapter 1's one citation (`Albina et al. [1]` → `Albina et al. (2022)`) so the whole document is internally consistent.
- **Removed all Chapter 2 subheadings** (Theoretical Framework / Foreign Literature / Local Literature / Chapter Summary), rewriting it as one continuous, paragraph-by-paragraph (4–6 sentences each) discussion that moves from theory → legal bases → SDGs → related literature → related studies → conclusion, per the guide.
- **Added Legal Bases — none existed before.** Independently verified three real Philippine legal sources: 1987 Constitution Art. XIV §§1, 5; Republic Act No. 11131 (the actual law establishing the CLE and its 75%-average/no-subject-below-60% passing standard — directly explaining why the app tracks mastery per subject); and Republic Act No. 10173, the Data Privacy Act (relevant since the app processes OTPs and personal quiz records).
- **Added SDG alignment — none existed before.** SDG 4 (Quality Education), SDG 9 (Industry, Innovation and Infrastructure), SDG 10 (Reduced Inequalities, tied directly to the offline-first design and Pacturan et al.'s documented access barriers) — three genuinely defensible alignments, not a padded list.
- **Added a real Related Literature category.** Per the guide's definition (books/reports/policy papers, excluding journal studies and theses), almost everything previously cited was actually "Related Studies." Independently verified and added Kapp (2012), *The Gamification of Learning and Instruction* (Pfeiffer) and UNESCO (2013), *Policy Guidelines for Mobile Learning* — both real, both directly relevant, neither previously cited.
- **Verified the 4-local/4-foreign/within-5-years requirement is met by the Related Studies alone**: 5 foreign (2022–2026) and 6 local (2021–2026) qualifying sources. Zainuddin et al. (2020) is kept in the discussion as the closest mechanism match found but explicitly flagged as falling just outside the window and not counted toward the minimum.
- **Reference list reordered alphabetically** in full APA 7 format; legal sources listed in a separate short list, since they don't fit standard author-alphabetization.
- Flagged two reference entries (Guisadio et al., Moldez et al.) as having only a verified lead author — full co-author lists should be filled in from the user's own source PDFs before finalizing, since APA 7 wants every author listed in the reference (unlike in-text "et al.").
- Updated both `docs/manuscript_ch1-3_full_revised.md` and the companion artifact.
- No Dart/SQL files were modified this session.

---

## 2026-08-27 — Session 18: Finished deploying Session 12's feature, and built a free alternative alongside it

You hit "Bucket not found" trying to use "Generate from Document" — Session 12 had written all the code, but three separate deployment steps had never actually been run against the live project. Fixed all three, then, because the LLM path costs API tokens, built a second, genuinely free generation path next to it rather than in place of it.

**Finishing Session 12's document-generation feature:**
- Diagnosed precisely rather than guessing: confirmed via direct queries that `document_uploads` didn't exist as a table and the `document-uploads` Storage bucket didn't exist either — ran `supabase_document_generation.sql` (had been sitting unexecuted since Session 12) to create both.
- Tested the Edge Function directly and got Supabase's platform-level `{"code":"NOT_FOUND"}` — confirming it had never been deployed, not just misconfigured. Downloaded the Supabase CLI directly (no local install existed; `npx` was too slow, switched to the official Windows release binary) and deployed `generate-questions-from-document` using a Supabase Personal Access Token you provided for this purpose — a broader-scoped credential than the database password (account-wide, not single-project), used only for this one deploy command. Verified after deploying: the function now returns a real application error instead of "not found."
- **Still outstanding, by your own choice, not an oversight:** `ANTHROPIC_API_KEY` is not set as a function secret — checked directly (`supabase secrets list`), only the auto-injected Supabase ones exist. The document-generation path is fully deployed and will work the moment that key is added; nothing else blocks it.

**Building the free alternative — template-based generation:**
- You asked whether question generation could work without paying for an API key at all. It can: `supabase_schema_v2.sql` (Session 1) had already scaffolded a completely separate, non-LLM method — `question_templates` + `concept_bank`, a slot-filling technique (Gierl & Lai) with 4 templates and 21 concepts already seeded — but nothing had ever been built to actually run it.
- Built **`supabase_template_generation.sql`**: one Postgres function, `generate_questions_from_template(template_id, count)` — picks a concept, uses its definition as the correct answer, pulls wrong answers (with individually-written reasons) from sibling concepts in the same legal group, fills in the template's stem, and inserts the result as `source: 'generated', is_active: false` — the identical review gate the LLM path uses. No network call, no API key, entirely inside the database. Also added `template_generation_status`, a view reporting how many concepts still haven't produced a question per template, since each concept can only ever generate one question (the stem is deterministic) — a real, disclosed ceiling of 21 questions total across the 4 seeded topics until someone adds more concepts by hand.
- Applied directly and **smoke-tested for real before building any UI**: generated 3 real questions for "Justifying Circumstances" and inspected the actual row — correct legal citation, all 3 distractors individually justified, exactly one `is_correct: true`. Left them in the database as genuine reviewable content rather than deleting them as test junk.
- Built **`lib/services/question_generation_service.dart`** and **`lib/screens/admin/admin_template_generation_screen.dart`** — one card per template showing "X of Y concepts available," a Generate button, routing into the same `AdminQuestionsScreen` review filter Session 12 already built.
- Wired a second icon next to the existing "Generate from Document" button in `AdminQuestionsScreen`'s app bar — both paths sit side by side; building the free one didn't touch or remove the paid one.
- Verified with `flutter analyze` (0 errors, project-wide).

---

## 2026-08-27 — Session 19: Made the missing Anthropic key self-service instead of something only I could diagnose

You asked me to prepare the document-generation feature so that adding the Anthropic key later is something you can do yourself, without needing me again.

- **`supabase/functions/generate-questions-from-document/index.ts`**: added an explicit, fail-fast check for `ANTHROPIC_API_KEY` right after parsing the request, before any storage/database work is wasted on a request that can't succeed. Previously, a missing key surfaced as the Anthropic SDK's own raw error — *"Could not resolve authentication method. Expected one of apiKey, authToken, credentials, config, or profile..."* — which tells an admin nothing actionable. Now it's a plain-language message with the exact fix and a link to where the steps live, written straight into `document_uploads.error_message`, which the admin app already displays under the "Failed" badge — no logs to dig through.
- Redeployed the function (reusing the same Personal Access Token from Session 18, for this one redeploy only). Verified live against two of your real stuck uploads (the ones sitting at "pending" since before Session 18) rather than a synthetic test — both now correctly resolve to "failed" with the new message, confirmed by reading the actual database rows, not just the API response.
- Added **README.md → "Enabling AI-Generated Questions"**: the exact self-service steps — where to get a key, the two ways to add it (Dashboard, no CLI needed, or one CLI command), and how to redeploy the function itself if it's ever edited again, including an explicit warning that a Supabase Personal Access Token is account-wide and should be handled like a password.
- Also documented `supabase_admin_management.sql`, `supabase_document_generation.sql`, and `supabase_template_generation.sql` in the README's Supabase Setup list — they existed and were required but had never been listed there.
- No Dart files touched this session — Edge Function + SQL/docs only.

---

## 2026-08-30 — Session 20: Automatic Item Generation added to the manuscript, and Chapter 4 (System Design) written

You shared your current submitted manuscript PDF (Chapters 1–3, already reflecting all prior revision sessions) and asked for the Automatic Item Generation feature to be added to it, and for Chapter 4 to be drafted up through the Activity Diagram — carefully, without breaking what was already there.

- Read the actual current manuscript source (`docs/manuscript_ch1-3_full_revised.md`) rather than assuming its state, confirmed it matches the shared PDF, and treated it as the base to extend rather than rewrite from scratch.
- **Wove Automatic Item Generation into Chapters 1–3**: new bullets in Objectives, Purpose and Description (with an inline Gierl & Lai 2012 citation, mirroring how the Adaptive Learning bullet already cites Corbett & Anderson), and Scope; a new Limitations bullet honestly disclosing the document method's connectivity/cost/PDF-only constraints and the template method's concept-bank ceiling; a new Chapter 3 entry (2.8 Anthropic Claude API) and an extension to 3.3 Faculty Members/Instructors.
- **Independently web-verified two new Chapter 2 citations** before adding them, matching the citation-verification standard set in Sessions 13–14: Gierl, M. J., & Lai, H. (2012), "The Role of Item Models in Automatic Item Generation" (*International Journal of Testing*) — the same source your own `supabase_schema_v2.sql`/`supabase_template_generation.sql` comments already name as the template method's theoretical basis, now surfaced in the actual manuscript; and Biancini, Ferrato, & Limongelli (2024), "Multiple-Choice Question Generation Using Large Language Models" (ACM UMAP Adjunct '24) for the document/LLM method — verified across ERIC, ResearchGate, and ACM Digital Library sources rather than taken from memory. No DOI is given for Gierl & Lai since none could be independently confirmed, consistent with this document's standing rule against inventing citation details.
- **Wrote Chapter 4 — System Design**, up through Activity Diagram as requested: built on the previously drafted `docs/chapter3_system_design.md` (System Framework, Use Case Diagram, Use Case Narrative, Activity Diagram — already matched to your Research Development Center guide from Session 11), adding two new sections ahead of it — 4.1 Software Development Methodology and 4.2 Conceptual Framework (an IPO model) — flagged explicitly as inferred rather than confirmed against your program's actual Chapter 4 guide, unlike 4.3–4.6.
- **Extended, not redrew, the existing diagrams**: added a "Generate Questions (Automatic Item Generation)" use case to the Use Case Diagram, connected via «extend» from Manage Questions, plus a new Table 6 narrative — and disclosed a real asymmetry rather than glossing over it: the template method calls `log_admin_action` immediately (verified in the SQL), the document method's audit trail is only created later, at admin approval, so the diagram does not draw a matching «include» arrow to Log Admin Action for it. The System Framework's node set was deliberately left unchanged (no new spoke) to avoid altering an already-reviewed figure; only its supplementary Question Bank description was extended. The Activity Diagram (Adaptive Quiz-Taking) was left untouched, since generation is an admin-authoring activity, not part of the student quiz-taking flow it depicts.
- Figures renumbered to fit the new Conceptual Framework figure ahead of System Framework (System Framework Figure 1→2, Use Case Diagram 2→3, Activity Diagram 3→4); section numbers 4.3–4.6 unchanged.
- Published `docs/manuscript_ch1-4_full_revised.md` — supersedes `manuscript_ch1-3_full_revised.md` as the current full draft; older draft files left in place, not deleted. Updated the companion artifact ("Chapters 1–3, Revised Draft" → "Chapters 1–4, Revised Draft", same link) to match, reusing the actual existing SVG diagram code read directly from the published artifact rather than redrawn from scratch, and adding a new IPO figure and the extended Use Case Diagram.
- No Dart/SQL files were modified this session — manuscript-text and diagram work only.

---

## 2026-08-31 — Session 21: Chapter 4 corrected against a real library example

Follow-up to Session 20: you shared photos of a prior manuscript's Chapter 4 held at your program's own library (Buenavista Community College Library, accession-stamped) — a "THIS CHAPTER SHALL" outline slide and five sample Activity Diagram pages — and asked for Chapter 4 to be rebuilt precisely against it, with a step-by-step manual-process account and an Activity Diagram section matching the library example's style.

- **Corrected 4.1/4.2**: Session 20's guess ("Software Development Methodology" and an IPO "Conceptual Framework") is wrong per the real outline, which opens with **Requirement Analysis** and **Requirement Documentation**. Rebuilt 4.1 to open with a step-by-step description of the existing manual review process (printed reviewers, no mastery tracking, answers checked only at the end, no centralized updates, no resumable progress) as the explicit source for 11 functional and 6 non-functional requirements — two of them (FR-08, FR-09) are the Automatic Item Generation capability. 4.2 documents these in a traceable ID/requirement/source/priority table.
- **Rebuilt 4.6 Activity Diagram as four small, per-feature diagrams** — Log In, Take Quiz, Manage Questions, and a new dedicated Generate Questions diagram — replacing the single large diagram from Session 20. Matched the library example's actual visual convention: plain white rounded activity boxes, maroon/seal-colored connector arrows, simple sentence-style labels ("The Admin will...", "The System will..."), one figure per major screen, rather than one dense diagram with heavy color fills. This is also the first time Automatic Item Generation gets its own diagram, not just a Use Case Narrative table.
- Figures renumbered again: System Framework is Figure 1, Use Case Diagram Figure 2, and the four Activity Diagrams are Figures 3–6.
- Updated both `docs/manuscript_ch1-4_full_revised.md` and the companion artifact (same link as Session 20 — "Chapters 1–4, Revised Draft").
- No Dart/SQL files were modified this session — manuscript-text and diagram work only.

---

## 2026-09-01 — Session 22: Chapter 4 rebuilt against the official Capstone Project Manual

Follow-up to Session 21: you shared your program's actual Capstone Project Manual in full (Buenavista Community College Research Development Center, prepared by Christian D. Padilla, MAEd) and asked for Chapter 4 to be built precisely against it, stopping at Activity Diagram since your instructor hasn't covered the sections after that yet.

- **Corrected 4.1 Requirement Analysis**: the manual's own worked example ("Rice Variety Recommendation Procedure") shows this section built around a figure of the *existing manual process*, not a bare requirements list. Rebuilt 4.1 around a new Figure 1 — an icon flowchart of the manual review process a criminology student follows today (gather printed reviewers → study independently → check answers only at the end → cross-reference weak topics → materials stay outdated → track progress by memory) — with the functional/non-functional requirements kept as a clearly-marked supplementary addition below it, since the manual's example doesn't show that list format itself.
- **Corrected 4.2 Requirement Documentation**: replaced an earlier requirements-traceability table (FR-IDs, sources, priorities) with a simple per-actor **"Actors:"** responsibility list — Admin / Student — matching the manual's own "Registrar / Students" worked example exactly.
- **Figures renumbered again**: Requirement Analysis's new figure is Figure 1, System Framework Figure 2, Use Case Diagram Figure 3, and the four Activity Diagrams are Figures 4–7 (Log In, Take Quiz, Manage Questions, Generate Questions).
- **Simplified the Log In activity diagram (Figure 4)** to match the manual's own "Log In" example almost exactly — System shows the login screen, Student logs in, System shows the Home screen — dropping an invalid-credential decision branch that wasn't part of the demonstrated example.
- **Confirmed Chapters 1–3's existing structure already matches the manual** (Level 1/2 heading conventions, numbered Hardware/Software/Peopleware/Network subsections, the Body-of-the-Review guidelines for Chapter 2) — checked directly against the manual this session; no changes needed.
- Confirmed sections 4.7 (Entity Relationship Diagram) through 4.12 (Implementation Plan) exist in the manual but were intentionally left out, per your instruction.
- Updated both `docs/manuscript_ch1-4_full_revised.md` and the companion artifact (same link — "Chapters 1–4, Revised Draft").
- No Dart/SQL files were modified this session — manuscript-text and diagram work only.

---

## 2026-09-01 — Session 23: System Framework rebuilt as a layered architecture, by request

You asked me to act as your instructor and redesign the System Framework (4.3) with whatever I judge best, rather than following the manual's hub-and-spoke example.

- Replaced Figure 2 with a three-layer architecture diagram — Presentation / Service / Application / Data & External Services — grounded directly in this repo's own README "Architecture Overview" (UI → Provider State → Services → Local/Cloud) rather than invented from scratch. Automatic Item Generation is shown in its real place, the Service layer, with a distinct dashed arrow out to External APIs for the document method's Claude call; a separate dashed loop connects Local (SharedPreferences) and Supabase for the offline sync queue, distinguished from the bold primary layer-to-layer arrows since it's conditional (fires only once connectivity returns).
- Added an instructor's-note callout at the top of 4.3 explaining the reasoning: a hub-and-spoke diagram suits coordination between roughly equal participants; CrimiReview's real story is a pipeline with one enforced order, which a layered diagram shows and a hub-and-spoke diagram can't. Explicitly states the manual's original format isn't wrong, just not what was asked for, and that it remains recoverable from this file's and the artifact's revision history.
- Nothing else in Chapter 4 (or the rest of the document) was touched this pass — 4.1, 4.2, 4.4–4.6 are exactly as Session 22 left them.
- **Handled a real multi-session conflict carefully**: another session had advanced both `docs/manuscript_ch1-4_full_revised.md` and the companion artifact significantly further (the full Capstone Project Manual rebuild, logged as Session 22) since this session last touched them. Re-read both in full before making any change, confirmed Session 22's work rather than assuming stale state, and applied only the requested System Framework edit on top of it — no content from Session 22 was lost or overwritten.
- Updated both `docs/manuscript_ch1-4_full_revised.md` and the companion artifact (same link — "Chapters 1–4, Revised Draft").
- No Dart/SQL files were modified this session — manuscript-text and diagram work only.

---

## 2026-09-01 — Session 24: Every use case given its own narrative and diagram; every include/extend named explicitly

Follow-up to Session 23: you asked for the Use Case Diagram to specify exactly which use cases include/extend which, and for every module to have its own Use Case Narrative and Activity Diagram, with nothing generalized into another's.

- **Added an Include/Extend specification table to 4.4** covering all 12 primary use cases from Figure 3 (actor, what it includes, what extends it or is extended by), with "—" only where genuinely checked against the codebase and found to have none — not a default. Two entries are called out explicitly as deliberate, already-documented facts rather than oversights: Take Daily Challenge does not include Record Answer & Update Mastery (unlike Take Quiz — a known, disclosed gap), and Generate Questions has no drawn «include» of its own since its template method's audit-log write is internal SQL, not a diagram-level use case.
- **Added six new Use Case Narratives (Tables 7–12)**: Log In, Take Daily Challenge, Study Flashcards, Log Out, View Dashboard, Monitor Students — every primary use case from Figure 3 that didn't already have one from earlier sessions (Tables 1–6).
- **Added eight new Activity Diagrams (Figures 8–15)**: Sign Up, Take Daily Challenge, Study Flashcards, Track Progress/Mastery, Log Out, View Dashboard, Monitor Students, Manage Admin Roles — every primary use case that didn't already have one (Figures 4–7). Manage Admin Roles' diagram (Figure 15) includes a real decision branch (self-account check) matching Table 5 exactly, rather than being simplified away.
- Existing figures and tables (1–7, 1–6) were **appended after, not renumbered** — the four already-reviewed activity diagrams and six narratives from earlier sessions are untouched.
- Updated both `docs/manuscript_ch1-4_full_revised.md` and the companion artifact (same link — "Chapters 1–4, Revised Draft").
- No Dart/SQL files were modified this session — manuscript-text and diagram work only.

---

## 2026-09-01 — Session 25: Use Case Diagram labels de-generalized

Follow-up to Session 24: you pointed out the Use Case Diagram (Figure 3) itself still had two generalized labels — a shared "«include» (×2)" standing in for two different arrows, and an "«extend»" label positioned nowhere near the three arrows it was meant to describe.

- **All nine «include»/«extend» arrows in Figure 3 now carry their own individually-placed label**, none shared. The two arrows into Log Admin Action (from Manage Questions, from Manage Admin Roles) are each labeled by source, since they terminate at the same target and would otherwise be indistinguishable. The three Use App Offline «extend» arrows are each labeled at their own destination (Take Quiz, Take Daily Challenge, Study Flashcards); the shared "no connectivity" extension point is stated once, at its actual source next to Use App Offline, instead of floating unlabeled in the middle of the diagram.
- The diagram's node set and geometry are otherwise unchanged — this was a labeling-precision fix, not a redesign.
- Updated both `docs/manuscript_ch1-4_full_revised.md` and the companion artifact (same link).
- No Dart/SQL files were modified this session — manuscript-text and diagram work only.

---

## 2026-09-01 — Session 26: Log Admin Action broken open — no more black box

Follow-up to Session 25: you pointed out "Log Admin Action" itself was still a generalization — one ellipse, no indication of what it actually records, or whether "delete" was the whole story.

- **Read the actual code rather than assume**: `admin_service.dart`, `supabase_admin_management.sql`, `supabase_template_generation.sql`. Confirmed `log_admin_action` is called with exactly 7 action-type values: `create`, `update`, `delete`, `restore` (all from Manage Questions), `promote`, `demote` (Manage Admin Roles), `generate` (Generate Questions, template method only).
- **Kept it as one use case** — it's genuinely one function, one RPC, one table (`admin_audit_log`) — but attached a note (dashed connector, bottom of Figure 3) listing every verified action-type value, instead of splitting it into several redundant near-duplicate bubbles that would misrepresent the architecture.
- **Two real corrections came out of checking this, not just presentation fixes**: `delete` has a counterpart, `restore` — `AdminService.setActive()` toggles a question inactive/active, logging `delete` or `restore` depending on direction, so "Delete" alone was already an incomplete description of that one Manage Questions action. And Generate Questions' template method **now has its own «include» arrow to Log Admin Action**, which an earlier pass had deliberately left undrawn, reasoning the SQL-internal call was "implementation detail" — on reflection that undersold a real, direct relationship the code actually has (verified: `PERFORM public.log_admin_action('generate', ...)` runs inside the template-generation SQL function itself), rather than avoided overstating one.
- Updated the Include/Extend specification table, the Figure 3 prose, and the diagram itself to match.
- Updated both `docs/manuscript_ch1-4_full_revised.md` and the companion artifact (same link).
- No Dart/SQL files were modified this session — manuscript-text and diagram work only.

---

## 2026-09-04 — Session 27: instructor's marked printout applied to the Use Case Diagram

You handed over a photo of your instructor's hand-marked printout of Figure 3 and asked to have the corrections applied exactly, with the include/extend relationships made specific and the diagram built cleanly. All five red marks are now in:

1. **"Log Admin Action" removed.** The catch-all bubble is gone. Three real use cases replace it — **Insert Question**, **Update Question**, **Delete Question** — each drawn as an «extend» of Manage Questions at the "choose operation" extension point. Generate Questions (AIG) now sits on that same extension point as the fourth operation, so all four question operations are shown consistently.
2. **Actor "User" renamed to "Students."**
3. **Admin/Teacher actor renamed to "Faculty."**
4. **"Send Verification Reset Code" shortened to "Send Verification Code"** — "Reset" was struck out.
5. **System boundary box added** — the red rectangle around all use cases, with both actors outside it. This reverses the earlier note that said not to frame the diagram; the marked copy is the newer instruction.

Also done in the same pass:
- Every arrow still carries its own individual label — no shared or stacked labels, keeping the earlier de-generalization work intact.
- Manage Questions now displays its extension point name ("choose operation") directly on the ellipse.
- The Include/Extend specification table gained rows for the three new use cases and lost every Log Admin Action row.
- The Relationship summary lists each new «extend» separately rather than grouping them.
- A short paragraph explains why Insert/Update/Delete are «extend» and not «include» — a Faculty member performs one operation per visit, not all four — so the choice can be defended if questioned.

**Audit logging was not deleted, only relocated.** Insert, Update, Delete, Generate, Promote and Demote all still write to `admin_audit_log` in the running app. That behaviour is now recorded in the Use Case Narratives (Tables 4, 5, 6) instead of being its own use case, which is the more accurate modelling — logging is a system side effect of each operation, not an actor's goal.

**One ambiguity flagged, not silently guessed.** The middle red word reads as either *Insert* or *Reset*. I used **Insert Question**, matching `AdminService.createQuestion()`. If *Reset* was meant, `setActive(true)` (restore a soft-deleted question) is the real counterpart and it is a one-line swap.

**One consistency item deliberately left alone.** The rename was marked only on the Use Case Diagram. The twelve Use Case Narrative tables and twelve Activity Diagram swimlanes still say Student/Admin. Renaming those is a bigger change than what was marked, so it is left as your call.

Files touched: the published artifact (Use Case Diagram SVG plus the surrounding prose, note box and specification table) and `docs/manuscript_ch1-4_full_revised.md` (Figure 3 block, Relationship summary, Include/Extend table, and a new "Latest pass" revision note). No Flutter or Supabase code changed — this was a manuscript pass only.

**Delivery format going forward:** you asked that the manuscript live in the published Artifact rather than a markdown file. Noted and saved as a standing preference — future manuscript changes go to the artifact only, and `docs/manuscript_*.md` will not be kept in sync. The artifact already carries all four chapters and every correction; the markdown copies are now redundant and can be deleted on your say-so.

## 2026-10-07 — Session 28: PDF question generation removed, template generation kept

You asked to remove automatic question/quiz generation from PDFs and keep only the template-based generator.

**Removed from the app**
- `lib/screens/admin/admin_document_generation_screen.dart` — the "Generate from Document" screen (PDF picker + upload queue).
- `lib/services/document_generation_service.dart` — uploaded the PDF to Storage and called the Edge Function.
- `supabase/functions/generate-questions-from-document/` — the Edge Function that sent the PDF to Claude.
- `supabase_document_generation.sql` — the setup script for the `document_uploads` table and `document-uploads` bucket.
- `file_picker` package from `pubspec.yaml` — nothing else used it.
- The "Generate from Document" (✨) button on the Admin → Questions toolbar.

**Kept, unchanged in behaviour**
- "Generate from Templates" (`admin_template_generation_screen.dart`, `question_generation_service.dart`, `supabase_template_generation.sql`). It is now the only generator; its toolbar tooltip dropped the "(free)" suffix since there's no paid option to contrast it with.
- The "Generated only" filter on the Questions screen — template output is also tagged `source = generated`, so the review flow still needs it.

**Tidied**: doc comments in `admin_questions_screen.dart`, `admin_service.dart`, `question_generation_service.dart` and `admin_template_generation_screen.dart` that pointed at the deleted classes now describe the template flow instead. README setup list renumbered (template SQL is now step 7) and the "Enabling AI-Generated Questions" section replaced with a short "Question generation" note.

**Added**: `supabase_remove_document_generation.sql` — optional, drops `document_uploads` and its three storage policies on the live project. Its header lists the two things SQL can't do (delete the bucket, delete the deployed Edge Function) with the exact Dashboard/CLI steps. Questions already generated from PDFs are deliberately left in the bank.

Verified: `flutter analyze lib` reports 0 errors.

---

## 2026-10-07 — Session 29: horizontal Entity Relationship Diagram (manuscript 4.7)

Supabase's Schema Visualizer stacks the tables in one vertical column, and you wanted them laid out horizontally. That layout is saved in your browser, not the database, so it can't be changed from here. Instead, a proper ERD was drawn for the manuscript.

- **New section 4.7 Entity Relationship Diagram (Figure 16)** in the published manuscript artifact (same link, version 14). It covers all 15 entities (14 `public` tables plus `auth.users`) with every column, PK/FK markers, and crow's-foot cardinality. It reads left to right in five groups: Accounts & Security, Student Records, Adaptive Learning, Question Bank & Audit, Item Generation.
- Built straight from `supabase_schema.sql`, `supabase_email_verification.sql` and `supabase_schema_v2.sql`. Enforced foreign keys are drawn solid. The three links matched by value without a foreign key are drawn dashed: `question_attempts.question_id`, `questions.template_id`, and concept_bank ↔ question_templates on subject_id + topic.
- `document_uploads` is left out on purpose, because it was removed in Session 28.
- Rail nav, the Chapter 4 intro, the formatting-notes card and the Revision Notes now say 4.7 is drafted (4.8–4.12 still are not).
- Flagged in the section itself: the Capstone Manual's own 4.7 example wasn't available, so the definition is the standard one. Compare against the manual once the class covers it.
- Housekeeping: the publish skeleton (`<!doctype>…<body>` plus six duplicated `</body></html>` lines that earlier republishes had piled up) was stripped from the page source.
- No Flutter or SQL files changed.

---

## 2026-10-07 — Session 30: full system-flow walkthrough (visual)

You asked for the complete workflow, from app start through both the student and Faculty (admin) flows, as a visual presentation.

- Traced the flow from the code (`main.dart` start-up order, `splash_screen.dart` routing, `auth_screen.dart` / `email_verification_screen.dart` / `forgot_password_screen.dart`, the five `home_screen.dart` tabs, `subjects_screen.dart` → `study_notes_screen.dart` → `quiz_screen.dart` → `results_screen.dart`, `daily_challenge_screen.dart`, `admin/`, and the sync, mastery and question services).
- Published as a new private artifact, **CrimiReview System Flow**: https://claude.ai/artifact/MAPSujU1K1zvFrvLjDVc4y. It has 8 stages (launch, accounts, student tabs, adaptive quiz loop, daily challenge, Faculty side, data & sync, rules table) and 6 flow diagrams.
- Facts it states, each checked in code: 4 segments × 10 questions per difficulty, 75% pass mark, Medium/Hard unlock rules, date-seeded 10-question daily challenge, reminders at 9:00 AM and 7:00 PM, offline queue retry every 10 s, generated questions start inactive, Faculty can't change their own role.
- No app code changed.

---

## 2026-10-07 — Session 31: System Framework (4.3) redrawn in the manual's format

You shared the Capstone Manual's 4.3 example (an app icon in the centre with users and services around it, joined by arrows) and asked for a clean, precise version in our own style, so future researchers can follow the system quickly.

- **New Figure 2** in the manuscript artifact (same link, version 15):
  - The CrimiReview app sits in the centre. Students and Faculty are on the left; Supabase Authentication, Database and Local Storage are on the right; the Email Service (Resend) is at the top; the seven modules are along the bottom.
  - All **12 flows are labelled and numbered arrows**, colour-coded as student, Faculty, data, email, and offline sync (dashed).
- A numbered list under the figure explains each arrow in the order of a typical session.
- Every arrow was checked against the code: the code is emailed by a server-side function and never passes through the phone; Authentication returns the session and role; the offline queue syncs later; Faculty view mastery read-only.
- The 4.3 definition and example paragraph now use the manual's own wording, from your photo.
- **Replaced** the earlier three-layer architecture diagram, which still showed the removed PDF/Claude path. It is still in the artifact's version history.
- Callout and Revision Notes updated to match. No app code changed.

---

## 2026-10-07 — Session 32: number badges removed from the System Framework

At your request, Figure 2 (4.3 System Framework) now shows only the illustration. The 1–12 number badges on the arrows are gone; every arrow keeps its short label, such as "email + password" or "session + role". The explanation under the figure is now a plain bullet list in the same order, and the paragraph, callout and Revision Notes no longer mention numbers. Manuscript artifact version 16. No app code changed.

---

## 2026-10-07 — Session 33: framework hub simplified + PNG export

- Figure 2 (4.3 System Framework): removed the four description lines and the divider inside the centre CrimiReview box. It now shows only the phone icon, "CrimiReview" and "Mobile App · Flutter · Android", centred vertically. Manuscript artifact version 17.
- **New file `docs/figures/system-framework.png`**: the same figure as a 3240 × 2160 PNG (3× resolution) on a white background, ready to paste into Word or print.
- No app code changed.

---

## 2026-10-07 — Session 34: arrow labels removed from the System Framework

- Figure 2 (4.3 System Framework): removed every word on the arrows ("email + password", "session + role", "code arrives in student's inbox", "opens the module the user picks", and so on). The arrows, colours, icons and boxes are unchanged. The small "Internet" signal icon stays, because it marks the connection rather than labelling an arrow.
- The paragraph, callout and Revision Notes now say "arrow" instead of "labeled arrow". The colour legend and the bullet list under the figure still explain each flow. Manuscript artifact version 18.
- `docs/figures/system-framework.png` re-exported to match (3240 × 2160).
- No app code changed.

---

## 2026-10-07 — Session 35: fixes from the pre-upload inspection

Fixed every issue found in the system check, plus one more found while fixing them.

**1. Offline results could be uploaded to the wrong account (newly found).** Queued offline items didn't record whose they were. If student A had unsent results and student B then logged in on the same phone, A's results were uploaded under B's account. Each queued item now stores the account id (`SyncOperation.userId`) and syncs only while that account is signed in. Items queued by the old version have no id and keep the old behaviour. — `lib/services/offline_sync_service.dart`

**2. Offline items were silently dropped after 3 failures.** The queue gave up after 3 tries, 10 s apart, so a 30-second outage could lose a quiz result with no message.
- Network and server errors are now retried indefinitely, with backoff (10 s, 20 s, 40 s … up to 5 min). The sync stops at the first network failure instead of failing every item.
- Only errors that retrying can't fix are removed from the queue: invalid data (Postgres codes 22xxx), constraint violations (23xxx), permission or RLS rejections (42xxx), and a deleted avatar file.
- When that happens the sync indicator shows a red "N not saved" chip. Tapping it explains what happened.
- Files: `offline_sync_service.dart`, `lib/widgets/sync_status_indicator.dart`.

**3. Daily Challenge could be retaken and overwritten.**
- The "done today" check only looked at the phone, so reinstalling or using a second phone allowed a retake. The retake also replaced the first score through an upsert and awarded the points again.
- The screen now also asks the server, when online. `saveDailyChallengeScore` uses a plain insert: a second attempt hits the unique constraint, is ignored, and awards no points.
- A challenge finished offline keeps the date it was played (`challengeDate`) instead of the date it synced.
- Files: `lib/screens/daily_challenge_screen.dart`, `lib/services/supabase_service.dart`, `offline_sync_service.dart`.

**4. Internet check (correction to what I first reported).** The old check didn't crash in a browser; its catch-all just kept reporting "online" forever, so a web build could never detect being offline. It also tested `google.com` rather than the app's own server. It now checks the Supabase host itself: a DNS lookup on Android, an HTTP request on web, with any error counted as offline. `http` (already in the lockfile at 1.6.0) is now a direct dependency. — `lib/services/connectivity_service.dart`, `pubspec.yaml`

**5. Release builds were signed with the debug key**, which the Play Store rejects.
- `android/app/build.gradle.kts` now reads `android/key.properties` when it exists. Without it, the build still works but prints a warning and uses the debug key.
- README "Release signing" has the three steps to create the key.
- Both files are already git-ignored.

**6. Cleanup.**
- All 19 analyzer warnings are fixed: unused imports, fields and variables; a dead `_buildInsightCard`; two `?? 'Student'` fallbacks that could never run; and an explanation box that showed even when the explanation was empty, now hidden when empty.
- `flutter analyze`: 0 errors, 0 warnings (204 style hints remain, such as "add const").
- The app's display name is "CrimiReview" on Android, iOS, web and Windows (was "crimireview").
- `android/build/` and `supabase/.temp/` are git-ignored, and the committed build report is untracked; the file stays on disk.

`flutter test`: passed.

---

## 2026-10-07 — Session 36: v1.0.0 published to www.crimireview.app

**Before this, the website's Download button was broken.** www.crimireview.app (a static page on Vercel) links to `github.com/kilewin021105/crimireview/releases/latest/download/app-release.apk`, but the repo had no releases, so every download returned 404. The website itself needed no change; publishing a release fixed the link.

- **Pushed** commit `f19b918` (Sessions 28–35) to `main`. The three `docs/manuscript_*.md` thesis drafts were deliberately left out, since the repo is public.
- **Built** `app-release.apk`: 56.4 MB, `com.crimireview.crimireview` 1.0.0 (versionCode 1), label "CrimiReview", min Android 7.0 (SDK 24), target SDK 35. Signed with the **debug key**, because there is no `key.properties` yet.
- **Published** GitHub release **v1.0.0** with `app-release.apk` attached: https://github.com/kilewin021105/crimireview/releases/tag/v1.0.0
- **Verified** by downloading through the site's own link (HTTP 200, 59,181,254 bytes). The SHA-256 matches the built file: `d02d3ebcca304cb72f49d9b0266b5df05b858617e541831d913b32c20808db8c`.

**Build problems hit on the way (none caused by app code):**
1. The first build stalled for a long time downloading about 55 MB of Flutter's Android release libraries on a slow connection.
2. Leftover Gradle and Kotlin daemons then locked `build/url_launcher_android/.../caches-jvm` ("Could not delete").
3. After that, Gradle's local build cache (`org.gradle.caching=true`) kept restoring an **empty** Kotlin result for `url_launcher_android`, so Java couldn't find `WebViewOptions`, even after `flutter clean`. Confirmed by compiling that task with `--no-build-cache`; fixed by deleting `~/.gradle/caches/build-cache-1`. If "cannot find symbol" appears for a plugin's Kotlin class again, that is the fix.

**Known follow-ups:**
- The website says "Requires Android 5.0 or higher". The app actually needs **Android 7.0+**; the site source isn't in this repo.
- If a release key is created later for the Play Store, phones with this debug-signed v1.0.0 must uninstall before installing the newly signed build.
- For the next update: bump `version:` in `pubspec.yaml` (e.g. `1.0.1+2`), build, and publish a new release with the asset named exactly `app-release.apk`.

---

## 2026-10-09 — Session 37: full pre-launch audit (security, flows, layout, slow internet, scale)

Audited the code, all SQL rules, the full git history, and the **live** Supabase project, probing it with only the public key shipped in the APK, which is what any outsider has. Every database fix was tested first on a local copy of the schema (PostgreSQL 18 with a Supabase stand-in), attacking it as an outsider, a student and an admin: **49/49 checks pass**. `flutter analyze`: 0 errors, 0 warnings. `flutter test`: 19/19 pass. Release APK v1.0.1 builds.

**Critical, confirmed live, fixed in code (you must run the SQL — see README steps 8–9):**
- **All 12 user profiles (emails, names, schools, who is admin) were readable by anyone, even logged out.** `user_profiles` now returns only your own row (admins: all). The leaderboard uses a new `get_leaderboard()` function that returns only name, avatar, points and rank, to signed-in users only. — `supabase_security_fixes_v2.sql`
- **Password-reset hijack window:** for 15 minutes after a real user verified their reset code, anyone could call `reset_user_password(email, new_password)`. The function now requires the verified code, allows 5 wrong guesses, and enforces 8–72 characters. The old function is dropped, and so is `cleanup_password_resets`, which let anyone cancel anyone's reset. App: `forgot_password_screen.dart`, `supabase_service.dart`, `email_verification_service.dart`.
- **Unlimited code emails:** anyone could flood any inbox and burn the Resend quota. Now limited to 1 per minute and 5 per hour per address, with a 300-per-hour project-wide backstop. Reset emails are sent only if an account exists, with the same response either way, so no account enumeration.
- **Email verification could be skipped** by calling Supabase sign-up directly. `supabase_enforce_email_verification.sql` makes the database refuse accounts without a verified code from the last 30 minutes. It is a separate file with a rollback line.

**Critical, needs you, not fixable from code:**
- **Active Resend API key in public git history.** `re_QjKf…`, committed in dd828ff and 6aaae1e (May), is **still valid with full access** to the Resend account and the verified domain crimireview.app. It must be rotated. (`re_5FEu…` from the same history is already dead.)

**Other fixes:**
- Daily challenge scores are private and insert-only; a score can't be raised after the fact.
- The avatars bucket allows only 2 MB images (no SVG).
- Name/school length limits are enforced in the app (30+30, 60, 100) and in the database (80 / 150).
- The leftover `document_uploads` table is dropped.
- **Slow internet:** every Supabase request now times out (25 s; storage 2 min) instead of spinning forever. All errors go through `lib/utils/error_messages.dart`, which gives clear "No internet" or "too slow" messages instead of raw exception text. Login's old matcher missed timeouts, because "TimeoutException" didn't match "timeout".
- **Change password** now requires the current password, so an unlocked phone can't be used to lock the owner out.
- **Leaderboard** shows a retry state on failure instead of looking empty. Its rank label now comes from the database, so the old client thresholds (Legend at 5,000 vs 10,000) no longer disagree with the rest of the app.
- **Sounds never worked:** `correct.mp3` and `wrong.mp3` were saved GitHub web pages, and `tap.mp3` was a 404 page. They are replaced with generated `correct.wav` / `wrong.wav`. Sound loading can no longer break the feedback service's startup.
- **Layout bugs found by rendering at real phone sizes** (with the real Poppins font; Flutter's square test font reported false overflows):
  - the email-verification code row overflowed at 360 px, the most common Android width. The cause was a margin arithmetic error (48 px of margins, 40 subtracted).
  - onboarding was cut off at 320×568.
  - Both are fixed; `test/responsive_screens_test.dart` covers 6 screens × 3 sizes.
- **Settings:** "Share App" had no link (now includes www.crimireview.app). The "Rate App" placeholder ("coming soon") is removed. "Send Feedback" silently did nothing on Android 11+, because the manifest had no mailto query and the false result was ignored; both are fixed.
- **Admin question search:** commas and brackets broke the query; they are now stripped.
- **Question bank download** (about 117 KB compressed): it was refreshed on every launch and every 10 minutes, roughly 20 GB/month at about 1,000 daily students. It is now refreshed once per hour and not at all when the saved copy is fresh.
- Version bumped to **1.0.1+2**.

**Known, not fixed (design-level or outside the code):**
- Leaderboard points are calculated on the phone, so a technical student can inflate their own points. A real fix needs server-side scoring.
- Questions, including correct answers, are readable without login. This is by design for offline use.
- Points updates from two devices at once can lose points (read-modify-write).
- Logged-in screens weren't layout-tested automatically, only scanned. Do a manual pass on a small phone.
- `support@crimireview.app` cannot receive mail: the domain has **no MX records**.
- The website still says Android 5.0; the app needs Android 7.0 or newer.
- The APK is still debug-signed.

**Launch order:**
1. Rotate the Resend key.
2. Run `supabase_security_fixes_v2.sql`, then `supabase_enforce_email_verification.sql`.
3. Publish APK v1.0.1.
4. Test sign-up, login, forgot password and the leaderboard.

Phones still on v1.0.0 will fail at the last step of Forgot Password, and their leaderboard will show only themselves, until they update.

---

## 2026-10-09 — Session 38: leaked Resend key revoked

- Listed the Resend account's keys. There were three:
  - **May 24 "CrimiReview"**: the one in public git history.
  - **Aug 6 "Crismireview"**: last used Oct 7 09:19, matching the app's sign-up and reset emails, so this is the key in Supabase Vault. It is not in any commit.
  - **Oct 9 "CrimiReview"**: newly created; confirmed valid and sending-only.
- **Revoked the leaked May 24 key** (id 9afbf4ab…) through the Resend API. Verified afterwards: it returns "API key is invalid". The app's emails were unaffected, because the app uses the Aug 6 key.
- Its last-used time showed only this session's own checks. Resend shows just the latest use, so for earlier misuse the Emails log (any range) is the record. The 15-day view showed only the app's own emails.
- Not done, because there is no Supabase access from this machine: switching Vault to the new key is optional. The Aug key was never leaked. If the new key isn't used, delete it in Resend.
- Still to run by the owner: `supabase_security_fixes_v2.sql`, then `supabase_enforce_email_verification.sql`, then publish v1.0.1.

---

## 2026-10-09 — Session 39: fix "cannot change return type" when running security fixes v2

- Running `supabase_security_fixes_v2.sql` in the SQL Editor failed with `42P13: cannot change return type of existing function` for `get_leaderboard`. The SQL Editor runs the script as one transaction, so **nothing was applied**: checked live, profiles were still readable anonymously.
- Cause: the live project still has the **original `get_leaderboard(limit_count)`** from the very first commit (`847b1eb:supabase/schema.sql`). It is no longer in any `.sql` file. It is callable **without logging in** (confirmed live: it returns names, avatars and points, but no emails), and no app version calls it.
- Fix: the file now runs `DROP FUNCTION IF EXISTS public.get_leaderboard(integer)` before creating the new one.
- Verified locally against a copy that includes the old function. The unfixed file reproduces the exact error (same message, DETAIL and HINT). The fixed file runs cleanly as a single transaction, twice. The attack suite plus the sign-up rule gives **45/45 PASS**.
- Checked git history for other leftover functions that could clash: only `get_leaderboard` does.

---

## 2026-10-09 — Session 40: security fixes v2 applied to the live project (launch step 1)

- **Before running**, checked the live database read-only for anything that could fail or leave a hole open: both old functions with other signatures (`get_leaderboard(limit_count)`, `reset_user_password(user_email, new_password)`) are dropped by the script first; every helper it calls exists; the only "anyone can read" policies on `user_profiles` / `daily_challenge_scores` were exactly the ones the script removes; sign-up doesn't need logged-out profile access (the `handle_new_user` trigger creates the profile).
- `document_uploads` held 3 rows: three **failed** Aug 27 attempts of the removed PDF generator (same PDF, missing API key, 0 questions). Dropped with the table. The PDF itself is still in the `document-uploads` storage bucket.
- The Supabase connector refused to apply the script three times (it declines database changes in this session), so **you ran it in the SQL Editor**: "Success. No rows returned."
- **Verified from inside the database:** new policies only, `anon` has no access to profiles, challenge scores, `get_leaderboard` or the rate-limit helper; the rate-limit table, avatar limits (2 MB, images only) and name/school length limits exist; `document_uploads` is gone.
- **Verified as an outsider** with only the APK's public key, 7/7 as expected: profiles → permission denied; challenge scores → permission denied; new leaderboard while logged out → permission denied; old leaderboard, old 2-argument reset and `cleanup_password_resets` → no longer exist; new reset with a wrong code → refused.
- **Resend key:** the Vault secret was changed by hand on Oct 9 at 11:23 PM (none of our SQL files write to Vault). Checked without revealing it: it is not the revoked leaked key nor the older dead one, and Resend accepts it (a deliberately empty request got "Missing `to` field", which means the key is valid; no email was sent).
- **Supabase security advisor**, remaining warnings:
  - Functions anyone can call: the sign-up / reset functions must be (they run before login). `generate_questions_from_template` and `log_admin_action` check `is_admin()` inside. `handle_new_user` / `protect_user_role` are trigger functions and fail if called directly.
  - **One to fix in step 2:** `cleanup_expired_verifications()` is callable by anyone and deletes **verified** rows too. Once `supabase_enforce_email_verification.sql` requires a verified row at sign-up, someone could call it in a loop and make sign-ups fail. Revoke it from `anon`/`authenticated` alongside step 2.
  - Minor: 6 trigger/helper functions have no fixed `search_path`; "leaked password protection" is off (a Supabase Auth setting).

---

## 2026-10-12 — Session 41: full UI redesign (student app and admin panel)

You asked for a modern redesign of the whole app, from login through every student screen and the admin panel. Every screen's look was rebuilt; the logic behind each screen (sign-in, sync, quiz scoring, BKT mastery, admin CRUD) was kept as it was, except for the bugs listed below.

**Design system (new)**
- **Brand colours now match the app icon.** The icon is navy and gold, but the app's screens were violet, so the two never matched. New palette: royal blue for anything you can tap, deep navy for hero cards, gold for points, ranks and achievements, plus one fixed colour per board subject. Light and dark mode each have a full set (`AppPalette` in `lib/services/theme_service.dart`); screens read colours from it instead of hard-coding ~200 colours across screens.
- **New typeface, bundled in the app:** Plus Jakarta Sans (`assets/fonts/`, SIL Open Font License, checksums verified against Google Fonts). Poppins used to be *downloaded* by the `google_fonts` package at runtime, so on a first launch without internet text fell back to the system font. The `google_fonts` dependency is removed.
- **Component kit** in `lib/widgets/ui/`: cards, gradient hero cards, stat tiles, headers/top bar, buttons, labelled text fields, a 6-box code input (supports pasting the whole code), pill tabs, tags, banners, list groups, progress bars and rings, empty/loading states, avatars, confirm dialog, snackbars. Every screen is built from these, so spacing, corners and colours are the same everywhere.
- **Real logo in the app:** `assets/images/logo_mark.png` (the app icon artwork, cropped) replaces the hand-drawn "CR" and graduation-cap placeholders. The `assets/icon/` folder was never packaged with the app, hence the separate copy.
- **Native launch screen** (Android) is now brand navy instead of white, and Android 12+ shows the app icon on navy, so starting the app no longer flashes white before the splash. The web manifest's colours (Flutter's default blue) are now the same navy.
- **Page transitions** (`lib/utils/page_transitions.dart`): a short slide plus fade instead of a full-screen slide, and a gentle scale instead of the old "bounce" (the curve overshot). Tab switches are instant, like other modern apps.

**Screens rebuilt**
- Before login: splash, onboarding (illustrated pages, Skip, dots + Next), sign-in / create account (navy header, form sheet, Sign in | Create account switch), forgot password (step progress, code boxes), email verification.
- Student: home (avatar, streak, Daily Challenge hero, stats, shortcuts, readiness ring, subject cards with accuracy), Quiz tab (subject cards with E/M/H level steps and accuracy ring, difficulty sheet), Flashcards tab (deck tiles), Progress (accuracy hero, streak, **new per-subject accuracy bar chart** with the 75% pass line, gold badges), Settings (grouped lists, standard switches), study notes, quiz (per-question progress strip, answer cards, explanation card with mastery bar), results, flashcard deck (subject-coloured cards, swipe labels, **new "Review again" / "I know it" buttons** so students don't have to know about swiping), study modules + chapter reader (reading progress bar, table of contents), achievements, leaderboard (your-rank card, podium, list), profile, change password, Daily Challenge (countdown ring, results with points card and answer review).
- Admin: **responsive shell** (bottom bar on phones, side navigation rail on tablets/desktop/web), dashboard (question-bank hero, stat grid, content-by-subject bars, activity feed), question bank (search, filter menus, tagged cards), question editor (sectioned form, difficulty switch, clear correct-option marker), students (mastery bars, metric strip, Admin/You tags), template generation.

**Bugs found and fixed while rebuilding**
1. **Quiz difficulty sheet:** segments a student hadn't tried yet were drawn as *full red bars*, as if failed. They are now empty.
2. **Daily Challenge confetti could crash or never play:** one confetti controller was shared by the challenge and results screens and disposed by both; the challenge screen is closed while the results screen still needs it. The results screen now owns its own.
3. **Daily Challenge timer:** every question added another "time's up" listener to the same timer without removing the old ones. Now added once.
4. **Admin question editor marked the wrong answer:** deleting an option *above* the correct one left the correct-answer index unchanged, so a different option became "correct". Fixed: the marker moves with its option.
5. **Lost sync results were silent:** the sync service documents that items the server permanently rejects are shown "until acknowledged", but the widget meant to show them was never placed on any screen. The home screen's status strip now shows "N results couldn't be saved online · Tap for details".
6. **Settings said "Version 1.0.0"**; the app is 1.0.1.
7. **Settings and Profile ignored the cloud avatar** (only a photo stored on this phone was shown).
8. **Profile:** saving updated the screen after it could already be closed; a failed photo pick showed raw exception text.
9. **Study modules:** the loader updated the screen without checking it was still open.
10. **Email verification:** navigated after several network calls without checking the screen was still open.
11. **Quiz:** answer letters came from a fixed A–D list, so a question with 5–6 options (the editor allows up to 6) would have crashed.
12. **Admin activity feed:** an audit entry with an empty action name crashed the dashboard.
13. **Admin screens showed raw exception text** on errors; they now show plain messages.
14. `profile_screen.dart` imported `path_provider` without declaring it; now declared in `pubspec.yaml`.

**Removed:** `lib/widgets/animated_widgets.dart`, `streak_widget.dart`, `sync_status_indicator.dart` (no screen used them; the one useful part, the lost-sync notice, now lives in the home screen) and the Poppins test fonts.

**Verification**
- `flutter analyze`: 0 errors, 0 warnings.
- `flutter test`: the layout test now uses the bundled font and checks the pre-login screens at 320, 360 and 412 px wide in **both light and dark mode** (33 checks, all pass).
- **New screenshot harness** (`test/screenshots/`, skipped in normal test runs): renders every screen to PNG with sample data, including the admin panel through a test-only `AdminService.debugInstance` hook. All 60+ screenshots were reviewed in light and dark; no layout overflows.
- A debug APK build was started but stopped before finishing (the laptop was low on memory); the release build below is what confirms the Android resources compile.
- Not tested on a physical phone in this session.

## 2026-10-12 — Session 42: redesign merged and published as v1.0.1 on www.crimireview.app

**Branches.** You first chose to keep the old design on `main` and put the redesign up as a separate pull request:
- `main` = commit `83e290a`, the old design plus the Session 37–40 security fixes.
- `redesign` = commit `33ea539` (on top of `main`), only the Session 41 redesign.
- **Pull request #1** (https://github.com/kilewin021105/crimireview/pull/1) was opened from `redesign`. Claude Code's safety check does not let me merge a pull request, so **you merged it on GitHub**: merge commit `a15829c`. `main` now has the redesign; the old design remains in the history at `83e290a`.
- The `docs/manuscript_*.md` drafts stay uncommitted on purpose.

**Published v1.0.1:** GitHub release https://github.com/kilewin021105/crimireview/releases/tag/v1.0.1, tagged at `a15829c` and marked "latest", with the APK below attached as `app-release.apk`.
- **Verified** by downloading through www.crimireview.app's own Download link: HTTP 200, 59,949,770 bytes, and the SHA-256 matches the built file. Visitors now get v1.0.1 with the new design instead of v1.0.0.
- As with v1.0.0, it was published through GitHub's API using the GitHub login Git already saves on this laptop; the GitHub CLI isn't needed.

**Release APK of the redesign**, built from the `redesign` branch with `flutter build apk --release` (its app code is identical to merged `main`):
- `build/app/outputs/flutter-apk/app-release.apk`, 57.2 MB, `com.crimireview.crimireview` **1.0.1 (versionCode 2)**, min Android 7.0 (SDK 24), target SDK 35.
- SHA-256 `A197781BF569BC4E4133E996BDD5C362CAE115106AF64E53FC3642317C7BD61B`.
- Checked inside the APK: the bundled Plus Jakarta Sans fonts and `logo_mark.png` are packaged, so this is the redesign, not the old UI.
- Still signed with the **debug key** (no `android/key.properties` yet), the same key as the published v1.0.0, so it installs as an update over v1.0.0 on a phone.
- Leftover Gradle processes from the stalled build were stopped first; the build then took about 6 minutes (Gradle `assembleRelease` 255 s).
- Not yet installed on a phone (none was connected).

**Housekeeping:** `android/.kotlin/` (the Kotlin compiler's temporary session files) is now git-ignored; one such file had been committed by mistake and is removed from the repo.

---

## 2026-10-14 — Session 43: website (www.crimireview.app) hardened, GitHub account no longer shown

The website's source is a separate repo, `kilewin021105/crimireview-landing`, now cloned to `C:\crimireview-landing`. Vercel redeploys it on every push to `main`. Commit `3150985`:
- **Download button** now links to `www.crimireview.app/download` instead of a github.com address. A new `vercel.json` redirects that link to the latest app release's `app-release.apk`, so publishing a new release still updates the site automatically.
- **Footer "GitHub" link removed.** The live page now contains no mention of GitHub. Clicking Download still briefly goes through GitHub (that's where the file is stored), but the page and its code only show your domain.
- **Security headers** on every page (`vercel.json`): the site can't be embedded inside other sites (`X-Frame-Options: DENY`, `frame-ancestors 'none'`), plus `X-Content-Type-Options: nosniff` and a referrer policy. HTTPS-only (HSTS) was already on.
- **Fixed "Requires Android 5.0 or higher"** to **7.0**, the app's real minimum (minSdk 24). Students on Android 5–6 were being offered an APK that can't install. This resolves the follow-up noted in Session 36.
- **Verified live:** all four headers present, 0 mentions of GitHub in the page, `/download` → 307 redirect to the release APK.
- Editing the page with the browser's Inspect tool only changes the copy on that person's own screen; the files on Vercel can't be changed that way. What protects the site is the GitHub, Vercel, domain-registrar and email accounts (2FA recommended).

---

## 2026-10-15 — Session 44: Google / Facebook sign-in, rebuilt dashboard, account-switch data fix

You asked for "sign in with Google or Facebook" so students don't have to type, with authentication that keeps each student's data protected and correct, plus a modern rebuild of the dashboard. Branch `social-login-dashboard`; `main` is unchanged until you merge its pull request.

**Google and Facebook sign-in**
- **How it works:** the student taps Google or Facebook and signs in on that company's own page in the phone's browser (this app never sees their password). The browser comes back to the app through the link `com.crimireview.crimireview://login-callback` with a one-time code. Supabase exchanges it for a session using **PKCE**: before opening the browser, the app keeps a secret on the phone, and the code is useless without it, so another app that catches the code can't use it.
- **Same account, same progress:** Supabase joins a Google/Facebook login to an existing account with the same verified email, so a student who signed up with email + password and later taps Google lands in their own account, not in a new empty one.
- Google always shows its account chooser (`prompt=select_account`), so on a shared or family phone the student picks their own account instead of being signed in silently as whoever used Google last.
- The buttons only appear for providers that are switched on in Supabase. The app checks Supabase's public settings each time the sign-in screen opens and remembers the last answer, so nobody taps into a "provider not enabled" error page. **Checked live today: Google and Facebook are both still off**, so the sign-in screen looks exactly as before until you do the README steps.
- Clear messages for: cancelled sign-in, Facebook not sharing an email address, an expired attempt, no internet.
- If the student closes the browser without finishing, the spinner stops by itself after a few seconds.
- Android sometimes closes the app while the browser is open (low-memory phones). The sign-in then finishes when the app restarts: the splash screen notices a session that hasn't been set up on this phone and runs the same data sync as the login screen.
- Android: intent filter for the link; Flutter's own deep-link router is switched off so it doesn't also try to open the link as a page (`AndroidManifest.xml`). iOS: the same URL scheme in `Info.plist`. Desktop builds hide the buttons (there's no way back from the browser there).
- **Settings:** an account that only uses Google/Facebook has no password, so "Change password" becomes "Signed in with Google". Also fixed: the Settings tab added a new sign-in listener every time it opened and never removed it.

**One sign-in pipeline (refactor):** the ~200 lines that ran after a password sign-in (account switching, cloud/local merge, admin check) lived inside the login button. They moved, unchanged, to `lib/services/post_sign_in_service.dart`, and the login button, Google/Facebook sign-in and the splash screen all call it. A Google login can't skip a step that an email login does.

**Bug fixed: one student's learning data could end up in another student's account.** When a different student signed in on the same phone, the app cleared the scores but **not** the BKT topic-mastery model or the "questions already seen" list. The next answer then uploaded the previous student's whole mastery model into the new student's account (`MasteryService.syncToCloud` uploads everything it holds under whoever is signed in), and the new student was steered away from questions they had never seen. The code's own comment said "one student must never inherit another student's model", but nothing called the cleanup. Now both are cleared on the phone only and the new student's own copies are loaded from the cloud (`forgetLocalForAccountSwitch()` in `mastery_service.dart` / `question_selection_service.dart`), from both sign-in and sign-up. The existing `reset()` wasn't usable for this because it would also delete the *new* student's cloud data.

**Database**
- `supabase_social_login.sql` (new): `handle_new_user()`, the trigger that creates each new account's profile, now also reads the name and photo Google/Facebook send. Before, a Google account would have been named after its email address with no photo. Photos are only accepted from Google/Facebook and only over https; names are trimmed to the 80-character limit (a longer name would have made sign-up fail). It also gets a fixed `search_path`, one of the advisor warnings from Session 40. Email sign-ups produce exactly the same profile as before.
- **Applied to the live project** through the Supabase connector (migration `social_login_handle_new_user`, recorded in the project's migration list). A read-back of the function afterwards was blocked by Claude Code's safety check, so it is confirmed by the migration record, not by reading the function.
- `supabase_enforce_email_verification.sql` (**not run yet**, still your launch step 2): now lets Google/Facebook accounts through, and it also revokes `cleanup_expired_verifications()` from the public (the Session 40 advisor note). The check uses `raw_app_meta_data.provider`, which only Supabase Auth itself can write. A sign-up that puts "google" in the user-editable metadata is still refused.
- **Run it before switching Google on.** Without it, someone could pre-create an email/password account for another student's Gmail (skipping the code) and get into that student's account once they use Google. See README "Google and Facebook sign-in", step 0.
- Tested on a local PostgreSQL 18 copy, 9/9 as expected: email sign-up with a verified code → created, name kept; the same code reused → refused; no code → refused; forged "google" in user metadata → refused; Google → created with name and photo; Facebook with a non-https picture → no photo; a 120-character name → trimmed to 80; Facebook with no name → email prefix; triggers run as Supabase's auth role even with EXECUTE revoked; the public can no longer call the cleanup function.
- Checked live: "Confirm email" is off (`mailer_autoconfirm: true`), as this app requires. Removed from the known gaps below.

**Dashboard rebuilt** (`lib/screens/dashboard_view.dart`, which replaces the Home tab's code inside `home_screen.dart`):
- **Today's goal:** questions answered today against a daily goal (10/20/30/50, tap the card to change it, default 20), as a ring, plus **this week's study days** (Mon–Sun). Days before this update are filled in from the current streak, so existing students don't start with an empty week.
- **Continue learning:** the subject studied most recently, at the lowest level not yet passed and the segment the student is on ("Easy · Questions 11–20", "1 of 4 segments passed"). One tap starts it the same way the Quiz tab does; that code moved to `lib/utils/quiz_launcher.dart` so both use one copy. A new student sees "Start here" with the first subject.
- **Daily Challenge** shows "Done" once today's is finished.
- Totals in one compact row; **board-exam readiness** (the ML model's recommended difficulty, weak and strong subjects, unchanged logic) in a cleaner card.
- **Topics to review (new):** the three topics with the lowest BKT mastery (answered at least twice, not yet mastered), with a mastery bar; tapping one opens that subject's study notes. This shows the thesis's learner model on the main screen.
- Shortcuts (Quiz, Cards, Ranks, Badges) and study modules as a swipeable row.
- New small record: questions answered per day (`daily_activity`, last 60 days, on the phone only), written when a quiz or the Daily Challenge finishes. It is cleared on account switch and on progress reset like the rest of the local progress.

**Verification**
- `flutter analyze`: 0 errors, 0 warnings (the 17 info-level notes were there before).
- `flutter test`: 34 pass, 1 skipped (the screenshot harness, which only runs when asked).
- Screenshots reviewed: sign-in with both providers / Google only / 320 px phone, light and dark; the full dashboard on 390 px and 320 px, light and dark, and a brand-new student. No overflows. Two texts cut off on 320 px phones were fixed. The screenshot harness now also loads the ML model and sample BKT data, so the readiness and topics sections are visible in the review images.
- **Not tested end to end:** a real Google/Facebook login. That needs the providers switched on (README steps) and the new APK on a phone.

---

## 2026-10-15 — Session 45: admin panel Settings (separate branch, optional)

You said the admin panel lacking settings was a gap, and asked for it on its own branch so you can take it or leave it. It is on branch `admin-settings`, built on top of `social-login-dashboard` (Session 44), with its own pull request. Merge it to add Settings to the admin panel; close it to keep the admin panel as it is. Nothing else depends on it.

**What it adds:** a fourth admin tab, **Settings** (bottom bar on phones; side menu on wide screens), `lib/screens/admin/admin_settings_screen.dart`:
- **Account:** name, email and an "Administrator" tag.
- **Appearance:** Light / Dark / Phone setting. The admin panel had no way to change the theme before.
- *(The first version also listed the sign-in methods (Email / Google / Facebook) with their on/off status, and the account card showed how the admin signs in. Both were removed in Session 46 at your request: sign-in methods appear only on their own page before signing in, never inside the admin or student screens.)*
- **Security:** Change password (asks for the current one first; hidden for an admin account that has no password), and Sign out.
- **About:** website, support email, version.

**Moved:** on phones, Sign out used to be an icon in the dashboard's top bar; it now lives in Settings, where people look for it. The wide-screen side menu keeps its Sign out button. Both use the same confirm-and-sign-out code.

**Small cleanup:** the version number shown in Settings is now one shared constant (`lib/utils/app_info.dart`) used by both the student and admin Settings, so the two can't disagree. In Session 41 the student Settings was still showing 1.0.0.

**Verification:** `flutter analyze` 0 errors / 0 warnings; `flutter test` all pass; screenshots of the Settings tab (phone, light and dark) and the wide layout reviewed, no overflows.

---

## 2026-10-15 — Session 46: Google / Facebook moved to their own sign-in page

You showed an app-setup page (a title, a short explanation, then large rounded choice buttons and an "I'm already a member" link) and asked for the Google/Facebook choice to look like that: on a page of its own, not inside the student or admin screens, and without Discord.

- **New page, "Decide how you sign in to CrimiReview"** (`lib/screens/sign_in_choice_screen.dart`):
  - It first explains in plain words what happens: one tap with Google or Facebook; the password is typed only on their own page; CrimiReview receives only the name, email address and profile photo; nothing is posted to the account; the same email opens the same account and progress.
  - Below, in a grey band, are two large rounded buttons ("Google (use your Google account)" / "Facebook (use your Facebook account)"). They sit one above the other on phones and side by side on wider screens.
  - A "Use my email instead" link opens the email form, which now has a back arrow.
- **Removed from inside the app:**
  - The email form no longer has the Google/Facebook buttons.
  - The student Settings no longer says "Signed in with Google". For an account without a password, "Change password" is simply not shown.
- **Only Google and Facebook.** No other providers (Discord etc.) are offered.
- **When it shows:** after onboarding, at app start when signed out, and after signing out, but only when Google or Facebook is switched on in Supabase. The app checks that while the logo animates, waiting at most 3 more seconds, and uses the last saved answer when offline. With both off, which is the case today, the app goes straight to the email form as before.
- **One shared "finish sign-in" step for both pages** (`lib/screens/sign_in_completion.dart`). Only the page on top reacts to a new session, so a Google sign-in can never be finished twice. Sign-up and forgot-password, opened on top, still finish their own. After sign-in, every sign-in page is removed from the back stack.
- **Screenshot harness:** it used to report only overflow errors and hid all others. A first version of this page threw during layout and rendered blank, and the harness still passed. It now reports every layout error. The rest of the catalog was re-rendered with it, and the only remaining failure, `quiz_answered`, is older and test-only: the sound player has no audio device in a test. It fails the same way with the previous harness.
- **Checks:** `flutter analyze` 0 errors / 0 warnings; `flutter test` 34 pass; screenshots of the new page reviewed (390 px light/dark, 320 px, Google only, 1280 px wide, and the email form opened from it), no layout problems.
- **Why you don't see the page yet:** you tested in Chrome and saw only the email form. That is expected: Google and Facebook are still switched off in Supabase (checked again: `google: false, facebook: false`), so the app skips the page. It appears once the README steps are done.
- **Web fix found while checking that:** on the web, Google/Facebook sign-in would have returned to Supabase's Site URL instead of the page being tested. It now returns to the address the app runs on (`Uri.base.origin`). README step 3 says which address to add for testing in Chrome.
- **Preview switch:** `flutter run --dart-define=PREVIEW_SIGN_IN_CHOICE=true` shows the page before Google/Facebook are set up, so you can see it now. It carries a "Preview mode" note, and a provider that isn't switched on just says so. It is a build-time switch that is off unless you type it, so the APK you publish can never be in preview mode.

---

## 2026-10-15 — Session 47: three offline fixes

You asked whether every feature works offline. I checked: studying works offline (quiz, Daily Challenge, flashcards, modules, dashboard, progress, achievements, profile edits); sign-in, change password, the leaderboard and the admin panel need internet. I also found three offline problems, which you asked me to fix:

1. **Sign out did nothing visible while offline.** Supabase removes the login from the phone first, then calls the server. Offline, that call failed and the error stopped the app before it went back to the sign-in page. The student was really signed out, but the app looked frozen on Settings. `SupabaseService.signOut()` now skips a failed or slow (5-second) server call. The phone is signed out either way, and the token on the server simply expires.
2. **An admin who opened the app offline got the student screens.** The admin check needs the server, and a failed check counted as "student". The app now remembers the last role the server confirmed **for that account** (`admin_role_cache_v1`) and uses it when the server can't be reached. A role saved for a different account is ignored. This only decides which screens open: every admin action is still checked by the database's own rules (`is_admin()`), so a wrong value on the phone can't unlock anything.
3. **Start-up could hang on Wi-Fi without internet.** Before the first screen appeared, the app waited for the admin check and for uploading results saved offline. Each server call can take up to 25 seconds to give up. Both now run in the background: the admin check starts from the saved role, and the splash screen waits at most 3 more seconds for the server's answer. Pending results upload after the app opens, and the top banner shows the sync as before.

**Checks:**
- `flutter analyze`: 0 errors / 0 warnings. `flutter test`: 34 pass.
- A throwaway test with the server unreachable (every request fails in the test environment) confirmed 3/3:
  - an admin falls back to their saved role;
  - another account's saved role is ignored;
  - sign-out no longer errors and the phone is signed out.
  The old sign-out error is visible in that run's log. The test was deleted afterwards because it needs the live project's settings.
- Not tested on a phone in airplane mode yet.

---

## 2026-10-15 — Session 48: new logo, and the app's colours now follow it

You gave a new logo (white C, red R, graduation cap, scales of justice and an open book, on black) and asked for it everywhere: the app, its colours, the website and anything else that shows the logo. App changes are on branch `new-logo` with their own pull request; the website change is on a `new-logo` branch in `crimireview-landing` with its own pull request. Nothing is live until you merge.

**Logo files** (all made from your image by one script, so they match exactly):
- `assets/icon/logo_original.png`: your logo, kept as the master copy.
- **App icons:** `assets/icon/app_icon.png` + `app_icon_foreground.png`, then `dart run flutter_launcher_icons` regenerated the Android icons (all sizes, plus the adaptive icon on a black background), iOS (all sizes) and, for the first time, **Windows** (`app_icon.ico`) and **macOS**. Those two still had Flutter's default icon.
  - Android launchers cut icons to a circle or rounded square. The adaptive icon keeps a 20% margin, so the whole logo, book corners included, stays inside the safe area: the farthest point is at 0.283 of the size, the limit is 0.306. Checked with a simulated circle and rounded square.
- **In-app logo:** `assets/images/logo_mark.png` (cropped close to the artwork), shown by `AppLogo` on a black rounded tile; it used to be a white tile.
- **Web app:** `web/favicon.png`, `web/icons/Icon-192/512` and the maskable versions (scaled so a round crop doesn't cut the logo); `manifest.json` colours are now black.
- **Removed:** the old navy/gold logo files `logo_original.jpg`, `graduation_cap.png`, `graduation_cap_splash.png`, `splash_logo.png`. Nothing used them, and they are still in git history.

**Colours: navy, blue and gold become the logo's black, red and white** (`AppPalette` in `theme_service.dart`; every screen reads from it):
- The logo's red is the interactive colour (buttons, links, tabs): `#D7101F` in light mode and `#E8192C` in dark mode. Both were checked for readability: white text on them scores 5.3:1 and 4.6:1.
- Hero cards (dashboard goal card, sign-in header, admin question-bank card) go from that red to black.
- Greys are neutral now (the old ones were tinted blue), so black and white look like the logo. Dark mode is near-black.
- Unchanged on purpose: gold for points and achievements, green / amber / red for right / so-so / wrong, blue for information, and each subject's own colour.
- The wordmark is "Crimi" in ink and "Review" in red, like the logo's white C and red R.
- **Splash and launch screens:**
  - The in-app splash is now the logo's black with a soft red glow.
  - The phone's own launch screen (Android, including Android 12+) is black too, so there is no jump in colour when the app starts. It used to be navy.

**Places where red would have meant the wrong thing, fixed:**
- **Quiz:** a tapped answer that hasn't been checked yet showed in the brand colour. In red it would look like a wrong answer before checking. It now shows in ink (black, or white in dark mode); red stays for wrong answers only.
- **Topic mastery bar** under each answer used the brand colour, so a good 72% looked red. It now uses green / amber / red by level, like every other score.
- Achievement progress is now gold (like all achievements). "Subjects attempted" on the results screen is now neutral blue, so it doesn't read as a warning.
- Leftover fixed colours (navy shadow on the logo tile, navy tick on the week strip, gold goal ring, blue first onboarding page, blue snackbar action) were switched to the new palette.

**Website** (`crimireview-landing`, branch `new-logo`):
- New `logo.png`, `favicon.png` and an `apple-touch-icon.png` (iPhone home-screen icon).
- The violet accent became the logo's red, and the navy background became black. The mock phone screenshot uses the same colours.
- A `theme-color` tag makes the phone browser bar black.
- Merging that pull request publishes it through Vercel as before.

**Checks:**
- `flutter analyze`: 0 errors / 0 warnings. `flutter test`: 34 pass.
- All 70 screens re-rendered in light and dark; no layout problems. `quiz_answered` still fails only for the old test-only sound reason.
- The website was rendered in Chrome.
- **Debug APK builds**, and the new launcher icon and logo are inside it (the packaged in-app logo matches the new file byte for byte).

**Laptop problem found while building: VS Code was eating the memory.**
- The first APK build stalled. About 35 Gradle helper programs (Gradle daemons) were running, about 250 MB each.
- They were started by VS Code's Java extensions (`redhat.java`, `vscode-gradle`), not by the build. These extensions kept trying to load `android/` as a Java project: 13 new ones in 45 seconds with nothing building. The 26 `hs_err_pid*.log` crash files in the project folder, all from 2026-09-05, fit this pattern.
- Fix: `.vscode/settings.json` tells those extensions not to load Gradle projects in this folder. Flutter builds don't use them.
- After that, 0 new daemons in 60 seconds, and the build took 121 s instead of 308 s.
- The settings file is local and not committed, so it applies whichever branch is checked out.

---

## 2026-10-16 — Session 49: overflow error fixed, app responsive on phones, tablets and computers

You saw "A RenderFlex overflowed by 5.8 pixels on the bottom" and asked for the app to work on every device, tablets included.

**How the problems were found:** the screenshot tests got a **sweep mode** (`--dart-define=SWEEP=true`, see README). It renders every screen on 12 devices and reports any layout error:
- small phone 320×568, 360×640, 390×844, 430×932;
- a phone held sideways (844×390);
- 7-inch, 10-inch, landscape and 12-inch tablets;
- desktop 1440×900;
- small and normal phones with the system text size at 130%.

The first run found **15 problems on 6 screens**. After the fixes: **0 problems in all 420 renders**.

**The overflows and what fixed each:**
1. **Admin dashboard, the six number tiles** (your error). The tiles had a fixed shape, so on phones 320-360 px wide they were too short for their content: 6.2 px at 360 px wide (yours was 5.8 px), 18 px at 320 px, up to 20 px with larger text. It also showed while the Settings tab was open, because the dashboard stays laid out behind it. The tiles now sit in a new kit component, `AdaptiveGrid`, whose rows are as tall as their tallest tile.
2. **Admin side menu on a short screen** (a phone held sideways), 49 px. The menu couldn't scroll. It now scrolls when needed; "Sign out" stays at the bottom when there's room.
3. **"Decide how you sign in" page, phone held sideways**, 22 px. The fill-the-screen layout measured the text at the full screen width, but drew it in a narrower column, so the page came out too short. Replaced with a layout that needs no measuring: at least one screen tall, explanation on top, choices at the bottom, scrolls if longer.
4. **Sign-up page with larger text**, 2 px. The red header had a fixed height; "Create your account" wrapped to two lines and no longer fit. The header now grows with its text. Normal phones look exactly as before (checked).
5. **Question editor with larger text**, 7 px to the right. A section title couldn't wrap; now it can.

**Tablets and computers:**
- The student app now uses a **side navigation rail** (logo on top, the same five tabs) when the screen is at least 840 px wide and 480 px tall: tablets in landscape, computers and the web. This matches the admin panel. Phones, including a phone held sideways (too short for five rail items), keep the bottom bar.
- The **Home dashboard uses two columns** from about 1000 px: today's goal, continue learning, Daily Challenge, totals and shortcuts on the left; readiness and topics to review on the right. Before, it was one phone-width column in the middle of a large screen.
- The 840 px breakpoint is now one shared constant (`kWideLayoutWidth`) for the student and admin layouts.

**Very large system text:** text now follows the phone's text-size setting **up to 130%**, then stops (`kMaxTextScale`, applied once in `main.dart`). Newer Android phones allow up to 200%, which would push buttons and cards apart on any screen. Every screen is checked at 130% on small and normal phones.

**Screenshot harness:** besides `SWEEP`, it now has `DETAILS=true` (prints which widget overflowed, with file and line) and `ALL_IMAGES=true` (keeps every render, not only the ones with problems).

**Checks:**
- `flutter analyze`: 0 errors / 0 warnings. `flutter test`: 34 pass.
- Sweep: 0 layout problems in 420 renders.
- Reviewed images: tablet landscape (rail + two columns), the smallest phone (admin tiles), the sign-up page at 130% text, and the normal sign-in page (unchanged).

---

## 2026-10-16 — Session 50: exam subjects corrected to the official 2021 table; research for Chapters 1–4

You asked for Chapters 1–4 of the capstone manuscript to be rebuilt precisely, including a study of competing review apps.

**Research done first** (deep research, six tracks). Notes are in `research_notes/CrimiReview capstone chapters 1 to 4/`, and the report is in `reports/CrimiReview capstone chapters 1 to 4.md`. Both folders are kept out of git with `.git/info/exclude`. The six tracks:
- competing CLE and other review apps;
- the Philippine Criminologist Licensure Examination;
- the adaptive-learning literature;
- mobile learning, gamification, local studies and data privacy;
- methodology and evaluation standards;
- a code-checked audit of the Oct 7 manuscript draft (61 findings).

**App fix found by that research: the six subjects showed the wrong weights.**
- `lib/models/subject.dart` said "2026 PRC Board Exam subjects with actual weights" but held the RA 11131 Sec. 15 table from 2018.
- The official table since the 2nd exam of 2022 is PRC Board of Criminology Resolution No. 01, s. 2021, confirmed by the PRC Program of Examination for February 4–6, 2026:

  | Subject | Weight |
  |---|---|
  | Criminal Law and Jurisprudence | 20% |
  | Law Enforcement Administration | 15% |
  | Crime Detection and Investigation | 20% |
  | Forensic Science | 15% |
  | Criminology | 20% |
  | Correctional Administration | 10% |

- Fixed:
  - Names: "Criminal Jurisprudence" is now "Criminal Law and Jurisprudence", and "Criminalistics" is now "Forensic Science".
  - Short names, the component-course descriptions and the weights. LEA 20→15, CDI 15→20, Criminology 15→20, Forensic Science 20→15.
  - The two study-module titles that used the old names.
- The internal subject ids (`criminal_jurisprudence`, `criminalistics`, ...) are unchanged. Saved progress, the question bank and the cloud tables use them, so no data moves.
- The weights are shown to students ("% of exam") but no calculation uses them.
- **Not changed:** the bundled readiness model was trained with a 50% per-subject floor, while the law says no subject below 60%. Fixing that means retraining the model. It is noted as a limitation for the manuscript.

**Checks:**
- `flutter analyze`: 0 errors / 0 warnings. `flutter test`: 34 pass.
- Screenshot sweep: 0 layout problems in 420 renders (the longer subject name fits everywhere).

---

## 2026-10-16 — Session 51: Chapters 1–4 manuscript rebuilt from the Session 50 research — no app code touched

Published to the same manuscript page as before: https://claude.ai/artifact/5dtwfNPojdeZoCnhjy9RvB (version 19). The page's own "Revision notes — October 16, 2026" section lists every change and every open item; the main ones:

- **Facts corrected against the code and PRC sources:**
  - Subjects and weights now follow Res. No. 01, s. 2021 (Table 1). National results from June 2022 to August 2026 were added (Table 2).
  - The removed PDF/AI question generator is gone from every chapter. Template generation is described exactly, including its 21-question ceiling.
  - "Adaptive difficulty" was corrected: students pick unlocked levels, and BKT steers which questions appear.
  - "No machine learning" was replaced by a description of the readiness model.
  - Android 7.0 (API 24), not Android 10.
- **Chapter 1:** added Statement of the Problem, Significance of the Study and Definition of Terms. The limitations now list the real ones.
- **Chapter 2:** unverifiable sources were replaced with verified ones. A Review of Related Systems compares competing CLE review apps in a dated feature matrix (Table 3).
- **Chapter 4:** all twelve activity diagrams were redrawn to match the app as built. Sections 4.8 Development Model, 4.9 Testing, 4.10 Evaluation Method (ISO/IEC 25010:2023, SUS), 4.11 Results and Discussion (placeholders) and 4.12 Implementation Plan were drafted.
- **Numbering:** Tables 1–30 in page order (the old Tables 1–12 are now 8–19). Figures 1–16 keep their numbers; Figure 17 is new.
- **References:** one APA 7 list for all four chapters (145 entries, plus 8 legal bases and official issuances listed separately). 16 references that could not be verified were removed.
- **Open items for the team** (also listed on the page):
  - adviser name and title-page date;
  - Chapter 4 heading per the manual;
  - six items tagged "verify";
  - evaluation results and Scrum roles, which are placeholders;
  - five exam results sourced from an aggregator;
  - the readiness model's 50% subject floor.
- The untracked `docs/manuscript_*.md` files are older drafts and are now out of date. The published page is the current manuscript.

---

## 2026-10-16 — Session 52: Google and Facebook icons under the email sign-in form

You asked for Google and Facebook icons below the log-in form, in the style of a sample screen but keeping CrimiReview's own design, on a separate branch (`login-social-icons`, stacked on `new-logo`).

**What changed:**
- **New `lib/screens/social_sign_in_icons.dart`.** It sits under the Sign in / Create account button and shows:
  - an "or continue with" line;
  - a rounded tile with just the Google logo and one with just the Facebook logo, in the app's own card style, light and dark;
  - a short note: "Your password stays with Google or Facebook. CrimiReview only receives your name, email address and profile photo."
  - The tiles have no text, so screen readers and a long press say "Continue with Google / Facebook".
- **How a tap works.** It uses the same sign-in path as the "Decide how you sign in" page:
  - `SocialAuthService.start`, which keeps PKCE and Google's account chooser;
  - then `SignInCompletion` and `PostSignInService`. That step does the account-switch cleanup, the cloud sync and the admin/student role check.
  - So the email button, the choice page and the icons all finish a sign-in the same way.
- **Only providers switched on in Supabase are shown,** the same rule as the choice page. While both are off, which is the case on 2026-10-16, the page looks exactly as before. `--dart-define=PREVIEW_SIGN_IN_CHOICE=true` shows the icons for a preview.
- **Guarded against double sign-ins:**
  - the icons are disabled while the email button signs in, and while a Google/Facebook sign-in is being finished;
  - a cancelled or failed browser sign-in shows its reason under the icons;
  - coming back from the browser without finishing stops the spinner after 4 seconds.
- **`SocialAuthService.start` now checks the connection first.** Offline, it says "You're offline. Connect to the internet to sign in with Google." instead of opening a browser page that can't load. This also applies to the choice page.
- Comments that said Google/Facebook appear only on the choice page were corrected: `auth_screen.dart`, `sign_in_choice_screen.dart`, `admin_settings_screen.dart`, `social_auth_service.dart` and README.

**Checked on the live project (2026-10-16):**
- Google and Facebook are still switched off in Supabase.
- `supabase_enforce_email_verification.sql` was not installed, so you ran it in the SQL Editor the same day. It stops anyone from pre-creating an email/password account for another student's Gmail address, which Supabase would later join to that student's Google sign-in.
- Checked on the live database afterwards:
  - the `require_verified_email_before_signup` trigger is on (BEFORE INSERT on `auth.users`), and its code matches the file;
  - nobody outside the database can run `require_verified_email()` or `cleanup_expired_verifications()`;
  - the Supabase security advisor no longer flags `cleanup_expired_verifications`.
- The app's own sign-up verifies the emailed code before creating the account, so it is compatible with the trigger. Still to do: one real sign-up in the app to confirm.

**Checks:**
- `flutter analyze`: 0 errors, 0 warnings.
- `flutter test`: 46 pass, 12 of them new:
  - 6 for the icons: hidden when off, one or both providers, disabled while busy, the "finishing" message, hidden on Windows;
  - 6 for log-in and sign-up with the icons on 320, 360 and 412 px phones.
- Screenshot sweep of every sign-in screen on 12 devices (phones, tablets, desktop, 130% text): 84 renders, 0 layout problems.

---

## 2026-10-17 — Session 53: the Google and Facebook icons are always on the log-in page

You ran the app, didn't see the icons (Google and Facebook are still switched off in Supabase, so Session 52 hid them), and chose to always show them.

**What changed** (`lib/screens/social_sign_in_icons.dart`, same branch, PR #5):
- **On Android, iPhone and the web, the log-in page always shows** "or continue with", the Google and Facebook icons, and the note about what they share. This is on both the Sign in and Create account tabs. Nothing is needed in Supabase, and no preview setting.
- **Tapping a provider that isn't switched on yet:**
  1. The icon spins while the app checks Supabase again, in case it was just switched on.
  2. If it's still off, it says "Google sign-in isn't available yet. Please sign in with your email." No browser page opens.
- **Once a provider is switched on,** the same tap opens its sign-in page, as in Session 52.
- **Unchanged:**
  - The desktop apps still don't show the icons; they can't receive the browser's answer.
  - The "Decide how you sign in" page still appears only once a provider is switched on. You chose to keep it on 2026-10-17.
- Comments, README and tests were updated to match.

**Checks:**
- `flutter analyze`: 0 errors, 0 warnings.
- `flutter test`: 45 pass. One icon test was replaced, because "hidden while switched off" no longer applies, and a new one covers the "isn't available yet" message.
- Sweep of every sign-in screen on 12 devices: 72 renders, 0 layout problems.

---

## 2026-10-17 — Session 54: "Decide how you sign in" page removed

You asked to remove the separate "Decide how you sign in" page, because students already know they can sign in with Google or Facebook from the icons on the log-in page.

**What changed** (same branch, PR #5):
- **Deleted `lib/screens/sign_in_choice_screen.dart`.** Every place that opened it now opens the log-in page directly:
  - the splash screen;
  - the end of onboarding;
  - signing out from student Settings, the Admin Panel's Settings tab and the admin side menu;
  - the "Sign in" button in Settings.
- **Faster start when signed out.** The splash screen no longer waits up to 3 seconds to ask Supabase which providers are on; that question existed only for the deleted page. The icons on the log-in page ask on their own, and again on a tap if needed.
- **Log-in page header back to its original look.** The back arrow existed only for returning to the deleted page, so it was removed.
- **The `PREVIEW_SIGN_IN_CHOICE` preview setting is gone,** since the icons are always shown and need no preview. The VS Code run option for it was removed too.
- **Shared sign-in code tidied** (`sign_in_completion.dart`): the error hook only the deleted page used was removed. Browser errors are shown by the icons.
- Comments and README updated. The deleted page's five screenshot shots were removed from the screenshot catalog.
- **Manuscript updated** (same page, version 20). These passages no longer describe the deleted page:
  - Chapter 3, 9.2;
  - Table 14 (Log In);
  - Section 4.12 and Tables 20, 29 and 30.
  - The release status now also says the email-verification rule was applied on October 16, and that #5 is pending merge. A dated note was added to the revision notes.

**Checks:**
- `flutter analyze`: 0 errors, 0 warnings.
- `flutter test`: 45 pass.
- Splash, onboarding, sign-in and settings screens re-rendered in light and dark: no layout problems.
- Sign-in and onboarding swept on 12 devices: 48 renders, 0 problems.

---

## 2026-10-17 — Session 55: Privacy Policy and Terms of Service pages on the website (for Google and Facebook sign-in)

You were setting up Google sign-in. In Google Auth Platform, **"Publish app" stayed greyed out** ("you must complete your configuration on the Branding page"). Publishing needs a home page and privacy policy link on an authorized domain, and the website had neither. Facebook also requires a privacy policy and data deletion instructions before its sign-in can go live.

**What changed:**
- **Website** (repo `crimireview-landing`, branch `privacy-terms`, **website PR #2**, merge after website PR #1):
  - new pages `privacy.html` and `terms.html`, styled like the site;
  - Privacy / Terms links in the footer.
- **Privacy policy:** written from what the app and database really do. It covers:
  - what is collected (including answer times and seen questions) and what isn't (no location, contacts, ads or third-party analytics);
  - who sees what: the leaderboard shows name, photo, points and rank; faculty see name, email, points and mastery, read-only; profile photos have public links;
  - service providers: Supabase (Singapore, as the project's region `ap-southeast-1` confirms) and Resend;
  - how to delete your data (`#delete-your-data`, for Facebook);
  - the rights under RA 10173.
- **Terms of service:** not affiliated with the PRC; content may contain mistakes; no guarantee of passing; fair use; Philippine law.
- **README updated** with the exact links to type into Google (home page, privacy, terms, authorized domain `crimireview.app`) and Facebook (privacy, terms, data deletion).

**Still to do (you):**
- Check that **support@crimireview.app receives mail**; deletion requests go there.
- Keep the **30-day** deletion promise only if the team can honour it.
- Have your adviser look at the two pages. They were drafted by an AI assistant and are not legal advice.
- Merge website PRs #1 and #2.
- Fill in Google's Branding page with the links, then **Publish app**. Meanwhile, Google sign-in works for **test users** you add in Audience.

**Checks:** pages rendered in Edge at 1280, 390 and 320 px wide: no horizontal scrolling, and the links work.

---

## 2026-10-17 — Session 56: full pre-release audit, and fixes

You asked for a full audit before uploading the new version: sign-in and sign-up, every module, database rules and API permissions, exposed keys, layout on all devices, links and missing pages, error and loading states, slow internet, invalid input, and many users at once. Fixes are on branch `audit-fixes` (app) plus website PR #3. The database part is the new file `supabase_audit_fixes.sql`, which has to be run in the SQL Editor.

### What was checked
- **Secrets:** all tracked files and the whole git history. The only key in the app is the public `anon` key (its token says `"role":"anon"`), which is meant to be public. No service key, Resend key, Google/Facebook secret or signing key anywhere.
- **Live database:** every table's row-level security, every policy, grants, both views (both run with the caller's permissions; the student overview returns rows to admins only), every server function's permission checks, storage buckets (avatars: images only, 2 MB), constraints, indexes, and the Security Advisor.
- **App:** every screen's loading, error and empty states; network time limits (25 s per request, 2 min for photo uploads, already in place); inputs; double taps; the offline queue; start-up; links; Android manifest and build settings.
- **Website:** every link, the download redirect (the current APK is 60 MB).
- **Layout:** every screen on 12 devices (phones 320–430 px, landscape phone, 7–12" tablets, desktop, 130% text): 396 renders, 0 problems.

### Fixed: database (`supabase_audit_fixes.sql`, run it once)
1. **A student could have been promoted to admin in a teacher's place (high).**
   - "Make admin" looked accounts up by `user_profiles.email`, which every student can edit on their own row through the API.
   - Now a profile's email is always copied from the sign-in email by a trigger, and "Make admin" searches `auth.users`.
   - No profile email differed from its sign-in email on 2026-10-17.
2. **A profile photo could point at any web address (medium).** That address would load on every student's leaderboard, so the site behind it could log their addresses or show anything. Now only the student's own uploaded photo, or a Google/Facebook photo, can be saved.
3. **A password reset now signs the account out on every device (medium).** Before, an old session stayed valid after the reset.
4. **The internal email functions (schema `private`) can only be run by the database.** They weren't reachable from the app before (no access to the schema); this removes the leftover default permission.
- Checked first, with a test that undid itself completely: a trigger fires even when ordinary users lack permission to run its function. So the trigger installed in Session 52 does not block sign-ups, and the new one won't either.

### Fixed: app
5. **Quiz results could be saved twice (high).**
   - "See results" waited for up to four server uploads (25 s each on slow internet) while the button still worked, so a second tap counted the quiz twice: double progress and points on the phone.
   - Now the button is locked with a spinner, the result is saved on the phone first, and the upload runs in the background, one quiz after another in order. "Check answer" can't record an answer twice either.
6. **Daily Challenge skipped a question (high).** After the timer ran out, the app moved on by itself 2 s later. Tapping "Next" in those 2 s moved on twice, skipping a question that then counted as unanswered. On the last question, the two could also save the score twice on the phone. Both fixed; the score upload also runs in the background.
7. **Study reminders never appeared on Android 13 and newer (high).**
   - The permission request existed but was never called.
   - Now the app asks once when Home first opens, and again when reminders are switched on in Settings. If the student refuses, the switch stays off with an explanation instead of showing "On".
8. **Reminders would have arrived at 5 PM and 3 AM.** The scheduler's time zone was never set, so "9:00" and "7:00 PM" were UTC. Now they're built on the phone's clock (`NotificationService.nextReminderTime`, with tests).
9. **Sign-up said "Could not create your account" when the account had been created.**
   - This happened if the progress upload after sign-up was slow. Retrying then failed with "No pending verification found".
   - Now that upload can't fail sign-up, and a retry after a failed account step doesn't re-check the already-used code.
10. **Clearing "School" on the Profile screen was never saved online.** Empty was sent as "no change", so the old school came back at the next sign-in. Fixed.
11. **The Profile "Email (optional)" field suggested you could change your sign-in email.** It only saved on the phone and was overwritten at the next sign-in. Signed in, it now shows the sign-in email, read-only, with a short note.
12. **No in-app link to the Privacy Policy or Terms.** Added to student Settings (Support) and admin Settings (About).
13. **First start without internet said "No easy questions available".** It now says the questions need one download: "Connect to the internet once…".

### Fixed: website (PR #3 on `crimireview-landing`)
14. **The home page claimed things the app doesn't have.**
    - "1000+ questions" is now "750+": 760 are active.
    - The outdated subject list is replaced by the six official CLE subjects.
    - "Our AI tracks…" now describes what the app actually does.

### Not fixed: decisions or settings for you (see the end of this list)
- **Leaderboard points are reported by the app.** A technically skilled student could raise their own points through the API. No one else's data is exposed. A real fix means scoring answers on the server, which is a larger change.
- **The APK is signed with this laptop's debug key.** If the laptop is reset, no update can be installed over the old app. Create a permanent release key before more students install it; existing installs would need one reinstall.
- **Supabase Free plan:**
  - the project is paused after 7 days without activity;
  - backups can't be downloaded;
  - sign-ins are limited to bursts of about 30 per network address, so a whole class on one school Wi-Fi may need to retry after a minute.
- **Resend free plan:** 100 emails a day (sign-up and reset codes).
- **Optional in the Supabase dashboard:**
  - "Prevent use of leaked passwords" (Authentication), if your plan has it;
  - the 3 old test accounts from May 23 without profiles can be deleted.
- **Smaller items:**
  - passwords are capped at 16 characters in the app (the server allows 72);
  - Google Play would require target API 36 (the website APK doesn't);
  - reminders after a phone restart return only once the app is opened;
  - the leftover `document-uploads` storage bucket can be deleted;
  - `crimireview.app/privacy` without `.html` shows 404.

**Checks:**
- `flutter analyze`: 0 errors, 0 warnings, the same 17 style notes as before.
- `flutter test`: 49 pass, 4 of them new for the reminder times.
- Changed screens re-rendered and swept on 12 devices: 132 renders, 0 problems.
- `quiz_answered` still fails in the test harness only, from the missing audio plugin, exactly as on `main` before the changes.

---

## 2026-10-17 — Session 57: Facebook sign-in removed; Google only. Audit SQL confirmed live

You asked, before the release, to remove the Facebook sign-up and keep only Google.

**Audit SQL first.** You ran `supabase_audit_fixes.sql`, and PR #6 and website PR #3 are merged. All four database fixes are live. A test that undid itself afterwards, acting as a real signed-in student, confirmed:
- trying to change the profile email left it unchanged;
- an outside photo address was rejected ("Profile photo must be uploaded through the app.").

**What changed** (branch `google-only`):
- **App:**
  - `SocialProvider` now has only `google`, and the `FacebookLogo` widget was removed;
  - the log-in page shows one centred Google icon and "Your password stays with Google…";
  - comments, the Android manifest and the iOS `Info.plist` notes now say Google only;
  - a phone that still has "facebook" in its saved provider check simply ignores it (covered by a test).
- **Tests:** the icon tests now check that only Google appears and that the word "Facebook" is nowhere on the page.
- **README:** the Facebook setup steps were removed, and the README says to keep the Facebook provider switched off in Supabase.
- **Website** (`crimireview-landing`, branch `google-only`, website PR #4): the Privacy Policy no longer mentions Facebook.
- **Left as is, harmless:** the database functions still recognise a "facebook" provider (sign-up exemption, name and photo, photo hosts). With Facebook switched off in Supabase, no Facebook account can be created, and there are none (checked).
- **Manuscript:** it still says "Google or Facebook" in 47 places, including Figures 2–4. It will be updated together with the release status after version 1.0.2 is published.

**Checks:**
- `flutter analyze`: 0 errors, 0 warnings.
- `flutter test`: 49 pass.
- Sign-in screens re-rendered and swept on 12 devices: 36 renders, 0 problems.

---

## 2026-10-18 — Session 58: concept bank screen, four question forms per concept, approve-selected (branch `concept-bank-and-forms`)

**The problem you raised.** Template generation was a hassle for Faculty: a concept made exactly one question, so the 21 seeded concepts meant 21 questions, ever. Concepts could only be added with SQL, so Faculty could not feed the generator at all.

**Found while checking it (a real bug):** the "N available" number on the Generate screen could be wrong. The old generator picked concepts at random without skipping used ones, so asking for exactly the "2 available" created 0 or 1. Reproduced on a local PostgreSQL 18 copy (6 trials: 1, 1, 0, 1, 0, 1 created for "2 available").

**What changed**
- **New SQL file `supabase_concept_bank.sql`** (run it in the SQL Editor after `supabase_template_generation.sql`; safe to re-run; ends with a rollback block):
  - **Four question forms per concept** (new `question_templates.form` column): term to definition (the existing one), definition to term, legal basis to term, term to legal basis. The four topics already in the database keep their hand-written template and gain the other three, so the same 21 concepts can now make up to **74 questions** (21 + 21 + 16 + 16).
  - **One shared rule** for "which concepts can still make a question" (`template_eligible` / `template_candidates`), used by both the generator and the status view. Asking for exactly the number shown now always creates that many (tested: 71 asked, 71 created, 0 mismatches; asking again creates 0).
  - **Safety rules in the generator:** at least 2 wrong options (3 options total); wrong options never repeat the correct text; the two legal-basis forms are used only for a group in which every concept has its own legal basis and no basis equals or contains another. Without that rule, "which is covered by RA 6975?" would have two right answers in the PNP/BJMP group; that group correctly gets 0 for the two basis forms.
  - **Text is filled with `replace()`, not `regexp_replace()`**, so a backslash or `&` typed into a definition stays literal.
  - A question typed by hand with the same text also counts as "already has one", the same comparison the database already uses to refuse duplicates.
  - **Faculty tools (all admin-only, validated, audit-logged):** `admin_save_concept` (add/edit), `admin_set_concept_active`, `admin_import_concepts` (up to 200 rows; valid rows are saved and refused rows come back with the reason), `admin_approve_generated`. Topic spelling is matched ignoring case, so "justifying circumstances" cannot create a second, empty topic. Adding a concept to a new topic creates its four templates automatically.
  - Audit entries use the actions the dashboard already labels (create, update, delete, restore, generate); no new action names.
- **App:**
  - New **Concepts** screen (Questions toolbar book icon, or "Manage concepts" on the Generate screen): concepts grouped by subject and topic, search, subject filter, add/edit/deactivate/restore, and a per-topic note saying whether it is ready for questions and why the legal-basis forms are off.
  - New concept form and a **paste import** screen (rows copied from Excel or Word, Tab or `|` separated, header row skipped, quotes removed). It shows what will be imported and which lines will be skipped, with reasons, before anything is sent.
  - **Generate screen** rebuilt around topics: four cards per topic with the form's name, "Generate all (N)", and clear text when a form is not available yet.
  - **Approve selected** in the generated-questions list: tick the questions you have read, press Approve. There is deliberately no "approve everything pending", because a generated question that was deactivated on purpose looks the same as one still waiting. Only ticked questions that are generated and still inactive are switched on; a hand-written draft in the list is left alone.
- Files: `supabase_concept_bank.sql`, `lib/models/concept.dart`, `lib/services/concept_service.dart`, `lib/utils/concept_import_parser.dart`, `lib/utils/concept_rules.dart`, `lib/screens/admin/admin_concepts_screen.dart`, `admin_concept_editor_screen.dart`, `admin_concept_import_screen.dart`, `concept_subject_topic_fields.dart`; changed `question_generation_service.dart`, `admin_service.dart`, `admin_template_generation_screen.dart`, `admin_questions_screen.dart`, README.

**Checks**
- **Database, on a local PostgreSQL 18 copy of the real schema and seed (old generator first, then the new file twice):**
  - all 74 generated questions are inactive, generated, have 3 to 4 options, exactly one correct, no duplicate options, no empty reasons, no leftover `{{`;
  - every question traces back to exactly one source concept, the correct option is that concept's answer, every wrong option comes from a sibling, and no wrong option overlaps the key's legal basis;
  - 76 explicit pass/fail checks: students and logged-out users are refused by every tool, internal helpers cannot be called directly, duplicates and invalid text are refused, import row numbers are right, approval touches only the selected generated questions, students see approved questions and not pending ones, audit rows are written;
  - 3 questions made by the OLD generator are recognised as already used after upgrading.
- **App:** `flutter analyze` 0 errors, 0 warnings (the same 17 style notes as before). `flutter test`: 80 pass (31 new: 20 for the paste parser, 11 for the legal-basis and readiness rules). New screens rendered in light and dark and swept on 12 device profiles: 96 renders, 0 layout problems. Three layout problems seen in the first renders (cramped buttons, cut-off helper text, import preview below the fold) were fixed.

**Not done, and not claimed**
- A "which is NOT…" form: it needs a different data model (concepts from outside the group), so it was left out rather than faked.
- **Not run on the live project yet:** you have to run `supabase_concept_bank.sql` in the SQL Editor, and the app changes need the new APK. Until the SQL is run, the new Concepts and Approve screens will show errors.
- Each form still depends on enough concepts: a group needs 3 or more, and the legal-basis forms need a distinct legal basis on every concept. Faculty still have to enter the concepts; this only multiplies what each concept gives.
- Questions of the form "legal basis to term" and "term to legal basis" are hard memorisation items; Faculty review each one before it reaches students.
- The manuscript still describes the old one-question-per-concept ceiling (21) and has not been updated.

---

## 2026-10-20 — Session 59: upload a CSV file of concepts for many topics; topics are created automatically (same branch)

You asked for teachers to upload their concepts as a file, with the topics made automatically. The Session 58 import took pasted rows for **one** topic chosen on screen. Now a CSV file can hold the whole concept bank, with the subject and topic of every concept in the file.

**How it works**
- **Concepts → upload icon** (or the link "Have a CSV file with many topics?" on the paste screen) opens **Upload a CSV file**:
  1. "Get the template" shares a ready-made file (header row + three seeded RPC Art. 11 examples).
  2. "Choose CSV file" opens the phone's file chooser.
  3. A preview, then Import.
- **Columns:** `subject, topic, term, definition, legal_basis` (optional), `group` (optional).
  - Subject accepts the app's names, short names, ids, the 2018 names and the common abbreviations (CLJ, LEA, CDI). An unknown subject skips only that line.
  - A topic not yet in the bank is **created automatically**, with its four question forms. An existing topic is matched ignoring letter case and extra spaces.
- **The preview** shows, before anything is sent:
  - how many concepts in how many topics, and how many topics are new;
  - each topic with "New topic", "+N concepts", and whether it will be **ready for questions** (all four forms, term and definition forms only, or not yet because a group needs 3 concepts);
  - every skipped line with its **line number** and reason;
  - columns that are not used.
- **Lines that are skipped:**
  - a term already in that topic, including deactivated ones, as the database does;
  - a term repeated in the file, or a definition repeated in the same group;
  - a field that is too short or too long, or contains `{{ }}`;
  - a topic with several groups but no group given;
  - an invalid group name.
- **Import:** one request per topic and group, at most 200 rows each, through the existing `admin_import_concepts`. **No new SQL**: it uses `supabase_concept_bank.sql` from Session 58.
  - Rows the database refuses are reported with their line in the file.
  - A topic that fails (for example, no connection) doesn't stop the others.
  - Uploading the same file again is safe: rows already saved are skipped.
  - The result screen offers **Generate questions**, which opens the Generate screen.
- **Reading real files:**
  - quoted cells with commas, line breaks and doubled quotes;
  - comma, semicolon or Tab as the separator;
  - UTF-8 with or without Excel's mark, UTF-16, and Excel's older Windows character set (so ñ and curly quotes survive).
  - Limits: at most 1,000 concepts and 2 MB per file. Only `.csv` or `.txt` files are accepted; an Excel `.xlsx` gets a message explaining how to save as CSV.

**Files:** new `lib/utils/concept_csv.dart`, `lib/screens/admin/admin_concept_csv_import_screen.dart`, `test/concept_csv_test.dart`. Changed: `concept_service.dart` (`importCsvPlan`), `admin_concepts_screen.dart` (upload button), `admin_concept_import_screen.dart` (link), screenshot catalog, README, `pubspec.yaml`.

**New package:** `file_picker` 11.0.3, for choosing the file. It adds no Android permission, only the system file chooser.

**Checks:**
- `flutter analyze`: 0 errors, 0 warnings (the same 17 style notes).
- `flutter test`: 112 pass, including 32 new for the CSV reader and import:
  - template round trip; quotes and line breaks; separators; character sets; header names; subjects; topics and groups; duplicates; field rules; line numbers; readiness; the 1,000 limit;
  - a 450-row topic sent as 200 + 200 + 50, with refused rows mapped back to file lines and a failed topic not stopping the rest.
- New screen rendered in light and dark. Concept screens swept on 12 devices: 120 renders, 0 problems.

**Not done:**
- **Not tried on a phone or against the live database yet.** The database part needs `supabase_concept_bank.sql` (Session 58), which has not been run live. Until then, the upload's Import fails like the other concept tools.
- An APK has not been built with the new `file_picker` package.
- Excel `.xlsx` files are not read directly: save as CSV first.

---

## 2026-10-21 — Session 60: Faculty can open a student's full record (branch `student-record`, stacked on `concept-bank-and-forms`)

You asked that tapping a student's stats row (Mastered, Needs review, Tracked, Last active) in **Admin Panel → Students** show that student's record: their progress and which difficulty they have reached.

**Found first:** Faculty could not see levels or quiz history at all. `user_progress` (levels and segments) and `quiz_results` only let a student read their **own** rows. Only `topic_mastery` was readable by admins, which is all the Students list used.

**What changed**
- **New SQL file `supabase_student_record.sql`** (run it in the SQL Editor; safe to re-run; one-line undo in its header). It adds one function, `admin_student_record(user_id)`:
  - **read-only** (marked STABLE; it writes nothing), and it checks `is_admin()` itself;
  - returns, in one call: the profile, every subject's progress with the 4 segments of each level, every topic's mastery (weakest first), the 30 most recent quizzes, and counts of quizzes, Daily Challenges and badges;
  - **no table rule is changed**: students still read only their own rows, and nobody can change a student's data through it.
- **App:**
  - **Students:** tapping a student card (the stats row now ends with a `›`) opens the record. The card's height is unchanged, so the two-column tablet layout still fits.
  - **New record screen** (`admin_student_record_screen.dart`):
    - **Summary:** points, rank, quizzes, accuracy, streak, last active, mastered, needs review, Daily Challenges, badges, questions answered, best streak, join date.
    - **Level reached:** all six subjects in official order. Each says "Not started", "On Easy", "On Medium", "On Hard" or "All levels passed", and shows the 4 segments of every level: green = passed (10 answered, 75% or more), amber = tried but not passed, grey = not tried; a level not yet open says "Locked". The rule is the same gate as the student's difficulty sheet (Medium after all 4 Easy segments, Hard after all 4 Medium).
    - **Topic mastery:** weakest first, with the percentage, a bar, and Mastered / Needs review / band. "Mastered" and "Needs review" use exactly the rules behind the Students list's counts, so the two screens agree.
    - **Recent quizzes:** subject, level, score, correct out of total, when.
    - A note that the figures are read-only and come from the student's phone when it syncs.
- Files: new `supabase_student_record.sql`, `lib/models/student_record.dart`, `lib/screens/admin/admin_student_record_screen.dart`, `test/student_record_test.dart`; changed `admin_service.dart` (`studentRecord`), `admin_students_screen.dart`, screenshot fakes and catalog, README.

**Checks**
- **Database** (local PostgreSQL 18 copy, file applied twice): 18 of 18 checks pass. An admin gets the right profile, subjects, segments, mastery (only that student's, weakest first), the 30 newest of 35 quizzes, and the counts. A student with no data gets empty lists. A student is refused, even for their own record. A logged-out visitor has no access. An unknown or empty id is refused. Nothing is written.
- **App:** `flutter analyze` 0 errors, 0 warnings (the same 17 style notes). `flutter test`: 127 pass, 15 new: segment reading (always 4, bad data ignored, correct never above answered), the level gate (including "10 answered is required, not just 75%"), totals, the mastered and needs-review rules, unknown difficulty, last active, an empty response.
- Record screen and Students list rendered in light and dark and swept on 12 devices: 36 renders, 0 layout problems.

**Not done, needs you**
- **Run `supabase_student_record.sql`** in the SQL Editor. Until then, opening a record says it couldn't be loaded.
- **Update the website Privacy Policy before releasing this.** It says Faculty see "name, email, points and mastery, read-only". With this screen, Faculty also see each student's level progress and quiz history (still read-only).
- The figures are what the phone last synced. A student who studied offline appears up to date only after their phone reconnects.

**Fix, same day: "Couldn't load the record" on the live project.**
- **What you saw:** after running `supabase_student_record.sql`, every record showed "Couldn't load this student's record. Please try again."
- **The cause, checked on the live database:** the function exists, but calling it failed with `column r.created_at does not exist`. On the live project, `quiz_results` (and `daily_challenge_scores`) store the time in a column named **`completed_at`**. The live tables were created from the first schema (commit `847b1eb`), and `supabase_schema.sql` in the repo names it `created_at`. My local test copy was built from the repo file, so it passed there.
- **The fix (`supabase_student_record.sql`):** the quiz time is read from the row as JSON, `completed_at` first and then `created_at`, so the function works with either name and never names a column that may not exist. The result still uses the key `created_at`, so the app already installed needs no rebuild for this.
- **Checks:**
  - the old version reproduces your exact error on a `completed_at` table;
  - the new version passes all 18 checks on both table layouts;
  - on the live data, run as a read-only query with no changes (counts only, no personal details), it returns all 24 of the student's quizzes, each with a time.
- **App:** a database error is now shown as itself, with what to do (for example "The database could not build this record (error 42703). Run the latest supabase_student_record.sql…"), instead of a "try again" that retrying could never fix. Connection problems still say "No internet". 3 new tests (130 pass).
- **You need to:** run the updated `supabase_student_record.sql` in the SQL Editor once more. It replaces the first version.
- Nothing else in the app reads those time columns; the app only inserts into these tables, so it is not affected.

---

## 2026-10-22 — Session 61: branch `adaptive-focus` — the question generator and the Concepts screens removed from the app

You asked for a separate branch without the two Admin Panel features **Generate from Templates** and **Concepts**, so the system and the defense focus on how the adaptive learning works. You can switch back if the panel asks for them.

**Where things are now**
- **`adaptive-focus`** (new, made from `student-record`): the app without the generator and the Concepts screens. It keeps the student record screen (Session 60), which shows each student's level reached and mastery and supports the adaptive explanation.
- **`student-record`** and **`concept-bank-and-forms`**: unchanged, with both features. Switching back is `git switch student-record` (or `concept-bank-and-forms`), then `flutter pub get`.

**Removed from the app (everything connected to the two features was traced first)**
- **Screens:** Generate from Templates; Concepts list; concept form; paste import; CSV upload; the shared subject/topic fields.
- **Services and logic:** `question_generation_service.dart`, `concept_service.dart`, the `Concept` model, `concept_import_parser.dart`, `concept_rules.dart`, `concept_csv.dart`, and `AdminService.approveGenerated`.
- **Admin → Questions:**
  - the two toolbar buttons (Concepts, Generate from templates);
  - the "Generated only" filter and the tick-to-approve bar;
  - the deep link that opened one generated batch.
  - Compared with `main`, the screen now differs only by these removals.
- **Dashboard:** the "Auto-generated" tile is replaced by **"Topics mastered"**, the number of topics students have mastered according to the BKT model. Six tiles keep the grid even.
- **Package `file_picker`** (only the CSV upload used it): removed from `pubspec.yaml`, `pubspec.lock` and the macOS plugin list, restored exactly to `main`'s versions of those three files.
- **Tests:** the 63 tests of the removed code (paste parser 20, rules 11, CSV 32), and the screenshot fakes and screens for them.
- **README:** the Admin Panel description, steps 7 and 12 (marked optional, generator only), and a new "Question generation" section explaining this branch and how to switch back.

**Not changed, on purpose**
- **The database.** No SQL was run and no tables or functions were dropped, so switching back needs no database work. The SQL files stay in the repo, marked optional.
- **Questions the generator made earlier** (14 on the live project on 2026-10-21: 5 active, 9 inactive) stay in the bank. Active ones are served to students like any other question, and the admin list still labels them "generated", because that is where they came from. An inactive one can still be switched on with **Restore** in its menu.
- `AdminService.listQuestions` keeps its `source` / `templateId` parameters (unused here) so the feature branch can be merged back without changing the service.
- Earlier CHANGELOG entries (Sessions 12, 18, 28, 58, 59) are history and stay as written.

**Checks**
- No code anywhere in `lib/`, `test/` or `pubspec.yaml` refers to the removed parts (searched).
- `flutter analyze`: 0 errors, 0 warnings (the same 17 style notes).
- `flutter test`: 67 pass, which is the previous 130 minus the 63 removed tests.
- Admin screens (shell and dashboard, wide shell, questions, editor, students, student record) swept on 12 devices: 72 renders, 0 layout problems.

**Worth knowing for the defense**
- Pre-oral **panel note 1** asked that questions be generated automatically. On this branch the app does not do that. If the panel asks, the honest answer is that template generation was built and tested (CHANGELOG Sessions 18, 58, 59) and is kept on a separate branch, and the presented version focuses on the adaptive learning.
- The manuscript (and the defense guide) still describe template generation. Decide which version you present and make them match.

## 2026-10-22 — Session 62: quiz answers no longer guessable by length (branch `adaptive-focus`)

You noticed the correct answer was usually the longest, most complete-sounding option, so students could pass without knowing the material. You asked for the options to be harder to predict, more so at higher levels. You chose "I rewrite, you review": the wrong options of every imported question are rewritten, you review them before anything goes live, and Faculty get an automatic warning for new questions.

**What was measured first (all 759 imported questions, identical to the live bank)**
- The correct answer was the longest option 84% of the time (Easy 79%, Medium 86%, Hard 91%). By chance it would be 25%.
- In 72% it also **stood out**: it was the longest and at least 1.4 times longer than the longest wrong option (Easy 61%, Medium 71%, Hard 81%).
- Many wrong options were obviously wrong ("No moral issues", "Only blood", "Color of gun"), so a student could rule them out without studying.

**What changed in the questions (once the SQL is run; nothing is live yet)**
- Only the **wrong options and their "why this is wrong" reasons** change. The question, the correct option, its position and the explanation stay exactly as they are.
- Each wrong option is now a real look-alike from the same topic: a related term, a neighbouring law, a sibling concept. Its reason says what it actually is ("That is parole", "That is RA 9208"). Hard and Medium use close near-misses, for example a correct rule with the wrong number or the wrong agency. Easy uses look-alikes that a student who studied can tell apart.
- Lengths were deliberately varied, so the correct answer is sometimes the longest, sometimes the shortest, and usually in between.
- **642 questions rewritten**: Hard 216, Medium 224, Easy 202. **117 kept as they are** (Hard 19, Medium 31, Easy 67), each with a written reason, because their options were already fair (for example four article numbers, or four ages in the same form).

| Level | Correct is longest, before → after | Stands out, before → after |
|---|---|---|
| Easy | 78.8% → 28.6% | 61.0% → 0% |
| Medium | 85.5% → 19.6% | 71.4% → 0% |
| Hard | 91.1% → 18.3% | 81.3% → 0% |

**16 questions flagged for Faculty.** These are not about option length; while rewriting, the stored correct answer itself looked wrong, outdated or disputed. They are listed at the top of the review page with the reason. The most important:
- **ca_073** says the Board of Pardons and Parole *supervises* parolees. The Board *grants* parole; the Parole and Probation Administration supervises them.
- **le_031, le_032, lea_073**: the PNP minimum height. RA 11549 (2021) lowered it to 1.57 m (5'2") for men and 1.52 m (4'11") for women. In le_031 and le_032 the option currently marked wrong is now the legal requirement.
- **cdi_086** uses the US meaning of entrapment; under Philippine law that is instigation, and cdi_135 teaches the Philippine meaning, so the two contradict.
- **cr_017 and qb_crim_002** name two different "Fathers of Fingerprint Identification" (Galton and Vucetich).
- **cj_002, qb_cl_009** ("Below 15"; the law says 15 and under), **cj_004** (death penalty prohibited by RA 9346), **cj_056, cj_089** (penalty depends on the paragraph or article), **cdi_050** (answer too broad), **le_004** (oldest vs most common patrol), **le_054** (17 PROs, possibly 18 since the Negros Island Region), **le_035** (NEAP expansion not verified).
- The rewrite does **not** change these answers; that is for Faculty, in the Admin Panel.

**How it is packaged**
- `content_review/snapshot_imported.jsonl`: the 759 questions exactly as they are live (their fingerprint matched the live table).
- `content_review/rewrites/<level>_NN.jsonl`: the rewrites, one line per question, in 16 batches by level and subject.
- `tools/rebalance_options.dart` checks every rewrite and writes the outputs only if all checks pass:
  - three wrong options;
  - no duplicate options, and no wrong option the same as the correct one;
  - a reason for each wrong option;
  - no "all/none of the above";
  - the correct answer does not stand out, which is checked for kept questions too;
  - a warning when a wrong option is much shorter than the answer.
- `content_review/rebalance_review.html`: **the review page**. It shows each question with its old and new options side by side, by level and subject, with the flags and the kept list.
- Six SQL files, one pair per level, so each stays under 400 KB for the SQL Editor:
  - `supabase_rebalance_options_hard.sql`, `_medium.sql`, `_easy.sql` apply the rewrites;
  - each has a matching `_rollback.sql` that undoes it.
  - A question changes only if its options are still exactly the snapshot, so an edit Faculty make in the meantime is never overwritten.
  - Its version goes up by 1, so phones download the new options.
  - Each file is safe to run twice and reports changed / already done / skipped.

**The automatic check for Faculty (new and edited questions)**
- `lib/utils/answer_length_check.dart` uses the same rule as the tool: the correct option is the longest and at least 1.4 times the longest wrong one.
- **Question editor:** an orange warning, "The correct answer stands out", appears above the answer options while Faculty type. It asks them to make the wrong options about as long, using real look-alike answers from the same topic. It is advice only and does not block saving.
- **Question bank list:** questions with the giveaway show an "Answer stands out" label, so old ones can be found and fixed.

**Checks**
- Rewrite tool: 759 of 759 imported questions reviewed, 0 errors, 0 warnings.
- On a local copy of the database identical to live (same fingerprint):
  - **apply:** 216 / 224 / 202 changed; run again: 0 changed;
  - after applying, every question still has exactly one correct option, in the same position with the same text, and the same number of options;
  - question text and explanations are unchanged, every new wrong option has a reason, and the version rose by 1 only on changed questions;
  - **rollback:** everything restored exactly (same fingerprint as before); run again: 0 changed;
  - a Faculty edit made before applying or before rolling back was skipped both times and kept.
- `flutter analyze`: 0 errors, 0 warnings. `flutter test`: 75 pass (67 + 8 new for the length check).
- Question editor and question list rendered on all 12 sweep devices: 0 layout problems.

**What you need to do**
1. Open `content_review/rebalance_review.html` in a browser and review the changes (and the 16 flags).
2. When you approve, run the three apply files in the Supabase SQL Editor, one at a time, in any order. This changes the live bank, so it affects **every** branch and every installed app, not just `adaptive-focus`.
3. Fix the flagged answers in the Admin Panel; the new length warning will guide the options.

## 2026-10-22 — Session 63: requirements baseline from the Capstone Project Manual (no code changed)

You gave a set of working rules: the official manuals are the source of truth, every requirement gets an ID and a source page, nothing is marked verified without evidence, and the first deliverable is a requirements analysis and compliance checklist. You then provided the official manual, `ITCAPSTONEMANUAL2025-1.pdf` (BCC BSIT Capstone Project Manual, 57 pages).

**What was made**
- **CrimiReview Compliance Checklist**, a published page: https://claude.ai/artifact/HcqDVtcXSr9fNhqjMjVt6U.
  - **91 requirements** (REQ-001 to REQ-091) extracted from the manual. Each has its source page, whether it is mandatory, the planned response, how it is checked, the evidence and the deliverable.
  - **13 questions for the adviser** (Q-01 to Q-13): places where the manual is unclear or contradicts itself. Examples: title page margins (p. 3 against p. 7), which cover parts are bold (p. 6), whether Chapter 1 keeps a Statement of the Problem (p. 2 and 54 against p. 19 to 23), Chapter 2 subheadings (p. 25 against p. 19), and the five-year rule for sources (p. 25).
  - **The documents still needed from the team**: the template, the rubric, the approved concept paper, the pre-oral comments, the manuscript as a Word file, the adviser's name, the members' full names and the defense month.
  - Statuses and notes are kept in the page's shared store. People with Contributor access or above can change them, and each change records who made it and when.
- The requirements were checked against the manuscript (Chapters 1 to 4, revised draft of October 17, 2026) and the project's code.

**Result of the check: 27 verified, 36 need review, 28 failed**
- **Failed, in the manuscript text:**
  - Chapter 2 uses the four separate subheadings the manual forbids, and its Related Literature cites journal papers.
  - Quotations lack page numbers.
  - About 27 of 47 Chapter 2 paragraphs fall outside the 4 to 6 sentence rule (approximate, automated count).
  - Chapter 3 gives no recommended hardware specifications.
  - Chapter 4 is titled "System Design" instead of "Methodology, Results, and Discussion", and it has no Recommendations section and no screenshots in 4.9.
  - The reference list sits between Chapters 2 and 3, and laws are not in the manual's format.
  - The Vision and Mission page lacks the RDC's.
- **Failed because not written yet:** the cover and title pages, Approval Sheet, Acknowledgement, Abstract and keywords, Table of Contents, lists of tables and figures, appendices, curricula vitae, and the results (no evaluation has been run).
- **Needs review:**
  - Everything about margins, fonts, spacing and page numbers, because the manuscript is a web page and only the Word file can show these.
  - The author names, which appear surname first without middle initials.
  - The cover date ("March 2026").
  - Whether the manuscript describes the version of the system that will be defended. It still describes Facebook sign-in and template generation, and does not mention the student record screen or the rewritten answer options.

**Not changed:** no code, no database, and no change to the manuscript itself. Phase 3 (fixing the manuscript) waits for your approval of this baseline.

## 2026-10-22 — Session 64: Chapters 1 to 3 rewritten as a Word file in the team's format (no code changed)

You shared the team's own manuscript, `CrimiReview_GRP49_Chapter1-3 (1).pdf`, and asked for the chapters to be made like it while following the manual, with no mistakes in the citations or in Chapter 2. You chose the **full version** of the system (template generation, Concepts and the student record, as on `student-record`) and a **Word file**.

**What was made**
- `CrimiReview_Chapters1-3_revised.docx`, with a PDF copy, in the Desktop folder `CrimiReview manuscript`. It has 31 pages: the title page, the Vision and Mission page, Chapters 1 to 3 and the References.
- The file is built by a script, so every rebuild runs two checks. Every in-text citation must have a reference entry and every reference must be cited. Every Chapter 2 paragraph must have 4 to 6 sentences.

**Formatting, per the manual**
- Times New Roman 12, double spacing, and a 0.5 in first-line indent.
- Margins of 1 in, with 1.5 in on the left. The title page has 1 in on every side and no page number (p. 7).
- Page numbers sit at the top right of every other page.
- Chapter titles are centered and bold. Subheadings are flush left and bold.
- The Vision and Mission page uses the manual's text for the BCC **and** the RDC (p. 9). The RDC wording in the team's file differed from the manual.

**Chapter 2, per p. 25 of the manual**
- One continuous section with no subheadings.
- 17 paragraphs, each with 4 to 6 sentences.
- Related literature comes from reports, laws and policy documents. Related studies come from journals.
- The legal bases are the 1987 Constitution, RA 10173, RA 11131 and the UN 2030 Agenda (SDG 4, target 4.3).
- **Table 1** compares CrimiReview with two CLE reviewer apps and two LET reviewers.

**Citations: every source was checked at its publisher, Crossref, OpenAlex, the app store or the official site**
- **Fixed:**
  - The team's file mixed numbered and APA citations, and the numbers were wrong. Everything is now APA 7.
  - Gligorea et al. was cited but missing from the reference list; it was added.
  - The Albina et al. entry was wrong. It is now the 2022 *European Journal of Educational Research* paper.
  - "Gerarda et al." is Gerard et al. (2025), *Journal of Criminal Justice Education*, 36(4).
  - "Haas, D." is the developer DODO LABS PTE. LTD.
  - Lasala et al. was missing the co-author Dioneda.
  - Two first authors are named Yang, so their citations now carry initials (C. Yang et al., 2021; H. L. Yang & Xiang, 2024).
  - Laws now follow the manual's format.
- **Dropped:**
  - Prado was cited but had no entry, and Pacturan et al. (2024) could not be found anywhere.
  - Mayne and Green (2023) could not be found. The real paper is from 2020, in *Science & Justice*.
  - Gerard (2022), "European Journal of Criminology Education", is really a conference paper with an unclear author.
  - Mertens (2022) could not be read to confirm what it says.
- 33 references remain, and each is cited in the text.

**System facts corrected against the code**
- The team's file described a second generator that used a large language model on uploaded PDFs, together with an "LLM API" software item. The app does not have it; it was removed in `supabase_remove_document_generation.sql`. Only template generation with Faculty approval remains.
- The minimum Android version is 7.0 (API 24), not Android 10.
- The subject names now follow Board Resolution No. 01, s. 2021.
- Sign-in is described as Google only, as on the current branch.

**Still open, for the team to confirm**
- The members' full names with middle initials (the file keeps the team's surname-first names), and the defense month on the title page ("March 2026").
- Recommended phone and computer specifications are the team's own values, not measured.
- The Official Gazette link for the Constitution could not be opened to confirm it. RA 10173 and RA 11131 cite the NPC and Senate copies instead.
- Adviser questions Q-01 (title page margins), Q-05 (Statement of the Problem, left out as in the team's file) and Q-07 (the five-year rule; Vygotsky 1978, Ryan & Deci 2000 and Corbett & Anderson 1995 are older foundational works).
- Content validation by criminology faculty is described as a role, but it has not been done yet.
- Chapter 4 is not included.

**Not changed:** no code and no database.

## 2026-10-22 — Session 65: Chapter 4 written to the manual, with redrawn diagrams and real test results (no code changed)

You approved Chapter 4. It describes the full version (branch `student-record`), like Chapters 1 to 3.

**What was made**
- `CrimiReview_Chapters1-4.docx`, with a PDF copy, in the Desktop folder `CrimiReview manuscript`. It holds the title page, the Vision and Mission page, Chapters 1 to 4 and the References, 100 pages in all. The earlier Chapters 1 to 3 file is kept beside it.
- The subfolder `Chapter 4 figures` holds the diagrams as editable SVG and as PNG, plus the 35 screenshots used.

**Chapter 4: "Methodology, Results, and Discussion", sections 4.1 to 4.12 as in the manual (pp. 30 to 41)**
- **4.1 and 4.2:** the team's manual review process figure, the requirements taken from the pre-oral panel's comments, and the actor lists for Faculty and Students.
- **4.3:** the team's system framework figure, kept, with its text corrected. The Admin Panel is in the same app, not a separate web app. The verification codes are sent by Resend; there is no LLM.
- **4.4: the use case diagram was redrawn** with the five corrections from your instructor's marked printout:
  - the actors are named "Students" and "Faculty";
  - there is a system boundary;
  - Insert, Update and Delete Question are «extend» of Manage Questions;
  - the use case is "Send Verification Code", without "Reset";
  - there is no "Log Admin Action".
  It also adds the full version's use cases: Manage Concepts, Generate Questions, Approve Generated Questions, View Student Record, Read Modules, Reset Password, Leaderboard/Achievements and Profile/Settings.
- **4.5:** 17 use case narratives (Tables 2 to 18) in the manual's table layout, checked against the code. For example, the sign-up code is sent before the account is created, and the code expires in 10 minutes.
- **4.6: all 17 activity diagrams were redrawn** in the manual's two-lane style. The team's Oct 5 drawings had overlapping labels, broken boxes, and a removed document/LLM generator in Figure 7.
- **4.7: the ERD was redrawn from the live database** (read-only check), plus the `form` column that the full version adds. The team's ERD had tables and columns that do not exist, such as `users.password`, a `time_taken_seconds` table and `subject.stem_template`. Live, four user tables reference `user_profiles`, and `questions.created_by` has no foreign key.
- **4.8:** iterative development with real dates (first commit May 23, v1.0.0 on Oct 7, v1.0.1 on Oct 12, 2026) and the four kinds of testing.
- **4.9:** 18 figures of 35 screens from the screenshot harness, labelled as sample data.
- **4.10: real results only:**
  - `flutter test`: 130 of 130 pass (commit 9f69147);
  - `flutter analyze`: 0 errors, 0 warnings, 17 informational notes;
  - layout sweep: 540 renders, 0 problems;
  - the database tests recorded in this log: 49, 9, 76 and 18 checks, all passing.
  The ISO/IEC 25010 user evaluation has not been run, so its table is an empty, highlighted shell.
- **4.11 and 4.12:** the recommendations follow the manual's guidelines. The implementation plan's durations are proposals, highlighted for the team.

**Also changed**
- ISO/IEC 25010:2023 is now in the References. It was checked on iso.org: Edition 2, November 2023, standard 78176. It is cited in Chapter 1's third objective and in 4.10.
- The build also checks that every figure number mentioned in the text exists.

**Found while checking, not fixed in the code**
- The screenshot harness's `tab_quiz` and `tab_cards` shots tap the dashboard shortcut, not the bottom tab, so they show the Home screen. The correct shots were made in a scratch copy, which has since been deleted. The harness itself was not changed.

**Still open, for the team**
- The ISO/IEC 25010 evaluation and its results (Table 22).
- Confirm the durations in Table 23.
- Faculty content validation.
- Phone captures of the email verification screen, if wanted. The harness shows a "failed to send" banner there because it runs offline, so that screen was left out.
- The items from Session 64: names, month, Gazette link, Q-01, Q-05, Q-07.

**Not changed:** no code and no database.

## 2026-10-23 — Session 66: Generate questions from a PDF with Google Gemini (branch `pdf-uploader-gemini`, from `adaptive-focus`)

You asked how CrimiReview can keep up when the criminology curriculum changes, then asked to bring back the PDF uploader with a free AI model. Gemini was chosen because:
- its free tier needs no credit card;
- it reads a PDF directly;
- its JSON output can be forced into a fixed shape.

The feature existed before (Sessions 12–19, using the Claude API). It was never switched on because the paid key was never added, and it was removed on Oct 7 (`f19b918`). This session restores it from git history, switches it to Gemini, and closes a security gap.

**What faculty can do now**
- Admin Panel → **Questions → PDF icon → Generate from PDF**: choose the subject, an optional topic, the difficulty (Mixed, Easy, Medium or Hard) and the number of questions (5 to 20), then pick a PDF of at most 20 MB.
- **Recent uploads** shows each PDF as "Writing questions…", "N questions to review" or "Failed" with a plain reason. The screen refreshes itself every few seconds while Gemini works. An upload still working after 5 minutes is reported as stopped.
- **Review**: every generated question is shown with its options (correct one marked), legal basis and explanation, plus the "Answer stands out" warning. Faculty tick the good ones and tap **Approve**. Each question can also be edited or deleted. Nothing is approved without a tick, and students see nothing before approval.

**How it works**
- **App** (`lib/services/document_generation_service.dart`):
  - checks the file first: `.pdf`, at most 20 MB, real PDF bytes (`%PDF-`);
  - uploads it to the private `document-uploads` bucket in the faculty member's own folder;
  - adds a `document_uploads` row and starts the Edge Function.
- **Edge Function** (`supabase/functions/generate-questions-from-document/index.ts`), rewritten for Gemini (`generateContent`, PDF sent inline, JSON schema):
  - **New: checks the caller is a signed-in admin** (`is_admin()` with the caller's own token). The old function trusted anyone who knew an upload id.
  - **New: claims the upload only while it is `pending`**, so one upload is sent to Gemini once at most, and nobody can repeat it to use up the free quota.
  - Answers right away and finishes in the background.
  - Keeps a question only if it has 4 different, non-empty options and exactly one correct answer.
  - Inserts each kept question as `is_active = false`, `source = 'generated'`, `template_id` = the upload id.
  - Writes an audit row (`generate`, method `pdf`), and marks the upload completed or failed with a plain message: missing key, invalid key, free limit reached, blocked, not a PDF, or nothing usable.
  - Model: `gemini-flash-latest`, changeable with the `GEMINI_MODEL` secret.
- **Database** (`supabase_document_generation.sql`, recreating what `supabase_security_fixes_v2.sql` dropped):
  - faculty can read, add and delete uploads;
  - a new upload must be `pending` and under the faculty member's own id;
  - only the function can change a status;
  - students and logged-out visitors get nothing;
  - the bucket is private, PDF only, 20 MB.

**Checks**
- **Edge Function, 22 of 22 pass.** The real source ran under Node 24 with a fake Supabase and a fake Gemini. The checks cover:
  - logged-out and student callers refused;
  - unknown upload, and a second call that never reaches Gemini;
  - 3 good questions saved and 3 bad ones skipped;
  - inactive, tagged rows, with the correct answer index;
  - the audit row;
  - the request shape (inline PDF, JSON schema, key in a header);
  - error messages for 429, an invalid key, a missing key and a blocked document;
  - fenced JSON, a non-PDF file, the forced difficulty and the count cap.
- **Database, 18 of 18 pass** on the local PostgreSQL 18 copy, with the file applied twice. Faculty can add and read uploads, but cannot set a status, add one under another id, ask for more than 20 questions, or upload into another folder. Students and anon see and do nothing. The service role can claim an upload. The bucket settings are right.
- **App:**
  - `flutter test`: 88 pass, including 13 new in `test/document_generation_test.dart`;
  - `flutter analyze`: no new issues, only the same 17 informational notes;
  - the new screens rendered in light and dark;
  - the 12-device sweep: 48 renders, 0 layout problems.

**Not done, and not claimed**
- **Never run against the real Gemini or the live project.** There is no API key yet, and the SQL and function are not deployed. The README section "Generate questions from a PDF (Google Gemini)" gives the steps for you: free key, SQL, Edge Function, secret.
- `pubspec.lock` and the generated plugin files are **not committed**: they already held your own uncommitted changes. `flutter pub get` adds `file_picker` to them.
- The manuscript (Chapters 1–4) still describes the version without this feature. Update it only once the feature is kept for the defense.
- A PDF uploader handles **content** changes (new laws, revised topics). A **new subject or new subject weights** still needs an app update, because the six subjects and their weights are in `lib/models/subject.dart`.

## 2026-10-24 — Session 67: the Gemini function went live; VS Code red lines removed (same branch)

**Live check (read-only)**
- On 2026-10-23 you ran the SQL, replaced the Edge Function code and added the key.
- Checked on the live project afterwards:
  - the function is version 6, identical to this branch's code, with JWT verification on;
  - `document_uploads` has the three faculty rules;
  - the `document-uploads` bucket is private, PDF only, 20 MB.
- A call as a logged-out user was refused with "Sign in first." (401), so the new code runs.
- The Gemini key itself can only be checked by a real upload from a faculty account, which hasn't happened yet.

**Red lines in `index.ts`**
- VS Code checked the Edge Function as Node TypeScript, so it didn't know Deno's `Deno` global or `npm:` imports. The errors were "Cannot find name 'Deno'", "Cannot find module 'npm:@supabase/supabase-js@2'" and an implicit `any` on `req`.
- These were editor-only: Supabase runs the file on Deno.
- Added two editor-only files that Supabase and Deno never read or deploy:
  - `supabase/functions/tsconfig.json`;
  - `supabase/functions/editor-types.d.ts`, which describes `Deno.env`, `Deno.serve` and the Supabase client import.
- Checked with TypeScript 5.6: 0 errors. VS Code now shows no problems in the file. The function code is unchanged, so nothing needs redeploying.

## 2026-10-25 — Session 68: everything aligned with the PRC Tables of Specifications (branch `tos-aligned-bank`, from `pdf-uploader-gemini`)

You said your adviser requires every question to follow the Criminologist Licensure Examination TOS, shared a Scribd document titled "Criminology Board Exam TOS 2026", and asked for all content and every related feature to be updated on a separate branch.

**Which TOS, and why not the Scribd file**
- The Scribd document could not be checked: it is behind a paywall, uploaded by a private user, uses "easy / moderate / difficult" levels, and cites no resolution number. The official TOS uses Bloom's taxonomy levels.
- So the work follows the **official PRC documents** instead, listed with links and dates in `content/tos/SOURCES.md`:
  - PRB of Criminology **Resolution No. 02, s. 2024** (Enhanced Tables of Specifications), annexes "as of January 22, 2024", effective May 5, 2024, used from the July 2024 exam;
  - **Resolution No. 06, s. 2025**, which replaced Criminology Topic 4 with the Code of Ethical and Professional Conduct (Res. No. 07, s. 2024), used from the August 2025 exam.
- If your adviser has a newer official resolution, the same tools can rebuild everything from it.

**The TOS as data**
- `assets/tos/tos_2024.json`: 6 subjects, 37 topics and 146 competencies, each with its items per Bloom level. Read from the six annex PDFs by position on the page (`tools/tos/parse_annex.py`, `tools/tos/build_tos.py`).
- Every count checks out: each competency's Bloom split equals its items, each topic equals its competencies, each subject equals 100. The PDFs' own inconsistencies (two header rows, LEA's "20%" total) are noted in SOURCES.md; the competency rows were followed.
- Two parse leftovers fixed in this session: a stray "Total" at the end of LEA 6.4, and the titles "Character Formation 1-Nationalism" and "2- Leadership".

**600 new questions, exactly to the TOS**
- `content/tos/bank/{clj,lea,fs,cdi,crim,ca}.jsonl`: 100 per subject. Every competency has exactly its TOS number of items at each Bloom level (for example CLJ 3.4: 6 Applying; CLJ 4.1: 4 Applying and 4 Analyzing).
- Each question has four options, a reason for every option, an explanation and, where there is one, its legal basis.
- `tools/tos/build_bank.py` checks all of that and refuses a correct answer that stands out by length; the options of 101 questions were rewritten until every question passed. It also checks that no stem repeats an old question's (one did, and was reworded).
- It writes `supabase_tos_bank.sql`: the 600 questions **inactive** (`source = 'generated'`, `template_id = 'tos_2024'`), with `tos_code` and `bloom_level`. Difficulty follows the Bloom level (Remembering and Understanding are easy, Applying is medium, Analyzing to Creating are hard).
- **These were written with AI assistance (Claude) from the TOS competencies and the laws they name. They are drafts.** Students see one only after a faculty member approves it.

**The existing 759 questions**
- `assets/tos/topic_map.json` sends every old topic name to a TOS topic, with 17 single-question overrides for mixed topics such as "Special Crime Investigation".
- Where the TOS puts a topic in another subject, the questions move there: Legal Medicine and Police Intelligence go to Crime Detection and Investigation, Philippine Criminal Justice System goes to Criminal Law.
- Dry run on the live snapshot: 693 keep their subject, 49 move, 6 stay put and are deactivated (the target subject already has the same question), 11 deactivated (police radio codes and police psychology are not in the TOS), and the 16 flagged as wrong on 2026-10-22 deactivated. Nothing is deleted.
- Old questions are linked to a TOS topic (e.g. `CLJ-3`), not a competency; faculty can refine that in the editor.

**`supabase_tos_alignment.sql`** (from `tools/tos/build_alignment.py`, one transaction)
- `tos_topics` and `tos_competencies`, readable by everyone, with no write rules.
- `questions.tos_code` (checked by a trigger: it must be a real TOS code of the question's own subject) and `questions.bloom_level`.
- The move described above, with the old values kept in `tos_alignment_backup`.
- Students' topic mastery merged into the TOS topic names (attempts added up, p(known) averaged by attempts), old rows kept in `tos_alignment_mastery_backup`.
- `admin_tos_coverage()` for the Admin Panel; refuses non-faculty.
- `document_uploads.tos_code`, and an audit-log row with the counts.
- `supabase_tos_alignment_rollback.sql` undoes it.
- **Tested on a local copy** (bootstrap + schema + the 759-question snapshot + sample mastery): 742 linked, 49 moved, 33 deactivated, 600 TOS questions in; mastery 0.95 × 6 and 0.40 × 2 merged to 0.813 over 8 attempts. A second run changes nothing, and a question faculty re-activated stays active. Students are refused coverage data but can read the TOS. The trigger rejects unknown and wrong-subject codes. The rollback restores questions and mastery exactly; fingerprints match an untouched copy.

**App**
- `lib/models/tos.dart`: the TOS catalog, Bloom levels with their difficulty, each subject's difficulty mix, and the old-topic map.
- `Question` has `tosCode` and `bloomLevel`. They are sent to the database only when set, so saving still works before the SQL is run.
- Subject topics and descriptions are now the TOS topics.
- **Readiness:** each subject weights easy, medium and hard by its own TOS split (CLJ 30/50/20, LEA 31/49/20, FS 30/51/19, CDI 30/50/20, CRIM 31/51/18, CA 30/50/20), and the overall score weights subjects by their exam share (20/15/15/20/20/10) instead of a plain average.
  - **Correction:** earlier in this conversation I said the 30/50/20 split had no traceable source. It does: grouping the TOS Bloom levels this way gives it in every subject.
- **Topic mastery on the phone:** at start-up `MasteryService` renames saved topics the same way the SQL does, before any cloud sync, so old names are not pushed back up. Topics the TOS dropped leave the live model; their database rows are kept.
- The question cache now notices subject and topic changes (the SQL moves questions without bumping their version).
- **Study modules:** all six rebuilt from `content/tos/modules/*.md` by `tools/tos/build_modules.py`: one chapter per TOS topic and one section per competency, each with the TOS wording, notes, a key point and key terms (146 sections). They replace the old modules, which were lists of old question explanations.
- **Study notes before a quiz:** taken from the module, starting with the competencies the quiz's questions test. The old hardcoded notes had errors ("Minority (below 15)" where the law says 15 and under; social learning credited to Sutherland).

**Admin Panel**
- **TOS coverage** (Dashboard shortcut, or the check-list icon on Questions): per subject, each topic and competency with its TOS items, active questions and drafts, and the Bloom split.
- **Review** of one competency: the drafts with their answers and legal basis; tick the checked ones and **Approve** them together.
- **Question editor:** pick the TOS topic, competency and Bloom level (the Bloom level sets the difficulty). "Other topic" keeps free text. A link to another subject's TOS is ignored instead of crashing the form; the screenshot sweep found that.
- **Question list:** a TOS pill on every question, and a filter for linked or not linked.
- **Generate from PDF:** "Target in the TOS" lets Faculty ask Gemini for questions on one topic or competency. The Edge Function then names the competency and its Bloom mix in the prompt, asks for a Bloom level per question, and saves the TOS code, the TOS topic title and the Bloom level. **The function must be redeployed** for this.

**Checks**
- `flutter analyze`: no errors or warnings.
- `flutter test`: all tests pass, including 17 new ones in `test/tos_test.dart` (TOS counts, topics, weights, readiness, the map, the mastery merge, the question fields, the 600-question bank and its SQL, the modules, the study notes).
- Edge Function under Node with fake Supabase and Gemini: 31 of 31 pass, 9 of them new for TOS uploads.
- Screenshots of the new and changed screens checked by eye; the 12-device sweep renders 552 screens with no layout problems.

**What you need to do**
1. Run `supabase_tos_alignment.sql`, then `supabase_tos_bank.sql`, in the Supabase SQL Editor.
2. Redeploy `generate-questions-from-document` with the new `index.ts`.
3. Have the criminology faculty review and approve the drafts in Admin Panel → TOS coverage, checking each against the current law.
4. The manuscript (Chapters 1-4) does not mention the TOS alignment yet.

---

## Known gaps — not fixed yet, worth knowing about

- **On branch `adaptive-focus` there is no question generator in the app** (Session 61); the two notes below describe the feature branches.
- **Template-based generation is limited by the concept bank.** Since Session 58 each concept can make up to four questions (74 from the 21 seeded concepts) and Faculty add concepts in the app, but a group still needs 3 or more concepts, and the two legal-basis forms need a distinct legal basis on every concept in the group.

- **Daily Challenge** shows an explanation either way (better than the old Quiz screen was), but still uses the plain overall `explanation` field, not the richer per-option "why THIS specific wrong choice fails" rationale, and does not call `MasteryService.recordAttempt()`. Only the main Quiz flow does, as of Session 9.
- **The quiz Results screen** has no per-question answer review at all (Daily Challenge's own separate results screen does have one). A student who wants to see *why* they missed something after finishing has to remember it from the quiz itself.
- **Google / Facebook sign-in is built but switched off** until the README "Google and Facebook sign-in" steps are done. `supabase_enforce_email_verification.sql`, which had to come first, is installed (Session 52).

## Files this project gained that didn't exist before Session 1

`lib/services/admin_service.dart`, `lib/screens/admin/` (now 9 files as of Session 18), `lib/screens/flashcards_home_screen.dart`, `supabase_security_fixes.sql`, `supabase_admin_management.sql`, `supabase_remove_document_generation.sql` (Session 28), `supabase_template_generation.sql` (Session 18), `lib/services/question_generation_service.dart` (Session 18), this file. (`supabase_schema_v2.sql`, `question_repository.dart`, `mastery_service.dart`, `question_selection_service.dart`, `explanation_service.dart`, and the `Question`/`AnswerFeedback`/`TopicMastery` models already existed, unused, before Session 1 — see that section for what "unused" meant in practice.)

Session 68 (`tos-aligned-bank`): `assets/tos/tos_2024.json`, `assets/tos/topic_map.json`, `content/tos/` (SOURCES.md, `bank/`, `modules/`), `tools/tos/` (parse_annex, build_tos, build_bank, build_alignment, build_modules), `supabase_tos_alignment.sql`, `supabase_tos_alignment_rollback.sql`, `supabase_tos_bank.sql`, `lib/models/tos.dart`, `lib/services/study_notes_service.dart`, `lib/screens/admin/admin_tos_coverage_screen.dart`, `test/tos_test.dart`. Rebuilt: the six `assets/modules/*_module.json`.

Session 59: `lib/utils/concept_csv.dart`, `lib/screens/admin/admin_concept_csv_import_screen.dart`, `test/concept_csv_test.dart`.

Session 62 (`adaptive-focus`): `tools/rebalance_options.dart`, `content_review/` (snapshot, rewrites, review page), `supabase_rebalance_options_{hard,medium,easy}.sql` and their `_rollback.sql` files, `lib/utils/answer_length_check.dart`, `test/answer_length_check_test.dart`.

Session 61 (`adaptive-focus`): no new files. Removed on that branch: the generator and Concepts screens, services, models, utilities and their tests (listed in the Session 61 entry).

Session 60: `supabase_student_record.sql`, `lib/models/student_record.dart`, `lib/screens/admin/admin_student_record_screen.dart`, `test/student_record_test.dart`.

Session 58: `supabase_concept_bank.sql`, `lib/models/concept.dart`, `lib/services/concept_service.dart`, `lib/utils/concept_import_parser.dart`, `lib/utils/concept_rules.dart`, `lib/screens/admin/admin_concepts_screen.dart`, `admin_concept_editor_screen.dart`, `admin_concept_import_screen.dart`, `concept_subject_topic_fields.dart`, `test/concept_import_parser_test.dart`, `test/concept_rules_test.dart`.

Session 56: `supabase_audit_fixes.sql`, `test/notification_time_test.dart`.

Session 52: `lib/screens/social_sign_in_icons.dart`, `test/social_sign_in_icons_test.dart`.

Session 48: `assets/icon/logo_original.png` (new logo master); Windows and macOS app icons.

Session 46: `lib/screens/sign_in_choice_screen.dart`, `lib/screens/sign_in_completion.dart`.

Session 45: `lib/screens/admin/admin_settings_screen.dart`, `lib/utils/app_info.dart`.

Session 44: `lib/services/social_auth_service.dart`, `lib/services/post_sign_in_service.dart`, `lib/screens/dashboard_view.dart`, `lib/utils/quiz_launcher.dart`, `lib/widgets/brand_logos.dart`, `supabase_social_login.sql`.

Session 41 (redesign): `lib/widgets/ui/` (design-system components), `assets/fonts/` (Plus Jakarta Sans + OFL licence), `assets/images/logo_mark.png`, `test/screenshots/` (screenshot harness), `android/app/src/main/res/values-v31/` and `values-night-v31/` (Android 12+ launch screen).

## Files this project lost

`lib/data/question_bank.dart`, `lib/data/questions_database.dart` — 7,013 lines of hardcoded quiz content, deleted in Session 4 once nothing referenced them anymore.

`lib/screens/admin/admin_document_generation_screen.dart`, `lib/services/document_generation_service.dart`, `supabase/functions/generate-questions-from-document/`, `supabase_document_generation.sql` — the PDF → AI generation path (added Session 12), removed in Session 28.

Session 41: `lib/widgets/animated_widgets.dart`, `lib/widgets/streak_widget.dart`, `lib/widgets/sync_status_indicator.dart` (unused by any screen), `test/fonts/` (Poppins, replaced by the bundled app font).

Session 54: `lib/screens/sign_in_choice_screen.dart` (the "Decide how you sign in" page from Session 46; Google and Facebook are icons on the log-in page instead).

Session 48: `assets/icon/logo_original.jpg`, `graduation_cap.png`, `graduation_cap_splash.png`, `splash_logo.png` (the old navy/gold logo artwork; nothing used them).
