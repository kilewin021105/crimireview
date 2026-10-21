import '../models/question.dart';

/// The correct option "stands out" when it is the longest option and at least
/// this many times longer than the longest wrong one. Students then pick it by
/// length without knowing the answer.
///
/// Same rule as `tools/rebalance_options.dart`, which removed this giveaway
/// from the imported question bank (CHANGELOG Session 62).
const double kAnswerStandOutRatio = 1.4;

/// True when [correct] stands out by length against the [wrong] options.
/// Lengths are counted after trimming spaces. False when there is nothing to
/// compare (no wrong option, or an empty answer).
bool answerStandsOutByLength(String correct, Iterable<String> wrong) {
  final c = correct.trim().length;
  final lengths = wrong.map((w) => w.trim().length).where((l) => l > 0).toList();
  if (c == 0 || lengths.isEmpty) return false;
  final longestWrong = lengths.reduce((a, b) => a > b ? a : b);
  return c > longestWrong && c >= kAnswerStandOutRatio * longestWrong;
}

/// [answerStandsOutByLength] for a saved question. False unless exactly one
/// option is marked correct.
bool questionAnswerStandsOut(Question q) {
  final correct = q.answerOptions.where((o) => o.isCorrect).toList();
  if (correct.length != 1) return false;
  return answerStandsOutByLength(
    correct.first.text,
    q.answerOptions.where((o) => !o.isCorrect).map((o) => o.text),
  );
}
