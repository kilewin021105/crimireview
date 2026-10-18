import 'package:flutter_test/flutter_test.dart';

import 'package:crimireview/utils/concept_import_parser.dart';

const _defA = 'The conditional release of a prisoner after serving the minimum sentence.';
const _defB = 'An act of grace by the Chief Executive that exempts a person from punishment.';

void main() {
  group('parseConceptImport', () {
    test('reads tab-separated rows with and without a legal basis', () {
      final r = parseConceptImport('Parole\t$_defA\tAct 4103, Sec. 5\nPardon\t$_defB');
      expect(r.problems, isEmpty);
      expect(r.rows, hasLength(2));
      expect(r.rows[0].term, 'Parole');
      expect(r.rows[0].definition, _defA);
      expect(r.rows[0].legalBasis, 'Act 4103, Sec. 5');
      expect(r.rows[1].legalBasis, isNull);
      expect(r.rows[1].line, 2);
    });

    test('falls back to the | sign when a line has no tab', () {
      final r = parseConceptImport('Parole | $_defA | Act 4103');
      expect(r.problems, isEmpty);
      expect(r.rows.single.term, 'Parole');
      expect(r.rows.single.legalBasis, 'Act 4103');
    });

    test('a tab wins over | so a definition may contain a pipe', () {
      final r = parseConceptImport('Parole\tRelease | on conditions after the minimum term.');
      expect(r.problems, isEmpty);
      expect(r.rows.single.definition, 'Release | on conditions after the minimum term.');
    });

    test('skips a header row and blank lines, keeps real line numbers', () {
      final r = parseConceptImport('Term\tDefinition\tLegal basis\n\nParole\t$_defA\n\n');
      expect(r.problems, isEmpty);
      expect(r.rows.single.line, 3);
    });

    test('does not treat a real concept named "Term" as a header', () {
      final r = parseConceptImport('Term\tThe fixed period of a sentence imposed by the court.');
      expect(r.problems, isEmpty);
      expect(r.rows.single.term, 'Term');
    });

    test('handles Windows line endings', () {
      final r = parseConceptImport('Parole\t$_defA\r\nPardon\t$_defB\r\n');
      expect(r.rows, hasLength(2));
    });

    test('removes the quotes Excel adds', () {
      final r = parseConceptImport('"Parole"\t"A ""conditional"" release of a prisoner."\t"Act 4103, Sec. 5"');
      expect(r.rows.single.term, 'Parole');
      expect(r.rows.single.definition, 'A "conditional" release of a prisoner.');
      expect(r.rows.single.legalBasis, 'Act 4103, Sec. 5');
    });

    test('ignores trailing empty columns', () {
      final r = parseConceptImport('Parole\t$_defA\t\t\t');
      expect(r.problems, isEmpty);
      expect(r.rows.single.legalBasis, isNull);
    });

    test('reports a line with no separator', () {
      final r = parseConceptImport('Parole is the release of a prisoner');
      expect(r.rows, isEmpty);
      expect(r.problems.single.line, 1);
      expect(r.problems.single.message, contains('Tab'));
    });

    test('reports a missing definition', () {
      final r = parseConceptImport('Parole\t');
      expect(r.rows, isEmpty);
      expect(r.problems.single.message, contains('definition is required'));
    });

    test('reports more than 3 columns', () {
      final r = parseConceptImport('Parole\t$_defA\tAct 4103\tExtra');
      expect(r.rows, isEmpty);
      expect(r.problems.single.message, contains('more than 3 columns'));
    });

    test('reports a short definition', () {
      final r = parseConceptImport('Parole\tshort');
      expect(r.rows, isEmpty);
      expect(r.problems.single.message, contains('too short'));
    });

    test('rejects {{ and }} because they are template slots', () {
      final r = parseConceptImport('Parole\tA {{term}} inside the definition text.');
      expect(r.rows, isEmpty);
      expect(r.problems.single.message, contains('{{'));
    });

    test('reports a repeated term (any letter case) and keeps the first', () {
      final r = parseConceptImport('Parole\t$_defA\nPAROLE\t$_defB');
      expect(r.rows.single.line, 1);
      expect(r.problems.single.line, 2);
      expect(r.problems.single.message, contains('line 1'));
    });

    test('reports a repeated definition', () {
      final r = parseConceptImport('Parole\t$_defA\nRelease\t$_defA');
      expect(r.rows, hasLength(1));
      expect(r.problems.single.message, contains('definition is already used on line 1'));
    });

    test('good lines still import when others have problems', () {
      final r = parseConceptImport('Parole\t$_defA\nbad line\nPardon\t$_defB');
      expect(r.rows.map((e) => e.term), ['Parole', 'Pardon']);
      expect(r.problems.single.line, 2);
    });

    test('flags more than 200 concepts', () {
      final text = [for (var i = 1; i <= 201; i++) 'Term $i\tDefinition number $i that is long enough.'].join('\n');
      final r = parseConceptImport(text);
      expect(r.rows, hasLength(201));
      expect(r.tooMany, isTrue);
      expect(parseConceptImport(text.split('\n').take(200).join('\n')).tooMany, isFalse);
    });

    test('toJson uses the names the database function reads', () {
      final r = parseConceptImport('Parole\t$_defA\tAct 4103');
      expect(r.rows.single.toJson(), {'term': 'Parole', 'definition': _defA, 'legal_basis': 'Act 4103'});
    });
  });

  group('conceptFieldError', () {
    test('accepts a normal concept', () {
      expect(conceptFieldError('Parole', _defA, 'Act 4103'), isNull);
      expect(conceptFieldError('  Parole ', _defA, null), isNull);
    });

    test('mirrors the database limits', () {
      expect(conceptFieldError('', _defA, null), isNotNull);
      expect(conceptFieldError('P', _defA, null), isNotNull);
      expect(conceptFieldError('x' * 201, _defA, null), isNotNull);
      expect(conceptFieldError('Parole', 'x' * 9, null), isNotNull);
      expect(conceptFieldError('Parole', 'x' * 10, null), isNull);
      expect(conceptFieldError('Parole', 'x' * 1501, null), isNotNull);
      expect(conceptFieldError('Parole', _defA, 'x' * 201), isNotNull);
      expect(conceptFieldError('Pa}}role', _defA, null), isNotNull);
    });
  });
}
