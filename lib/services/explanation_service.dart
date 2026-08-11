import '../models/answer_feedback.dart';
import '../models/mastery.dart';
import '../models/question.dart';

/// Turns a scored answer into feedback that explains WHY.
///
/// Panel note 5, verbatim: *"Your App can explain WHY the answer is wrong."*
///
/// The previous build did the exact opposite. `quiz_screen.dart` wrapped the
/// explanation in `if (isCorrect) ...[`, so a student who answered correctly
/// got a full explanation and a student who answered WRONG -- the only one who
/// needed it -- got the words "Not quite!" and nothing else. Worse, the item
/// model carried a single `explanation` string, so even if the branch were
/// fixed there was nowhere to record why *the option the student actually
/// picked* was wrong.
///
/// [AnswerOption.rationale] fixed the data; this service fixes the logic. Its
/// single guarantee, enforced on every path through [build]:
///
/// > when [AnswerFeedback.isCorrect] is false, [AnswerFeedback.whySelectedIsWrong]
/// > is NEVER empty.
///
/// It is deliberately pure and synchronous -- no I/O, no network, no
/// SharedPreferences -- so it can be called inline while the answer sheet is
/// being rendered and can never fail a quiz.
class ExplanationService {
  ExplanationService._();

  static final ExplanationService _instance = ExplanationService._();

  static ExplanationService get instance => _instance;

  /// Builds the feedback card for one answered item.
  ///
  /// [selectedIndex] is the option the student tapped. Values outside the
  /// option range are treated as "no answer" (timer expiry, skipped item), which
  /// is scored as incorrect and still produces a full explanation.
  ///
  /// [masteryBefore] / [masteryAfter] are the BKT p(known) for this item's topic
  /// either side of the update, straight from `MasteryService.recordAttempt`.
  /// Surfacing both is panel note 2 made visible: the student can watch the
  /// model's estimate move.
  AnswerFeedback build({
    required Question question,
    required int selectedIndex,
    required double masteryBefore,
    required double masteryAfter,
  }) {
    final options = question.answerOptions;
    final hasSelection = selectedIndex >= 0 && selectedIndex < options.length;
    final correctIndex = question.correctAnswerIndex;

    // No selection can never be scored correct, so an unanswered item still
    // gets the full "why" treatment rather than being silently skipped.
    final isCorrect = hasSelection && selectedIndex == correctIndex;

    final selectedText = hasSelection ? options[selectedIndex].text : '';
    final correctText = question.correctAnswer;

    final whyCorrectIsRight = _whyCorrectIsRight(question, correctText);
    final whySelectedIsWrong = isCorrect
        ? '' // Contract: empty on the correct branch; the UI shows whyCorrectIsRight.
        : _whySelectedIsWrong(
            question: question,
            hasSelection: hasSelection,
            selectedIndex: selectedIndex,
            selectedText: selectedText,
            correctText: correctText,
            whyCorrectIsRight: whyCorrectIsRight,
          );

    return AnswerFeedback(
      isCorrect: isCorrect,
      selectedText: selectedText,
      whySelectedIsWrong: whySelectedIsWrong,
      correctText: correctText,
      whyCorrectIsRight: whyCorrectIsRight,
      legalBasis: _blankToNull(question.legalBasis),
      topic: question.topic,
      studyTip: _studyTip(question),
      masteryBefore: masteryBefore,
      masteryAfter: masteryAfter,
      // Panel note 3: below the BKT mastery threshold the topic WILL come back,
      // with different questions (QuestionSelectionService rule R3). Saying so
      // up front is what makes the repeat feel deliberate instead of buggy.
      willRepeatTopic: masteryAfter < TopicMastery.masteryThreshold,
    );
  }

  // ---------------------------------------------------------------------------
  // Panel note 5 -- the wrong-answer path. This must NEVER return ''.
  // ---------------------------------------------------------------------------

  /// Explains why the chosen option fails, in the priority order the contract
  /// fixes:
  ///
  /// 1. the selected [AnswerOption]'s own rationale, when authored;
  /// 2. otherwise a synthesized sentence built from the item's overall
  ///    explanation;
  /// 3. otherwise, for content with neither, a statement of the correct answer.
  ///
  /// Tier 3 exists because ~6000 lines of legacy items were authored with a
  /// single explanation and no per-option rationales. They are being migrated,
  /// but a student on the old content must still never see a blank reason.
  String _whySelectedIsWrong({
    required Question question,
    required bool hasSelection,
    required int selectedIndex,
    required String selectedText,
    required String correctText,
    required String whyCorrectIsRight,
  }) {
    // Special case: the timer ran out or the item was skipped. There is no
    // chosen option to critique, so explain the item instead of pretending.
    if (!hasSelection) {
      final answer = correctText.isEmpty ? '' : ' The correct answer is "$correctText".';
      return _sentence('No answer was selected.$answer $whyCorrectIsRight');
    }

    // TIER 1 -- the authored, option-specific reason. This is the real payload
    // of panel note 5: "Insanity is an EXEMPTING circumstance under Art. 12,
    // not a justifying one."
    final rationale = question.rationaleFor(selectedIndex).trim();
    if (rationale.isNotEmpty) return _sentence(rationale);

    // TIER 2 -- synthesize from the item's overall explanation.
    final explanation = question.explanation.trim();
    if (explanation.isNotEmpty) {
      return _sentence('"$selectedText" is not correct. $explanation');
    }

    // TIER 3 -- last resort, still specific enough to be useful.
    if (correctText.isNotEmpty) {
      final tail = whyCorrectIsRight.trim();
      return _sentence(
        '"$selectedText" is not correct. The correct answer is '
        '"$correctText".${tail.isEmpty ? '' : ' $tail'}',
      );
    }

    // Absolute floor -- an item with no key and no explanation at all. Should be
    // unreachable with content served by QuestionRepository, but the guarantee
    // holds regardless of how bad the row is.
    return _sentence(
      '"$selectedText" is not correct for this item. Review '
      '${question.topic.isEmpty ? 'this topic' : question.topic} '
      'in the reviewer before trying again.',
    );
  }

  /// Why the keyed option is right: its own rationale, then the item's overall
  /// explanation, then a plain statement of the key.
  String _whyCorrectIsRight(Question question, String correctText) {
    final rationale = question.correctRationale.trim();
    if (rationale.isNotEmpty) return _sentence(rationale);

    final explanation = question.explanation.trim();
    if (explanation.isNotEmpty) return _sentence(explanation);

    if (correctText.isNotEmpty) {
      return _sentence('The correct answer is "$correctText".');
    }
    return '';
  }

  /// What to re-read before the topic comes back.
  ///
  /// Panel note 3's flow is reviewer -> questions -> monitor -> repeat, so the
  /// feedback has to point back at the reviewer, not just report a verdict.
  String _studyTip(Question question) {
    final hint = (question.remediationHint ?? '').trim();
    if (hint.isNotEmpty) return _sentence(hint);

    final topic = question.topic.trim();
    if (topic.isEmpty) {
      return 'Review this topic in the reviewer before trying again.';
    }
    return 'Review $topic in the reviewer before trying again.';
  }

  // ---------------------------------------------------------------------------
  // Formatting helpers
  // ---------------------------------------------------------------------------

  /// Collapses stray whitespace and guarantees terminal punctuation, so
  /// concatenated fragments from different authors still read as prose.
  String _sentence(String text) {
    final cleaned = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.isEmpty) return '';
    if (RegExp(r'[.!?)"”]$').hasMatch(cleaned)) return cleaned;
    return '$cleaned.';
  }

  String? _blankToNull(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }
}
