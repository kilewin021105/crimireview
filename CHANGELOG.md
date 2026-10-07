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

## Known gaps — not fixed yet, worth knowing about

- **Template-based generation is capped at 21 questions, ever**, across its 4 seeded topics, until someone manually adds more rows to `concept_bank` — this is a content task, not something the generator can do for itself. Since Session 28 it is the only generator, so this cap is now the cap on generated questions overall.

- **Daily Challenge** shows an explanation either way (better than the old Quiz screen was), but still uses the plain overall `explanation` field, not the richer per-option "why THIS specific wrong choice fails" rationale, and does not call `MasteryService.recordAttempt()`. Only the main Quiz flow does, as of Session 9.
- **The quiz Results screen** has no per-question answer review at all (Daily Challenge's own separate results screen does have one). A student who wants to see *why* they missed something after finishing has to remember it from the quiz itself.
- **Supabase Authentication → "Confirm email" setting** — the app's own custom code-verification flow assumes this dashboard toggle is off. This was flagged early on but never independently re-verified after the security fixes; worth a quick check in the dashboard if login-right-after-signup ever behaves oddly.

## Files this project gained that didn't exist before Session 1

`lib/services/admin_service.dart`, `lib/screens/admin/` (now 9 files as of Session 18), `lib/screens/flashcards_home_screen.dart`, `supabase_security_fixes.sql`, `supabase_admin_management.sql`, `supabase_remove_document_generation.sql` (Session 28), `supabase_template_generation.sql` (Session 18), `lib/services/question_generation_service.dart` (Session 18), this file. (`supabase_schema_v2.sql`, `question_repository.dart`, `mastery_service.dart`, `question_selection_service.dart`, `explanation_service.dart`, and the `Question`/`AnswerFeedback`/`TopicMastery` models already existed, unused, before Session 1 — see that section for what "unused" meant in practice.)

## Files this project lost

`lib/data/question_bank.dart`, `lib/data/questions_database.dart` — 7,013 lines of hardcoded quiz content, deleted in Session 4 once nothing referenced them anymore.

`lib/screens/admin/admin_document_generation_screen.dart`, `lib/services/document_generation_service.dart`, `supabase/functions/generate-questions-from-document/`, `supabase_document_generation.sql` — the PDF → AI generation path (added Session 12), removed in Session 28.
