// Renders app screens to PNG files so the design can be reviewed without
// a phone. Skipped in normal `flutter test` runs; to produce images:
//
//   flutter test test/screenshots --dart-define=SHOTS=<output folder>
//
// Optional: --dart-define=ONLY=home,auth   (comma-separated name filter)
//
// Uses the app's real bundled font and the Material icon font, sample
// local progress, and no network (Supabase is never initialised here).

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
import 'package:crimireview/services/connectivity_service.dart';
import 'package:crimireview/services/offline_sync_service.dart';
import 'package:crimireview/services/storage_service.dart';
import 'package:crimireview/services/theme_service.dart';

import 'package:crimireview/services/admin_service.dart';

import 'admin_fakes.dart';
import 'screen_catalog.dart';

const _outDir = String.fromEnvironment('SHOTS');
const _only = String.fromEnvironment('ONLY');

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
  };
}

void main() {
  if (_outDir.isEmpty) {
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
    Directory(_outDir).createSync(recursive: true);
    AdminService.debugInstance = FakeAdminService();
  });

  final filters = _only.isEmpty ? <String>[] : _only.split(',');

  for (final shot in screenCatalog()) {
    if (filters.isNotEmpty && !filters.any((f) => shot.name.contains(f))) continue;
    for (final dark in [false, if (shot.dark) true]) {
      final name = '${shot.name}${dark ? '_dark' : ''}';
      testWidgets(name, (tester) async {
        SharedPreferences.setMockInitialValues({
          if (shot.seeded) ...sampleProgressPrefs(),
          ...shot.prefs,
        });
        final previous = FlutterError.onError;
        final problems = <String>[];
        FlutterError.onError = (details) {
          final text = details.exceptionAsString();
          if (text.contains('overflowed')) problems.add(text.split('\n').first);
        };
        tester.view.physicalSize = shot.size * 2;
        tester.view.devicePixelRatio = 2;
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
          await tester.runAsync(() async {
            final boundary = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
            final image = await boundary.toImage(pixelRatio: 1.5);
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            File('$_outDir/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
          });
          if (problems.isNotEmpty) {
            // ignore: avoid_print
            print('OVERFLOW in $name: ${problems.join(' | ')}');
          }
        } finally {
          FlutterError.onError = previous;
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 3));
      });
    }
  }
}
