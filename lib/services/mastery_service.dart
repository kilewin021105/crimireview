import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/mastery.dart';
import '../models/question.dart' show Difficulty;
import 'supabase_service.dart';

/// The learner model of CrimiReview: **Bayesian Knowledge Tracing (BKT)**.
///
/// ---------------------------------------------------------------------------
/// WHY THIS FILE EXISTS (panel notes 2 and 4)
/// ---------------------------------------------------------------------------
/// Panel note 2 asked us to "make it a machine learning so that the system can
/// monitor the progress of the students". Panel note 4 asked us to "show or
/// state in your RRL, your basis on the adaptive learning".
///
/// The old system answered neither. It decided difficulty with a hardcoded
/// ladder -- `accuracy >= 0.8 ? hard : accuracy >= 0.6 ? medium : easy` -- which
/// is a rule of thumb with no literature behind it, and it kept no model of
/// what the student actually knows.
///
/// This service replaces that with the standard algorithm of the intelligent
/// tutoring systems literature:
///
///   Corbett, A. T., & Anderson, J. R. (1995). *Knowledge tracing: Modeling the
///   acquisition of procedural knowledge.* User Modeling and User-Adapted
///   Interaction, 4(4), 253-278.
///
/// ---------------------------------------------------------------------------
/// THE ALGORITHM IN PLAIN LANGUAGE
/// ---------------------------------------------------------------------------
/// BKT is a two-state Hidden Markov Model. For every topic the student is
/// modelled as being in one of two hidden states -- "knows it" or "does not
/// know it". We can never observe that state directly; all we ever see is
/// whether an answer was right or wrong. So instead of a state we keep a
/// *probability*: `pKnown` = P(the student has learned this topic).
///
/// Four parameters connect the hidden state to what we observe:
///
///   * **p(init)  = 0.20** -- prior. Before any evidence, we assume a 20%
///     chance the student already knows the topic.
///   * **p(transit) = 0.20** -- learning rate. Each practice attempt has a 20%
///     chance of actually teaching the topic (this is what makes practice pay
///     off even when the answer was wrong).
///   * **p(slip) = 0.10** -- the student KNOWS it but answers wrong anyway
///     (misread, mis-tap, careless). Scaled up for hard items, see [_pSlipFor].
///   * **p(guess) = 0.25** -- the student does NOT know it but answers right
///     anyway. 0.25 = 1/4, the guess rate of a 4-option multiple choice item.
///     Scaled by the real option count, see [_pGuessFor].
///
/// After every answer we do two steps:
///
///   1. **Evidence (Bayes' rule).** Given what just happened, how likely is it
///      that the student already knew the topic?
///   2. **Learning.** Even if they did not know it, the attempt itself may have
///      taught them, with probability p(transit).
///
/// The consequence -- and this is the whole point when defending the system --
/// is that a *lucky guess raises `pKnown` only a little* and a *careless slip
/// lowers it only a little*, whereas raw accuracy treats both as gospel. That
/// is exactly why BKT, not accuracy, decides whether to advance or repeat.
///
/// ---------------------------------------------------------------------------
/// HOW THIS DRIVES THE APP (panel note 3)
/// ---------------------------------------------------------------------------
/// Panel note 3: *"give a reviewer to the student, then give questions. Then the
/// system monitors the progress -- if the student is good at that topic
/// [advance]; if not, it will REPEAT the topic but NOT the same question."*
///
///   * "monitors the progress"  -> [recordAttempt] updates `pKnown` per topic.
///   * "is good at that topic"  -> [TopicMastery.isMastered]
///                                 (pKnown >= 0.90 with >= 4 attempts).
///   * "if not, REPEAT"         -> [TopicMastery.needsRemediation]
///                                 (pKnown < 0.60 with >= 3 attempts), surfaced
///                                 by [weakTopics].
///   * "but NOT the same question" -> enforced by `QuestionSelectionService`,
///     which weights its picks toward the lowest-`pKnown` topics returned here
///     while excluding question ids the learner has already seen.
///
/// ---------------------------------------------------------------------------
/// DATA
/// ---------------------------------------------------------------------------
///   * Local (always): SharedPreferences key `topic_mastery_v1`, a JSON map of
///     `'subjectId::topic'` -> [TopicMastery]. The model therefore works fully
///     offline; a quiz never depends on the network.
///   * Cloud (best effort): `public.topic_mastery`, upserted on
///     `(user_id, subject_id, topic)` so the model follows the student across
///     devices and reinstalls.
///   * Audit trail: every single attempt is appended to
///     `public.question_attempts` with `p_known_before` / `p_known_after`, so
///     the full knowledge trajectory can be replayed -- the evidence that the
///     model is really learning, and the dataset for any future retraining.
///
/// Every cloud call is wrapped and silently degrades: logged out, offline or a
/// server error must never interrupt a quiz.
class MasteryService extends ChangeNotifier {
  MasteryService._();

  static final MasteryService _instance = MasteryService._();

  /// Process-wide singleton, matching the pattern of the other services.
  static MasteryService get instance => _instance;

  // ---------------------------------------------------------------------------
  // BKT PARAMETERS (Corbett & Anderson, 1995)
  // ---------------------------------------------------------------------------

  /// P(L_0) -- prior probability the topic is already known before any
  /// evidence. Kept identical to [TopicMastery.defaultPInit] and to the
  /// `p_known` default in `supabase_schema_v2.sql`, so the code, the database
  /// and the RRL all state the same number.
  static const double pInit = TopicMastery.defaultPInit; // 0.20

  /// P(T) -- probability that an attempt moves the student from "does not know"
  /// to "knows". This is why answering wrong is still progress: the student saw
  /// the explanation (panel note 5) and may have learned from it.
  static const double pTransit = 0.20;

  /// P(S) -- base slip rate: knows the topic, still answers wrong.
  static const double pSlip = 0.10;

  /// P(G) -- base guess rate: does not know the topic, still answers right.
  ///
  /// 0.25 = 1/4, the chance of guessing correctly on a 4-option multiple choice
  /// item, which is the format of every item in CrimiReview.
  static const double pGuess = 0.25;

  /// Slip rate used for [Difficulty.hard] items.
  ///
  /// A student who genuinely knows a topic still slips more often on a hard,
  /// heavily-qualified bar-style stem than on a definition recall item, so a
  /// single miss on a hard item should cost less confidence than a miss on an
  /// easy one.
  static const double pSlipHard = 0.15;

  /// Slip rate used for [Difficulty.easy] items -- a miss here is much stronger
  /// evidence of not knowing, so we lower the excuse.
  static const double pSlipEasy = 0.08;

  /// `pKnown` is clamped into [[_pMin], [_pMax]] so it never reaches an
  /// absorbing 0 or 1 that no future evidence could move.
  static const double _pMin = 0.001;
  static const double _pMax = 0.999;

  /// Denominators smaller than this are treated as degenerate and the update is
  /// skipped (defensive: with the parameters above it cannot happen, but a
  /// future admin-tunable parameter set must not divide by zero).
  static const double _epsilon = 1e-9;

  // ---------------------------------------------------------------------------
  // FORGETTING / SPACED REPETITION
  // ---------------------------------------------------------------------------

  /// Days of inactivity tolerated before decay begins.
  ///
  /// Classic BKT has no forgetting term: once `pKnown` is high it stays high
  /// forever, which would let a student "master" Criminal Jurisprudence in
  /// March and still look mastered in September. The forgetting-curve
  /// literature (Ebbinghaus, 1885; Cepeda, Pashler, Vul, Wixted & Rohrer, 2006,
  /// *Distributed practice in verbal recall tasks*, Psychological Bulletin
  /// 132(3)) says retention decays without spaced review, so we relax an
  /// untouched topic back toward the prior. This is what makes the app schedule
  /// review instead of declaring victory once.
  static const int decayGraceDays = 14;

  /// Half-life, in days, of the decay applied AFTER the grace period: the gap
  /// between `pKnown` and the prior halves every 30 idle days. Mild on purpose
  /// -- forgetting should nudge a student back to review, not erase months of
  /// evidence.
  static const double decayHalfLifeDays = 30.0;

  // ---------------------------------------------------------------------------
  // STORAGE KEYS
  // ---------------------------------------------------------------------------

  static const String _prefsKey = 'topic_mastery_v1';
  static const String _masteryTable = 'topic_mastery';
  static const String _attemptsTable = 'question_attempts';

  /// Cloud upserts are debounced so a 10-question quiz produces one network
  /// round trip rather than ten.
  static const Duration _syncDebounce = Duration(seconds: 4);

  // ---------------------------------------------------------------------------
  // STATE
  // ---------------------------------------------------------------------------

  SharedPreferences? _prefs;

  /// `'subjectId::topic'` -> traced state. The whole learner model.
  final Map<String, TopicMastery> _mastery = <String, TopicMastery>{};

  bool _initialized = false;
  bool _isSyncing = false;
  Timer? _syncTimer;

  /// True once [init] has completed. Reads before that simply return neutral
  /// values instead of throwing.
  bool get isReady => _initialized;

  /// Number of topics with at least one recorded attempt.
  int get trackedTopicCount => _mastery.length;

  /// Read-only view of the whole model (used by the progress screen).
  List<TopicMastery> get all =>
      List<TopicMastery>.unmodifiable(_mastery.values.map(_decayed));

  // ---------------------------------------------------------------------------
  // LIFECYCLE
  // ---------------------------------------------------------------------------

  /// Loads the local model, then refreshes from the cloud in the background.
  ///
  /// Safe to call more than once. Never throws: a corrupt cache or a dead
  /// network leaves the service usable with an empty model.
  Future<void> init() async {
    if (_initialized) return;
    try {
      _prefs = await SharedPreferences.getInstance();
      _loadLocal();
    } catch (e) {
      debugPrint('MasteryService.init local load failed: $e');
    }
    _initialized = true;
    notifyListeners();

    // Cloud merge must not block app start-up or the first quiz.
    unawaited(loadFromCloud());
  }

  Future<SharedPreferences> _getPrefs() async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  // ---------------------------------------------------------------------------
  // THE BKT UPDATE -- the heart of the service
  // ---------------------------------------------------------------------------

  /// Records one answered item and returns the updated [TopicMastery].
  ///
  /// This is the single place where the learner model changes. Call it once per
  /// answered question, from the quiz screen, the daily challenge, or anywhere
  /// else the student is assessed.
  ///
  /// [optionCount], [questionId] and [selectedIndex] are optional: they refine
  /// the guess parameter and enrich the audit trail, but the update works
  /// without them.
  ///
  /// The maths, step by step, for `pL = pKnown` before this answer:
  ///
  /// ```text
  /// CORRECT ANSWER
  ///   P(knew it AND did not slip)          = pL * (1 - pSlip)
  ///   P(did not know it AND guessed right) = (1 - pL) * pGuess
  ///   posterior = the first over the sum of both
  ///
  /// WRONG ANSWER
  ///   P(knew it AND slipped)               = pL * pSlip
  ///   P(did not know it AND did not guess) = (1 - pL) * (1 - pGuess)
  ///   posterior = the first over the sum of both
  ///
  /// THEN, either way
  ///   pKnown_next = posterior + (1 - posterior) * pTransit
  /// ```
  ///
  /// Worked example with the defaults (pL = 0.20, pSlip = 0.10, pGuess = 0.25):
  /// one correct answer gives posterior = 0.18/(0.18+0.20) = 0.474, then
  /// 0.474 + 0.526*0.20 = **0.579**. One right answer is encouraging but far
  /// from mastery -- it could have been a guess. That restraint is precisely
  /// what a hardcoded accuracy ladder cannot express.
  Future<TopicMastery> recordAttempt({
    required String subjectId,
    required String topic,
    required bool isCorrect,
    required Difficulty difficulty,
    int responseTimeMs = 0,
    String questionId = '',
    int? selectedIndex,
    int optionCount = 4,
  }) async {
    if (!_initialized) await init();

    final normalizedSubject = subjectId.trim();
    final normalizedTopic = topic.trim().isEmpty ? 'General' : topic.trim();
    final key = '$normalizedSubject::$normalizedTopic';

    // Start from the stored state, first relaxed by any forgetting that
    // happened since the last practice (see [_decayed]).
    final existing = _mastery[key];
    final current = existing == null
        ? TopicMastery(subjectId: normalizedSubject, topic: normalizedTopic)
        : _decayed(existing);

    final double pL = current.pKnown.clamp(_pMin, _pMax).toDouble();
    final double slip = _pSlipFor(difficulty);
    final double guess = _pGuessFor(optionCount);
    final double masteryBefore = pL;

    // -------------------------------------------------------------------
    // Evidence step -- posterior that the learner already knew the skill,
    // given what they just did.
    // -------------------------------------------------------------------
    double pLgivenObs;
    if (isCorrect) {
      // Right answer: either they knew it and did not slip, or they did not
      // know it and guessed correctly.
      final double knewAndDidNotSlip = pL * (1 - slip);
      final double guessedRight = (1 - pL) * guess;
      final double denominator = knewAndDidNotSlip + guessedRight;
      pLgivenObs =
          denominator < _epsilon ? pL : knewAndDidNotSlip / denominator;
    } else {
      // Wrong answer: either they knew it and slipped, or they did not know it
      // and failed to guess.
      final double knewButSlipped = pL * slip;
      final double didNotKnowAndMissed = (1 - pL) * (1 - guess);
      final double denominator = knewButSlipped + didNotKnowAndMissed;
      pLgivenObs = denominator < _epsilon ? pL : knewButSlipped / denominator;
    }

    // -------------------------------------------------------------------
    // Learning step -- chance the attempt itself taught them the skill.
    // Applied whether they were right or wrong, because seeing the worked
    // explanation after a miss (panel note 5) is itself instruction.
    // -------------------------------------------------------------------
    double pLNext = pLgivenObs + (1 - pLgivenObs) * pTransit;
    pLNext = pLNext.clamp(_pMin, _pMax).toDouble();

    // consecutiveCorrect resets to 0 on a miss -- that streak is what the
    // "on a roll" UI shows and a tiebreaker when ranking weak topics.
    final updated = current.copyWith(
      pKnown: pLNext,
      attempts: current.attempts + 1,
      correct: current.correct + (isCorrect ? 1 : 0),
      consecutiveCorrect: isCorrect ? current.consecutiveCorrect + 1 : 0,
      lastPracticed: DateTime.now(),
    );

    _mastery[key] = updated;

    await _saveLocal();
    notifyListeners();

    // Fire and forget -- neither of these may ever block or fail a quiz.
    unawaited(_logAttempt(
      questionId: questionId,
      subjectId: normalizedSubject,
      topic: normalizedTopic,
      difficulty: difficulty,
      selectedIndex: selectedIndex,
      isCorrect: isCorrect,
      responseTimeMs: responseTimeMs,
      pKnownBefore: masteryBefore,
      pKnownAfter: pLNext,
    ));
    _scheduleCloudSync();

    return updated;
  }

  /// Slip probability for an item of this difficulty.
  ///
  /// A strong student slips more on hard items, so a single miss there is
  /// weaker evidence of not knowing the topic.
  double _pSlipFor(Difficulty difficulty) {
    switch (difficulty) {
      case Difficulty.easy:
        return pSlipEasy;
      case Difficulty.medium:
        return pSlip;
      case Difficulty.hard:
        return pSlipHard;
    }
  }

  /// Guess probability for an item with [optionCount] choices: 1/n.
  ///
  /// Defaults to 0.25 for the standard 4-option MCQ. A true/false item would
  /// give 0.5, meaning a correct answer barely moves `pKnown` -- which is the
  /// statistically honest response. Clamped so a malformed item with 0 or 1
  /// options cannot produce a degenerate parameter.
  double _pGuessFor(int optionCount) {
    if (optionCount < 2) return pGuess;
    return (1.0 / optionCount).clamp(0.05, 0.50).toDouble();
  }

  // ---------------------------------------------------------------------------
  // FORGETTING DECAY
  // ---------------------------------------------------------------------------

  /// Returns [m] with `pKnown` relaxed toward [pInit] for time not practised.
  ///
  /// Nothing happens for the first [decayGraceDays] days. After that the gap
  /// between the traced `pKnown` and the prior halves every
  /// [decayHalfLifeDays] idle days:
  ///
  /// ```text
  /// retention = 0.5 ^ ((idleDays - 14) / 30)
  /// pKnown'   = pInit + (pKnown - pInit) * retention
  /// ```
  ///
  /// Rationale: the spacing effect / forgetting curve (Ebbinghaus, 1885;
  /// Cepeda et al., 2006). Unreviewed knowledge decays, so a topic mastered
  /// two months ago should re-enter the review rotation rather than stay
  /// permanently green. Only decays downward -- a `pKnown` already below the
  /// prior is left alone, because idleness is not evidence of improvement.
  TopicMastery _decayed(TopicMastery m) {
    final last = m.lastPracticed;
    if (last == null || m.attempts == 0) return m;
    if (m.pKnown <= pInit) return m;

    final idleDays = DateTime.now().difference(last).inDays;
    if (idleDays <= decayGraceDays) return m;

    final double elapsed = (idleDays - decayGraceDays) / decayHalfLifeDays;
    final double retention =
        math.pow(0.5, elapsed).toDouble().clamp(0.0, 1.0).toDouble();
    final double decayedP =
        (pInit + (m.pKnown - pInit) * retention).clamp(_pMin, _pMax).toDouble();

    return m.copyWith(pKnown: decayedP);
  }

  // ---------------------------------------------------------------------------
  // READS -- what the UI and the selection service ask for
  // ---------------------------------------------------------------------------

  /// Current traced state for one topic, decay applied.
  ///
  /// Never null: an untouched topic comes back at the prior (`pKnown` = 0.20,
  /// 0 attempts, [MasteryLevel.notStarted]).
  TopicMastery masteryFor(String subjectId, String topic) {
    final key = '${subjectId.trim()}::${topic.trim()}';
    final found = _mastery[key];
    if (found == null) {
      return TopicMastery(subjectId: subjectId.trim(), topic: topic.trim());
    }
    return _decayed(found);
  }

  /// Every traced topic of one subject, strongest first.
  List<TopicMastery> allFor(String subjectId) {
    final id = subjectId.trim();
    final list = _mastery.values
        .where((m) => m.subjectId == id)
        .map(_decayed)
        .toList();
    list.sort((a, b) => b.pKnown.compareTo(a.pKnown));
    return list;
  }

  /// The topics to re-teach, weakest first (panel note 3, the "if not" branch).
  ///
  /// Only topics with at least 2 attempts qualify: one answer is far too little
  /// evidence to label a topic weak, and acting on it would send the student
  /// into remediation for a single unlucky tap.
  ///
  /// `QuestionSelectionService` consumes this to bias item selection toward the
  /// lowest `pKnown` (its rule R4) while excluding already-seen question ids
  /// (rule R1) -- together, "repeat the topic but NOT the same question".
  List<TopicMastery> weakTopics(String subjectId, {int limit = 5}) {
    final id = subjectId.trim();
    final list = _mastery.values
        .where((m) => m.subjectId == id && m.attempts >= 2)
        .map(_decayed)
        .toList();

    list.sort((a, b) {
      final byP = a.pKnown.compareTo(b.pKnown);
      if (byP != 0) return byP;
      // Tie-break: fewer correct answers in a row is the shakier topic.
      final byStreak = a.consecutiveCorrect.compareTo(b.consecutiveCorrect);
      if (byStreak != 0) return byStreak;
      return a.topic.compareTo(b.topic);
    });

    if (limit <= 0 || limit >= list.length) return list;
    return list.sublist(0, limit);
  }

  /// Topics cleared for advancement (panel note 3, the "is good" branch):
  /// `pKnown >= 0.90` backed by at least 4 attempts.
  List<TopicMastery> masteredTopics(String subjectId) {
    final id = subjectId.trim();
    final list = _mastery.values
        .where((m) => m.subjectId == id)
        .map(_decayed)
        .where((m) => m.isMastered)
        .toList();
    list.sort((a, b) => b.pKnown.compareTo(a.pKnown));
    return list;
  }

  /// Topics that fell below the remediation threshold with enough evidence.
  List<TopicMastery> remediationTopics(String subjectId) {
    final id = subjectId.trim();
    final list = _mastery.values
        .where((m) => m.subjectId == id)
        .map(_decayed)
        .where((m) => m.needsRemediation)
        .toList();
    list.sort((a, b) => a.pKnown.compareTo(b.pKnown));
    return list;
  }

  /// Mean `pKnown` over the practised topics of one subject; 0.0 if none.
  ///
  /// Unpractised topics are excluded on purpose: averaging in the 0.20 prior of
  /// topics the student has never opened would understate real progress and
  /// make the progress bar move for the wrong reason.
  double subjectMastery(String subjectId) {
    final id = subjectId.trim();
    final values = _mastery.values
        .where((m) => m.subjectId == id && m.attempts > 0)
        .map((m) => _decayed(m).pKnown)
        .toList();
    return _mean(values);
  }

  /// Mean `pKnown` over every practised topic in every subject.
  double overallMastery() {
    final values = _mastery.values
        .where((m) => m.attempts > 0)
        .map((m) => _decayed(m).pKnown)
        .toList();
    return _mean(values);
  }

  /// Convenience wrapper used by the quiz flow to decide advance vs repeat.
  bool isTopicMastered(String subjectId, String topic) =>
      masteryFor(subjectId, topic).isMastered;

  /// True when the topic should be repeated with different items.
  bool needsRemediation(String subjectId, String topic) =>
      masteryFor(subjectId, topic).needsRemediation;

  static double _mean(List<double> values) {
    if (values.isEmpty) return 0.0;
    final sum = values.fold<double>(0.0, (a, b) => a + b);
    return (sum / values.length).clamp(0.0, 1.0).toDouble();
  }

  // ---------------------------------------------------------------------------
  // SNAPSHOT -- one map the progress screen and the admin dashboard both read
  // ---------------------------------------------------------------------------

  /// A single digest of the learner model (panel note 2: the system MONITORS
  /// the student, and that monitoring must be visible).
  ///
  /// Pass [subjectId] to scope the snapshot to one subject; omit it for the
  /// whole account. Shape:
  ///
  /// ```json
  /// {
  ///   "overallMastery": 0.62,        // 0.0-1.0 mean pKnown
  ///   "masteryPercent": 62,          // rounded, for a progress bar
  ///   "masteredCount": 4,            // pKnown >= 0.90 with >= 4 attempts
  ///   "strugglingCount": 2,          // pKnown < 0.30
  ///   "topicsInProgress": 11,        // topics with >= 1 attempt
  ///   "totalAttempts": 137,
  ///   "totalCorrect": 96,
  ///   "accuracy": 0.70,
  ///   "weakest": [ {topic, subjectId, pKnown, level, attempts, accuracy}, ... ],
  ///   "strongest": [ ... ]
  /// }
  /// ```
  Map<String, dynamic> learnerSnapshot({String? subjectId, int listSize = 3}) {
    final id = subjectId?.trim();
    final tracked = _mastery.values
        .where((m) => id == null || m.subjectId == id)
        .map(_decayed)
        .where((m) => m.attempts > 0)
        .toList();

    final overall =
        _mean(tracked.map((m) => m.pKnown).toList(growable: false));

    final sorted = List<TopicMastery>.from(tracked)
      ..sort((a, b) => a.pKnown.compareTo(b.pKnown));

    final weakest = sorted
        .where((m) => m.attempts >= 2)
        .take(listSize)
        .map(_topicDigest)
        .toList();
    final strongest = sorted.reversed
        .take(listSize)
        .map(_topicDigest)
        .toList();

    final totalAttempts =
        tracked.fold<int>(0, (sum, m) => sum + m.attempts);
    final totalCorrect = tracked.fold<int>(0, (sum, m) => sum + m.correct);

    return <String, dynamic>{
      'overallMastery': overall,
      'masteryPercent': (overall * 100).round(),
      'masteredCount': tracked.where((m) => m.isMastered).length,
      'strugglingCount':
          tracked.where((m) => m.level == MasteryLevel.struggling).length,
      'topicsInProgress': tracked.length,
      'totalAttempts': totalAttempts,
      'totalCorrect': totalCorrect,
      'accuracy': totalAttempts == 0 ? 0.0 : totalCorrect / totalAttempts,
      'weakest': weakest,
      'strongest': strongest,
    };
  }

  Map<String, dynamic> _topicDigest(TopicMastery m) => <String, dynamic>{
        'subjectId': m.subjectId,
        'topic': m.topic,
        'pKnown': m.pKnown,
        'masteryPercent': m.masteryPercent.round(),
        'level': m.level.name,
        'levelLabel': m.levelLabel,
        'attempts': m.attempts,
        'correct': m.correct,
        'accuracy': m.accuracy,
        'needsRemediation': m.needsRemediation,
        'isMastered': m.isMastered,
      };

  // ---------------------------------------------------------------------------
  // LOCAL PERSISTENCE
  // ---------------------------------------------------------------------------

  void _loadLocal() {
    final raw = _prefs?.getString(_prefsKey);
    if (raw == null || raw.trim().isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      _mastery.clear();
      decoded.forEach((key, value) {
        if (value is! Map) return;
        try {
          final m = TopicMastery.fromJson(
            value.map((k, v) => MapEntry(k.toString(), v)),
          );
          if (m.subjectId.isEmpty || m.topic.isEmpty) return;
          _mastery[m.key] = m;
        } catch (_) {
          // One malformed entry must never wipe the whole model.
        }
      });
    } catch (e) {
      debugPrint('MasteryService: corrupt local model, starting fresh ($e)');
      _mastery.clear();
    }
  }

  Future<void> _saveLocal() async {
    try {
      final prefs = await _getPrefs();
      final payload = <String, dynamic>{
        for (final entry in _mastery.entries) entry.key: entry.value.toJson(),
      };
      await prefs.setString(_prefsKey, jsonEncode(payload));
    } catch (e) {
      debugPrint('MasteryService._saveLocal failed: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // CLOUD MIRROR -- best effort, never load-bearing
  // ---------------------------------------------------------------------------

  bool get _canReachCloud {
    try {
      return SupabaseService.isInitialized && SupabaseService.instance.isLoggedIn;
    } catch (_) {
      return false;
    }
  }

  void _scheduleCloudSync() {
    if (!_canReachCloud) return;
    _syncTimer?.cancel();
    _syncTimer = Timer(_syncDebounce, () {
      unawaited(syncToCloud());
    });
  }

  /// Upserts the whole model into `public.topic_mastery`.
  ///
  /// No-ops silently when logged out, when Supabase was never initialised, or
  /// when the network is unavailable -- the local model remains the source of
  /// truth for the running session and will be pushed on the next attempt.
  Future<void> syncToCloud() async {
    if (_isSyncing || _mastery.isEmpty || !_canReachCloud) return;

    _isSyncing = true;
    try {
      final userId = SupabaseService.instance.userId;
      if (userId == null) return;

      final rows = _mastery.values.map((m) {
        final decayed = _decayed(m);
        return <String, dynamic>{
          ...decayed.toSupabaseRow(),
          'user_id': userId,
          // Denormalised so the admin dashboard can count mastered topics
          // without re-deriving the threshold in SQL.
          'is_mastered': decayed.isMastered,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        };
      }).toList(growable: false);

      await SupabaseService.instance.client
          .from(_masteryTable)
          .upsert(rows, onConflict: 'user_id,subject_id,topic');
    } catch (e) {
      debugPrint('MasteryService.syncToCloud failed (kept local): $e');
    } finally {
      _isSyncing = false;
    }
  }

  /// Pulls `public.topic_mastery` and merges it into the local model.
  ///
  /// Merge rule: for each `(subject, topic)` the record with MORE attempts wins,
  /// because more evidence means a better-informed posterior; ties are broken by
  /// the more recent `lastPracticed`. This makes a fresh install on a new phone
  /// adopt the cloud model, while a phone that has been used offline keeps the
  /// attempts it recorded and pushes them up on the next [syncToCloud].
  Future<void> loadFromCloud() async {
    if (!_canReachCloud) return;
    try {
      final userId = SupabaseService.instance.userId;
      if (userId == null) return;

      final response = await SupabaseService.instance.client
          .from(_masteryTable)
          .select()
          .eq('user_id', userId);

      final rows = List<Map<String, dynamic>>.from(response as List);
      if (rows.isEmpty) return;

      var changed = false;
      for (final row in rows) {
        try {
          final remote = TopicMastery.fromJson(row);
          if (remote.subjectId.isEmpty || remote.topic.isEmpty) continue;

          final local = _mastery[remote.key];
          if (local == null || _remoteWins(local, remote)) {
            _mastery[remote.key] = remote;
            changed = true;
          }
        } catch (_) {
          // Skip an unreadable row rather than aborting the whole merge.
        }
      }

      if (changed) {
        await _saveLocal();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('MasteryService.loadFromCloud failed (kept local): $e');
    }
  }

  static bool _remoteWins(TopicMastery local, TopicMastery remote) {
    if (remote.attempts != local.attempts) {
      return remote.attempts > local.attempts;
    }
    final localAt = local.lastPracticed;
    final remoteAt = remote.lastPracticed;
    if (remoteAt == null) return false;
    if (localAt == null) return true;
    return remoteAt.isAfter(localAt);
  }

  /// Appends one immutable row to `public.question_attempts`.
  ///
  /// This is the training / audit dataset behind panel note 2: with
  /// `p_known_before` and `p_known_after` on every row, the entire knowledge
  /// trajectory of a student can be replayed and defended, and the four BKT
  /// parameters can later be re-fitted from real data instead of using the
  /// published defaults.
  ///
  /// Deliberately fire-and-forget: an unreachable server must cost the student
  /// nothing.
  Future<void> _logAttempt({
    required String questionId,
    required String subjectId,
    required String topic,
    required Difficulty difficulty,
    required int? selectedIndex,
    required bool isCorrect,
    required int responseTimeMs,
    required double pKnownBefore,
    required double pKnownAfter,
  }) async {
    if (!_canReachCloud) return;
    try {
      final userId = SupabaseService.instance.userId;
      if (userId == null) return;

      await SupabaseService.instance.client.from(_attemptsTable).insert({
        'user_id': userId,
        // question_id is NOT NULL in the schema; an attempt recorded without an
        // id (e.g. a legacy caller) is still valid evidence, so it is tagged
        // rather than dropped.
        'question_id': questionId.trim().isEmpty ? 'unknown' : questionId.trim(),
        'subject_id': subjectId,
        'topic': topic,
        'difficulty': difficulty.name,
        'selected_index': selectedIndex,
        'is_correct': isCorrect,
        'response_time_ms': responseTimeMs < 0 ? 0 : responseTimeMs,
        'p_known_before': double.parse(pKnownBefore.toStringAsFixed(5)),
        'p_known_after': double.parse(pKnownAfter.toStringAsFixed(5)),
      });
    } catch (e) {
      debugPrint('MasteryService._logAttempt skipped: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // RESET
  // ---------------------------------------------------------------------------

  /// Wipes the learner model locally and, when possible, in the cloud.
  ///
  /// Used by "reset progress" in settings and when switching accounts on a
  /// shared device -- one student must never inherit another student's model.
  /// `question_attempts` is append-only and is intentionally NOT deleted: the
  /// audit trail survives a reset.
  Future<void> reset() async {
    _syncTimer?.cancel();
    _syncTimer = null;
    _mastery.clear();

    try {
      final prefs = await _getPrefs();
      await prefs.remove(_prefsKey);
    } catch (e) {
      debugPrint('MasteryService.reset local clear failed: $e');
    }

    notifyListeners();

    if (!_canReachCloud) return;
    try {
      final userId = SupabaseService.instance.userId;
      if (userId == null) return;
      await SupabaseService.instance.client
          .from(_masteryTable)
          .delete()
          .eq('user_id', userId);
    } catch (e) {
      debugPrint('MasteryService.reset cloud clear failed: $e');
    }
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    _syncTimer = null;
    super.dispose();
  }
}
