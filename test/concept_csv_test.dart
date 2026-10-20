// CSV upload of concepts for many topics (lib/utils/concept_csv.dart) and the
// import step that sends it (ConceptService.importCsvPlan).
//
// Run: flutter test test/concept_csv_test.dart

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:crimireview/models/concept.dart';
import 'package:crimireview/models/subject.dart';
import 'package:crimireview/services/concept_service.dart';
import 'package:crimireview/utils/concept_csv.dart';
import 'package:crimireview/utils/concept_import_parser.dart';

const _def = 'A definition that is long enough to pass the checks';

Concept _concept(
  String term, {
  String subject = 'criminal_jurisprudence',
  String topic = 'Justifying Circumstances',
  String group = 'rpc_art11_justifying',
  String? basis,
  String? definition,
  bool active = true,
}) =>
    Concept(
      id: 'cb_$term',
      subjectId: subject,
      topic: topic,
      term: term,
      definition: definition ?? '$_def for $term.',
      legalBasis: basis,
      siblingGroup: group,
      isActive: active,
    );

String _csv(List<String> rows) => '${rows.join('\r\n')}\r\n';

const _header = 'subject,topic,term,definition,legal_basis,group';

void main() {
  group('template', () {
    test('reads back as 3 concepts in one new topic, with no problems', () {
      final plan = planConceptCsv(conceptCsvTemplate(), existing: const []);
      expect(plan.fileError, isNull);
      expect(plan.problems, isEmpty);
      expect(plan.conceptCount, 3);
      expect(plan.topics, hasLength(1));
      expect(plan.topics.single.subjectId, 'criminal_jurisprudence');
      expect(plan.topics.single.topic, 'Justifying Circumstances');
      expect(plan.topics.single.isNew, isTrue);
      expect(plan.batches.single.rows.map((r) => r.legalBasis),
          ['RPC Art. 11(1)', 'RPC Art. 11(3)', 'RPC Art. 11(6)']);
    });

    test('uploaded unchanged next to the seeded concepts, every row is reported as already there', () {
      final existing = [
        _concept('Self-Defense'),
        _concept('Defense of a Stranger'),
        _concept('Obedience to a Lawful Order of a Superior'),
      ];
      final plan = planConceptCsv(conceptCsvTemplate(), existing: existing);
      expect(plan.conceptCount, 0);
      expect(plan.problems, hasLength(3));
      expect(plan.problems.first.message, contains('already in "Justifying Circumstances"'));
    });

    test('the file starts with the UTF-8 mark and decodes to the same text', () {
      final bytes = conceptCsvTemplateBytes();
      expect(bytes.sublist(0, 3), [0xEF, 0xBB, 0xBF]);
      expect(decodeConceptCsv(bytes), conceptCsvTemplate());
    });
  });

  group('reading CSV text', () {
    test('quoted cells keep commas, line breaks and doubled quotes', () {
      final table = parseCsvTable('a,"b, c","line 1\nline 2","say ""hi"""\r\nx,y,z,w\r\n');
      expect(table.records, hasLength(2));
      expect(table.records[0].cells, ['a', 'b, c', 'line 1\nline 2', 'say "hi"']);
      expect(table.records[1].line, 3, reason: 'the second row starts on line 3');
      expect(table.unclosedQuoteLine, isNull);
    });

    test('finds a semicolon or Tab separator from the first line', () {
      expect(parseCsvTable('subject;topic;term\na;b;c').delimiter, ';');
      expect(parseCsvTable('subject\ttopic\tterm\na\tb\tc').delimiter, '\t');
      expect(parseCsvTable('subject,topic,term\na,b,c').delimiter, ',');
      expect(parseCsvTable('subject;topic;term\na;b, with comma;c').records[1].cells,
          ['a', 'b, with comma', 'c']);
    });

    test('reports a quote that is never closed', () {
      final table = parseCsvTable('a,b\r\nc,"never closed\r\nd,e\r\n');
      expect(table.unclosedQuoteLine, 2);
    });
  });

  group('decoding bytes', () {
    test('Windows-1252 from Excel keeps ñ and curly quotes', () {
      // "Niño" and “x” in Windows-1252, which is not valid UTF-8.
      final bytes = Uint8List.fromList([0x4E, 0x69, 0xF1, 0x6F, 0x20, 0x93, 0x78, 0x94]);
      expect(decodeConceptCsv(bytes), 'Niño “x”');
    });

    test('UTF-8 with and without the mark, and UTF-16', () {
      expect(decodeConceptCsv(Uint8List.fromList(utf8.encode('Niño'))), 'Niño');
      expect(decodeConceptCsv(Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode('Niño')])), 'Niño');
      final utf16le = <int>[0xFF, 0xFE];
      for (final unit in 'Niño'.codeUnits) {
        utf16le..add(unit & 0xFF)..add(unit >> 8);
      }
      expect(decodeConceptCsv(Uint8List.fromList(utf16le)), 'Niño');
    });
  });

  group('header', () {
    test('other column names are accepted, ignoring case and spaces', () {
      final plan = planConceptCsv(
        _csv([
          'Subject, Topic ,Concept,Meaning,Basis,Sibling Group,Notes',
          'Criminology,Theories of Crime,Anomie,$_def about norms.,,,my note',
        ]),
        existing: const [],
      );
      expect(plan.fileError, isNull);
      expect(plan.conceptCount, 1);
      expect(plan.ignoredColumns, ['Notes']);
    });

    test('a missing required column is named', () {
      final plan = planConceptCsv(_csv(['subject,term,definition', 'Criminology,A,$_def.']),
          existing: const []);
      expect(plan.fileError, contains('Missing: topic'));
      expect(plan.canImport, isFalse);
    });

    test('a file without a header row is refused', () {
      final plan = planConceptCsv(_csv(['Criminology,Theories,Anomie,$_def.']), existing: const []);
      expect(plan.fileError, contains('first row must name the columns'));
    });

    test('a column named twice is refused', () {
      final plan = planConceptCsv(_csv(['subject,topic,term,definition,basis,legal basis']),
          existing: const []);
      expect(plan.fileError, contains('appears twice'));
    });

    test('an empty file is refused', () {
      expect(planConceptCsv('\r\n , ,\r\n', existing: const []).fileError, 'The file is empty.');
    });
  });

  group('subjects', () {
    test('names, short names, ids and the usual other names all resolve', () {
      for (final s in CriminologySubjects.all) {
        expect(resolveConceptSubject(s.name), s.id);
        expect(resolveConceptSubject(s.shortName), s.id);
        expect(resolveConceptSubject(s.id), s.id);
        expect(resolveConceptSubject(s.name.toUpperCase()), s.id);
      }
      expect(resolveConceptSubject('CLJ'), 'criminal_jurisprudence');
      expect(resolveConceptSubject('Criminal Jurisprudence and Procedure'), 'criminal_jurisprudence');
      expect(resolveConceptSubject('LEA'), 'law_enforcement');
      expect(resolveConceptSubject('Criminalistics'), 'criminalistics');
      expect(resolveConceptSubject('cdi'), 'crime_detection');
      expect(resolveConceptSubject('Criminal Sociology'), 'criminology');
      expect(resolveConceptSubject('Correctional Admin.'), isNull);
      expect(resolveConceptSubject('Crim'), isNull, reason: 'could be two subjects');
      expect(resolveConceptSubject(''), isNull);
    });

    test('an unknown subject skips only that line', () {
      final plan = planConceptCsv(
        _csv([_header, 'Ethics,Values,Integrity,$_def.,,', 'Criminology,Theories,Anomie,$_def.,,']),
        existing: const [],
      );
      expect(plan.conceptCount, 1);
      expect(plan.problems.single.line, 2);
      expect(plan.problems.single.message, contains('not one of the six subjects'));
    });
  });

  group('topics and groups', () {
    test('an existing topic is matched ignoring case and extra spaces', () {
      final plan = planConceptCsv(
        _csv([_header, 'Crim Law,  justifying   circumstances ,Fulfillment of Duty,$_def.,RPC Art. 11(5),']),
        existing: [_concept('Self-Defense')],
      );
      expect(plan.topics.single.isNew, isFalse);
      expect(plan.batches.single.topic, 'Justifying Circumstances');
      expect(plan.batches.single.group, isNull, reason: 'the database uses the topic\'s only group');
    });

    test('a topic with several groups needs the group column', () {
      final existing = [
        _concept('PNP', subject: 'law_enforcement', topic: 'DILG Bureaus', group: 'dilg_a'),
        _concept('BFP', subject: 'law_enforcement', topic: 'DILG Bureaus', group: 'dilg_b'),
      ];
      final plan = planConceptCsv(
        _csv([
          _header,
          'LEA,DILG Bureaus,BJMP,$_def.,,',
          'LEA,DILG Bureaus,PPSC,$_def. Two.,,DILG A',
        ]),
        existing: existing,
      );
      expect(plan.problems.single.line, 2);
      expect(plan.problems.single.message, contains('more than one group'));
      expect(plan.batches.single.group, 'dilg_a');
    });

    test('group names are normalized, and a too-short one is refused', () {
      expect(normalizeConceptGroup('  PNP vs. BJMP '), 'pnp_vs_bjmp');
      final plan = planConceptCsv(
        _csv([_header, 'Criminology,Theories,Anomie,$_def.,,ab']),
        existing: const [],
      );
      expect(plan.problems.single.message, contains('group "ab"'));
    });

    test('the default group is the one the database gives a new topic', () {
      expect(defaultConceptGroup('criminology', 'Juvenile Delinquency & Justice'),
          'criminology_juvenile_delinquency_justice');
      expect(defaultConceptGroup('criminology', 'x' * 120).length, 80);
    });

    test('within a topic, the batch without a group is sent first', () {
      final plan = planConceptCsv(
        _csv([
          _header,
          'Criminology,Theories,Anomie,$_def. 1.,,zeta_group',
          'Criminology,Theories,Strain,$_def. 2.,,',
          'Criminology,Theories,Labeling,$_def. 3.,,alpha_group',
        ]),
        existing: const [],
      );
      expect(plan.batches.map((b) => b.group), [null, 'alpha_group', 'zeta_group']);
      expect(plan.topics, hasLength(1));
    });

    test('topics are listed by subject order, then by name', () {
      final plan = planConceptCsv(
        _csv([
          _header,
          'Corrections,Probation,Probation,$_def. 1.,,',
          'Criminology,Theories,Anomie,$_def. 2.,,',
          'Criminology,Basics,Crime,$_def. 3.,,',
        ]),
        existing: const [],
      );
      expect(plan.topics.map((t) => t.topic), ['Basics', 'Theories', 'Probation']);
      expect(plan.newTopicCount, 3);
    });
  });

  group('duplicates and field checks', () {
    test('the same term twice in one topic is skipped with the earlier line', () {
      final plan = planConceptCsv(
        _csv([
          _header,
          'Criminology,Theories,Anomie,$_def. 1.,,',
          'Criminology,Theories,anomie,$_def. 2.,,',
          'Criminology,Other Topic,Anomie,$_def. 3.,,',
        ]),
        existing: const [],
      );
      expect(plan.conceptCount, 2, reason: 'the same term in another topic is fine');
      expect(plan.problems.single.line, 3);
      expect(plan.problems.single.message, contains('already on line 2'));
    });

    test('the same definition twice in one group is skipped', () {
      final plan = planConceptCsv(
        _csv([_header, 'Criminology,Theories,Anomie,$_def.,,', 'Criminology,Theories,Strain,$_def.,,']),
        existing: const [],
      );
      expect(plan.problems.single.message, contains('already used on line 2'));
    });

    test('a definition already in the group is skipped', () {
      final plan = planConceptCsv(
        _csv([_header, 'Crim Law,Justifying Circumstances,New Term,$_def for Self-Defense.,,']),
        existing: [_concept('Self-Defense')],
      );
      expect(plan.problems.single.message, contains('already has this definition'));
    });

    test('an inactive concept still counts as already there (as in the database)', () {
      final plan = planConceptCsv(
        _csv([_header, 'Crim Law,Justifying Circumstances,Self-Defense,$_def. New.,,']),
        existing: [_concept('Self-Defense', active: false)],
      );
      expect(plan.conceptCount, 0);
    });

    test('the same field rules as the single-concept form', () {
      final plan = planConceptCsv(
        _csv([
          _header,
          'Criminology,Theories,Anomie,Too short,,',
          'Criminology,Theories,X,$_def.,,',
          'Criminology,{{bad}},Anomie,$_def.,,',
          'Criminology,,Anomie,$_def.,,',
          ',Theories,Anomie,$_def.,,',
        ]),
        existing: const [],
      );
      expect(plan.conceptCount, 0);
      expect(plan.problems.map((p) => p.line), [2, 3, 4, 5, 6]);
      expect(plan.problems[0].message, contains('definition is too short'));
      expect(plan.problems[1].message, contains('term is too short'));
      expect(plan.problems[2].message, contains('{{'));
      expect(plan.problems[3].message, 'The topic is empty.');
      expect(plan.problems[4].message, 'The subject is empty.');
    });

    test('line numbers follow the file even after a cell with line breaks', () {
      final plan = planConceptCsv(
        _csv([_header, 'Criminology,Theories,Anomie,"$_def,\nsecond line",,', 'Criminology,Theories,X,$_def.,,']),
        existing: const [],
      );
      expect(plan.batches.single.rows.single.line, 2);
      expect(plan.problems.single.line, 4);
    });
  });

  group('readiness after the import', () {
    test('a new topic needs three concepts in a group', () {
      final two = planConceptCsv(
        _csv([_header, 'Criminology,T,Aa,$_def. 1.,,', 'Criminology,T,Bb,$_def. 2.,,']),
        existing: const [],
      );
      expect(two.topics.single.after.canMakeQuestions, isFalse);

      final three = planConceptCsv(
        _csv([
          _header,
          'Criminology,T,Aa,$_def. 1.,RA 1,',
          'Criminology,T,Bb,$_def. 2.,RA 2,',
          'Criminology,T,Cc,$_def. 3.,RA 3,',
        ]),
        existing: const [],
      );
      expect(three.topics.single.after.canMakeQuestions, isTrue);
      expect(three.topics.single.after.basisFormsReady, isTrue);
    });

    test('a basis contained in another turns the legal-basis forms off', () {
      final plan = planConceptCsv(
        _csv([
          _header,
          'LEA,Bureaus,PNP,$_def. 1.,RA 6975,',
          'LEA,Bureaus,BJMP,$_def. 2.,"RA 6975, Sec. 60",',
          'LEA,Bureaus,BFP,$_def. 3.,RA 9514,',
        ]),
        existing: const [],
      );
      expect(plan.topics.single.after.canMakeQuestions, isTrue);
      expect(plan.topics.single.after.basisFormsReady, isFalse);
    });

    test('existing concepts count towards readiness', () {
      final plan = planConceptCsv(
        _csv([_header, 'Crim Law,Justifying Circumstances,Third One,$_def. 3.,,']),
        existing: [_concept('Self-Defense'), _concept('Defense of a Relative')],
      );
      expect(plan.topics.single.after.canMakeQuestions, isTrue);
      expect(plan.topics.single.after.active, 3);
    });
  });

  test('more than 1000 concepts cannot be imported', () {
    final rows = [_header, for (var i = 0; i < 1001; i++) 'Criminology,T$i,Term $i,$_def number $i.,,'];
    final plan = planConceptCsv(_csv(rows), existing: const []);
    expect(plan.conceptCount, 1001);
    expect(plan.tooMany, isTrue);
    expect(plan.canImport, isFalse);
  });

  group('importing a plan', () {
    test('sends each topic in requests of at most 200, maps refused rows to file lines, and goes on after a failure', () async {
      final rows = [
        _header,
        for (var i = 0; i < 450; i++) 'Criminology,Big Topic,Term $i,$_def number $i.,,',
        'Corrections,Failing Topic,Parole,$_def for parole.,,',
        'Corrections,Fine Topic,Pardon,$_def for pardon.,,',
      ];
      final plan = planConceptCsv(_csv(rows), existing: const []);
      expect(plan.batches, hasLength(3));

      final fake = _FakeConceptService();
      final progress = <(int, int)>[];
      final report = await fake.importCsvPlan(plan, onProgress: (d, t) => progress.add((d, t)));

      // Same order as the preview: Criminology before Corrections, topics by name.
      expect(fake.calls.map((c) => c.$1),
          ['Big Topic', 'Big Topic', 'Big Topic', 'Failing Topic', 'Fine Topic']);
      expect(fake.calls.map((c) => c.$2), [200, 200, 50, 1, 1],
          reason: 'Big Topic is split into 200 + 200 + 50');
      expect(progress.last, (5, 5));
      // The fake refuses the 2nd row of every request with 2 or more rows.
      expect(report.rejected.map((r) => r.line), [3, 203, 403]);
      // Big Topic: 199 + 199 + 49; Failing Topic: none; Fine Topic: 1.
      expect(report.inserted, 448);
      expect(report.failedTopics.single, contains('"Failing Topic" (1 concept)'));
      expect(report.topicsUpdated, {'criminology::big topic', 'corrections::fine topic'});
    });
  });
}

/// Saves every row except the 2nd of each request, and fails "Failing Topic".
class _FakeConceptService extends ConceptService {
  _FakeConceptService() : super.forTesting();

  final List<(String, int)> calls = [];

  @override
  Future<ConceptImportResult> importConcepts({
    required String subjectId,
    required String topic,
    String? siblingGroup,
    required List<ConceptDraft> rows,
  }) async {
    calls.add((topic, rows.length));
    if (topic == 'Failing Topic') {
      return const ConceptImportResult(success: false, error: 'No internet connection.');
    }
    final rejected = rows.length >= 2
        ? [ConceptReject(row: 2, term: rows[1].term, reason: 'This topic already has this term.')]
        : <ConceptReject>[];
    return ConceptImportResult(
      success: true,
      inserted: rows.length - rejected.length,
      rejected: rejected,
      topic: topic,
    );
  }
}
