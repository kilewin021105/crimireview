import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/question.dart';
import '../models/student_record.dart';
import 'question_repository.dart';
import 'supabase_service.dart';

/// Everything the admin panel needs, talking straight to the tables and
/// policies defined in `supabase_schema_v2.sql`.
///
/// Panel note 7: *"Do NOT put your questions in your code. It should have an
/// ADMIN to add questions."* This is that admin surface's backend. It never
/// duplicates access rules -- every read/write is simply the query a normal
/// authenticated user would run, and Postgres Row Level Security (the
/// `is_admin()` policies in the schema) is what actually decides whether it
/// succeeds. A non-admin calling any method here just gets a Postgrest
/// permission error back, exactly as if they had opened the SQL editor
/// themselves. That is deliberate: the UI hides these screens from students,
/// but the *security* boundary lives in the database, not in this class.
///
/// [isAdmin] is resolved by calling the same `public.is_admin()` SQL function
/// the RLS policies use (via RPC), so the app's idea of "is this user an
/// admin" can never drift from the database's.
class AdminService extends ChangeNotifier {
  AdminService._();

  /// For tests only: lets a subclass return sample data (the screenshot
  /// tests render the admin screens without a database).
  @visibleForTesting
  AdminService.forTesting();

  static AdminService _instance = AdminService._();
  static AdminService get instance => _instance;

  @visibleForTesting
  static set debugInstance(AdminService value) => _instance = value;

  static const String _questionsTable = 'questions';
  static const String _overviewView = 'student_progress_overview';
  static const String _auditTable = 'admin_audit_log';

  bool _isAdmin = false;
  bool _roleChecked = false;
  StreamSubscription<AuthState>? _authSub;
  Object? _lastError;

  /// The role check started at app start-up, still running or finished.
  Future<bool>? _startupCheck;

  /// Last role the server confirmed, with the account it belongs to.
  static const String _roleCacheKey = 'admin_role_cache_v1';

  /// True once a role check has completed at least once (including a failed
  /// one). Lets the UI distinguish "still loading" from "confirmed student".
  bool get isReady => _roleChecked;

  /// True when the signed-in user has `role = 'admin'` in `user_profiles`.
  bool get isAdmin => _isAdmin;

  Object? get lastError => _lastError;

  /// Call once at app start-up (after [SupabaseService.initialize]). Starts
  /// from the role last confirmed for this account on this phone, checks the
  /// server in the background, and then keeps it in sync with sign-in/out.
  ///
  /// It no longer waits for the server: on Wi-Fi with no internet that wait
  /// could hold the app on a blank screen for up to 25 seconds. The splash
  /// screen asks [resolvedRole], which waits a few seconds at most.
  Future<void> init() async {
    if (!SupabaseService.isInitialized) return;
    final cached = await _cachedRoleFor(SupabaseService.instance.userId);
    if (cached != null) _setAdmin(cached);
    _startupCheck = refreshRole();
    _authSub ??= SupabaseService.instance.authStateChanges.listen((_) {
      unawaited(refreshRole());
    });
  }

  /// The role to route by at start-up: the server's answer if it arrives
  /// within [wait], otherwise the last confirmed one (offline).
  Future<bool> resolvedRole({Duration wait = const Duration(seconds: 3)}) async {
    final check = _startupCheck;
    if (check == null) return isAdmin;
    try {
      return await check.timeout(wait);
    } on TimeoutException {
      return isAdmin;
    }
  }

  /// Re-resolves [isAdmin] against the database. Call after sign-in/sign-out
  /// and after promoting/demoting a user, so a stale cached role can never
  /// hide or wrongly expose the admin screens.
  ///
  /// When the server can't be reached (offline), the role last confirmed
  /// for this same account is used, so an admin opening the app offline
  /// still gets the admin panel instead of the student screens. This only
  /// chooses which screens open: every admin action is still checked by the
  /// database itself (`is_admin()` in its row-level security), so a wrong
  /// value on the phone can't unlock anything.
  Future<bool> refreshRole() async {
    if (!SupabaseService.isInitialized || !SupabaseService.instance.isLoggedIn) {
      _roleChecked = true;
      _setAdmin(false);
      return false;
    }
    final userId = SupabaseService.instance.userId;
    try {
      final result = await SupabaseService.instance.client.rpc('is_admin');
      _lastError = null;
      _roleChecked = true;
      _setAdmin(result == true);
      await _saveRole(userId, _isAdmin);
      return _isAdmin;
    } catch (e) {
      debugPrint('AdminService.refreshRole failed: $e');
      _lastError = e;
      _roleChecked = true;
      _setAdmin(await _cachedRoleFor(userId) ?? false);
      return _isAdmin;
    }
  }

  Future<bool?> _cachedRoleFor(String? userId) async {
    if (userId == null) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_roleCacheKey);
      if (raw == null) return null;
      final saved = jsonDecode(raw) as Map<String, dynamic>;
      // Another account's role never applies to this one.
      if (saved['userId'] != userId) return null;
      return saved['isAdmin'] == true;
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveRole(String? userId, bool isAdmin) async {
    if (userId == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_roleCacheKey, jsonEncode({'userId': userId, 'isAdmin': isAdmin}));
    } catch (e) {
      debugPrint('AdminService role cache not saved: $e');
    }
  }

  void _setAdmin(bool value) {
    if (_isAdmin == value) {
      notifyListeners(); // still notify: _roleChecked may have just flipped.
      return;
    }
    _isAdmin = value;
    notifyListeners();
  }

  SupabaseClient get _client => SupabaseService.instance.client;

  // ---------------------------------------------------------------------------
  // Question bank -- CRUD
  // ---------------------------------------------------------------------------

  /// Lists questions for the editor, newest-edited first.
  ///
  /// [subjectId] / [difficulty] narrow the result; [includeInactive] also
  /// returns soft-deleted rows (visible to admins only, per RLS); [search]
  /// matches against the question stem. Returns [AdminQuestionEntry] rather
  /// than a bare [Question] because [Question] itself carries no `is_active`
  /// field (students only ever see active rows) -- the admin list screen
  /// needs that flag to know whether "toggle" means deactivate or restore.
  ///
  /// [source] / [templateId] narrow the list by how a question was made and
  /// by the template that made it (the TOS question bank uses template
  /// `tos_2024`, PDF uploads use the upload id).
  ///
  /// [tosCode] keeps questions linked to that TOS topic or competency (a topic
  /// code such as `CLJ-3` also matches its competencies `CLJ-3.1`, `CLJ-3.2`
  /// ...). [tosLink] keeps only linked or only unlinked questions.
  Future<List<AdminQuestionEntry>> listQuestions({
    String? subjectId,
    Difficulty? difficulty,
    bool includeInactive = true,
    bool onlyInactive = false,
    String? search,
    QuestionSource? source,
    String? templateId,
    String? tosCode,
    TosLinkFilter tosLink = TosLinkFilter.any,
    int limit = 50,
    int offset = 0,
  }) async {
    dynamic query = _client.from(_questionsTable).select();

    if (subjectId != null && subjectId.isNotEmpty) {
      query = query.eq('subject_id', subjectId);
    }
    if (difficulty != null) {
      query = query.eq('difficulty', difficulty.name);
    }
    if (onlyInactive) {
      query = query.eq('is_active', false);
    } else if (!includeInactive) {
      query = query.eq('is_active', true);
    }
    if (source != null) {
      query = query.eq('source', source.name);
    }
    if (templateId != null && templateId.isNotEmpty) {
      query = query.eq('template_id', templateId);
    }
    if (tosCode != null && tosCode.isNotEmpty) {
      query = tosCode.contains('.')
          ? query.eq('tos_code', tosCode)
          : query.or('tos_code.eq.$tosCode,tos_code.like.$tosCode.*');
    }
    switch (tosLink) {
      case TosLinkFilter.linked:
        query = query.not('tos_code', 'is', null);
      case TosLinkFilter.unlinked:
        query = query.isFilter('tos_code', null);
      case TosLinkFilter.any:
        break;
    }
    // Commas, brackets, quotes and wildcards are part of PostgREST's filter
    // syntax; typed into the search box they broke the query ("Could not
    // load questions"). Treat them as spaces.
    final term = (search ?? '').replaceAll(RegExp(r'[,()"*%\\]'), ' ').trim();
    if (term.isNotEmpty) {
      query = query.or('question_text.ilike.%$term%,topic.ilike.%$term%');
    }

    final rows = await query
        .order('updated_at', ascending: false)
        .range(offset, offset + limit - 1);

    return List<Map<String, dynamic>>.from(rows)
        .map((row) => AdminQuestionEntry(
              question: Question.fromJson(row),
              isActive: row['is_active'] != false,
              updatedAt: DateTime.tryParse((row['updated_at'] ?? '').toString()),
            ))
        .toList();
  }

  /// Inserts a brand-new item. `id` must be unique; the DB trigger derives
  /// `correct_answer_index` from the options' `is_correct` flags.
  Future<void> createQuestion(Question question) async {
    await _client.from(_questionsTable).insert(question.toSupabaseRow());
    unawaited(_logAction(
      'create',
      targetId: question.id,
      details: {'subject_id': question.subject, 'topic': question.topic},
    ));
    QuestionRepository.instance.invalidate();
  }

  /// Updates an existing item and bumps [Question.version] so every cached
  /// copy on a student's device knows to refresh.
  ///
  /// A question without a TOS code leaves the stored link alone (so this still
  /// works before supabase_tos_alignment.sql); pass [clearTosLink] when the
  /// editor removed the link on purpose.
  Future<void> updateQuestion(Question question, {bool clearTosLink = false}) async {
    final row = question.toSupabaseRow()..['version'] = question.version + 1;
    if (clearTosLink && question.tosCode == null) {
      row['tos_code'] = null;
      row['bloom_level'] = null;
    }
    await _client.from(_questionsTable).update(row).eq('id', question.id);
    unawaited(_logAction(
      'update',
      targetId: question.id,
      details: {'subject_id': question.subject, 'topic': question.topic},
    ));
    QuestionRepository.instance.invalidate();
  }

  /// Soft delete / restore. Inactive items stop being served to students
  /// (`QuestionRepository` only reads `is_active = true`) but stay in the
  /// table, so `question_attempts` history referencing them stays valid.
  Future<void> setActive(String questionId, bool active) async {
    await _client
        .from(_questionsTable)
        .update({'is_active': active}).eq('id', questionId);
    unawaited(_logAction(active ? 'restore' : 'delete', targetId: questionId));
    QuestionRepository.instance.invalidate();
  }

  /// Approves (or withdraws) several questions at once, such as all the
  /// reviewed drafts of one TOS competency. Returns how many were changed.
  Future<int> setActiveMany(List<String> questionIds, bool active) async {
    if (questionIds.isEmpty) return 0;
    final rows = await _client
        .from(_questionsTable)
        .update({'is_active': active})
        .inFilter('id', questionIds)
        .select('id');
    final changed = (rows as List).length;
    unawaited(_logAction(
      active ? 'approve' : 'delete',
      targetId: questionIds.length == 1 ? questionIds.first : null,
      details: {'count': changed, 'ids': questionIds.take(50).toList()},
    ));
    QuestionRepository.instance.invalidate();
    return changed;
  }

  /// How many questions each TOS topic and competency has, against the
  /// number of items the TOS gives it. Read through `admin_tos_coverage()`
  /// (supabase_tos_alignment.sql), which checks `is_admin()` itself.
  Future<List<TosCoverageRow>> tosCoverage() async {
    try {
      final rows = await _client.rpc('admin_tos_coverage');
      return List<Map<String, dynamic>>.from(rows as List)
          .map(TosCoverageRow.fromJson)
          .toList();
    } on PostgrestException catch (e) {
      throw Exception(tosCoverageErrorMessage(e.code));
    }
  }

  @visibleForTesting
  static String tosCoverageErrorMessage(String? code) {
    if (code == 'PGRST202' || code == '42883') {
      return 'This screen needs supabase_tos_alignment.sql. '
          'Run it in the Supabase SQL Editor, then try again.';
    }
    if (code == '42501') return 'Only faculty accounts can view TOS coverage.';
    return 'The database could not count the TOS coverage (error ${code ?? 'unknown'}).';
  }

  /// Hard delete. Only for genuine mistakes (e.g. a duplicate just created);
  /// prefer [setActive] otherwise, since `question_attempts` rows do not
  /// foreign-key to this table and would otherwise silently orphan.
  Future<void> deleteQuestionPermanently(String questionId) async {
    await _client.from(_questionsTable).delete().eq('id', questionId);
    unawaited(_logAction(
      'delete',
      targetId: questionId,
      details: {'permanent': true},
    ));
    QuestionRepository.instance.invalidate();
  }

  /// `{subjectId: {'total', 'active', 'admin', 'generated', 'imported'}}` plus
  /// a `'_overall'` entry -- the numbers the dashboard renders as tiles.
  Future<Map<String, dynamic>> questionStats() async {
    final rows = await _client
        .from(_questionsTable)
        .select('subject_id, difficulty, source, is_active');

    final bySubject = <String, Map<String, int>>{};
    var total = 0, active = 0, admin = 0, generated = 0, imported = 0;
    final byDifficulty = <String, int>{'easy': 0, 'medium': 0, 'hard': 0};

    for (final row in List<Map<String, dynamic>>.from(rows)) {
      final subjectId = (row['subject_id'] ?? '').toString();
      final isActive = row['is_active'] == true;
      final source = (row['source'] ?? 'admin').toString();
      final difficulty = (row['difficulty'] ?? 'medium').toString();

      total++;
      if (isActive) active++;
      if (source == 'admin') admin++;
      if (source == 'generated') generated++;
      if (source == 'imported') imported++;
      byDifficulty[difficulty] = (byDifficulty[difficulty] ?? 0) + 1;

      final bucket = bySubject.putIfAbsent(
        subjectId,
        () => {'total': 0, 'active': 0},
      );
      bucket['total'] = (bucket['total'] ?? 0) + 1;
      if (isActive) bucket['active'] = (bucket['active'] ?? 0) + 1;
    }

    return <String, dynamic>{
      'total': total,
      'active': active,
      'inactive': total - active,
      'admin': admin,
      'generated': generated,
      'imported': imported,
      'byDifficulty': byDifficulty,
      'bySubject': bySubject,
    };
  }

  // ---------------------------------------------------------------------------
  // Student monitoring (panel note 2)
  // ---------------------------------------------------------------------------

  /// Reads `public.student_progress_overview` -- one row per student with
  /// their BKT rollup (mastered/remediation topic counts, mean p(known),
  /// totals). The view itself already filters to admins only; a non-admin
  /// calling this simply gets an empty list back.
  Future<List<Map<String, dynamic>>> studentProgressOverview({
    String? search,
  }) async {
    final rows = await _client
        .from(_overviewView)
        .select()
        .order('total_points', ascending: false);

    var list = List<Map<String, dynamic>>.from(rows);
    final term = search?.trim().toLowerCase() ?? '';
    if (term.isNotEmpty) {
      list = list.where((row) {
        final name = (row['display_name'] ?? '').toString().toLowerCase();
        final email = (row['email'] ?? '').toString().toLowerCase();
        return name.contains(term) || email.contains(term);
      }).toList();
    }
    return list;
  }

  /// One student's full record for the Students screen's detail page: level
  /// reached and segments per subject, topic mastery, and recent quizzes.
  ///
  /// Read through `admin_student_record` (supabase_student_record.sql), a
  /// read-only function that checks `is_admin()` itself. The tables keep
  /// their own-rows-only rules for everyone else. Throws with a plain message
  /// when the database refuses.
  ///
  /// A database error is reported as such, with what to do, instead of the
  /// generic "please try again": retrying cannot fix a missing or outdated
  /// function. Connection problems are rethrown unchanged, so the screen
  /// still says "No internet" for those.
  Future<StudentRecord> studentRecord(String userId) async {
    dynamic result;
    try {
      result = await _client.rpc('admin_student_record', params: {
        'p_user_id': userId,
      });
    } on PostgrestException catch (e) {
      throw Exception(studentRecordErrorMessage(e.code));
    }
    final map = result is Map
        ? result.map((k, v) => MapEntry(k.toString(), v))
        : const <String, dynamic>{};
    if (map['success'] != true) {
      throw Exception((map['error'] ?? "Couldn't load this student's record.").toString());
    }
    return StudentRecord.fromJson(map);
  }

  /// What to tell an admin when the database itself fails to build a
  /// student record. [code] is the PostgREST / Postgres error code.
  @visibleForTesting
  static String studentRecordErrorMessage(String? code) {
    if (code == 'PGRST202') {
      return 'This screen needs supabase_student_record.sql. '
          'Run it in the Supabase SQL Editor, then try again.';
    }
    return 'The database could not build this record (error ${code ?? 'unknown'}). '
        'Run the latest supabase_student_record.sql in the Supabase SQL Editor, then try again.';
  }

  /// Promotes or demotes a user by email. This is the same operation the
  /// SQL Editor's `UPDATE user_profiles SET role = ...` does -- exposed as
  /// an RPC (`admin_set_user_role`, see supabase_admin_management.sql) so an
  /// admin can grant/revoke access to other admins from inside the app
  /// instead of needing direct database access every time.
  ///
  /// The security boundary is unchanged and enforced twice, independently,
  /// on the database side: the RPC itself checks `is_admin()`, and the
  /// `protect_user_role` trigger (supabase_schema_v2.sql) silently reverts
  /// any role change attempted by a caller who is not already an admin --
  /// even if this method were called directly without going through the UI.
  Future<Map<String, dynamic>> setUserRole(String email, String role) async {
    try {
      final result = await _client.rpc('admin_set_user_role', params: {
        'p_email': email,
        'p_role': role,
      });
      if (result is Map) {
        return result.map((k, v) => MapEntry(k.toString(), v));
      }
      return {'success': false, 'error': 'Unexpected response.'};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  // ---------------------------------------------------------------------------
  // Audit trail
  // ---------------------------------------------------------------------------

  /// Most recent admin actions (create/update/delete/restore), newest first --
  /// the evidence trail behind panel note 7.
  Future<List<Map<String, dynamic>>> recentAuditLog({int limit = 30}) async {
    final rows = await _client
        .from(_auditTable)
        .select()
        .order('created_at', ascending: false)
        .limit(limit);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<void> _logAction(
    String action, {
    String targetTable = 'questions',
    String? targetId,
    Map<String, dynamic>? details,
  }) async {
    try {
      await _client.rpc('log_admin_action', params: {
        'p_action': action,
        'p_target_table': targetTable,
        'p_target_id': targetId,
        'p_details': details,
      });
    } catch (e) {
      // The audit log is diagnostic, never load-bearing: a failed write must
      // not roll back a legitimate content edit.
      debugPrint('AdminService._logAction failed: $e');
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }
}

/// One row of [AdminService.listQuestions]: the parsed [Question] plus the
/// admin-only bookkeeping fields (`is_active`, `updated_at`) that
/// [Question] itself does not carry, because students never need them.
/// Which questions to list by their TOS link.
enum TosLinkFilter { any, linked, unlinked }

/// One row of `admin_tos_coverage()`: a TOS topic or competency with its TOS
/// items, its active questions and its drafts (inactive questions).
class TosCoverageRow {
  final String code;
  final String subjectId;
  final String topicCode;
  final bool isTopic;
  final int tosItems;
  final int active;
  final int drafts;

  const TosCoverageRow({
    required this.code,
    required this.subjectId,
    required this.topicCode,
    required this.isTopic,
    required this.tosItems,
    required this.active,
    required this.drafts,
  });

  factory TosCoverageRow.fromJson(Map<String, dynamic> json) => TosCoverageRow(
        code: (json['code'] ?? '').toString(),
        subjectId: (json['subject_id'] ?? '').toString(),
        topicCode: (json['topic_code'] ?? '').toString(),
        isTopic: json['level'] == 'topic',
        tosItems: (json['tos_items'] as num?)?.toInt() ?? 0,
        active: (json['active'] as num?)?.toInt() ?? 0,
        drafts: (json['drafts'] as num?)?.toInt() ?? 0,
      );

  /// True when the active questions cover every TOS item.
  bool get isCovered => active >= tosItems;
}

class AdminQuestionEntry {
  final Question question;
  final bool isActive;
  final DateTime? updatedAt;

  const AdminQuestionEntry({
    required this.question,
    required this.isActive,
    this.updatedAt,
  });
}
