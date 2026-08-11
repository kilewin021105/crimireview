import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/question.dart';
import 'mastery_service.dart';
import 'question_repository.dart';
import 'supabase_service.dart';

/// One learner-vs-item exposure row.
///
/// This is the ledger that makes panel note 3 -- "REPEAT the topic but NOT the
/// same question" -- enforceable rather than aspirational. The old build sliced
/// the bank with a stable `sublist()`, so a retry served literally the same ten
/// items in the same order; nothing in the app remembered what the student had
/// already been shown. This record is that memory.
///
/// [subjectId] / [topic] / [difficulty] are denormalised copies of the item's
/// metadata so the service can answer `seenIds(subject)` synchronously without
/// hitting the repository (and so cloud-hydrated rows can be filtered once the
/// pool has been loaded once).
class _ExposureRecord {
  final String questionId;

  /// Denormalised item metadata. May be blank on rows hydrated from the cloud
  /// before the matching pool has been loaded; [_backfillMetadata] fills them in.
  String subjectId;
  String topic;
  String difficulty;

  /// How many times this exact item has been served. Drives R2 recycling order.
  int timesSeen;

  /// When it was last served. Second key of the R2 recycling order, and what
  /// guarantees the item the student just missed sorts LAST among recycled ones.
  DateTime lastSeen;

  _ExposureRecord({
    required this.questionId,
    this.subjectId = '',
    this.topic = '',
    this.difficulty = '',
    this.timesSeen = 0,
    DateTime? lastSeen,
  }) : lastSeen = lastSeen ?? DateTime.fromMillisecondsSinceEpoch(0);

  Map<String, dynamic> toJson() => {
        'questionId': questionId,
        'subjectId': subjectId,
        'topic': topic,
        'difficulty': difficulty,
        'timesSeen': timesSeen,
        'lastSeen': lastSeen.toIso8601String(),
      };

  /// Tolerant parser -- a malformed row must never blank the whole ledger and
  /// silently re-expose questions the student has already answered.
  static _ExposureRecord? fromJson(Map<String, dynamic> json) {
    final id = (json['questionId'] ?? json['question_id'] ?? '').toString();
    if (id.isEmpty) return null;
    return _ExposureRecord(
      questionId: id,
      subjectId: (json['subjectId'] ?? json['subject_id'] ?? '').toString(),
      topic: (json['topic'] ?? '').toString(),
      difficulty: (json['difficulty'] ?? '').toString(),
      timesSeen: _asInt(json['timesSeen'] ?? json['times_seen'], 1),
      lastSeen: _asDate(json['lastSeen'] ?? json['last_seen']),
    );
  }

  static int _asInt(dynamic v, int fallback) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim()) ?? fallback;
    return fallback;
  }

  static DateTime _asDate(dynamic v) {
    if (v is DateTime) return v;
    if (v is String && v.trim().isNotEmpty) {
      final parsed = DateTime.tryParse(v.trim());
      if (parsed != null) return parsed;
    }
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    return DateTime.fromMillisecondsSinceEpoch(0);
  }
}

/// Chooses WHICH questions a learner sees next.
///
/// This service is the direct answer to panel note 3:
///
/// > "Give a reviewer to the student, then give questions. Then the system
/// > monitors the progress of the student -- if the student is good at that
/// > topic [advance]; if not, it will REPEAT the topic but NOT THE SAME
/// > QUESTION, then monitor the progress of the student again."
///
/// The "monitor" half lives in [MasteryService] (Bayesian Knowledge Tracing).
/// The "repeat the topic but not the same question" half lives here, as five
/// explicit rules:
///
/// * **R1** Never serve an item the learner has already seen while ANY unseen
///   item remains in the pool for that subject + difficulty.
/// * **R2** Only once the unseen pool is exhausted, recycle -- least-seen and
///   least-recently-seen first.
/// * **R3** Remediation targets the SAME weak topic but strictly DIFFERENT
///   question ids.
/// * **R4** Weight selection toward the topics with the lowest BKT p(known),
///   i.e. practise where the model says the student is weakest.
/// * **R5** Shuffle within the chosen bucket, so even an identical selection
///   never arrives in an identical order.
///
/// R4 is the Zone-of-Proximal-Development / mastery-learning targeting the
/// panel asked us to justify in note 4: instead of a hardcoded
/// `accuracy >= 0.8 ? hard : ...` ladder, item selection is driven by the
/// latent p(known) estimate per topic.
///
/// Every cloud call degrades gracefully: the ledger is authoritative locally,
/// Supabase is a mirror, and a network failure can never fail a quiz.
class QuestionSelectionService {
  QuestionSelectionService._();

  static final QuestionSelectionService _instance =
      QuestionSelectionService._();

  static QuestionSelectionService get instance => _instance;

  // ---------------------------------------------------------------------------
  // Tunables
  // ---------------------------------------------------------------------------

  /// SharedPreferences key holding the exposure ledger.
  static const String _prefsKey = 'question_exposure_v1';

  /// Supabase mirror table (see SECTION 8 of supabase_schema_v2.sql).
  static const String _cloudTable = 'question_exposure';

  /// R4: share of a quiz set drawn from the single weakest topic. The rest is
  /// spread over the remaining topics, weakest first, so a quiz still has
  /// breadth and does not become ten questions on one thing.
  static const double weakestTopicShare = 0.40;

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------

  /// questionId -> exposure. The single source of truth for R1/R2/R3.
  final Map<String, _ExposureRecord> _exposure = <String, _ExposureRecord>{};

  /// '<subjectId>::<difficulty>' -> every question id in that pool.
  ///
  /// Populated whenever a pool is loaded, so [hasUnseenRemaining] can answer
  /// synchronously for the UI ("you have exhausted the new questions for this
  /// level") without an await.
  final Map<String, Set<String>> _poolIds = <String, Set<String>>{};

  final math.Random _random = math.Random();

  bool _initialized = false;
  Future<void>? _initFuture;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Loads the local ledger, then hydrates from the cloud in the background.
  ///
  /// Safe to call repeatedly and concurrently; only the first call does work.
  Future<void> init() {
    if (_initialized) return Future<void>.value();
    return _initFuture ??= _init();
  }

  Future<void> _init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final entry in decoded) {
            if (entry is! Map) continue;
            final rec = _ExposureRecord.fromJson(
              entry.map((k, v) => MapEntry(k.toString(), v)),
            );
            if (rec != null) _exposure[rec.questionId] = rec;
          }
        } else if (decoded is Map) {
          // Older shape: { questionId: {...} }.
          decoded.forEach((k, v) {
            if (v is! Map) return;
            final map = v.map((mk, mv) => MapEntry(mk.toString(), mv));
            map.putIfAbsent('questionId', () => k.toString());
            final rec = _ExposureRecord.fromJson(map);
            if (rec != null) _exposure[rec.questionId] = rec;
          });
        }
      }
    } catch (e) {
      // A corrupt ledger is recoverable: worst case the student sees a repeat.
      debugPrint('[QuestionSelection] local ledger load failed: $e');
    }

    _initialized = true;
    debugPrint(
      '[QuestionSelection] ready -- ${_exposure.length} exposure records',
    );

    // Cross-device continuity. Deliberately NOT awaited: a slow or offline
    // network must never delay the first quiz.
    unawaited(_hydrateFromCloud());
  }

  Future<void> _ensureInit() async {
    if (!_initialized) await init();
  }

  // ---------------------------------------------------------------------------
  // Selection -- the main entry point
  // ---------------------------------------------------------------------------

  /// Builds the next quiz set for [subjectId] at [difficulty].
  ///
  /// [segmentIndex] is accepted for call-site compatibility with the existing
  /// 4-segments-of-10 flow and is used for diagnostics only. It deliberately no
  /// longer slices the bank: the old `sublist(segment * 10, ...)` is exactly why
  /// a retry served the same ten items. Which items a segment contains is now
  /// decided by the exposure ledger (R1) and BKT weakness (R4), so segment 1
  /// retried after a fail is a genuinely different set of questions.
  ///
  /// Returns fewer than [count] items only when the bank itself is smaller, and
  /// an empty list when there is no content at all (there are no hardcoded
  /// fallbacks anywhere in this file -- panel note 7).
  Future<List<Question>> buildQuizSet({
    required String subjectId,
    required Difficulty difficulty,
    int count = 10,
    int? segmentIndex,
  }) async {
    await _ensureInit();
    if (count <= 0) return const <Question>[];

    // STEP 1 -- candidate pool for this subject + difficulty.
    final pool = await _loadPool(subjectId, difficulty);
    if (pool.isEmpty) {
      debugPrint(
        '[QuestionSelection] empty pool for $subjectId/${difficulty.name} '
        '-- nothing to serve',
      );
      return const <Question>[];
    }

    // STEP 2 -- split into UNSEEN and SEEN (R1).
    final unseen = <Question>[];
    final seen = <Question>[];
    for (final q in pool) {
      (_exposure.containsKey(q.id) ? seen : unseen).add(q);
    }

    final label = segmentIndex == null ? '' : ' segment ${segmentIndex + 1}';
    debugPrint(
      '[QuestionSelection] $subjectId/${difficulty.name}$label -- '
      'pool ${pool.length}, unseen ${unseen.length}, seen ${seen.length}',
    );

    final picked = <Question>[];
    final takenIds = <String>{};

    // STEPS 3 + 4 -- rank topics by BKT p(known) ascending and draw from the
    // UNSEEN bucket, weighted toward the weakest topics.
    _drawWeighted(
      subjectId: subjectId,
      candidates: unseen,
      slots: count,
      into: picked,
      taken: takenIds,
    );

    // Any shortfall is still filled from UNSEEN before anything is recycled --
    // R1 is absolute.
    if (picked.length < count) {
      final leftover = unseen.where((q) => !takenIds.contains(q.id)).toList()
        ..shuffle(_random);
      for (final q in leftover) {
        if (picked.length >= count) break;
        if (takenIds.add(q.id)) picked.add(q);
      }
    }

    // STEP 5 -- only now may we recycle (R2): least-seen, then longest-ago.
    if (picked.length < count && seen.isNotEmpty) {
      final needed = count - picked.length;
      debugPrint(
        '[QuestionSelection] R2 RECYCLING -- unseen pool exhausted for '
        '$subjectId/${difficulty.name}; topping up $needed item(s) '
        'least-seen / least-recently-seen first',
      );
      for (final q in _recycleOrder(seen)) {
        if (picked.length >= count) break;
        if (takenIds.add(q.id)) picked.add(q);
      }
    }

    // STEP 6 -- R5: shuffle so the order is never reproducible.
    picked.shuffle(_random);
    return picked;
  }

  /// Builds a REPEAT set for topics the learner has not mastered.
  ///
  /// This is the literal "if not [good at the topic], it will REPEAT the topic
  /// but NOT the same question" branch of panel note 3. The topic stays the
  /// same; the item ids are hard-excluded against the exposure ledger (R3).
  ///
  /// [topics] lets the caller name the topics just failed; when omitted the
  /// weakest topics by BKT p(known) are used.
  Future<List<Question>> buildRemediationSet({
    required String subjectId,
    required Difficulty difficulty,
    int count = 10,
    List<String>? topics,
  }) async {
    await _ensureInit();
    if (count <= 0) return const <Question>[];

    final pool = await _loadPool(subjectId, difficulty);
    if (pool.isEmpty) return const <Question>[];

    final targets = _resolveRemediationTopics(subjectId, pool, topics);
    if (targets.isEmpty) {
      // Nothing is flagged weak -- fall back to a normal set rather than
      // returning an empty quiz.
      return buildQuizSet(
        subjectId: subjectId,
        difficulty: difficulty,
        count: count,
      );
    }

    final inTargets = pool.where((q) => targets.contains(q.topic)).toList();
    debugPrint(
      '[QuestionSelection] remediation for $subjectId/${difficulty.name} '
      'on topics ${targets.join(", ")} -- ${inTargets.length} candidate(s)',
    );

    final picked = <Question>[];
    final takenIds = <String>{};

    // TIER 1 (R3) -- same topic, strictly UNSEEN ids, weakest topic first.
    final unseenInTargets =
        inTargets.where((q) => !_exposure.containsKey(q.id)).toList();
    _drawWeighted(
      subjectId: subjectId,
      candidates: unseenInTargets,
      slots: count,
      into: picked,
      taken: takenIds,
    );
    if (picked.length < count) {
      final leftover =
          unseenInTargets.where((q) => !takenIds.contains(q.id)).toList()
            ..shuffle(_random);
      for (final q in leftover) {
        if (picked.length >= count) break;
        if (takenIds.add(q.id)) picked.add(q);
      }
    }

    // TIER 2 (R2) -- the topic has no unseen items left. Recycle within the
    // SAME topic, least-seen and longest-ago first. Because the item the
    // student just missed has the most recent `lastSeen`, it sorts LAST, which
    // is how "never return the same id if any alternative exists" is honoured.
    if (picked.length < count) {
      final seenInTargets =
          inTargets.where((q) => !takenIds.contains(q.id)).toList();
      if (seenInTargets.isNotEmpty) {
        debugPrint(
          '[QuestionSelection] R2 RECYCLING (remediation) -- no unseen items '
          'left on ${targets.join(", ")}; reusing least-seen items',
        );
        for (final q in _recycleOrder(seenInTargets)) {
          if (picked.length >= count) break;
          if (takenIds.add(q.id)) picked.add(q);
        }
      }
    }

    // TIER 3 -- last resort: the weak topics simply do not have enough items at
    // this difficulty. Widen to the rest of the subject so the student is never
    // handed a short or empty quiz. Logged loudly because it means the bank
    // needs more items on that topic (actionable for the admin, panel note 7).
    if (picked.length < count) {
      final rest = pool.where((q) => !takenIds.contains(q.id)).toList();
      if (rest.isNotEmpty) {
        debugPrint(
          '[QuestionSelection] remediation widened beyond target topics for '
          '$subjectId/${difficulty.name} -- bank is thin on '
          '${targets.join(", ")}',
        );
        final unseenRest =
            rest.where((q) => !_exposure.containsKey(q.id)).toList()
              ..shuffle(_random);
        for (final q in unseenRest) {
          if (picked.length >= count) break;
          if (takenIds.add(q.id)) picked.add(q);
        }
        if (picked.length < count) {
          for (final q in _recycleOrder(rest)) {
            if (picked.length >= count) break;
            if (takenIds.add(q.id)) picked.add(q);
          }
        }
      }
    }

    picked.shuffle(_random); // R5
    return picked;
  }

  // ---------------------------------------------------------------------------
  // Exposure bookkeeping
  // ---------------------------------------------------------------------------

  /// Records that [questions] were served: bumps `timesSeen`, stamps
  /// `lastSeen`, persists locally, and mirrors to Supabase when logged in.
  ///
  /// Call this once per quiz, when the set is handed to the quiz screen. This
  /// is what makes R1 stick across app restarts.
  Future<void> markServed(List<Question> questions) async {
    if (questions.isEmpty) return;
    await _ensureInit();

    final now = DateTime.now();
    for (final q in questions) {
      if (q.id.isEmpty) continue;
      final rec = _exposure.putIfAbsent(
        q.id,
        () => _ExposureRecord(questionId: q.id),
      );
      rec.timesSeen += 1;
      rec.lastSeen = now;
      // Refresh the denormalised metadata every time -- cheap, and it repairs
      // rows hydrated from the cloud without subject/topic.
      if (q.subject.isNotEmpty) rec.subjectId = q.subject;
      if (q.topic.isNotEmpty) rec.topic = q.topic;
      rec.difficulty = q.difficulty.name;
    }

    await _persist();
    unawaited(_mirrorToCloud(questions));
  }

  /// Every question id this learner has already been served in [subjectId].
  ///
  /// Synchronous on purpose: the quiz and results screens read it during build.
  Set<String> seenIds(String subjectId) {
    final out = <String>{};
    for (final rec in _exposure.values) {
      if (rec.subjectId == subjectId) out.add(rec.questionId);
    }
    return out;
  }

  /// How many times [questionId] has been served to this learner; 0 if never.
  int timesSeen(String questionId) => _exposure[questionId]?.timesSeen ?? 0;

  /// Whether any never-before-seen item remains for [subjectId] at [d].
  ///
  /// Lets the UI honestly tell the student "you have exhausted the new
  /// questions for this level" instead of quietly repeating items.
  ///
  /// Optimistic when the pool has not been loaded yet this session: claiming
  /// the bank is exhausted when it is not would be the worse error.
  bool hasUnseenRemaining(String subjectId, Difficulty d) {
    final ids = _poolIds[_poolKey(subjectId, d)];
    if (ids == null || ids.isEmpty) return true;
    for (final id in ids) {
      if (!_exposure.containsKey(id)) return true;
    }
    return false;
  }

  /// Wipes the ledger locally and in the cloud -- every question becomes
  /// unseen again. Used by "reset progress" and by the admin demo flow.
  Future<void> reset() async {
    await _ensureInit();
    _exposure.clear();
    _poolIds.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey);
    } catch (e) {
      debugPrint('[QuestionSelection] local reset failed: $e');
    }
    try {
      final supabase = SupabaseService.instance;
      if (supabase.isLoggedIn) {
        await supabase.client
            .from(_cloudTable)
            .delete()
            .eq('user_id', supabase.userId!);
      }
    } catch (e) {
      debugPrint('[QuestionSelection] cloud reset failed: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Internals -- pool loading
  // ---------------------------------------------------------------------------

  String _poolKey(String subjectId, Difficulty d) => '$subjectId::${d.name}';

  /// Loads the pool from the repository and refreshes the synchronous id cache.
  ///
  /// The repository is the ONLY source of items (Supabase-backed, with an
  /// offline JSON snapshot). Nothing here falls back to code-resident content.
  Future<List<Question>> _loadPool(
    String subjectId,
    Difficulty difficulty,
  ) async {
    List<Question> pool;
    try {
      pool = await QuestionRepository.instance
          .byDifficulty(subjectId, difficulty);
    } catch (e) {
      debugPrint('[QuestionSelection] pool load failed: $e');
      return const <Question>[];
    }

    _poolIds[_poolKey(subjectId, difficulty)] =
        pool.map((q) => q.id).toSet();
    _backfillMetadata(pool);
    return pool;
  }

  /// Fills in subject/topic on ledger rows that arrived from the cloud without
  /// them, now that we have the matching items in hand. Keeps [seenIds] honest
  /// after a fresh install on a second device.
  void _backfillMetadata(List<Question> pool) {
    for (final q in pool) {
      final rec = _exposure[q.id];
      if (rec == null) continue;
      if (rec.subjectId.isEmpty && q.subject.isNotEmpty) {
        rec.subjectId = q.subject;
      }
      if (rec.topic.isEmpty && q.topic.isNotEmpty) rec.topic = q.topic;
      if (rec.difficulty.isEmpty) rec.difficulty = q.difficulty.name;
    }
  }

  // ---------------------------------------------------------------------------
  // Internals -- weighted drawing (R4)
  // ---------------------------------------------------------------------------

  /// Draws up to [slots] items from [candidates], weighted toward the topics
  /// with the lowest BKT p(known).
  ///
  /// Appends to [into] and records ids in [taken] so callers can chain several
  /// draws without duplicating items.
  void _drawWeighted({
    required String subjectId,
    required List<Question> candidates,
    required int slots,
    required List<Question> into,
    required Set<String> taken,
  }) {
    if (candidates.isEmpty || slots <= 0) return;

    // Bucket by topic.
    final byTopic = <String, List<Question>>{};
    for (final q in candidates) {
      byTopic.putIfAbsent(q.topic, () => <Question>[]).add(q);
    }

    // STEP 3 -- rank topics by p(known) ASCENDING: weakest first. This is the
    // Zone-of-Proximal-Development targeting that replaces the old hardcoded
    // accuracy ladder (panel note 4).
    final ranked = byTopic.keys.toList()
      ..sort((a, b) {
        final ma = MasteryService.instance.masteryFor(subjectId, a);
        final mb = MasteryService.instance.masteryFor(subjectId, b);
        final byP = ma.pKnown.compareTo(mb.pKnown);
        if (byP != 0) return byP;
        // Tie-break on evidence: practise the topic we know least about first.
        final byAttempts = ma.attempts.compareTo(mb.attempts);
        if (byAttempts != 0) return byAttempts;
        return a.compareTo(b);
      });

    final quotas = _allocateSlots(
      rankedTopics: ranked,
      available: {
        for (final e in byTopic.entries) e.key: e.value.length,
      },
      slots: math.min(slots, candidates.length),
    );

    if (ranked.isNotEmpty) {
      final weakest = ranked.first;
      debugPrint(
        '[QuestionSelection] R4 weakest topic "$weakest" '
        'p(known)=${MasteryService.instance.masteryFor(subjectId, weakest).pKnown.toStringAsFixed(2)} '
        '-> ${quotas[weakest] ?? 0}/$slots slot(s)',
      );
    }

    for (final topic in ranked) {
      final want = quotas[topic] ?? 0;
      if (want <= 0) continue;
      // R5 -- shuffle WITHIN the bucket so two students on the same topic (and
      // the same student on a retry) never get the same ordering.
      final bucket = List<Question>.from(byTopic[topic]!)..shuffle(_random);
      var drawn = 0;
      for (final q in bucket) {
        if (drawn >= want || into.length >= slots) break;
        if (taken.add(q.id)) {
          into.add(q);
          drawn++;
        }
      }
    }
  }

  /// Splits [slots] across [rankedTopics] (weakest first), never asking a topic
  /// for more items than it actually has.
  ///
  /// The weakest topic takes [weakestTopicShare] of the set; the remainder is
  /// spread round-robin over the other topics, still weakest-first, so the
  /// second- and third-weakest outrank the strong ones. Any slots left over
  /// (because a topic ran out of items) are redistributed over whatever spare
  /// capacity remains.
  Map<String, int> _allocateSlots({
    required List<String> rankedTopics,
    required Map<String, int> available,
    required int slots,
  }) {
    final quota = <String, int>{};
    if (rankedTopics.isEmpty || slots <= 0) return quota;

    final capacity = <String, int>{
      for (final t in rankedTopics) t: available[t] ?? 0,
    };
    var remaining = slots;

    void give(String topic, int n) {
      if (n <= 0) return;
      quota[topic] = (quota[topic] ?? 0) + n;
      capacity[topic] = (capacity[topic] ?? 0) - n;
      remaining -= n;
    }

    // Pass A -- the weakest topic's dedicated share (R4). Skipped when there is
    // only one topic, because the round-robin below gives it everything anyway.
    if (rankedTopics.length > 1) {
      final weakest = rankedTopics.first;
      final want = math.max(1, (slots * weakestTopicShare).round());
      give(weakest, math.min(math.min(want, capacity[weakest] ?? 0), remaining));
    }

    // Pass B -- spread the remainder over the OTHER topics, weakest first.
    if (rankedTopics.length > 1) {
      _roundRobin(rankedTopics.sublist(1), capacity, () => remaining, give);
    }

    // Pass C -- mop up any slots left because a topic ran dry, using every
    // topic (including the weakest) that still has spare items.
    _roundRobin(rankedTopics, capacity, () => remaining, give);

    return quota;
  }

  /// Hands out one slot at a time, in [order], until nothing is left to give.
  void _roundRobin(
    List<String> order,
    Map<String, int> capacity,
    int Function() remaining,
    void Function(String topic, int n) give,
  ) {
    var progressed = true;
    while (remaining() > 0 && progressed) {
      progressed = false;
      for (final topic in order) {
        if (remaining() <= 0) break;
        if ((capacity[topic] ?? 0) <= 0) continue;
        give(topic, 1);
        progressed = true;
      }
    }
  }

  /// R2 ordering: least-seen first, then least-recently-seen.
  ///
  /// The consequence that matters for panel note 3: an item the student saw
  /// seconds ago has the highest `lastSeen`, so it lands at the very end of
  /// this list and is only ever re-served when there is literally no
  /// alternative left in the bank.
  List<Question> _recycleOrder(List<Question> seen) {
    final sorted = List<Question>.from(seen);
    sorted.sort((a, b) {
      final ra = _exposure[a.id];
      final rb = _exposure[b.id];
      final ta = ra?.timesSeen ?? 0;
      final tb = rb?.timesSeen ?? 0;
      if (ta != tb) return ta.compareTo(tb);
      final la = ra?.lastSeen ?? DateTime.fromMillisecondsSinceEpoch(0);
      final lb = rb?.lastSeen ?? DateTime.fromMillisecondsSinceEpoch(0);
      return la.compareTo(lb);
    });
    return sorted;
  }

  /// Which topics a remediation set should target.
  ///
  /// Priority: the topics the caller says were just failed, then the weakest
  /// topics by BKT p(known), then any topic in the pool that is not yet
  /// mastered. Mastered topics are never targeted -- panel note 3's "if the
  /// student is good at that topic, advance".
  Set<String> _resolveRemediationTopics(
    String subjectId,
    List<Question> pool,
    List<String>? requested,
  ) {
    final poolTopics = pool.map((q) => q.topic).toSet();
    final targets = <String>{};

    if (requested != null) {
      for (final t in requested) {
        final topic = t.trim();
        if (topic.isNotEmpty && poolTopics.contains(topic)) targets.add(topic);
      }
    }
    if (targets.isNotEmpty) return targets;

    for (final m in MasteryService.instance.weakTopics(subjectId, limit: 5)) {
      if (poolTopics.contains(m.topic)) targets.add(m.topic);
    }
    if (targets.isNotEmpty) return targets;

    for (final topic in poolTopics) {
      if (!MasteryService.instance.isTopicMastered(subjectId, topic)) {
        targets.add(topic);
      }
    }
    return targets;
  }

  // ---------------------------------------------------------------------------
  // Internals -- persistence
  // ---------------------------------------------------------------------------

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload =
          _exposure.values.map((r) => r.toJson()).toList(growable: false);
      await prefs.setString(_prefsKey, jsonEncode(payload));
    } catch (e) {
      debugPrint('[QuestionSelection] persist failed: $e');
    }
  }

  /// Mirrors the served items to `public.question_exposure`.
  ///
  /// Best-effort by design: the local ledger is authoritative for this device,
  /// so a failed upsert costs cross-device continuity, never a working quiz.
  Future<void> _mirrorToCloud(List<Question> questions) async {
    try {
      final supabase = SupabaseService.instance;
      if (!supabase.isLoggedIn) return;
      final userId = supabase.userId;
      if (userId == null) return;

      final rows = <Map<String, dynamic>>[];
      for (final q in questions) {
        final rec = _exposure[q.id];
        if (rec == null) continue;
        rows.add({
          'user_id': userId,
          'question_id': q.id,
          'times_seen': rec.timesSeen,
          'last_seen': rec.lastSeen.toUtc().toIso8601String(),
        });
      }
      if (rows.isEmpty) return;

      await supabase.client
          .from(_cloudTable)
          .upsert(rows, onConflict: 'user_id,question_id');
    } catch (e) {
      debugPrint('[QuestionSelection] cloud mirror failed (kept locally): $e');
    }
  }

  /// Pulls the learner's exposure rows from Supabase and merges them in.
  ///
  /// Merge policy: highest `times_seen` and latest `last_seen` win, so syncing
  /// can only ever make the service MORE conservative about repeating an item.
  Future<void> _hydrateFromCloud() async {
    try {
      final supabase = SupabaseService.instance;
      if (!supabase.isLoggedIn) return;
      final userId = supabase.userId;
      if (userId == null) return;

      final rows = await supabase.client
          .from(_cloudTable)
          .select('question_id, times_seen, last_seen')
          .eq('user_id', userId);

      var merged = 0;
      for (final row in List<Map<String, dynamic>>.from(rows)) {
        final id = (row['question_id'] ?? '').toString();
        if (id.isEmpty) continue;
        final cloudSeen = _ExposureRecord._asInt(row['times_seen'], 1);
        final cloudAt = _ExposureRecord._asDate(row['last_seen']);

        final local = _exposure[id];
        if (local == null) {
          _exposure[id] = _ExposureRecord(
            questionId: id,
            timesSeen: cloudSeen,
            lastSeen: cloudAt,
          );
          merged++;
        } else {
          if (cloudSeen > local.timesSeen) local.timesSeen = cloudSeen;
          if (cloudAt.isAfter(local.lastSeen)) local.lastSeen = cloudAt;
        }
      }

      if (merged > 0) {
        debugPrint(
          '[QuestionSelection] hydrated $merged exposure row(s) from cloud',
        );
        await _persist();
      }
    } catch (e) {
      debugPrint('[QuestionSelection] cloud hydrate skipped: $e');
    }
  }
}
