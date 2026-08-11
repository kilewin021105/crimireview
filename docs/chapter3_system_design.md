# System Framework, Use Case Diagram &amp; Activity Diagram (Draft)

> Plain-text copy of sections 4.3–4.6 for CrimiReview, for pasting into your Word manuscript. The polished version with the actual diagrams is published as an artifact — ask Claude for the link if you don't have it, or regenerate it from this file.
>
> **Format matches your Research Development Center's guide** (Buenavista Community College), not a generic textbook template: System Framework uses the hub-and-spoke icon diagram (no boundary frame), Use Case Diagram has no boundary frame either, Use Case Narrative uses your instructor's exact table fields, and Activity Diagram keeps the bordered lane-table look. Figure/table numbers follow the guide's own numbering; adjust if an earlier section in your manuscript already used Figure 1.
>
> Every claim below traces to the actual implemented codebase (services, models, and the live Supabase schema) and was independently reviewed for technical accuracy, UML notation correctness, and this format convention.

---

## 4.3 System Framework

A system framework is a structure that guides the creation and management of complex systems. It provides standardized processes, tools, and methodologies, breaking down tasks into manageable parts. For CrimiReview, the framework shows how the mobile application sits at the center of the system, exchanging information with the people who use it and with the services it depends on.

**Figure 1**
_System Framework_

_(hub-and-spoke diagram: central "CrimiReview App" icon, with Student, Admin, and Adaptive Learning (BKT) on the left; Database, Connectivity, and Question Bank on the right; Progress Reports and Notifications at the bottom — each connected to the center by an arrow. Double-headed arrows = two-way exchange (Student, Admin, Database, Question Bank); single-headed = one-way (Adaptive Learning → App, Connectivity → App, App → Progress Reports, App → Notifications). See the published artifact for the actual figure.)_

Arrows drawn with a head at both ends indicate a two-way exchange of data; a single-headed arrow indicates data moving in one direction only. The Student and Admin exchange information directly with the app, as does the Database (Supabase), which both stores what the app writes and returns what the app reads, and the Question Bank, which the Admin writes to and the Student reads from through the same app. Adaptive Learning (the Bayesian Knowledge Tracing engine) and Connectivity feed information into the app; the app, in turn, produces Progress Reports and Notifications as one-directional outputs.

This system framework shown in Figure 1 is designed to describe and explain the entire process of the system.

**What each node is in the codebase** (supplementary, not part of the required figure): Student/Admin — the shared, role-differentiated accounts table, routed to separate app shells after login. Database — Supabase Postgres (`questions`, `topic_mastery`, `question_attempts`, `question_exposure`, `quiz_results`). Adaptive Learning (BKT) — `MasteryService` and `QuestionSelectionService`, implementing Bayesian Knowledge Tracing (Corbett & Anderson, 1995). Connectivity — `ConnectivityService` / `OfflineSyncService`. Question Bank — `QuestionRepository` reading/writing `public.questions`. Progress Reports — mastery percentages on the Progress screen. Notifications — scheduled study-reminder notifications via `NotificationService`.

---

## 4.4 Use Case Diagram

It is a visual representation of how users (people or other systems) interact with a system. It shows the system's main functions (use cases) and who uses them (actors).

**Example:** This use case diagram represents the interactions between two user roles, "Student" and "Admin," and the CrimiReview system.

**Figure 2**
_Use Case Diagram_

_(no boundary frame, per your guide's own correction note. Two columns: Student and Admin actors on the left fan out to primary use cases — Sign Up, Log In, Take Quiz, Take Daily Challenge, Study Flashcards, Track Progress/Mastery, Log Out, View Dashboard, Manage Questions, Monitor Students, Manage Admin Roles. A right-hand column holds the include/extend-only sub-behaviors — Send Verification/Reset Code, Select Adaptive Question Set, Record Answer & Update Mastery, Compile Answer Explanation, Use App Offline, Log Admin Action — reached only via «include»/«extend» arrows from the left column, never directly from an actor. See the published artifact for the actual figure.)_

Figure 2 shows the process of CrimiReview, highlighting how the Student and Admin actors interact with the system to access its main functions. Take Quiz always executes three mandatory sub-behaviors (Select Adaptive Question Set, Record Answer & Update Mastery, and Compile Answer Explanation) via «include»; Use App Offline «extend»s Take Quiz, Take Daily Challenge, and Study Flashcards when the device has no connectivity; and Manage Questions and Manage Admin Roles both «include» Log Admin Action, since every write and every role change is recorded to a server-side audit log.

**Full use case list beyond the diagram's primary actions** (supplementary): Verify Email, Request Password Reset, Change Password (shared), View Onboarding, View Achievements, View Leaderboard, Manage Profile, and Manage Settings for the Student; Deliver Study Reminder Notification (triggered automatically, not by the Student). Omitted from Figure 2 for legibility, per the guideline to "identify system actors and key actions."

**Relationship summary:**
- «include»: Sign Up→Send Verification/Reset Code · Take Quiz→Select Adaptive Question Set · Take Quiz→Record Answer & Update Mastery · Take Quiz→Compile Answer Explanation · Manage Questions→Log Admin Action · Manage Admin Roles→Log Admin Action
- «extend»: Use App Offline→Take Quiz · Use App Offline→Take Daily Challenge · Use App Offline→Study Flashcards (extension point: "no connectivity")

---

## 4.5 Use Case Narrative

It is a written explanation of a use case from start to finish. It describes how the system and the actors interact step by step, providing more detail than a diagram.

The use case consists of several possible interactions between users and the system in a specific environment that are connected to a specific objective. The procedure generates a document that lists each step a user takes to complete an activity.

> **Table format note:** use only horizontal lines to separate information; avoid vertical lines. Limit rules to those necessary for clarity (above/below column headings, and at the bottom of the table).

### Table 1 — _Use Case Narrative for Sign Up_

| | |
|---|---|
| **USE CASE NAME** | Sign Up (Register Account) |
| **PRIMARY ACTOR** | Student |
| **GOAL ON CONTEXT** | To create a new CrimiReview account by providing registration details. |
| **TRIGGER** | The actor wants to access CrimiReview for the first time. |
| **PRE-CONDITION** | The device has network connectivity, and the supplied email address is not already registered. |
| **FLOW OF EVENTS** | **Actor Action:** 1. The actor selects "Sign Up" and enters name, email, and password. <br>**System Response:** 2. The system validates the input and creates a new account record with role "student." 3. The system generates a six-digit verification code, stores it server-side, and sends it to the actor's email through the Email Service. 4. The system displays a confirmation instructing the actor to check their email. |
| **EXCEPTION** | The email address is already registered, or the device has no network connectivity. |
| **POST-CONDITION** | The account exists in an unverified state pending email verification. |

### Table 2 — _Use Case Narrative for Take Quiz_

| | |
|---|---|
| **USE CASE NAME** | Take Quiz |
| **PRIMARY ACTOR** | Student |
| **GOAL ON CONTEXT** | To answer an adaptive set of questions on a chosen subject and receive mastery-based feedback. |
| **TRIGGER** | The actor wants to practice a subject after selecting it from Browse Subjects. |
| **PRE-CONDITION** | The actor is logged in and has selected a subject and difficulty level. |
| **FLOW OF EVENTS** | **Actor Action:** 1. The actor selects a subject and difficulty. 4. The actor selects an answer for each question. <br>**System Response:** 2. The system selects an unseen-first, mastery-weighted question set. 3. The system displays each question in turn. 5. The system updates the actor's topic mastery and compiles an answer-specific explanation after each response. 6. The system records the question set as served, computes the score, and saves the result. |
| **EXCEPTION** | The device loses connectivity mid-quiz, or no unseen questions remain for the topic. |
| **POST-CONDITION** | The actor's topic mastery is updated, and a quiz result is saved and viewable on the Results screen. |

### Table 3 — _Use Case Narrative for Track Progress / Mastery_

| | |
|---|---|
| **USE CASE NAME** | Track Progress / Mastery |
| **PRIMARY ACTOR** | Student |
| **GOAL ON CONTEXT** | To view personal mastery and progress across subjects and topics. |
| **TRIGGER** | The actor wants to check their performance before the next study session. |
| **PRE-CONDITION** | The actor is logged in. |
| **FLOW OF EVENTS** | **Actor Action:** 1. The actor navigates to the Progress section. 3. The actor selects a topic to view further detail. <br>**System Response:** 2. The system retrieves the actor's mastery records and renders them per subject and topic. 4. The system displays the detailed mastery breakdown for that topic. |
| **EXCEPTION** | No quiz attempts have been recorded yet, in which case default (not-started) values are shown. |
| **POST-CONDITION** | No data is modified; the actor has viewed their current mastery state. |

### Table 4 — _Use Case Narrative for Manage Questions_

| | |
|---|---|
| **USE CASE NAME** | Manage Questions |
| **PRIMARY ACTOR** | Admin |
| **GOAL ON CONTEXT** | To create, edit, delete, search, and filter questions in the shared question bank. |
| **TRIGGER** | The actor wants to add new content or correct existing content in the question bank. |
| **PRE-CONDITION** | The actor is authenticated with the admin role. |
| **FLOW OF EVENTS** | **Actor Action:** 1. The actor opens the Questions tab and searches or filters the list. 3. The actor selects Create, Edit, or Delete, and enters the question stem, choices, rationale, and optional legal citation. <br>**System Response:** 2. The system displays the matching questions. 4. The system validates and saves the change to the shared question bank and appends an audit log entry. |
| **EXCEPTION** | The actor lacks the admin role, in which case the action is blocked by the system's security rules. |
| **POST-CONDITION** | The question bank reflects the change immediately and is visible to all students; an audit record exists. |

### Table 5 — _Use Case Narrative for Manage Admin Roles_

| | |
|---|---|
| **USE CASE NAME** | Manage Admin Roles |
| **PRIMARY ACTOR** | Admin |
| **GOAL ON CONTEXT** | To promote a student account to admin or demote an existing admin back to student. |
| **TRIGGER** | The actor wants to grant or revoke administrative access for another account. |
| **PRE-CONDITION** | The actor is authenticated with the admin role, and the target account exists. |
| **FLOW OF EVENTS** | **Actor Action:** 1. The actor opens Monitor Students and selects "Make Admin" or "Remove Admin Access" for the target account. <br>**System Response:** 2. The system checks whether the target is the actor's own account. 3. If different, the system updates the target's role and appends an audit log entry. |
| **EXCEPTION** | The actor attempts to change their own role, which the system rejects with no change made. |
| **POST-CONDITION** | The target account's role reflects the change, and an audit record exists. |

---

## 4.6 Activity Diagram

It is a visual representation of the workflow or sequence of activities in a system. It shows how processes flow from one action to another, including decisions, parallel processes, and start/end points.

**Example:** An activity diagram is a graphical representation of the workflow of stepwise activities and actions with support for choice, iteration, and concurrency.

**Figure 3**
_Adaptive Quiz-Taking_

Two lanes in a bordered table, per your guide's "Log In" example style: **Student** and **CrimiReview System**.

1. _(initial node)_
2. **[Student]** Select subject and difficulty (Browse Subjects)
3. **[System]** Check device connectivity
4. **[System] Decision:** Connected?
   - [Offline] → Retrieve cached data; queue writes for later sync
   - [Online] → Select Adaptive Question Set (BKT-weighted)
5. _(merge)_
6. **[System]** Display next question
7. **[Student]** Select an answer choice
8. **[System]** Evaluate the selected answer
9. **[System] Decision:** Correct?
   - [Correct] → Update BKT mastery (+evidence); compile explanation confirming the correct choice
   - [Incorrect] → Update BKT mastery (transit evidence); compile the specific wrong-choice rationale + legal citation if available
10. _(merge)_
11. **[System]** Display answer-feedback card (explanation + mastery %)
12. **[System] Decision:** More questions remaining? — [Yes] → repeat from step 6 · [No] → continue
13. **[System]** Mark set served (`question_exposure` ledger)
14. **[System]** Compute score; save `quiz_results`
15. **[Student]** View Results screen
16. _(final node)_

Figure 3 illustrates the workflow for the adaptive quiz-taking process. It starts with the Student selecting a subject and difficulty. The system checks connectivity: offline, it falls back to previously cached data and queues writes for later sync; online, it builds a fresh adaptive question set weighted by the Student's current mastery level. The system then displays each question, the Student answers it, and the system checks whether the answer is correct — either way it updates the Student's Bayesian Knowledge Tracing mastery estimate and compiles an explanation, with a legal citation on wrong answers where one is available. This repeats until no questions remain, at which point the system marks the set as served, scores the quiz, saves the result, and the Student views the Results screen. This diagram visually represents the sequence of actions and interactions between the Student and the system during the quiz-taking process.

**Scope note:** this diagram covers the Subjects → Quiz flow only. Daily Challenge reads the same question bank but does not currently call the mastery-update step, so it is not depicted here.

---

## Formatting notes (from your instructor's guide)

- No frames/boxes around the System Framework or Use Case diagrams.
- Use Case Narrative tables: horizontal rules only, never vertical lines.
- Leave a blank line before and after every inserted table or figure.
- Figure captions sit below the figure; table labels sit above the table.
- Confirm the exact section number for System Framework in your manuscript (used "4.3" here, inferred from 4.4/4.5/4.6 following it).
- If an earlier section already used "Figure 1," renumber Figures 1–3 here to continue that sequence.
- Two limitations are documented honestly rather than glossed over: Daily Challenge doesn't yet update BKT mastery, and explanations are _compiled_ from admin-authored rationale text rather than AI-generated. Worth flagging to your panel as known future work.
