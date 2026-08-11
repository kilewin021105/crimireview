/// Everything the UI needs to answer the student's real question after a miss:
/// "why is MY answer wrong?"
///
/// Panel note 5: the app must explain WHY the answer is wrong. The previous
/// build showed the explanation only inside an `if (isCorrect)` branch, so a
/// wrong answer produced the words "Not quite!" and nothing else -- the exact
/// opposite of what the panel asked for. This object is produced by
/// `ExplanationService` for BOTH outcomes and is guaranteed to carry a
/// non-empty [whySelectedIsWrong] whenever [isCorrect] is false.
class AnswerFeedback {
  /// Whether the student's selection was the keyed answer.
  final bool isCorrect;

  /// The exact option text the student picked, echoed back so the feedback
  /// reads as personal ("You chose: Insanity") rather than generic.
  final String selectedText;

  /// Panel note 5: why the CHOSEN option fails. Empty string when
  /// [isCorrect] is true; never empty when it is false.
  final String whySelectedIsWrong;

  /// The keyed option's text.
  final String correctText;

  /// Why the keyed option is right -- the option rationale, falling back to the
  /// item's overall explanation.
  final String whyCorrectIsRight;

  /// Citable authority, e.g. `RPC Art. 11` / `RA 9344` (panel note 4: the
  /// feedback must have a stated basis). Null when the item has none.
  final String? legalBasis;

  /// Topic this item belongs to -- the unit tracked by Bayesian Knowledge
  /// Tracing and the thing that gets repeated under panel note 3.
  final String topic;

  /// What to re-read before the next attempt; comes from the item's
  /// remediation hint or is synthesized from the topic (panel note 3: give the
  /// reviewer, then re-test).
  final String studyTip;

  /// BKT p(known) for [topic] BEFORE this answer was scored.
  ///
  /// Panel note 2: progress must be visible. Showing before/after makes the
  /// model's monitoring concrete to the student and to the panel.
  final double masteryBefore;

  /// BKT p(known) for [topic] AFTER this answer was scored.
  final double masteryAfter;

  /// True when the topic is not yet mastered, i.e. the system will bring this
  /// topic back with DIFFERENT questions (panel note 3).
  final bool willRepeatTopic;

  const AnswerFeedback({
    required this.isCorrect,
    required this.selectedText,
    required this.whySelectedIsWrong,
    required this.correctText,
    required this.whyCorrectIsRight,
    this.legalBasis,
    required this.topic,
    this.studyTip = '',
    this.masteryBefore = 0.0,
    this.masteryAfter = 0.0,
    this.willRepeatTopic = false,
  });

  /// Change in BKT p(known) caused by this answer; negative after a miss.
  double get masteryDelta => masteryAfter - masteryBefore;

  /// [masteryDelta] in percentage points, for a "+8%" style badge.
  double get masteryDeltaPercent => masteryDelta * 100;

  /// [masteryAfter] as 0-100, for progress bars.
  double get masteryPercent => (masteryAfter * 100).clamp(0.0, 100.0);

  /// True when there is an authority to cite in the feedback card.
  bool get hasLegalBasis => (legalBasis ?? '').trim().isNotEmpty;

  /// True when there is a study tip to render.
  bool get hasStudyTip => studyTip.trim().isNotEmpty;

  /// Short headline for the feedback card.
  String get headline => isCorrect ? 'Correct' : 'Not quite';

  /// The single most important line to show, whichever branch we are in.
  ///
  /// Guarantees the wrong-answer path is never empty (panel note 5).
  String get primaryReason =>
      isCorrect ? whyCorrectIsRight : whySelectedIsWrong;

  Map<String, dynamic> toJson() => {
        'isCorrect': isCorrect,
        'selectedText': selectedText,
        'whySelectedIsWrong': whySelectedIsWrong,
        'correctText': correctText,
        'whyCorrectIsRight': whyCorrectIsRight,
        'legalBasis': legalBasis,
        'topic': topic,
        'studyTip': studyTip,
        'masteryBefore': masteryBefore,
        'masteryAfter': masteryAfter,
        'willRepeatTopic': willRepeatTopic,
      };

  AnswerFeedback copyWith({
    bool? isCorrect,
    String? selectedText,
    String? whySelectedIsWrong,
    String? correctText,
    String? whyCorrectIsRight,
    String? legalBasis,
    String? topic,
    String? studyTip,
    double? masteryBefore,
    double? masteryAfter,
    bool? willRepeatTopic,
  }) {
    return AnswerFeedback(
      isCorrect: isCorrect ?? this.isCorrect,
      selectedText: selectedText ?? this.selectedText,
      whySelectedIsWrong: whySelectedIsWrong ?? this.whySelectedIsWrong,
      correctText: correctText ?? this.correctText,
      whyCorrectIsRight: whyCorrectIsRight ?? this.whyCorrectIsRight,
      legalBasis: legalBasis ?? this.legalBasis,
      topic: topic ?? this.topic,
      studyTip: studyTip ?? this.studyTip,
      masteryBefore: masteryBefore ?? this.masteryBefore,
      masteryAfter: masteryAfter ?? this.masteryAfter,
      willRepeatTopic: willRepeatTopic ?? this.willRepeatTopic,
    );
  }

  @override
  String toString() =>
      'AnswerFeedback(${isCorrect ? 'correct' : 'wrong'}, topic: $topic, '
      'mastery: ${masteryBefore.toStringAsFixed(2)} -> ${masteryAfter.toStringAsFixed(2)})';
}
