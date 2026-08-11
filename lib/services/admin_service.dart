import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/question.dart';
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

  static final AdminService _instance = AdminService._();
  static AdminService get instance => _instance;

  static const String _questionsTable = 'questions';
  static const String _overviewView = 'student_progress_overview';
  static const String _auditTable = 'admin_audit_log';

  bool _isAdmin = false;
  bool _roleChecked = false;
  StreamSubscription<AuthState>? _authSub;
  Object? _lastError;

  /// True once a role check has completed at least once (including a failed
  /// one). Lets the UI distinguish "still loading" from "confirmed student".
  bool get isReady => _roleChecked;

  /// True when the signed-in user has `role = 'admin'` in `user_profiles`.
  bool get isAdmin => _isAdmin;

  Object? get lastError => _lastError;

  /// Call once at app start-up (after [SupabaseService.initialize]). Resolves
  /// the current role and then keeps it in sync with sign-in/sign-out.
  Future<void> init() async {
    if (!SupabaseService.isInitialized) return;
    await refreshRole();
    _authSub ??= SupabaseService.instance.authStateChanges.listen((_) {
      unawaited(refreshRole());
    });
  }

  /// Re-resolves [isAdmin] against the database. Call after sign-in/sign-out
  /// and after promoting/demoting a user, so a stale cached role can never
  /// hide or wrongly expose the admin screens.
  Future<bool> refreshRole() async {
    if (!SupabaseService.isInitialized || !SupabaseService.instance.isLoggedIn) {
      _roleChecked = true;
      _setAdmin(false);
      return false;
    }
    try {
      final result = await SupabaseService.instance.client.rpc('is_admin');
      _lastError = null;
      _roleChecked = true;
      _setAdmin(result == true);
      return _isAdmin;
    } catch (e) {
      debugPrint('AdminService.refreshRole failed: $e');
      _lastError = e;
      _roleChecked = true;
      _setAdmin(false);
      return false;
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
  /// [source] / [templateId] scope the list to one Automatic Item Generation
  /// batch -- e.g. `source: QuestionSource.generated, templateId: <upload
  /// id>` is exactly the "review this document's output" view opened from
  /// `AdminDocumentGenerationScreen`. Both are optional and independent of
  /// [includeInactive]: a pending-review batch is inactive by definition,
  /// so callers that want to see it must also pass `includeInactive: true`.
  Future<List<AdminQuestionEntry>> listQuestions({
    String? subjectId,
    Difficulty? difficulty,
    bool includeInactive = true,
    String? search,
    QuestionSource? source,
    String? templateId,
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
    if (!includeInactive) {
      query = query.eq('is_active', true);
    }
    if (source != null) {
      query = query.eq('source', source.name);
    }
    if (templateId != null && templateId.isNotEmpty) {
      query = query.eq('template_id', templateId);
    }
    final term = search?.trim() ?? '';
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
  Future<void> updateQuestion(Question question) async {
    final row = question.toSupabaseRow()..['version'] = question.version + 1;
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
