import 'dart:convert';

/// Difficulty tiers used across the whole app.
///
/// Declared HERE on purpose: every screen and service imports `Difficulty`
/// from `models/question.dart`. Do not move it to another file.
enum Difficulty { easy, medium, hard }

/// Where an item came from.
///
/// Panel note 7 ("do NOT put your questions in your code -- have an ADMIN add
/// them, or automate everything") and panel note 1 ("should generate a question
/// automatically") both need to be *provable* to the panel. Tagging every item
/// with its provenance lets the admin dashboard show, e.g., "412 admin-authored,
/// 96 auto-generated", which is the evidence that no item is hardcoded.
enum QuestionSource {
  /// Authored by an admin through the admin UI (panel note 7).
  admin,

  /// Produced by Automatic Item Generation from a template + concept bank
  /// (panel note 1). Such items always carry a [Question.templateId].
  generated,

  /// Bulk-imported (CSV/JSON) by an admin.
  imported,
}

/// One selectable choice of a multiple-choice item.
///
/// The old model stored answers as a bare `List<String>`, which made panel
/// note 5 ("your app can explain WHY the answer is wrong") impossible to
/// satisfy: there was nowhere to record why *the option the student picked*
/// was wrong. [rationale] is that missing field.
class AnswerOption {
  /// The text shown on the answer button.
  final String text;

  /// Whether this option is the keyed (correct) answer.
  final bool isCorrect;

  /// Panel note 5: the app must explain why the answer is wrong.
  ///
  /// For a distractor this is why *this* option fails (e.g. "Insanity is an
  /// EXEMPTING circumstance under Art. 12, not a justifying one"). For the key
  /// it is why this option is right. May be blank on legacy/imported data;
  /// `ExplanationService` synthesizes a fallback so the student is never shown
  /// an empty reason.
  final String rationale;

  const AnswerOption({
    required this.text,
    this.isCorrect = false,
    this.rationale = '',
  });

  /// camelCase form, used by the local offline cache.
  Map<String, dynamic> toJson() => {
        'text': text,
        'isCorrect': isCorrect,
        'rationale': rationale,
      };

  /// snake_case form, used inside [Question.toSupabaseRow].
  Map<String, dynamic> toSupabaseJson() => {
        'text': text,
        'is_correct': isCorrect,
        'rationale': rationale,
      };

  /// Tolerant parser: accepts camelCase (`isCorrect`) and snake_case
  /// (`is_correct`), a missing rationale, and a plain string payload.
  factory AnswerOption.fromJson(Map<String, dynamic> json) {
    return AnswerOption(
      text: _readString(json, const ['text', 'option', 'label', 'value']),
      isCorrect: _readBool(
        json,
        const ['isCorrect', 'is_correct', 'correct'],
      ),
      rationale: _readString(
        json,
        const ['rationale', 'why', 'reason', 'feedback'],
      ),
    );
  }

  AnswerOption copyWith({String? text, bool? isCorrect, String? rationale}) {
    return AnswerOption(
      text: text ?? this.text,
      isCorrect: isCorrect ?? this.isCorrect,
      rationale: rationale ?? this.rationale,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AnswerOption &&
          other.text == text &&
          other.isCorrect == isCorrect &&
          other.rationale == rationale;

  @override
  int get hashCode => Object.hash(text, isCorrect, rationale);

  @override
  String toString() => 'AnswerOption($text, correct: $isCorrect)';
}

/// A single quiz item.
///
/// Content lives in Supabase (`public.questions`) and is served by
/// `QuestionRepository`; this class is only the in-memory shape. It must
/// therefore survive three different JSON dialects (see [Question.fromJson]).
class Question {
  /// Stable primary key. Also the identity used by [==] / [hashCode] and by
  /// `QuestionSelectionService` exposure tracking (panel note 3: never repeat
  /// the same question).
  final String id;

  /// Subject id, e.g. `criminal_jurisprudence`.
  ///
  /// Named `subject` (not `subjectId`) because ~900 existing call sites and
  /// several screens already read `q.subject`. Supabase stores it as
  /// `subject_id`; the mapping happens in [fromJson] / [toSupabaseRow].
  final String subject;

  /// Topic within the subject, e.g. `Justifying Circumstances`.
  ///
  /// Panel note 3: mastery, remediation and "repeat the topic" all key off
  /// this, so it is the unit of the Bayesian Knowledge Tracing model.
  final String topic;

  /// The stem shown to the student.
  final String questionText;

  /// The choices, each carrying its own [AnswerOption.rationale]
  /// (panel note 5).
  final List<AnswerOption> answerOptions;

  final Difficulty difficulty;

  /// Overall explanation of the correct answer. Shown for BOTH right and wrong
  /// answers (panel note 5 -- the old quiz screen showed it only when correct).
  final String explanation;

  /// Citable authority, e.g. `RPC Art. 11` or `RA 9344`.
  ///
  /// Panel note 4 asks for a defensible basis; for legal items the statute is
  /// that basis, and it is what makes the feedback credible to a criminology
  /// panel.
  final String? legalBasis;

  /// What to re-read after missing this item.
  ///
  /// Panel note 3: when a topic is not yet mastered the app sends the student
  /// back to the reviewer before re-testing; this points at the right section.
  final String? remediationHint;

  /// Provenance (panel notes 1 and 7).
  final QuestionSource source;

  /// Content revision, bumped by the admin editor so caches can be refreshed.
  final int version;

  /// Set when the item was produced by Automatic Item Generation
  /// (panel note 1); null for hand-authored items.
  final String? templateId;

  /// Correct index captured at construction, used ONLY as a fallback when no
  /// [AnswerOption.isCorrect] flag is set (e.g. legacy rows keyed purely by
  /// index). -1 means "no fallback recorded".
  final int _correctAnswerIndex;

  /// Canonical generative constructor. Private so the public entry points can
  /// normalize the many legacy shapes before reaching it.
  const Question._({
    required this.id,
    required this.subject,
    required this.topic,
    required this.questionText,
    required this.answerOptions,
    required this.difficulty,
    required this.explanation,
    required this.legalBasis,
    required this.remediationHint,
    required this.source,
    required this.version,
    required this.templateId,
    required int correctAnswerIndex,
  }) : _correctAnswerIndex = correctAnswerIndex;

  /// Primary constructor.
  ///
  /// Deliberately accepts BOTH the new shape and the legacy one so that
  /// existing call sites keep compiling while new code uses rationales:
  ///
  /// ```dart
  /// // new (panel note 5)
  /// Question(..., answerOptions: [AnswerOption(text: 'A', isCorrect: true, rationale: '...')]);
  /// // legacy
  /// Question(..., options: ['A', 'B'], correctAnswerIndex: 0);
  /// ```
  ///
  /// If both are supplied, [answerOptions] wins; [correctAnswerIndex] is still
  /// honoured when no option carries an `isCorrect` flag.
  factory Question({
    required String id,
    required String subject,
    required String topic,
    required String questionText,
    List<AnswerOption>? answerOptions,
    List<String>? options,
    int? correctAnswerIndex,
    required Difficulty difficulty,
    String explanation = '',
    String? legalBasis,
    String? remediationHint,
    QuestionSource source = QuestionSource.admin,
    int version = 1,
    String? templateId,
  }) {
    final built = answerOptions ??
        (options ?? const <String>[])
            .map((t) => AnswerOption(text: t))
            .toList(growable: false);

    return Question._(
      id: id,
      subject: subject,
      topic: topic,
      questionText: questionText,
      answerOptions: _applyCorrectIndex(built, correctAnswerIndex),
      difficulty: difficulty,
      explanation: explanation,
      legalBasis: legalBasis,
      remediationHint: remediationHint,
      source: source,
      version: version,
      templateId: templateId,
      correctAnswerIndex: correctAnswerIndex ?? -1,
    );
  }

  /// Builds an item from a plain string list plus a key index.
  ///
  /// Kept so old call sites, fixtures and tests keep working while the content
  /// migrates into Supabase. Items built this way have blank rationales, so
  /// `ExplanationService` falls back to [explanation] for panel note 5.
  factory Question.legacy({
    required String id,
    required String subject,
    required String topic,
    required String questionText,
    required List<String> options,
    required int correctAnswerIndex,
    required Difficulty difficulty,
    String explanation = '',
    String? legalBasis,
    String? remediationHint,
    QuestionSource source = QuestionSource.admin,
    int version = 1,
    String? templateId,
  }) {
    return Question(
      id: id,
      subject: subject,
      topic: topic,
      questionText: questionText,
      options: options,
      correctAnswerIndex: correctAnswerIndex,
      difficulty: difficulty,
      explanation: explanation,
      legalBasis: legalBasis,
      remediationHint: remediationHint,
      source: source,
      version: version,
      templateId: templateId,
    );
  }

  // ---------------------------------------------------------------------------
  // BACKWARD-COMPATIBLE ACCESSORS -- existing screens depend on these.
  // DO NOT REMOVE.
  // ---------------------------------------------------------------------------

  /// Plain option texts, for widgets that only render strings
  /// (quiz_screen, daily_challenge_screen, flashcard_screen).
  List<String> get options =>
      answerOptions.map((o) => o.text).toList(growable: false);

  /// Index of the keyed option.
  ///
  /// Resolution order: the [AnswerOption.isCorrect] flag, then the index
  /// captured at construction (legacy rows), then 0. Never throws.
  int get correctAnswerIndex {
    final flagged = answerOptions.indexWhere((o) => o.isCorrect);
    if (flagged >= 0) return flagged;
    if (_correctAnswerIndex >= 0 && _correctAnswerIndex < answerOptions.length) {
      return _correctAnswerIndex;
    }
    return 0;
  }

  /// Text of the keyed option; `''` when the item has no options.
  String get correctAnswer {
    if (answerOptions.isEmpty) return '';
    final i = correctAnswerIndex;
    if (i < 0 || i >= answerOptions.length) return answerOptions.first.text;
    return answerOptions[i].text;
  }

  /// Why the option at [index] is right or wrong; `''` when out of range.
  ///
  /// Panel note 5: this is what lets the results UI say "you picked B --
  /// here is why B is wrong", not just "Not quite!".
  String rationaleFor(int index) {
    if (index < 0 || index >= answerOptions.length) return '';
    return answerOptions[index].rationale;
  }

  /// Why the keyed option is right.
  String get correctRationale => rationaleFor(correctAnswerIndex);

  /// True when at least one option carries a non-blank rationale, i.e. the item
  /// can fully satisfy panel note 5 without a synthesized fallback.
  bool get hasRationales =>
      answerOptions.any((o) => o.rationale.trim().isNotEmpty);

  /// True when this item was produced by Automatic Item Generation
  /// (panel note 1).
  bool get isGenerated => source == QuestionSource.generated;

  // ---------------------------------------------------------------------------
  // Serialization
  // ---------------------------------------------------------------------------

  /// camelCase form written to the local offline cache.
  ///
  /// Emits `options` as a list of rich maps AND a flat `correctAnswerIndex`, so
  /// a cache written by this version stays readable by [fromJson] even if the
  /// rich fields are ever dropped.
  Map<String, dynamic> toJson() => {
        'id': id,
        'subject': subject,
        'topic': topic,
        'questionText': questionText,
        'options': answerOptions.map((o) => o.toJson()).toList(),
        'correctAnswerIndex': correctAnswerIndex,
        'explanation': explanation,
        'difficulty': difficulty.name,
        'legalBasis': legalBasis,
        'remediationHint': remediationHint,
        'source': source.name,
        'version': version,
        'templateId': templateId,
      };

  /// snake_case row for `public.questions`.
  Map<String, dynamic> toSupabaseRow() => {
        'id': id,
        'subject_id': subject,
        'topic': topic,
        'question_text': questionText,
        'options': answerOptions.map((o) => o.toSupabaseJson()).toList(),
        'correct_answer_index': correctAnswerIndex,
        'explanation': explanation,
        'difficulty': difficulty.name,
        'legal_basis': legalBasis,
        'remediation_hint': remediationHint,
        'source': source.name,
        'version': version,
        'template_id': templateId,
      };

  /// Bullet-proof parser. Accepts, in any mix:
  ///
  /// * the Supabase row -- `question_text`, `subject_id`,
  ///   `correct_answer_index`, `options` as a list of maps;
  /// * the current camelCase cache -- `questionText`, `correctAnswerIndex`,
  ///   `options` as a list of maps;
  /// * the OLD camelCase cache -- `options` as a plain `List<String>` with no
  ///   rationales at all.
  ///
  /// `difficulty` may arrive as an int index, a name (`hard`), or a stringified
  /// enum (`Difficulty.hard`). Nothing here throws: every field falls back to a
  /// sensible default, because a single malformed row must never blank the
  /// whole question bank on a student's phone.
  factory Question.fromJson(Map<String, dynamic> json) {
    final rawOptions = json['answerOptions'] ??
        json['answer_options'] ??
        json['options'] ??
        json['choices'];

    final parsedOptions = _parseOptions(rawOptions);

    final idx = _readInt(
      json,
      const ['correctAnswerIndex', 'correct_answer_index', 'answer_index'],
      fallback: -1,
    );

    // Last-resort key resolution: some rows store the answer as text.
    var resolvedIdx = idx;
    if (resolvedIdx < 0 && !parsedOptions.any((o) => o.isCorrect)) {
      final answerText =
          _readString(json, const ['correctAnswer', 'correct_answer', 'answer']);
      if (answerText.isNotEmpty) {
        final match = parsedOptions.indexWhere(
          (o) => o.text.trim().toLowerCase() == answerText.trim().toLowerCase(),
        );
        if (match >= 0) resolvedIdx = match;
      }
    }

    final questionText = _readString(
      json,
      const ['questionText', 'question_text', 'question', 'stem'],
    );

    var id = _readString(json, const ['id', 'question_id', 'questionId']);
    if (id.isEmpty) {
      // A blank id would make every malformed item compare equal under [==]
      // (which List.contains relies on), so synthesize a deterministic one.
      id = 'q_${questionText.hashCode.toUnsigned(32)}';
    }

    return Question._(
      id: id,
      subject: _readString(
        json,
        const ['subject', 'subject_id', 'subjectId'],
      ),
      topic: _readString(json, const ['topic', 'topic_name', 'topicName']),
      questionText: questionText,
      answerOptions: _applyCorrectIndex(
        parsedOptions,
        resolvedIdx >= 0 ? resolvedIdx : null,
      ),
      difficulty: _parseDifficulty(json['difficulty'] ?? json['level']),
      explanation: _readString(json, const ['explanation', 'rationale']),
      legalBasis: _readNullableString(
        json,
        const ['legalBasis', 'legal_basis', 'basis'],
      ),
      remediationHint: _readNullableString(
        json,
        const ['remediationHint', 'remediation_hint', 'hint'],
      ),
      source: _parseSource(json['source']),
      version: _readInt(json, const ['version'], fallback: 1),
      templateId: _readNullableString(
        json,
        const ['templateId', 'template_id'],
      ),
      correctAnswerIndex: resolvedIdx,
    );
  }

  Question copyWith({
    String? id,
    String? subject,
    String? topic,
    String? questionText,
    List<AnswerOption>? answerOptions,
    Difficulty? difficulty,
    String? explanation,
    String? legalBasis,
    String? remediationHint,
    QuestionSource? source,
    int? version,
    String? templateId,
  }) {
    return Question._(
      id: id ?? this.id,
      subject: subject ?? this.subject,
      topic: topic ?? this.topic,
      questionText: questionText ?? this.questionText,
      answerOptions: answerOptions ?? this.answerOptions,
      difficulty: difficulty ?? this.difficulty,
      explanation: explanation ?? this.explanation,
      legalBasis: legalBasis ?? this.legalBasis,
      remediationHint: remediationHint ?? this.remediationHint,
      source: source ?? this.source,
      version: version ?? this.version,
      templateId: templateId ?? this.templateId,
      correctAnswerIndex:
          answerOptions != null ? -1 : _correctAnswerIndex,
    );
  }

  /// Identity is the [id] alone.
  ///
  /// `adaptive_learning_service.dart` calls `List<Question>.contains(...)` and
  /// `QuestionSelectionService` de-duplicates by identity, so two instances of
  /// the same item (one from cache, one from the network) must compare equal.
  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Question && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'Question($id, $subject/$topic, ${difficulty.name}, ${answerOptions.length} options)';

  // ---------------------------------------------------------------------------
  // Parsing helpers -- all total functions, none of them throw.
  // ---------------------------------------------------------------------------

  /// Ensures exactly one option carries the `isCorrect` flag when a legacy
  /// index is the only key available.
  static List<AnswerOption> _applyCorrectIndex(
    List<AnswerOption> options,
    int? index,
  ) {
    if (options.isEmpty) return const <AnswerOption>[];
    if (options.any((o) => o.isCorrect)) {
      return List<AnswerOption>.unmodifiable(options);
    }
    if (index == null || index < 0 || index >= options.length) {
      return List<AnswerOption>.unmodifiable(options);
    }
    final out = <AnswerOption>[];
    for (var i = 0; i < options.length; i++) {
      out.add(i == index ? options[i].copyWith(isCorrect: true) : options[i]);
    }
    return List<AnswerOption>.unmodifiable(out);
  }

  /// Handles `List<String>`, `List<Map>`, a JSON-encoded string (jsonb columns
  /// occasionally arrive as text), and null.
  static List<AnswerOption> _parseOptions(dynamic raw) {
    dynamic value = raw;
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return const <AnswerOption>[];
      try {
        value = jsonDecode(trimmed);
      } catch (_) {
        return const <AnswerOption>[];
      }
    }
    if (value is! List) return const <AnswerOption>[];

    final out = <AnswerOption>[];
    for (final entry in value) {
      if (entry == null) continue;
      if (entry is String) {
        out.add(AnswerOption(text: entry));
      } else if (entry is Map) {
        out.add(AnswerOption.fromJson(
          entry.map((k, v) => MapEntry(k.toString(), v)),
        ));
      } else {
        out.add(AnswerOption(text: entry.toString()));
      }
    }
    return out;
  }

  /// Accepts an int index, a numeric string, `easy`/`EASY`, or
  /// `Difficulty.easy`. Defaults to [Difficulty.medium].
  static Difficulty _parseDifficulty(dynamic raw) {
    if (raw is Difficulty) return raw;
    if (raw is int) {
      if (raw >= 0 && raw < Difficulty.values.length) {
        return Difficulty.values[raw];
      }
      return Difficulty.medium;
    }
    if (raw is num) return _parseDifficulty(raw.toInt());
    if (raw is String) {
      final s = raw.trim().toLowerCase().split('.').last;
      for (final d in Difficulty.values) {
        if (d.name == s) return d;
      }
      final asInt = int.tryParse(s);
      if (asInt != null) return _parseDifficulty(asInt);
    }
    return Difficulty.medium;
  }

  /// Defaults to [QuestionSource.admin]: an unlabelled item is assumed to be
  /// admin-authored content (panel note 7).
  static QuestionSource _parseSource(dynamic raw) {
    if (raw is QuestionSource) return raw;
    if (raw is int) {
      if (raw >= 0 && raw < QuestionSource.values.length) {
        return QuestionSource.values[raw];
      }
      return QuestionSource.admin;
    }
    if (raw is String) {
      final s = raw.trim().toLowerCase().split('.').last;
      for (final v in QuestionSource.values) {
        if (v.name == s) return v;
      }
    }
    return QuestionSource.admin;
  }

  static int _readInt(
    Map<String, dynamic> json,
    List<String> keys, {
    required int fallback,
  }) {
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
}

// -----------------------------------------------------------------------------
// Shared tolerant readers (used by both AnswerOption and Question).
// -----------------------------------------------------------------------------

String _readString(Map<String, dynamic> json, List<String> keys) {
  return _readNullableString(json, keys) ?? '';
}

String? _readNullableString(Map<String, dynamic> json, List<String> keys) {
  for (final k in keys) {
    final v = json[k];
    if (v == null) continue;
    if (v is String) {
      if (v.isEmpty) continue;
      return v;
    }
    return v.toString();
  }
  return null;
}

bool _readBool(Map<String, dynamic> json, List<String> keys) {
  for (final k in keys) {
    final v = json[k];
    if (v == null) continue;
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) {
      final s = v.trim().toLowerCase();
      if (s == 'true' || s == 't' || s == '1' || s == 'yes') return true;
      if (s == 'false' || s == 'f' || s == '0' || s == 'no') return false;
    }
  }
  return false;
}
