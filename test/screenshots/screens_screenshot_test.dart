// Renders app screens to PNG files so the design can be reviewed without
// a phone. Skipped in normal `flutter test` runs; to produce images:
//
//   flutter test test/screenshots --dart-define=SHOTS=<output folder>
//
// Optional: --dart-define=ONLY=home,auth   (comma-separated name filter)
//
// Uses the app's real bundled font and the Material icon font, sample
// local progress, and no network (Supabase is never initialised here).

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crimireview/models/subject.dart';
import 'package:crimireview/models/user_progress.dart';
import 'package:crimireview/services/adaptive_learning_service.dart';
import 'package:crimireview/services/adaptive_ml_service.dart';
import 'package:crimireview/services/mastery_service.dart';
import 'package:crimireview/services/connectivity_service.dart';
import 'package:crimireview/services/offline_sync_service.dart';
import 'package:crimireview/services/storage_service.dart';
import 'package:crimireview/services/theme_service.dart';

import 'package:crimireview/services/admin_service.dart';
import 'package:crimireview/services/document_generation_service.dart';

import 'admin_fakes.dart';
import 'screen_catalog.dart';

const _outDir = String.fromEnvironment('SHOTS');
const _only = String.fromEnvironment('ONLY');

/// `--dart-define=SWEEP=true`: render every screen at every device in
/// [_sweepDevices] (light mode) and report any layout problem. Images are
/// written only when SHOTS is also given.
const _sweep = bool.fromEnvironment('SWEEP');

/// `--dart-define=DETAILS=true`: print the full error (which widget, where)
/// for each layout problem, not just its first line.
const _details = bool.fromEnvironment('DETAILS');

/// With SWEEP: `--dart-define=ALL_IMAGES=true` saves every render, not only
/// the ones with problems.
const _allImages = bool.fromEnvironment('ALL_IMAGES');

/// Phones, landscape, tablets, desktop/web, and large system text.
const _sweepDevices = <(String, Size, double)>[
  ('phone-se', Size(320, 568), 1.0),
  ('phone-small', Size(360, 640), 1.0),
  ('phone', Size(390, 844), 1.0),
  ('phone-large', Size(430, 932), 1.0),
  ('phone-landscape', Size(844, 390), 1.0),
  ('tablet-7in', Size(600, 960), 1.0),
  ('tablet-10in', Size(800, 1280), 1.0),
  ('tablet-landscape', Size(1280, 800), 1.0),
  ('tablet-12in', Size(1024, 1366), 1.0),
  ('desktop', Size(1440, 900), 1.0),
  ('phone-small-bigtext', Size(360, 640), 1.3),
  ('phone-bigtext', Size(390, 844), 1.3),
];

Future<void> _loadFont(String family, List<String> paths) async {
  final loader = FontLoader(family);
  for (final path in paths) {
    final bytes = File(path).readAsBytesSync();
    loader.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  await loader.load();
}

/// Flutter's bundled Material fonts folder, found by walking up from the
/// test runner's executable (which lives somewhere under flutter/bin/cache).
String _materialFontsDir() {
  final fromEnv = Platform.environment['FLUTTER_ROOT'];
  if (fromEnv != null) {
    final dir = Directory('$fromEnv/bin/cache/artifacts/material_fonts');
    if (dir.existsSync()) return dir.path;
  }
  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 8; i++) {
    final candidate = Directory('${dir.path}/bin/cache/artifacts/material_fonts');
    if (candidate.existsSync()) return candidate.path;
    final nested = Directory('${dir.path}/artifacts/material_fonts');
    if (nested.existsSync()) return nested.path;
    dir = dir.parent;
  }
  throw StateError('Material fonts not found from ${Platform.resolvedExecutable}');
}

Map<String, Object> sampleProgressPrefs() {
  final rnd = [0.82, 0.64, 0.71, 0.45, 0.9, 0.58];
  final progress = UserProgress(userName: 'Juan Dela Cruz');
  progress.currentStreak = 6;
  progress.longestStreak = 11;
  progress.lastActiveDate = DateTime.now();
  progress.unlockedAchievements = ['first_quiz', 'streak_3', 'perfect_score'];
  var i = 0;
  for (final s in CriminologySubjects.all) {
    final answered = 40 + i * 12;
    final correct = (answered * rnd[i % rnd.length]).round();
    final sp = SubjectProgress(
      subjectId: s.id,
      totalQuizzesTaken: 4 + i,
      totalQuestionsAnswered: answered,
      totalCorrectAnswers: correct,
      lastStudyDate: DateTime.now().subtract(Duration(days: i)),
      easyPassed: i < 4,
      mediumPassed: i < 2,
      easyCorrect: 18 + i,
      easyTotal: 22 + i,
      mediumCorrect: 10 + i,
      mediumTotal: 16 + i,
      hardCorrect: i,
      hardTotal: i * 2,
    );
    for (var seg = 0; seg < sp.easySegments.length; seg++) {
      if (seg <= i) {
        sp.easySegments[seg].questionsAnswered = 10;
        sp.easySegments[seg].correctAnswers = 8;
      }
    }
    progress.subjectProgress[s.id] = sp;
    i++;
  }
  return {
    'onboarding_completed': true,
    'user_name': 'Juan Dela Cruz',
    'user_email': 'juan.delacruz@example.com',
    'user_school': 'Philippine College of Criminology',
    'daily_streak': 6,
    'user_progress': progress.toJsonString(),
    // Questions answered per day, for the dashboard's goal ring.
    'daily_activity': jsonEncode({
      StorageService.dayKey(DateTime.now()): 12,
      StorageService.dayKey(DateTime.now().subtract(const Duration(days: 1))): 25,
    }),
  };
}

Map<String, Object> sampleMastery() {
  final rows = [
    ('criminal_jurisprudence', 'Justifying Circumstances', 0.34, 6, 2),
    ('law_enforcement', 'Police Patrol Operations', 0.48, 5, 3),
    ('criminalistics', 'Fingerprint Classification', 0.57, 8, 5),
    ('criminology', 'Theories of Crime Causation', 0.95, 9, 9),
  ];
  return {
    for (final (subject, topic, p, attempts, correct) in rows)
      '$subject::$topic': {
        'subjectId': subject,
        'topic': topic,
        'pKnown': p,
        'attempts': attempts,
        'correct': correct,
        'consecutiveCorrect': 1,
        'lastPracticed': DateTime.now().toIso8601String(),
      },
  };
}

void main() {
  if (_outDir.isEmpty && !_sweep) {
    test('screenshots (skipped: pass --dart-define=SHOTS=<dir>)', () {}, skip: true);
    return;
  }

  setUpAll(() async {
    const fonts = 'assets/fonts';
    await _loadFont(kAppFontFamily, [
      '$fonts/PlusJakartaSans-Regular.ttf',
      '$fonts/PlusJakartaSans-Italic.ttf',
      '$fonts/PlusJakartaSans-Medium.ttf',
      '$fonts/PlusJakartaSans-SemiBold.ttf',
      '$fonts/PlusJakartaSans-Bold.ttf',
      '$fonts/PlusJakartaSans-ExtraBold.ttf',
    ]);
    final material = _materialFontsDir();
    await _loadFont('MaterialIcons', ['$material/materialicons-regular.otf']);
    await _loadFont('Roboto', ['$material/roboto-regular.ttf', '$material/roboto-bold.ttf']);
    if (_outDir.isNotEmpty) Directory(_outDir).createSync(recursive: true);
    AdminService.debugInstance = FakeAdminService();
    DocumentGenerationService.debugInstance = FakeDocumentGenerationService();

    // Learning models the dashboard reads: a few BKT topic records, and
    // the bundled ML model (readiness, recommended difficulty).
    SharedPreferences.setMockInitialValues({'topic_mastery_v1': jsonEncode(sampleMastery())});
    await MasteryService.instance.init();
    try {
      await AdaptiveMLService.instance.initialize();
    } catch (e) {
      // ignore: avoid_print
      print('ML model not loaded for screenshots: $e');
    }
  });

  final filters = _only.isEmpty ? <String>[] : _only.split(',');

  // Normal run: each shot at its own size, light and dark. Sweep: each
  // shot at every device size (light only; colours don't change layout),
  // skipping the size variants that the sweep already covers.
  final runs = <(Shot, String, Size, double, bool)>[
    for (final shot in screenCatalog())
      if (filters.isEmpty || filters.any((f) => shot.name.contains(f)))
        if (!_sweep)
          for (final dark in [false, if (shot.dark) true])
            (shot, '${shot.name}${dark ? '_dark' : ''}', shot.size, 1.0, dark)
        else if (!RegExp(r'_(small|wide)$|^home_full').hasMatch(shot.name))
          for (final (device, size, textScale) in _sweepDevices)
            (shot, '${shot.name}@$device', size, textScale, false),
  ];

  for (final (shot, name, size, textScale, dark) in runs) {
    {
      testWidgets(name, (tester) async {
        SharedPreferences.setMockInitialValues({
          if (shot.seeded) ...sampleProgressPrefs(),
          ...shot.prefs,
        });
        final previous = FlutterError.onError;
        final problems = <String>[];
        FlutterError.onError = (details) {
          final text = details.exceptionAsString();
          // Every layout error, not only overflows: a page that throws
          // during layout renders blank, and that must not pass silently.
          problems.add(_details ? details.toString() : text.split('\n').first);
        };
        tester.view.physicalSize = size * 2;
        tester.view.devicePixelRatio = 2;
        tester.platformDispatcher.textScaleFactorTestValue = textScale;
        final storage = StorageService();
        final key = GlobalKey();
        try {
          await tester.pumpWidget(
            MultiProvider(
              providers: [
                Provider<StorageService>.value(value: storage),
                ChangeNotifierProvider(create: (_) => AdaptiveLearningService(storage)),
                ChangeNotifierProvider(create: (_) => ThemeService()),
                ChangeNotifierProvider.value(value: ConnectivityService.instance),
                ChangeNotifierProvider.value(value: OfflineSyncService.instance),
              ],
              child: RepaintBoundary(
                key: key,
                child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  theme: AppTheme.lightTheme,
                  darkTheme: AppTheme.darkTheme,
                  themeMode: dark ? ThemeMode.dark : ThemeMode.light,
                  home: Builder(builder: shot.builder),
                ),
              ),
            ),
          );
          // Images decode on real async time, not the test's fake clock.
          final ctx = key.currentContext!;
          await tester.runAsync(() => precacheImage(
                const AssetImage('assets/images/logo_mark.png'),
                ctx,
              ));
          for (var i = 0; i < shot.pumps; i++) {
            await tester.pump(const Duration(milliseconds: 250));
          }
          if (shot.act != null) {
            await shot.act!(tester);
            for (var i = 0; i < 8; i++) {
              await tester.pump(const Duration(milliseconds: 250));
            }
          }
          if (_outDir.isNotEmpty && (!_sweep || _allImages || problems.isNotEmpty)) {
            await tester.runAsync(() async {
              final boundary = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
              final image = await boundary.toImage(pixelRatio: _sweep ? 1 : 1.5);
              final data = await image.toByteData(format: ui.ImageByteFormat.png);
              File('$_outDir/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
            });
          }
          if (problems.isNotEmpty) {
            // ignore: avoid_print
            print('LAYOUT PROBLEM in $name: ${problems.join(' | ')}');
          }
        } finally {
          FlutterError.onError = previous;
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          tester.platformDispatcher.clearTextScaleFactorTestValue();
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 3));
      });
    }
  }
}
