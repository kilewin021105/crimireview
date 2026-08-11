import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/admin_service.dart';
import '../../services/supabase_service.dart';
import '../../services/theme_service.dart';
import '../../utils/responsive.dart';

enum _SortBy { points, mastery, remediation, recent }

/// Roster of every student's Bayesian Knowledge Tracing rollup, plus who
/// currently has admin access.
///
/// Panel note 2, verbatim: *"the system monitors the progress of the
/// students."* This screen is that monitoring made visible to a human --
/// it reads `public.student_progress_overview`, the view that joins
/// `user_profiles` with an aggregate of `topic_mastery` per student.
///
/// The mastery numbers themselves are still strictly read-only on purpose:
/// `topic_mastery` policy denies admin writes (a teacher must not be able to
/// fake a student's model). The one thing an admin CAN change from here is
/// the `role` column, via [_toggleRole] -> `AdminService.setUserRole` ->
/// `admin_set_user_role` (supabase_admin_management.sql) -- which is the
/// same operation `UPDATE user_profiles SET role = ...` in the SQL Editor
/// already does, just reachable without direct database access. The
/// `protect_user_role` trigger (supabase_schema_v2.sql) still enforces that
/// only an existing admin can ever change a role, independent of this UI.
class AdminStudentsScreen extends StatefulWidget {
  /// False when this screen is a tab root inside `AdminShellScreen` (no
  /// previous route to pop back to).
  final bool showBackButton;

  const AdminStudentsScreen({super.key, this.showBackButton = true});

  @override
  State<AdminStudentsScreen> createState() => _AdminStudentsScreenState();
}

class _AdminStudentsScreenState extends State<AdminStudentsScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _students = [];
  bool _loading = true;
  String? _error;
  _SortBy _sortBy = _SortBy.points;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await AdminService.instance.studentProgressOverview(search: _searchController.text);
      if (!mounted) return;
      setState(() {
        _students = rows;
        _loading = false;
      });
      _applySort();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _toggleRole(Map<String, dynamic> row) async {
    final email = (row['email'] ?? '').toString();
    final currentRole = (row['role'] ?? 'student').toString();
    final targetRole = currentRole == 'admin' ? 'student' : 'admin';
    final name = (row['display_name'] ?? email).toString();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? AppColors.darkCard : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(targetRole == 'admin' ? 'Grant admin access?' : 'Remove admin access?'),
        content: Text(
          targetRole == 'admin'
              ? '$name will be able to manage questions and view every student\'s progress.'
              : '$name will lose access to the Admin Panel.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: targetRole == 'admin' ? AppColors.accent : AppColors.error,
            ),
            child: Text(
              targetRole == 'admin' ? 'Make Admin' : 'Remove Admin',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final result = await AdminService.instance.setUserRole(email, targetRole);
    if (!mounted) return;
    if (result['success'] == true) {
      _showSnack(targetRole == 'admin' ? '$name is now an admin' : '$name is now a student');
      _load();
    } else {
      _showSnack('Failed: ${result['error'] ?? 'unknown error'}', isError: true);
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.error : AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _applySort() {
    setState(() {
      _students = List.of(_students)
        ..sort((a, b) {
          switch (_sortBy) {
            case _SortBy.points:
              return _num(b['total_points']).compareTo(_num(a['total_points']));
            case _SortBy.mastery:
              return _num(b['avg_p_known']).compareTo(_num(a['avg_p_known']));
            case _SortBy.remediation:
              return _num(b['topics_needing_remediation']).compareTo(_num(a['topics_needing_remediation']));
            case _SortBy.recent:
              final at = DateTime.tryParse('${a['last_practiced']}') ?? DateTime(2000);
              final bt = DateTime.tryParse('${b['last_practiced']}') ?? DateTime(2000);
              return bt.compareTo(at);
          }
        });
    });
  }

  num _num(dynamic v) => (v as num?) ?? 0;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final padding = Responsive.horizontalPadding(context);

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      appBar: _buildAppBar(isDark),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(padding, 8, padding, 0),
              child: _buildFilters(isDark),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? _buildError(isDark)
                      : _students.isEmpty
                          ? _buildEmpty(isDark)
                          : RefreshIndicator(
                              onRefresh: _load,
                              color: AppColors.accent,
                              child: ListView.builder(
                                padding: EdgeInsets.fromLTRB(padding, 0, padding, 32),
                                itemCount: _students.length,
                                itemBuilder: (context, i) => _buildStudentCard(_students[i], isDark),
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(bool isDark) {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      automaticallyImplyLeading: false,
      leading: widget.showBackButton
          ? IconButton(
              onPressed: () => Navigator.pop(context),
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkCard : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)],
                ),
                child: Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: isDark ? Colors.white : const Color(0xFF1A1A2E)),
              ),
            )
          : null,
      title: Text(
        'Students',
        style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w600, color: isDark ? Colors.white : const Color(0xFF1A1A2E)),
      ),
      centerTitle: true,
    );
  }

  Widget _buildFilters(bool isDark) {
    return Column(
      children: [
        TextField(
          controller: _searchController,
          onSubmitted: (_) => _load(),
          style: TextStyle(color: isDark ? Colors.white : const Color(0xFF1A1A2E)),
          decoration: InputDecoration(
            hintText: 'Search name or email',
            hintStyle: TextStyle(color: isDark ? Colors.grey.shade500 : Colors.grey.shade500),
            prefixIcon: const Icon(Icons.search_rounded),
            filled: true,
            fillColor: isDark ? AppColors.darkCard : AppColors.lightCard,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(vertical: 0),
          ),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final entry in const {
                _SortBy.points: 'Points',
                _SortBy.mastery: 'Mastery',
                _SortBy.remediation: 'Needs Review',
                _SortBy.recent: 'Recently Active',
              }.entries)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(entry.value),
                    selected: _sortBy == entry.key,
                    onSelected: (_) {
                      setState(() => _sortBy = entry.key);
                      _applySort();
                    },
                    selectedColor: AppColors.accent.withValues(alpha: 0.18),
                    backgroundColor: isDark ? AppColors.darkCard : AppColors.lightCard,
                    labelStyle: TextStyle(
                      fontSize: 12,
                      color: _sortBy == entry.key ? AppColors.accent : (isDark ? Colors.grey.shade400 : Colors.grey.shade700),
                    ),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide.none),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildError(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, color: AppColors.error, size: 48),
            const SizedBox(height: 12),
            Text('Could not load students.\n$_error', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _load,
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent),
              child: const Text('Retry', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty(bool isDark) {
    return Center(
      child: Text(
        'No students found.',
        style: TextStyle(color: isDark ? Colors.grey.shade500 : Colors.grey.shade600),
      ),
    );
  }

  Widget _buildStudentCard(Map<String, dynamic> row, bool isDark) {
    final name = (row['display_name'] ?? 'Student').toString();
    final email = (row['email'] ?? '').toString();
    final points = _num(row['total_points']).toInt();
    final mastered = _num(row['topics_mastered']).toInt();
    final remediation = _num(row['topics_needing_remediation']).toInt();
    final tracked = _num(row['topics_tracked']).toInt();
    final avgP = _num(row['avg_p_known']).toDouble();
    final lastPracticed = DateTime.tryParse('${row['last_practiced']}');
    final role = (row['role'] ?? 'student').toString();
    final isSelf = email.isNotEmpty &&
        email.toLowerCase() == (SupabaseService.instance.currentUser?.email ?? '').toLowerCase();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: AppColors.accent.withValues(alpha: 0.15),
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: isDark ? Colors.white : const Color(0xFF1A1A2E)),
                          ),
                        ),
                        if (role == 'admin') ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                            child: Text('admin', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.accent)),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      email,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: isDark ? Colors.grey.shade500 : Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
              Text(
                '$points pts',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.accent),
              ),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert_rounded, size: 18, color: isDark ? Colors.grey.shade500 : Colors.grey.shade500),
                tooltip: 'Manage access',
                onSelected: (_) => _toggleRole(row),
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'toggle',
                    enabled: !(isSelf && role == 'admin'),
                    child: Text(
                      role == 'admin' ? 'Remove admin access' : 'Make admin',
                      style: TextStyle(color: role == 'admin' ? AppColors.error : null),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildMetric('${(avgP * 100).round()}%', 'Avg. Mastery', isDark),
              _buildMetric('$mastered', 'Mastered', isDark, color: AppColors.success),
              _buildMetric('$remediation', 'Needs Review', isDark, color: remediation > 0 ? AppColors.error : null),
              _buildMetric('$tracked', 'Topics Tracked', isDark),
            ],
          ),
          if (lastPracticed != null) ...[
            const SizedBox(height: 8),
            Text(
              'Last active ${_timeAgo(lastPracticed)}',
              style: TextStyle(fontSize: 11, color: isDark ? Colors.grey.shade600 : Colors.grey.shade500),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMetric(String value, String label, bool isDark, {Color? color}) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: color ?? (isDark ? Colors.white : const Color(0xFF1A1A2E))),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10, color: isDark ? Colors.grey.shade500 : Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  String _timeAgo(DateTime at) {
    final diff = DateTime.now().difference(at);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 30) return '${diff.inDays}d ago';
    return '${(diff.inDays / 30).floor()}mo ago';
  }
}
