/// Coarse, human-readable band derived from [TopicMastery.pKnown].
///
/// Panel note 2 ("make it machine learning so the system can monitor the
/// progress of the students") needs progress to be *visible*, not just a float
/// buried in a service. These bands are what the UI renders.
enum MasteryLevel {
  /// No attempt recorded yet.
  notStarted,

  /// p(known) < 0.30 -- the topic will be repeated (panel note 3).
  struggling,

  /// p(known) < 0.60 -- improving but not safe to advance.
  developing,

  /// p(known) < 0.90 -- close; a couple more correct answers seals it.
  proficient,

  /// p(known) >= 0.90 with enough evidence -- advance to the next topic.
  mastered,
}

/// Per-topic knowledge state estimated with Bayesian Knowledge Tracing.
///
/// Panel note 2 asks for a model that MONITORS the student, and panel note 4
/// asks for a citable basis. BKT (Corbett & Anderson, 1995, *Knowledge tracing:
/// Modeling the acquisition of procedural knowledge*, User Modeling and
/// User-Adapted Interaction 4(4), 253-278) is that basis: it is the standard
/// latent-variable model behind intelligent tutoring systems, and it replaces
/// the old hardcoded `accuracy >= 0.8 ? hard : ...` if/else ladder that had no
/// theoretical grounding.
///
/// Panel note 3 -- "if the student is good at that topic advance; if not,
/// REPEAT the topic but NOT the same question" -- is decided by
/// [isMastered] / [needsRemediation]. The "not the same question" half is
/// enforced separately by `QuestionSelectionService`.
class TopicMastery {
  /// Subject id, e.g. `criminal_jurisprudence`.
  final String subjectId;

  /// Topic name; the unit of knowledge being traced.
  final String topic;

  /// BKT posterior P(L_n): the model's probability that the student has LEARNED
  /// this topic, given every response observed so far.
  ///
  /// It is a *latent* estimate, not an accuracy score. After each answer the
  /// service applies Bayes' rule with the four BKT parameters -- p(init) .20,
  /// p(transit) .20, p(slip) .10, p(guess) .25 for a 4-option MCQ -- so a lucky
  /// guess raises it only slightly while a careless slip lowers it only
  /// slightly. That is exactly why it beats raw accuracy for deciding whether
  /// to advance or repeat a topic.
  ///
  /// Range 0.0-1.0. Starts at [defaultPInit].
  double pKnown;

  /// Total items answered in this topic (the evidence count behind [pKnown]).
  int attempts;

  /// Items answered correctly.
  int correct;

  /// Current streak of correct answers; resets to 0 on a miss. Used for the
  /// "on a roll" UI and as a tiebreaker when ranking weak topics.
  int consecutiveCorrect;

  /// When the topic was last practiced; drives spaced-review ordering and the
  /// "least recently seen" recycling rule.
  DateTime? lastPracticed;

  /// BKT prior P(L_0): probability the student already knows a topic before any
  /// evidence (Corbett & Anderson 1995).
  static const double defaultPInit = 0.20;

  /// [pKnown] at or above this, with at least [masteryMinAttempts] attempts,
  /// counts as mastered.
  static const double masteryThreshold = 0.90;

  /// Minimum evidence before mastery may be declared, so 4 lucky guesses in a
  /// row cannot fake it.
  static const int masteryMinAttempts = 4;

  /// Below this, with at least [remediationMinAttempts] attempts, the topic is
  /// repeated (panel note 3).
  static const double remediationThreshold = 0.60;

  static const int remediationMinAttempts = 3;

  TopicMastery({
    required this.subjectId,
    required this.topic,
    this.pKnown = defaultPInit,
    this.attempts = 0,
    this.correct = 0,
    this.consecutiveCorrect = 0,
    this.lastPracticed,
  });

  /// Stable map key: `subjectId::topic`.
  String get key => '$subjectId::$topic';

  /// Observed proportion correct. Shown to students because it is intuitive;
  /// [pKnown] is what the system actually reasons with.
  double get accuracy => attempts == 0 ? 0.0 : correct / attempts;

  /// Panel note 3, the "student is good at that topic" branch: advance.
  bool get isMastered =>
      pKnown >= masteryThreshold && attempts >= masteryMinAttempts;

  /// Panel note 3, the "if not" branch: repeat the topic with DIFFERENT items.
  bool get needsRemediation =>
      pKnown < remediationThreshold && attempts >= remediationMinAttempts;

  /// Band used by the UI (panel note 2).
  MasteryLevel get level {
    if (attempts == 0) return MasteryLevel.notStarted;
    if (pKnown < 0.30) return MasteryLevel.struggling;
    if (pKnown < 0.60) return MasteryLevel.developing;
    if (pKnown < 0.90) return MasteryLevel.proficient;
    return MasteryLevel.mastered;
  }

  /// Human label for [level].
  String get levelLabel {
    switch (level) {
      case MasteryLevel.notStarted:
        return 'Not Started';
      case MasteryLevel.struggling:
        return 'Struggling';
      case MasteryLevel.developing:
        return 'Developing';
      case MasteryLevel.proficient:
        return 'Proficient';
      case MasteryLevel.mastered:
        return 'Mastered';
    }
  }

  /// [pKnown] as a 0-100 value for progress bars.
  double get masteryPercent => (pKnown * 100).clamp(0.0, 100.0);

  Map<String, dynamic> toJson() => {
        'subjectId': subjectId,
        'topic': topic,
        'pKnown': pKnown,
        'attempts': attempts,
        'correct': correct,
        'consecutiveCorrect': consecutiveCorrect,
        'lastPracticed': lastPracticed?.toIso8601String(),
      };

  /// snake_case row for `public.topic_mastery`.
  Map<String, dynamic> toSupabaseRow() => {
        'subject_id': subjectId,
        'topic': topic,
        'p_known': pKnown,
        'attempts': attempts,
        'correct': correct,
        'consecutive_correct': consecutiveCorrect,
        'last_practiced': lastPracticed?.toIso8601String(),
      };

  /// Tolerant parser: accepts camelCase (local cache) and snake_case (Supabase),
  /// and never throws on a missing or malformed field.
  factory TopicMastery.fromJson(Map<String, dynamic> json) {
    return TopicMastery(
      subjectId: _str(json, const ['subjectId', 'subject_id', 'subject']),
      topic: _str(json, const ['topic', 'topic_name', 'topicName']),
      pKnown: _dbl(json, const ['pKnown', 'p_known'], defaultPInit)
          .clamp(0.0, 1.0)
          .toDouble(),
      attempts: _int(json, const ['attempts', 'total_attempts'], 0),
      correct: _int(json, const ['correct', 'correct_count'], 0),
      consecutiveCorrect:
          _int(json, const ['consecutiveCorrect', 'consecutive_correct'], 0),
      lastPracticed: _date(json, const ['lastPracticed', 'last_practiced']),
    );
  }

  TopicMastery copyWith({
    String? subjectId,
    String? topic,
    double? pKnown,
    int? attempts,
    int? correct,
    int? consecutiveCorrect,
    DateTime? lastPracticed,
  }) {
    return TopicMastery(
      subjectId: subjectId ?? this.subjectId,
      topic: topic ?? this.topic,
      pKnown: pKnown ?? this.pKnown,
      attempts: attempts ?? this.attempts,
      correct: correct ?? this.correct,
      consecutiveCorrect: consecutiveCorrect ?? this.consecutiveCorrect,
      lastPracticed: lastPracticed ?? this.lastPracticed,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is TopicMastery && other.key == key;

  @override
  int get hashCode => key.hashCode;

  @override
  String toString() =>
      'TopicMastery($key, pKnown: ${pKnown.toStringAsFixed(2)}, '
      '$correct/$attempts, ${level.name})';

  // ---------------------------------------------------------------------------
  // Tolerant readers
  // ---------------------------------------------------------------------------

  static String _str(Map<String, dynamic> json, List<String> keys) {
    for (final k in keys) {
      final v = json[k];
      if (v == null) continue;
      final s = v.toString();
      if (s.isNotEmpty) return s;
    }
    return '';
  }

  static double _dbl(
      Map<String, dynamic> json, List<String> keys, double fallback) {
    for (final k in keys) {
      final v = json[k];
      if (v is double) return v;
      if (v is num) return v.toDouble();
      if (v is String) {
        final parsed = double.tryParse(v.trim());
        if (parsed != null) return parsed;
      }
    }
    return fallback;
  }

  static int _int(Map<String, dynamic> json, List<String> keys, int fallback) {
    for (final k in keys) {
      final v = json[k];
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) {
        final parsed = int.tryParse(v.trim());
        if (parsed != null) return parsed;
      }
    }
    return fallback;
  }

  static DateTime? _date(Map<String, dynamic> json, List<String> keys) {
    for (final k in keys) {
      final v = json[k];
      if (v == null) continue;
      if (v is DateTime) return v;
      if (v is String && v.trim().isNotEmpty) {
        final parsed = DateTime.tryParse(v.trim());
        if (parsed != null) return parsed;
      }
      if (v is int) {
        return DateTime.fromMillisecondsSinceEpoch(v);
      }
    }
    return null;
  }
}
