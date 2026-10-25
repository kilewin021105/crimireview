// The PRC Tables of Specifications (TOS) and everything built on them:
// the TOS file, subject topics, readiness weights, the old-topic map, the
// TOS question bank, the study modules and the study notes.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:crimireview/models/mastery.dart';
import 'package:crimireview/models/question.dart';
import 'package:crimireview/models/subject.dart';
import 'package:crimireview/models/tos.dart';
import 'package:crimireview/models/user_progress.dart';
import 'package:crimireview/services/adaptive_learning_service.dart';
import 'package:crimireview/services/admin_service.dart';
import 'package:crimireview/services/mastery_service.dart';
import 'package:crimireview/services/study_notes_service.dart';

Map<String, dynamic> _json(String path) => jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

void main() {
  final tosJson = _json('assets/tos/tos_2024.json');
  final tos = TosCatalog.fromJson(tosJson);
  final topicMap = TosTopicMap.fromJson(_json('assets/tos/topic_map.json'), tos);

  group('TOS file', () {
    test('six subjects of 100 items whose topics, competencies and Bloom levels add up', () {
      expect(tos.subjects.map((s) => s.subjectId), CriminologySubjects.all.map((s) => s.id));
      for (final s in tos.subjects) {
        expect(s.topics.fold<int>(0, (n, t) => n + t.items), 100, reason: s.code);
        for (final t in s.topics) {
          expect(t.competencies.fold<int>(0, (n, c) => n + c.items), t.items, reason: t.code);
          for (final level in BloomLevel.values) {
            expect(t.competencies.fold<int>(0, (n, c) => n + (c.bloom[level] ?? 0)), t.bloom[level] ?? 0,
                reason: '${t.code} ${level.label}');
          }
          for (final c in t.competencies) {
            expect(c.bloom.values.fold<int>(0, (n, v) => n + v), c.items, reason: c.code);
            expect(c.code, startsWith('${t.code}.'));
          }
        }
      }
      expect(tos.subjects.expand((s) => s.topics).length, 37);
      expect(tos.subjects.expand((s) => s.competencies).length, 146);
    });

    test('cites Res. No. 02 s. 2024 and its 2025 amendment of Criminology Topic 4', () {
      expect(tos.resolution, contains('No. 02, Series of 2024'));
      expect(tos.amendment, contains('No. 06, Series of 2025'));
      final crim4 = tos.topic('CRIM-4')!;
      expect(crim4.title, 'Professional Conduct and Ethical Standards for Criminologists');
      expect(crim4.items, 15);
      expect(crim4.amendedBy, contains('06'));
    });

    test('subject weights and topics in the app match the TOS', () {
      for (final subject in CriminologySubjects.all) {
        final t = tos.subject(subject.id)!;
        expect(subject.weight, t.weight, reason: subject.id);
        expect(subject.topics, t.topics.map((x) => x.title).toList(), reason: subject.id);
      }
      expect(CriminologySubjects.all.fold<int>(0, (n, s) => n + s.weight), 100);
    });

    test('lookups by code and title', () {
      expect(tos.topicOf('CLJ-3.4')!.code, 'CLJ-3');
      expect(tos.topicOf('CLJ-3')!.title, 'Criminal Law (Book 1)');
      expect(tos.topicOf('CLJ-9.9'), isNull);
      expect(tos.topicByTitle('criminal_jurisprudence', ' criminal law (book 1) ')!.code, 'CLJ-3');
      expect(tos.isKnownCode('FS-6.2'), isTrue);
      expect(tos.isKnownCode('FS-6.9'), isFalse);
    });
  });

  group('Bloom levels and readiness weights', () {
    test('Remembering and Understanding are easy, Applying medium, the rest hard', () {
      expect(BloomLevel.remembering.difficulty, Difficulty.easy);
      expect(BloomLevel.understanding.difficulty, Difficulty.easy);
      expect(BloomLevel.applying.difficulty, Difficulty.medium);
      expect(BloomLevel.analyzing.difficulty, Difficulty.hard);
      expect(BloomLevel.evaluating.difficulty, Difficulty.hard);
      expect(BloomLevel.creating.difficulty, Difficulty.hard);
      expect(BloomLevel.tryParse('Applying'), BloomLevel.applying);
      expect(BloomLevel.tryParse('an'), BloomLevel.analyzing);
      expect(BloomLevel.tryParse('Guessing'), isNull);
    });

    test('each subject\'s difficulty mix is its TOS Bloom split', () {
      for (final s in tos.subjects) {
        final byDifficulty = {for (final d in Difficulty.values) d: 0};
        for (final t in s.topics) {
          t.bloom.forEach((level, n) => byDifficulty[level.difficulty] = byDifficulty[level.difficulty]! + n);
        }
        final mix = TosDifficultyMix.forSubject(s.subjectId);
        expect([mix.easy, mix.medium, mix.hard],
            [byDifficulty[Difficulty.easy], byDifficulty[Difficulty.medium], byDifficulty[Difficulty.hard]],
            reason: s.code);
      }
    });

    test('subject readiness uses the subject\'s TOS mix', () {
      // LEA is 31 / 49 / 20. Easy all correct; medium and hard not tried
      // count as the 40% baseline; +5 x 1/3 for one level attempted.
      final p = SubjectProgress(subjectId: 'law_enforcement', easyCorrect: 10, easyTotal: 10);
      expect(p.boardExamReadiness, closeTo((0.31 * 1 + 0.49 * 0.4 + 0.20 * 0.4) * 100 + 5 / 3, 1e-9));
    });

    test('overall readiness weights subjects by their share of the examination', () {
      final crimLaw = SubjectProgress(subjectId: 'criminal_jurisprudence', easyCorrect: 10, easyTotal: 10,
          mediumCorrect: 10, mediumTotal: 10, hardCorrect: 10, hardTotal: 10); // 100 (+5, clamped)
      final corrections = SubjectProgress(subjectId: 'corrections', easyCorrect: 5, easyTotal: 10,
          mediumCorrect: 5, mediumTotal: 10, hardCorrect: 5, hardTotal: 10); // 50 + 5 = 55
      final overall = AdaptiveLearningService.overallReadinessFrom(
          {'criminal_jurisprudence': crimLaw, 'corrections': corrections});
      expect(crimLaw.boardExamReadiness, 100);
      expect(corrections.boardExamReadiness, closeTo(55, 1e-9));
      expect(overall, closeTo((100 * 20 + 55 * 10) / 30, 1e-9));
    });
  });

  group('Old topics', () {
    test('the map sends every old topic to a TOS topic or retires it', () {
      final r = topicMap.resolve('criminal_jurisprudence', 'Criminal Law Book I')!;
      expect(r.subjectId, 'criminal_jurisprudence');
      expect(r.topic, 'Criminal Law (Book 1)');
      // The TOS puts Legal Medicine in Crime Detection and Investigation.
      final lm = topicMap.resolve('criminalistics', 'legal medicine')!;
      expect(lm.subjectId, 'crime_detection');
      expect(lm.topic, 'Specialized Crime Investigation 1 with Legal Medicine');
      expect(topicMap.resolve('law_enforcement', 'Police Communication System'), isNull);
      // TOS titles and topics outside the map are kept as they are.
      expect(topicMap.resolve('criminology', 'Theories of Crime Causation')!.topic, 'Theories of Crime Causation');
      expect(topicMap.resolve('corrections', 'Something new')!.topic, 'Something new');
    });

    test('every code in the map exists in the TOS', () {
      final map = _json('assets/tos/topic_map.json');
      for (final entries in (map['topics'] as Map).values) {
        for (final code in (entries as Map).values) {
          if (code != null) expect(tos.topic(code as String), isNotNull, reason: code);
        }
      }
      for (final code in (map['overrides'] as Map).values) {
        expect(tos.topic(code as String), isNotNull, reason: code);
      }
      expect((map['flagged']['ids'] as List).length, 16);
    });

    test('saved topic mastery is merged onto TOS topics like the SQL does', () {
      final now = DateTime(2026, 10, 24);
      final aligned = MasteryService.alignTopics([
        TopicMastery(subjectId: 'criminal_jurisprudence', topic: 'Criminal Law Book I', pKnown: 0.95,
            attempts: 6, correct: 6, consecutiveCorrect: 6, lastPracticed: now.subtract(const Duration(days: 2))),
        TopicMastery(subjectId: 'criminal_jurisprudence', topic: 'Justifying Circumstances', pKnown: 0.40,
            attempts: 2, correct: 1, lastPracticed: now.subtract(const Duration(days: 1))),
        TopicMastery(subjectId: 'criminalistics', topic: 'Legal Medicine', pKnown: 0.70, attempts: 4, correct: 3),
        TopicMastery(subjectId: 'law_enforcement', topic: 'Police Communication System', pKnown: 0.5, attempts: 3),
      ], topicMap);
      expect(aligned.length, 2);
      final book1 = aligned.firstWhere((m) => m.topic == 'Criminal Law (Book 1)');
      expect(book1.attempts, 8);
      expect(book1.correct, 7);
      expect(book1.pKnown, closeTo((0.95 * 6 + 0.40 * 2) / 8, 1e-9)); // 0.8125, as in the SQL test
      expect(book1.consecutiveCorrect, 6);
      expect(book1.lastPracticed, now.subtract(const Duration(days: 1)));
      expect(book1.isMastered, isFalse);
      final legal = aligned.firstWhere((m) => m.subjectId == 'crime_detection');
      expect(legal.topic, 'Specialized Crime Investigation 1 with Legal Medicine');
      expect(MasteryService.alignTopics(aligned, null).length, 2);
    });
  });

  group('Question TOS fields', () {
    test('read from a row, written only when set', () {
      final row = {
        'id': 'tos24_CLJ-3.4_01',
        'subject_id': 'criminal_jurisprudence',
        'topic': 'Criminal Law (Book 1)',
        'question_text': 'Q?',
        'options': [
          {'text': 'A', 'is_correct': true, 'rationale': ''},
          {'text': 'B', 'is_correct': false, 'rationale': ''},
        ],
        'difficulty': 'medium',
        'tos_code': 'CLJ-3.4',
        'bloom_level': 'Applying',
      };
      final q = Question.fromJson(row);
      expect(q.tosCode, 'CLJ-3.4');
      expect(q.bloomLevel, 'Applying');
      expect(q.toSupabaseRow()['tos_code'], 'CLJ-3.4');
      expect(Question.fromJson(q.toJson()).bloomLevel, 'Applying');
      final plain = q.copyWith(topic: 'Other');
      expect(plain.tosCode, 'CLJ-3.4');
      final unlinked = Question(id: 'x', subject: 's', topic: 't', questionText: 'q', options: const ['a', 'b'],
          correctAnswerIndex: 0, difficulty: Difficulty.easy);
      expect(unlinked.toSupabaseRow().containsKey('tos_code'), isFalse);
      expect(unlinked.toSupabaseRow().containsKey('bloom_level'), isFalse);
    });

    test('coverage rows and their error messages', () {
      final row = TosCoverageRow.fromJson(
          {'code': 'CLJ-3.4', 'subject_id': 'criminal_jurisprudence', 'topic_code': 'CLJ-3', 'level': 'competency',
           'tos_items': 6, 'active': 6, 'drafts': 2});
      expect(row.isTopic, isFalse);
      expect(row.isCovered, isTrue);
      expect(AdminService.tosCoverageErrorMessage('PGRST202'), contains('supabase_tos_alignment.sql'));
      expect(AdminService.tosCoverageErrorMessage('42501'), contains('faculty'));
    });
  });

  group('TOS question bank', () {
    final codes = {for (final s in tos.subjects) s.code: s};
    const bloomCodes = {'R': 0, 'U': 1, 'Ap': 2, 'An': 3, 'E': 4, 'C': 5};

    test('600 questions with exactly the TOS items per competency and Bloom level', () {
      var total = 0;
      for (final entry in codes.entries) {
        final counts = <String, Map<BloomLevel, int>>{};
        final lines = File('content/tos/bank/${entry.key.toLowerCase()}.jsonl')
            .readAsLinesSync()
            .where((l) => l.trim().isNotEmpty);
        for (final line in lines) {
          final q = jsonDecode(line) as Map<String, dynamic>;
          final level = BloomLevel.values[bloomCodes[q['b']]!];
          final perLevel = counts.putIfAbsent(q['c'] as String, () => {});
          perLevel[level] = (perLevel[level] ?? 0) + 1;
          expect((q['a'] as List).toSet().length, 4, reason: q['q'] as String);
          expect((q['r'] as List).length, 4);
          total++;
        }
        for (final c in entry.value.competencies) {
          expect(counts[c.code] ?? const {}, c.bloom, reason: c.code);
        }
      }
      expect(total, 600);
    });

    test('the generated SQL inserts all 600, inactive and linked to the TOS', () {
      final sql = File('supabase_tos_bank.sql').readAsStringSync();
      final inserts = RegExp(r'^INSERT INTO public\.questions', multiLine: true).allMatches(sql).length;
      expect(inserts, 600);
      expect(RegExp(r"'generated', 'tos_2024', 1, FALSE, '[A-Z]+-\d\.\d+'").allMatches(sql).length, 600);
    });
  });

  group('Study modules and notes', () {
    test('one chapter per TOS topic, one key point per competency', () {
      for (final s in tos.subjects) {
        final module = _json('assets/modules/${s.subjectId}_module.json');
        final chapters = module['chapters'] as List;
        expect(chapters.map((c) => c['code']), s.topics.map((t) => t.code), reason: s.code);
        for (var i = 0; i < chapters.length; i++) {
          final c = chapters[i] as Map;
          final t = s.topics[i];
          expect(c['title'], t.title);
          expect(c['number'], t.number);
          expect(c['itemCount'], t.items);
          expect((c['keyPoints'] as List).map((p) => p['code']), t.competencies.map((x) => x.code));
          expect((c['keyTerms'] as List).length, greaterThanOrEqualTo(4));
          expect((c['content'] as String), contains('### ${t.competencies.first.number} '));
        }
      }
    });

    test('study notes follow the quiz questions\' competencies', () {
      final module = _json('assets/modules/criminal_jurisprudence_module.json');
      Question q(String code, String topic) => Question(id: code, subject: 'criminal_jurisprudence', topic: topic,
          questionText: 'q', options: const ['a', 'b'], correctAnswerIndex: 0, difficulty: Difficulty.medium,
          tosCode: code);
      final content = StudyNotesService.pick(module, [
        q('CLJ-3.4', 'Criminal Law (Book 1)'),
        q('CLJ-3.4', 'Criminal Law (Book 1)'),
        q('CLJ-5.4', 'Criminal Evidence'),
      ]);
      expect(content.notes.first.code, 'CLJ-3.4');
      expect(content.notes[1].code, 'CLJ-5.4');
      expect(content.notes.length, 6);
      expect(content.topics, ['Criminal Law (Book 1)', 'Criminal Evidence']);
      expect(content.keyTerms, isNotEmpty);
      // A question on an old topic name still finds its notes by title...
      final byTitle = StudyNotesService.pick(module, [
        Question(id: 'x', subject: 'criminal_jurisprudence', topic: 'Criminal Evidence', questionText: 'q',
            options: const ['a', 'b'], correctAnswerIndex: 0, difficulty: Difficulty.easy),
      ]);
      expect(byTitle.notes.every((n) => n.code.startsWith('CLJ-5.')), isTrue);
      // ...and with nothing to match, the notes span the chapters.
      final none = StudyNotesService.pick(module, const []);
      expect(none.notes.map((n) => n.code.split('.').first).toSet().length, 6);
    });
  });
}
