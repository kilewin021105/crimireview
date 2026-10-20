// The screens captured by screens_screenshot_test.dart.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crimireview/models/question.dart';
import 'package:crimireview/models/subject.dart';
import 'dart:convert';
import 'dart:io';

import 'package:crimireview/screens/achievements_screen.dart';
import 'package:crimireview/screens/admin/admin_concept_csv_import_screen.dart';
import 'package:crimireview/screens/admin/admin_concept_editor_screen.dart';
import 'package:crimireview/screens/admin/admin_concept_import_screen.dart';
import 'package:crimireview/screens/admin/admin_concepts_screen.dart';
import 'package:crimireview/screens/admin/admin_question_editor_screen.dart';
import 'package:crimireview/screens/admin/admin_questions_screen.dart';
import 'package:crimireview/screens/admin/admin_settings_screen.dart';
import 'package:crimireview/screens/admin/admin_shell_screen.dart';
import 'package:crimireview/screens/admin/admin_students_screen.dart';
import 'package:crimireview/screens/admin/admin_template_generation_screen.dart';
import 'package:crimireview/screens/auth_screen.dart';
import 'package:crimireview/screens/change_password_screen.dart';
import 'package:crimireview/screens/daily_challenge_screen.dart';
import 'package:crimireview/screens/flashcard_screen.dart';
import 'package:crimireview/screens/leaderboard_screen.dart';
import 'package:crimireview/screens/modules_screen.dart';
import 'package:crimireview/screens/profile_screen.dart';
import 'package:crimireview/services/question_repository.dart';
import 'package:crimireview/widgets/ui/ui.dart';

import 'admin_fakes.dart';
import 'package:crimireview/screens/quiz_screen.dart';
import 'package:crimireview/screens/results_screen.dart';
import 'package:crimireview/screens/study_notes_screen.dart';
import 'package:crimireview/screens/email_verification_screen.dart';
import 'package:crimireview/screens/forgot_password_screen.dart';
import 'package:crimireview/screens/home_screen.dart';
import 'package:crimireview/screens/onboarding_screen.dart';
import 'package:crimireview/screens/splash_screen.dart';

class Shot {
  final String name;
  final WidgetBuilder builder;
  final Size size;
  final bool dark;
  final bool seeded;
  final Map<String, Object> prefs;
  final Future<void> Function(WidgetTester tester)? act;

  /// How many 250 ms frames to let pass before capturing.
  final int pumps;

  const Shot(
    this.name,
    this.builder, {
    this.size = const Size(390, 844),
    this.dark = true,
    this.seeded = true,
    this.prefs = const {},
    this.act,
    this.pumps = 12,
  });
}

Future<void> tapText(WidgetTester tester, String text) async {
  final finder = find.text(text);
  if (finder.evaluate().isNotEmpty) {
    await tester.tap(finder.first, warnIfMissed: false);
  }
}

/// Ticks the first tick box on screen (the review list's approve flow).
Future<void> tapFirstCheckbox(WidgetTester tester) async {
  final finder = find.byType(Checkbox);
  if (finder.evaluate().isNotEmpty) {
    await tester.tap(finder.first, warnIfMissed: false);
  }
}

/// Taps a control by its screen-reader name, for icon-only buttons.
Future<void> tapSemantics(WidgetTester tester, String label) async {
  final finder = find.bySemanticsLabel(label);
  if (finder.evaluate().isNotEmpty) {
    await tester.tap(finder.first, warnIfMissed: false);
  }
}

final _subject = CriminologySubjects.all.first;

List<Question> sampleQuestions() => [
      Question(
        id: 'sample-1',
        subject: _subject.id,
        topic: 'Justifying Circumstances',
        questionText:
            'Which of the following is a justifying circumstance under Article 11 of the Revised Penal Code?',
        options: const [
          'Insanity',
          'Self-defense',
          'Minority',
          'Uncontrollable fear',
        ],
        correctAnswerIndex: 1,
        difficulty: Difficulty.easy,
        explanation: 'Self-defense is listed in Article 11; the others are exempting circumstances.',
        legalBasis: 'RPC Art. 11',
      ),
      for (var i = 2; i <= 10; i++)
        Question(
          id: 'sample-$i',
          subject: _subject.id,
          topic: 'Criminal Law Book I',
          questionText: 'Sample question $i about the general provisions of the Revised Penal Code?',
          options: const ['Option one', 'Option two', 'Option three', 'Option four'],
          correctAnswerIndex: 0,
          difficulty: Difficulty.easy,
        ),
    ];

/// Seeds QuestionRepository's offline snapshot so screens that read the
/// question bank (flashcards, Daily Challenge) have something to show.
Map<String, Object> questionBankPrefs() => {
      QuestionRepository.cacheKey: jsonEncode([
        for (var i = 0; i < 12; i++)
          sampleAdminQuestion(i, CriminologySubjects.all[i % 2 == 0 ? 0 : 1].id).toJson(),
      ]),
      QuestionRepository.cacheTimestampKey: DateTime.now().toIso8601String(),
    };

/// A concepts file as a teacher would save it from Excel (screenshots only).
const String _sampleConceptCsv = 'subject,topic,term,definition,legal_basis,group\r\n'
    'Correctional Administration,Executive Clemency,Pardon,An act of grace by the Chief Executive that exempts a person from the punishment the law inflicts for a crime.,"Const. Art. VII, Sec. 19",\r\n'
    'Correctional Administration,Executive Clemency,Commutation,A reduction of a sentence to a lighter penalty granted by the Chief Executive.,"Const. Art. VII, Sec. 19",\r\n'
    'Correctional Administration,Executive Clemency,Reprieve,A temporary suspension of the execution of a sentence granted by the Chief Executive.,"Const. Art. VII, Sec. 19",\r\n'
    'Corrections,probation law,Probationer,A person placed on probation by the court after conviction.,"PD 968, Sec. 3",\r\n'
    'Criminal Law and Jurisprudence,Justifying Circumstances,Self-Defense,Acting in defense of one\'s own person or rights under the conditions of Article 11.,RPC Art. 11(1),\r\n'
    'Ethics,Values,Integrity,Doing what is right even when no one is watching.,,\r\n';

List<Shot> screenCatalog() => [
      Shot('splash', (_) => const SplashScreen(), seeded: false, pumps: 6),
      Shot('onboarding', (_) => const OnboardingScreen(), seeded: false),
      Shot('auth_login', (_) => const AuthScreen(), seeded: false),
      Shot('auth_login_small', (_) => const AuthScreen(),
          seeded: false, dark: false, size: const Size(320, 568)),
      Shot('auth_signup', (_) => const AuthScreen(),
          seeded: false, act: (t) => tapText(t, 'Create account')),
      // Not switched on yet: tapping the Google icon under the form says so.
      Shot('auth_login_google_off', (_) => const AuthScreen(),
          seeded: false, dark: false, act: (t) => tapSemantics(t, 'Continue with Google')),
      Shot('forgot_password', (_) => const ForgotPasswordScreen(), seeded: false),
      Shot(
        'email_verification',
        (_) => const EmailVerificationScreen(
          email: 'juan.delacruz@example.com',
          password: 'Password1',
          displayName: 'Juan Dela Cruz',
        ),
        seeded: false,
      ),
      Shot('home', (_) => const HomeScreen()),
      Shot('home_small', (_) => const HomeScreen(), dark: false, size: const Size(320, 640)),
      // The whole dashboard in one tall image.
      Shot('home_full', (_) => const HomeScreen(), size: const Size(390, 2050)),
      Shot('home_full_small', (_) => const HomeScreen(), dark: false, size: const Size(320, 2150)),
      // A brand-new student: nothing studied yet.
      Shot('home_new_student', (_) => const HomeScreen(),
          seeded: false, dark: false, prefs: const {'onboarding_completed': true, 'user_name': 'Bea Ramos'}),
      Shot('tab_quiz', (_) => const HomeScreen(), act: (t) => tapText(t, 'Quiz')),
      Shot('tab_cards', (_) => const HomeScreen(), act: (t) => tapText(t, 'Cards')),
      Shot('tab_progress', (_) => const HomeScreen(), act: (t) => tapText(t, 'Progress')),
      Shot('tab_settings', (_) => const HomeScreen(), act: (t) => tapText(t, 'Settings')),
      // The whole Settings tab in one tall image (Support links at the end).
      Shot('tab_settings_full', (_) => const HomeScreen(),
          dark: false, size: const Size(390, 1500), act: (t) => tapText(t, 'Settings')),
      Shot(
        'study_notes',
        (_) => StudyNotesScreen(
          subject: _subject,
          difficulty: Difficulty.easy,
          questions: sampleQuestions(),
          segmentIndex: 0,
        ),
      ),
      Shot(
        'quiz',
        (_) => QuizScreen(
          subject: _subject,
          questions: sampleQuestions(),
          difficulty: Difficulty.easy,
          segmentIndex: 0,
        ),
      ),
      // An answer tapped but not checked yet: ink, not red.
      Shot(
        'quiz_selected',
        (_) => QuizScreen(
          subject: _subject,
          questions: sampleQuestions(),
          difficulty: Difficulty.easy,
          segmentIndex: 0,
        ),
        act: (t) => tapText(t, 'Self-defense'),
      ),
      Shot(
        'quiz_answered',
        (_) => QuizScreen(
          subject: _subject,
          questions: sampleQuestions(),
          difficulty: Difficulty.easy,
          segmentIndex: 0,
        ),
        dark: false,
        act: (t) async {
          // The options are shuffled; pick whichever shows the right answer.
          await tapText(t, 'Self-defense');
          await t.pump(const Duration(milliseconds: 300));
          await tapText(t, 'Check answer');
        },
      ),
      Shot(
        'results',
        (_) => ResultsScreen(
          subject: _subject,
          questions: sampleQuestions(),
          results: const [true, true, true, false, true, true, true, true, false, true],
          responseTimes: const [8000, 6500, 12000, 9000, 7000, 5000, 11000, 6000, 15000, 7000],
          difficulty: Difficulty.easy,
          segmentIndex: 0,
        ),
      ),
      Shot('flashcards', (_) => FlashcardScreen(subject: _subject), dark: false, prefs: questionBankPrefs()),
      Shot('modules', (_) => ModulesScreen(subject: _subject)),
      Shot(
        'module_reader',
        (_) => ModuleReaderScreen(
          moduleData: jsonDecode(File('assets/modules/criminal_jurisprudence_module.json').readAsStringSync())
              as Map<String, dynamic>,
          accent: AppColors.subjectColor(_subject.id),
        ),
      ),
      Shot('achievements', (_) => const AchievementsScreen()),
      Shot(
        'leaderboard',
        (_) => Scaffold(
          appBar: const AppTopBar(title: 'Leaderboard', subtitle: 'Compete with fellow reviewers'),
          body: LeaderboardView(
            entries: [
              for (final (i, n, s, r) in [
                (1, 'Maria Santos', 2480, 'Master'),
                (2, 'Paolo Reyes', 2210, 'Expert'),
                (3, 'Ana Villanueva', 1985, 'Expert'),
                (4, 'Juan Dela Cruz', 1240, 'Advanced'),
                (5, 'Carlo Mendoza', 990, 'Intermediate'),
                (6, 'Bea Ramos', 640, 'Rookie'),
              ])
                LeaderboardEntry(
                  id: 'u$i',
                  name: n,
                  score: s,
                  rank: r,
                  position: i,
                  isCurrentUser: i == 4,
                ),
            ],
            userRank: 4,
            onRefresh: () async {},
          ),
        ),
      ),
      Shot('profile', (_) => const ProfileScreen()),
      Shot('change_password', (_) => const ChangePasswordScreen(), dark: false),
      Shot('daily_challenge', (_) => const DailyChallengeScreen(), prefs: questionBankPrefs()),
      Shot('admin_shell', (_) => const AdminShellScreen()),
      Shot('admin_shell_wide', (_) => const AdminShellScreen(), size: const Size(1280, 800)),
      Shot('admin_settings', (_) => const AdminSettingsScreen()),
      Shot('admin_settings_tab', (_) => const AdminShellScreen(),
          dark: false, act: (t) => tapText(t, 'Settings')),
      Shot('admin_settings_wide', (_) => const AdminShellScreen(),
          dark: false, size: const Size(1280, 800), act: (t) => tapText(t, 'Settings')),
      Shot('admin_questions', (_) => const AdminQuestionsScreen(showBackButton: false)),
      Shot('admin_editor', (_) => AdminQuestionEditorScreen(existing: sampleAdminQuestion(0, _subject.id))),
      Shot('admin_students', (_) => const AdminStudentsScreen(showBackButton: false)),
      Shot('admin_templates', (_) => const AdminTemplateGenerationScreen()),
      Shot('admin_concepts', (_) => const AdminConceptsScreen()),
      Shot(
        'admin_concept_new',
        (_) => const AdminConceptEditorScreen(
          concepts: sampleConcepts,
          presetSubjectId: 'corrections',
          presetTopic: 'Probation Law',
        ),
      ),
      Shot('admin_concept_edit',
          (_) => AdminConceptEditorScreen(existing: sampleConcepts.first, concepts: sampleConcepts),
          dark: false),
      Shot(
        'admin_concept_import',
        (_) => const AdminConceptImportScreen(
          concepts: sampleConcepts,
          presetSubjectId: 'corrections',
          presetTopic: 'Probation Law',
          initialText: 'Term | Definition | Legal basis\n'
              'Pardon | An act of grace by the Chief Executive that exempts a person from punishment. | Const. Art. VII, Sec. 19\n'
              'Reprieve | A temporary suspension of the execution of a sentence by the Chief Executive.\n'
              'Commutation | A reduction of a sentence to a lighter penalty granted by the Chief Executive. | Const. Art. VII, Sec. 19\n'
              'this line has no separator\n'
              'Amnesty | short',
        ),
      ),
      Shot(
        'admin_concept_import_tall',
        (_) => const AdminConceptImportScreen(
          concepts: sampleConcepts,
          presetSubjectId: 'corrections',
          presetTopic: 'Probation Law',
          initialText: 'Term | Definition | Legal basis\n'
              'Pardon | An act of grace by the Chief Executive that exempts a person from punishment. | Const. Art. VII, Sec. 19\n'
              'Reprieve | A temporary suspension of the execution of a sentence by the Chief Executive.\n'
              'Commutation | A reduction of a sentence to a lighter penalty granted by the Chief Executive. | Const. Art. VII, Sec. 19\n'
              'this line has no separator\n'
              'Amnesty | short',
        ),
        dark: false,
        size: const Size(390, 1500),
      ),
      // CSV upload: before a file is chosen, and with a sample file that adds
      // a new topic, adds to an existing one, and has two lines to skip.
      Shot('admin_concept_csv_empty', (_) => const AdminConceptCsvImportScreen(concepts: sampleConcepts)),
      Shot(
        'admin_concept_csv',
        (_) => const AdminConceptCsvImportScreen(
          concepts: sampleConcepts,
          initialCsvText: _sampleConceptCsv,
          initialFileName: 'Corrections concepts.csv',
        ),
      ),
      Shot(
        'admin_concept_csv_tall',
        (_) => const AdminConceptCsvImportScreen(
          concepts: sampleConcepts,
          initialCsvText: _sampleConceptCsv,
          initialFileName: 'Corrections concepts.csv',
        ),
        dark: false,
        size: const Size(390, 1900),
      ),
      // Generated questions waiting for review, one ticked.
      Shot(
        'admin_review',
        (_) => const AdminQuestionsScreen(
          initialSource: QuestionSource.generated,
          initialTemplateId: 'tpl_sample',
        ),
        act: tapFirstCheckbox,
      ),
    ];
