import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/question.dart';
import 'supabase_service.dart';

/// THE single source of every question in CrimiReview.
///
/// Panel note 7 -- "Do NOT put your questions in your code. It should have an
/// ADMIN to add questions, or you automate everything." -- is answered *here*:
/// this file contains ZERO question content. Items come from
/// `public.questions` in Supabase (authored through the admin UI, or produced
/// by Automatic Item Generation), and from nowhere else.
///
/// Reading path:
///
/// ```text
///   Supabase public.questions (is_active = true)   <-- source of truth
///        |  paged .range() fetch, all rows
///        v
///   in-memory list + id/subject indexes           <-- memoised, short TTL
///        |  jsonEncode
///        v
///   SharedPreferences 'question_cache_v2'          <-- offline resilience
/// ```
///
/// Offline behaviour is deliberate and total: a network failure NEVER throws
/// out of this class. If the device is offline the last good snapshot is
/// served; if there is no snapshot the repository returns an empty list and
/// [hasCachedQuestions] is false, which is the UI's cue to show a
/// "no questions downloaded yet" empty state. There is no hardcoded fallback
/// because there is no hardcoded content anywhere in the app.
///
/// It is a [ChangeNotifier] so screens can rebuild when a background refresh
/// lands new or edited content.
class QuestionRepository extends ChangeNotifier {
  QuestionRepository._();

  static QuestionRepository? _instance;
  static QuestionRepository get instance =>
      _instance ??= QuestionRepository._();

  // ---------------------------------------------------------------------------
  // Constants
  // ---------------------------------------------------------------------------

  /// Supabase table that holds every item.
  static const String tableName = 'questions';

  /// SharedPreferences key holding the JSON snapshot of the whole bank.
  static const String cacheKey = 'question_cache_v2';

  /// SharedPreferences key holding the ISO-8601 time that snapshot was taken.
  static const String cacheTimestampKey = 'question_cache_v2_at';

  /// PostgREST caps a single `select` at 1000 rows, so the fetch pages with
  /// `.range()` until a short page comes back. The seeded bank is several
  /// hundred to a few thousand rows and ALL of it must load.
  static const int pageSize = 1000;

  /// Hard stop so a misbehaving server can never spin the pager forever.
  static const int _maxRows = 100000;

  static const Duration _requestTimeout = Duration(seconds: 20);

  /// How long the in-memory set is trusted before a *background* refresh is
  /// scheduled. Reads keep being served instantly from memory the whole time;
  /// this only decides when to go looking for newer content. It is what stops
  /// a 40-question quiz build from touching the disk or the network 40 times.
  static const Duration memoTtl = Duration(minutes: 10);

  /// Floor between two network attempts, so an offline device retries at a
  /// sane rate instead of once per question lookup.
  static const Duration _minRefreshGap = Duration(seconds: 30);

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------

  List<Question> _questions = const <Question>[];
  Map<String, Question> _byId = const <String, Question>{};
  Map<String, List<Question>> _bySubject = const <String, List<Question>>{};
  String _signature = '0:0';

  DateTime? _lastSyncedAt;
  DateTime? _lastAttemptAt;
  bool _staleOverride = false;

  bool _cacheLoaded = false;
  Future<void>? _cacheLoadFuture;
  Future<void>? _refreshFuture;
  Object? _lastError;

  // ---------------------------------------------------------------------------
  // Public state accessors
  // ---------------------------------------------------------------------------

  /// True when there is content to serve right now (from the offline snapshot
  /// or a completed fetch). False means the UI must show an empty state --
  /// there is no hardcoded bank to fall back to.
  bool get hasCachedQuestions => _questions.isNotEmpty;

  /// When the bank was last successfully pulled from Supabase. Survives
  /// restarts (it is restored from [cacheTimestampKey]).
  DateTime? get lastSyncedAt => _lastSyncedAt;

  /// Last network/parse failure, for the admin diagnostics panel. Never thrown.
  Object? get lastError => _lastError;

  /// True when a network refresh is in flight.
  bool get isRefreshing => _refreshFuture != null;

  /// Synchronous view of the memoised bank (empty before the first load).
  /// Prefer the async queries; this exists for widgets that cannot await.
  List<Question> get cachedQuestions => List<Question>.of(_questions);

  /// Synchronous id lookup against the memoised bank.
  Question? questionById(String id) => _byId[id];

  bool get _isStale {
    if (_staleOverride) return true;
    final at = _lastSyncedAt;
    if (at == null) return true;
    return DateTime.now().difference(at) > memoTtl;
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Loads the offline snapshot (fast, local) and then refreshes from Supabase
  /// in the BACKGROUND. Call it once during app start-up: it never blocks on
  /// the network, so a cold start on a dead connection is still instant.
  Future<void> init() async {
    await _ensureCacheLoaded();
    unawaited(refreshFromCloud());
  }

  /// Forces a fetch from `public.questions`, then rewrites the offline
  /// snapshot. Safe to call from anywhere: concurrent calls share one request,
  /// and failures are swallowed (the previous snapshot keeps serving).
  Future<void> refreshFromCloud({bool force = false}) {
    final inFlight = _refreshFuture;
    if (inFlight != null) return inFlight;

    if (!SupabaseService.isInitialized) return Future<void>.value();

    if (!force) {
      final last = _lastAttemptAt;
      if (last != null && DateTime.now().difference(last) < _minRefreshGap) {
        return Future<void>.value();
      }
    }

    final future = _runRefresh();
    _refreshFuture = future;
    return future.whenComplete(() {
      if (identical(_refreshFuture, future)) _refreshFuture = null;
    });
  }

  /// Marks the memoised bank stale and kicks a refresh. Call after an admin
  /// creates/edits/deletes an item so students see the change on next read.
  /// The current content keeps serving until the new content lands, so the UI
  /// never blanks.
  void invalidate() {
    _staleOverride = true;
    _lastAttemptAt = null;
    unawaited(refreshFromCloud(force: true));
  }

  /// Drops the in-memory bank AND the on-disk snapshot. Only for
  /// sign-out/reset flows; normal refreshes should use [invalidate].
  Future<void> clearCache() async {
    _questions = const <Question>[];
    _byId = const <String, Question>{};
    _bySubject = const <String, List<Question>>{};
    _signature = '0:0';
    _lastSyncedAt = null;
    _lastAttemptAt = null;
    _staleOverride = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(cacheKey);
      await prefs.remove(cacheTimestampKey);
    } catch (_) {
      // A cache we cannot clear is not worth crashing over.
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Queries
  // ---------------------------------------------------------------------------

  /// Every active question.
  ///
  /// * With content in memory: returns immediately, scheduling a background
  ///   refresh when the memo has gone stale.
  /// * With nothing in memory: waits for the first fetch, because there is
  ///   nothing useful to return otherwise.
  /// * Offline with no snapshot: returns `[]`.
  ///
  /// The returned list is a fresh growable copy, so callers may `shuffle()` or
  /// `sort()` it without corrupting the repository's indexes.
  Future<List<Question>> all({bool forceRefresh = false}) async {
    await _ensureCacheLoaded();

    if (forceRefresh) {
      await refreshFromCloud(force: true);
      return List<Question>.of(_questions);
    }

    if (_questions.isEmpty) {
      // Nothing to serve -- a blocking fetch is the only useful behaviour.
      await refreshFromCloud();
    } else if (_isStale) {
      unawaited(refreshFromCloud());
    }

    return List<Question>.of(_questions);
  }

  /// All active questions for a subject id, e.g. `criminal_jurisprudence`.
  Future<List<Question>> bySubject(String subjectId) async {
    await all();
    return List<Question>.of(_bySubject[_key(subjectId)] ?? const <Question>[]);
  }

  /// All active questions for one topic inside a subject. Topic matching is
  /// case/whitespace tolerant because topics are hand-typed by admins and are
  /// the key of the Bayesian mastery model.
  Future<List<Question>> byTopic(String subjectId, String topic) async {
    final pool = await bySubject(subjectId);
    final wanted = _key(topic);
    return pool.where((q) => _key(q.topic) == wanted).toList();
  }

  /// All active questions for a subject at one difficulty tier.
  Future<List<Question>> byDifficulty(String subjectId, Difficulty d) async {
    final pool = await bySubject(subjectId);
    return pool.where((q) => q.difficulty == d).toList();
  }

  /// Resolves ids to questions, preserving the order asked for and silently
  /// dropping ids that no longer exist (an item can be soft-deleted after a
  /// student's exposure log recorded it).
  Future<List<Question>> byIds(List<String> ids) async {
    await all();
    final out = <Question>[];
    final seen = <String>{};
    for (final id in ids) {
      if (!seen.add(id)) continue;
      final q = _byId[id];
      if (q != null) out.add(q);
    }
    return out;
  }

  /// Distinct topics inside a subject, alphabetically. Drives the mastery
  /// breakdown and the remediation picker.
  Future<List<String>> topicsFor(String subjectId) async {
    final pool = await bySubject(subjectId);
    final set = <String, String>{};
    for (final q in pool) {
      final t = q.topic.trim();
      if (t.isEmpty) continue;
      set.putIfAbsent(_key(t), () => t);
    }
    final out = set.values.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return out;
  }

  /// Distinct subject ids that actually have content.
  Future<List<String>> subjects() async {
    await all();
    final out = <String>[];
    for (final q in _questions) {
      final s = q.subject.trim();
      if (s.isNotEmpty && !out.contains(s)) out.add(s);
    }
    out.sort();
    return out;
  }

  /// `{subjectId: activeQuestionCount}` -- used by the subject cards and the
  /// admin dashboard.
  Future<Map<String, int>> countBySubject() async {
    await all();
    final counts = <String, int>{};
    for (final q in _questions) {
      counts[q.subject] = (counts[q.subject] ?? 0) + 1;
    }
    return counts;
  }

  /// Total number of active questions available to the learner.
  Future<int> total() async {
    await all();
    return _questions.length;
  }

  /// Counts by difficulty within a subject, for the difficulty sheet.
  Future<Map<Difficulty, int>> countByDifficulty(String subjectId) async {
    final pool = await bySubject(subjectId);
    final counts = <Difficulty, int>{
      for (final d in Difficulty.values) d: 0,
    };
    for (final q in pool) {
      counts[q.difficulty] = (counts[q.difficulty] ?? 0) + 1;
    }
    return counts;
  }

  // ---------------------------------------------------------------------------
  // Diagnostics
  // ---------------------------------------------------------------------------

  /// Synchronous snapshot of what the repository currently holds: totals by
  /// subject, difficulty and provenance, plus sync health.
  ///
  /// `bySource` is the panel-facing number -- it proves how many items were
  /// admin-authored versus auto-generated, and that none are compiled in.
  /// Call `await all()` first if you need the counts to be populated.
  Map<String, dynamic> debugDescribe() {
    final bySubject = <String, int>{};
    final byDifficulty = <String, int>{};
    final bySource = <String, int>{};
    final topics = <String>{};
    var withRationales = 0;

    for (final q in _questions) {
      bySubject[q.subject] = (bySubject[q.subject] ?? 0) + 1;
      byDifficulty[q.difficulty.name] =
          (byDifficulty[q.difficulty.name] ?? 0) + 1;
      bySource[q.source.name] = (bySource[q.source.name] ?? 0) + 1;
      if (q.topic.trim().isNotEmpty) topics.add('${q.subject}::${_key(q.topic)}');
      if (q.hasRationales) withRationales++;
    }

    return <String, dynamic>{
      'total': _questions.length,
      'subjects': bySubject.length,
      'topics': topics.length,
      'bySubject': bySubject,
      'byDifficulty': byDifficulty,
      'bySource': bySource,
      'withRationales': withRationales,
      'hasCachedQuestions': hasCachedQuestions,
      'lastSyncedAt': _lastSyncedAt?.toIso8601String(),
      'isStale': _isStale,
      'isRefreshing': isRefreshing,
      'supabaseInitialized': SupabaseService.isInitialized,
      'source': 'supabase:public.$tableName',
      'lastError': _lastError?.toString(),
    };
  }

  // ---------------------------------------------------------------------------
  // Offline snapshot
  // ---------------------------------------------------------------------------

  Future<void> _ensureCacheLoaded() {
    if (_cacheLoaded) return Future<void>.value();
    return _cacheLoadFuture ??= _loadCache();
  }

  Future<void> _loadCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final at = prefs.getString(cacheTimestampKey);
      if (at != null && at.isNotEmpty) {
        _lastSyncedAt = DateTime.tryParse(at);
      }

      final raw = prefs.getString(cacheKey);
      if (raw == null || raw.isEmpty) return;

      final decoded = jsonDecode(raw);
      if (decoded is! List) return;

      final parsed = <Question>[];
      for (final entry in decoded) {
        if (entry is! Map) continue;
        final q = Question.fromJson(
          entry.map((k, v) => MapEntry(k.toString(), v)),
        );
        if (_isUsable(q)) parsed.add(q);
      }
      if (parsed.isNotEmpty) _adopt(parsed);
    } catch (e) {
      // A corrupt snapshot must behave exactly like "no snapshot", never like
      // a crash on launch.
      _lastError = e;
    } finally {
      _cacheLoaded = true;
      _cacheLoadFuture = null;
    }
  }

  Future<void> _persist(List<Question> qs, DateTime at) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(
        qs.map((q) => q.toJson()).toList(growable: false),
      );
      await prefs.setString(cacheKey, encoded);
      await prefs.setString(cacheTimestampKey, at.toIso8601String());
    } catch (e) {
      // Out of disk / platform channel hiccup: we still have the data in
      // memory for this session.
      _lastError = e;
    }
  }

  // ---------------------------------------------------------------------------
  // Network
  // ---------------------------------------------------------------------------

  Future<void> _runRefresh() async {
    _lastAttemptAt = DateTime.now();
    try {
      final fetched = await _fetchAllPages();

      if (fetched.isEmpty && _questions.isNotEmpty) {
        // An empty response while we hold a healthy snapshot is far more
        // likely to be an RLS/policy problem than a genuinely empty bank, so
        // do NOT wipe the student's offline content over it.
        _lastError = StateError(
          'public.$tableName returned 0 active rows; kept the existing '
          '${_questions.length}-item offline snapshot.',
        );
        _staleOverride = false;
        return;
      }

      _lastError = null;
      final now = DateTime.now();
      final changed = _adopt(fetched);
      _lastSyncedAt = now;
      _staleOverride = false;

      await _persist(fetched, now);
      if (changed) notifyListeners();
    } catch (e) {
      // Offline, timeout, bad row, missing table -- keep serving whatever we
      // already have. A network failure must never break a quiz.
      _lastError = e;
    }
  }

  /// Pages through `public.questions` until a short page comes back.
  ///
  /// Ordered by the primary key so `.range()` windows cannot overlap or skip
  /// rows between requests.
  Future<List<Question>> _fetchAllPages() async {
    final client = SupabaseService.instance.client;
    final out = <Question>[];
    final seen = <String>{};

    var from = 0;
    while (from < _maxRows) {
      final rows = await client
          .from(tableName)
          .select()
          .eq('is_active', true)
          .order('id', ascending: true)
          .range(from, from + pageSize - 1)
          .timeout(_requestTimeout);

      if (rows.isEmpty) break;

      for (final row in rows) {
        final q = Question.fromJson(Map<String, dynamic>.from(row));
        if (!_isUsable(q)) continue;
        if (!seen.add(q.id)) continue;
        out.add(q);
      }

      if (rows.length < pageSize) break;
      from += pageSize;
    }

    return out;
  }

  // ---------------------------------------------------------------------------
  // Indexing
  // ---------------------------------------------------------------------------

  /// Installs [incoming] as the live bank, rebuilds the lookup indexes and
  /// reports whether the content actually changed (so we only notify and only
  /// rewrite the snapshot when it did).
  bool _adopt(List<Question> incoming) {
    final signature = _computeSignature(incoming);
    final changed = signature != _signature;

    final byId = <String, Question>{};
    final bySubject = <String, List<Question>>{};
    for (final q in incoming) {
      byId[q.id] = q;
      (bySubject[_key(q.subject)] ??= <Question>[]).add(q);
    }

    _questions = List<Question>.unmodifiable(incoming);
    _byId = Map<String, Question>.unmodifiable(byId);
    _bySubject = Map<String, List<Question>>.unmodifiable(bySubject);
    _signature = signature;
    return changed;
  }

  /// Cheap content fingerprint: id, version, stem and option count of every
  /// item. Catches admin edits and version bumps without deep-comparing a few
  /// thousand objects.
  static String _computeSignature(List<Question> qs) {
    var h = qs.length;
    for (final q in qs) {
      h = 0x1fffffff & (h * 31 + q.id.hashCode);
      h = 0x1fffffff & (h * 31 + q.version);
      h = 0x1fffffff & (h * 31 + q.questionText.hashCode);
      h = 0x1fffffff & (h * 31 + q.answerOptions.length);
    }
    return '${qs.length}:$h';
  }

  /// An item is only usable if it has an id, a stem and at least two choices.
  /// The DB trigger enforces this too; this is the client-side belt so one bad
  /// row can never render a broken quiz screen.
  static bool _isUsable(Question q) =>
      q.id.isNotEmpty &&
      q.questionText.trim().isNotEmpty &&
      q.answerOptions.length >= 2;

  static String _key(String value) => value.trim().toLowerCase();
}
