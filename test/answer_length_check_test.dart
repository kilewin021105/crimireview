import 'package:flutter_test/flutter_test.dart';

import 'package:crimireview/models/question.dart';
import 'package:crimireview/utils/answer_length_check.dart';

Question q(List<(String, bool)> options) => Question(
      id: 'q',
      subject: 'criminology',
      topic: 'T',
      questionText: 'Q?',
      answerOptions: [for (final (t, c) in options) AnswerOption(text: t, isCorrect: c, rationale: '')],
      difficulty: Difficulty.easy,
      explanation: '',
    );

void main() {
  group('answerStandsOutByLength (same rule as tools/rebalance_options.dart)', () {
    test('a real example from the old bank stands out', () {
      // "What is collective efficacy?" before the rewrite.
      expect(
        answerStandsOutByLength('Community willingness to intervene',
            ['Individual action', 'Police action', 'Court action']),
        isTrue,
      );
    });

    test('the rewritten version of that question does not', () {
      expect(
        answerStandsOutByLength('Community willingness to intervene',
            ['Police willingness to intervene', 'Community wealth and property values', 'Individual willingness to report']),
        isFalse,
      );
    });

    test('exactly at 1.4 times the longest wrong option counts as standing out', () {
      expect(answerStandsOutByLength('x' * 14, ['y' * 10, 'z' * 5]), isTrue);
      expect(answerStandsOutByLength('x' * 13, ['y' * 10, 'z' * 5]), isFalse);
    });

    test('a correct answer that is not the longest never stands out', () {
      expect(answerStandsOutByLength('short', ['a much longer wrong option', 'tiny']), isFalse);
    });

    test('spaces around the text are ignored', () {
      expect(answerStandsOutByLength('   ${'x' * 14}   ', ['y' * 10]), isTrue);
      expect(answerStandsOutByLength('x' * 14, ['${'y' * 10}          ']), isTrue);
    });

    test('nothing to compare means no warning', () {
      expect(answerStandsOutByLength('anything', []), isFalse);
      expect(answerStandsOutByLength('anything', ['', '   ']), isFalse);
      expect(answerStandsOutByLength('', ['a', 'b']), isFalse);
    });
  });

  group('questionAnswerStandsOut', () {
    test('checks the option marked correct, wherever it is', () {
      expect(questionAnswerStandsOut(q([('Court action', false), ('Community willingness to intervene', true), ('Police action', false)])), isTrue);
      expect(questionAnswerStandsOut(q([('Luminol test', true), ('Marquis test', false), ('Scott test', false)])), isFalse);
    });

    test('no warning unless exactly one option is correct', () {
      expect(questionAnswerStandsOut(q([('A very long option text here', true), ('b', true)])), isFalse);
      expect(questionAnswerStandsOut(q([('A very long option text here', false), ('b', false)])), isFalse);
    });
  });
}
