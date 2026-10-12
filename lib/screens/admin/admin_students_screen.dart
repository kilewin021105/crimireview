import 'package:flutter/material.dart';

import '../../services/admin_service.dart';
import '../../services/supabase_service.dart';
import '../../utils/error_messages.dart';
import '../../widgets/ui/ui.dart';
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
        _error = friendlyError(e, fallback: 'Please check your connection and try again.');
        _loading = false;
      });
    }
  }

  Future<void> _toggleRole(Map<String, dynamic> row) async {
    final email = (row['email'] ?? '').toString();
    final currentRole = (row['role'] ?? 'student').toString();
    final targetRole = currentRole == 'admin' ? 'student' : 'admin';
    final name = (row['display_name'] ?? email).toString();

    final confirmed = await showConfirmDialog(
      context,
      title: targetRole == 'admin' ? 'Grant admin access?' : 'Remove admin access?',
      message: targetRole == 'admin'
          ? "$name will be able to manage questions and view every student's progress."
          : '$name will lose access to the Admin Panel.',
      confirmLabel: targetRole == 'admin' ? 'Make admin' : 'Remove admin',
      destructive: targetRole != 'admin',
      icon: targetRole == 'admin' ? Icons.admin_panel_settings_rounded : Icons.remove_moderator_rounded,
    );
    if (!confirmed) return;

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
    showAppSnack(context, message, tone: isError ? BannerTone.danger : BannerTone.success);
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
    final padding = Responsive.horizontalPadding(context);

    return Scaffold(
      appBar: AppTopBar(
        title: 'Students',
        subtitle: _loading ? 'Loading...' : '${_students.length} student${_students.length == 1 ? '' : 's'}',
        showBack: widget.showBackButton,
        actions: [
          ToolbarIconButton(
            icon: Icons.refresh_rounded,
            tooltip: 'Refresh',
            size: 40,
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(padding, 4, padding, 0),
            child: ContentWidth(maxWidth: 1000, child: _buildFilters()),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _loading
                ? const LoadingView(label: 'Loading students...')
                : _error != null
                    ? Center(
                        child: EmptyState(
                          icon: Icons.error_outline_rounded,
                          title: "Couldn't load students",
                          message: _error,
                          actionLabel: 'Try again',
                          onAction: _load,
                          color: context.palette.danger,
                        ),
                      )
                    : _students.isEmpty
                        ? const Center(
                            child: EmptyState(
                              icon: Icons.person_search_rounded,
                              title: 'No students found',
                              message: 'Try a different name or email.',
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: LayoutBuilder(builder: (context, c) {
                              final columns = c.maxWidth >= 900 ? 2 : 1;
                              if (columns == 1) {
                                return ListView.builder(
                                  padding: EdgeInsets.fromLTRB(padding, 0, padding, 32),
                                  itemCount: _students.length,
                                  itemBuilder: (context, i) => ContentWidth(
                                    maxWidth: 1000,
                                    child: Padding(
                                      padding: const EdgeInsets.only(bottom: 10),
                                      child: _buildStudentCard(_students[i]),
                                    ),
                                  ),
                                );
                              }
                              return GridView.builder(
                                padding: EdgeInsets.fromLTRB(padding, 0, padding, 32),
                                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  mainAxisSpacing: 10,
                                  crossAxisSpacing: 10,
                                  mainAxisExtent: 196,
                                ),
                                itemCount: _students.length,
                                itemBuilder: (context, i) => _buildStudentCard(_students[i]),
                              );
                            }),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return Column(
      children: [
        TextField(
          controller: _searchController,
          onSubmitted: (_) => _load(),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Search name or email',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: IconButton(
              tooltip: 'Search',
              icon: const Icon(Icons.arrow_forward_rounded),
              onPressed: _load,
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text('Sort by', style: context.textStyles.labelMedium),
              ),
              for (final entry in const {
                _SortBy.points: 'Points',
                _SortBy.mastery: 'Mastery',
                _SortBy.remediation: 'Needs review',
                _SortBy.recent: 'Recently active',
              }.entries)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(entry.value),
                    selected: _sortBy == entry.key,
                    showCheckmark: false,
                    onSelected: (_) {
                      setState(() => _sortBy = entry.key);
                      _applySort();
                    },
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStudentCard(Map<String, dynamic> row) {
    final p = context.palette;
    final text = context.textStyles;
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

    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 4, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              UserAvatar(name: name, size: 42, color: role == 'admin' ? p.primary : const Color(0xFF0E9F9A)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(name, overflow: TextOverflow.ellipsis, style: text.titleSmall),
                        ),
                        if (role == 'admin') ...[
                          const SizedBox(width: 6),
                          Pill(label: 'Admin', icon: Icons.shield_rounded, color: p.primary, fontSize: 10),
                        ],
                        if (isSelf) ...[
                          const SizedBox(width: 6),
                          Pill(label: 'You', color: p.textSecondary, background: p.surfaceAlt, fontSize: 10),
                        ],
                      ],
                    ),
                    Text(email, overflow: TextOverflow.ellipsis, style: text.bodySmall),
                  ],
                ),
              ),
              Pill(label: '$points pts', icon: Icons.stars_rounded, color: p.gold),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_horiz_rounded, size: 22, color: p.textSecondary),
                tooltip: 'Manage access',
                onSelected: (_) => _toggleRole(row),
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'toggle',
                    enabled: !(isSelf && role == 'admin'),
                    child: ListTile(
                      dense: true,
                      leading: Icon(
                        role == 'admin' ? Icons.remove_moderator_rounded : Icons.admin_panel_settings_rounded,
                        color: role == 'admin' ? p.danger : null,
                      ),
                      title: Text(
                        role == 'admin' ? 'Remove admin access' : 'Make admin',
                        style: TextStyle(color: role == 'admin' ? p.danger : null),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 10, top: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('Avg. mastery', style: text.labelMedium),
                    const Spacer(),
                    Text(
                      '${(avgP * 100).round()}%',
                      style: text.labelMedium?.copyWith(
                        color: tracked == 0 ? p.textTertiary : p.forScore(avgP * 100),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                AppProgressBar(
                  value: avgP,
                  color: tracked == 0 ? p.textTertiary : p.forScore(avgP * 100),
                  height: 6,
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: p.surfaceAlt,
                    borderRadius: BorderRadius.circular(AppSpace.radiusSm),
                  ),
                  child: Row(
                    children: [
                      _buildMetric('$mastered', 'Mastered', color: mastered > 0 ? p.success : null),
                      _buildMetric('$remediation', 'Needs review', color: remediation > 0 ? p.danger : null),
                      _buildMetric('$tracked', 'Tracked'),
                      _buildMetric(
                        lastPracticed == null ? '—' : _timeAgo(lastPracticed),
                        'Last active',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetric(String value, String label, {Color? color}) {
    final text = context.textStyles;
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.titleSmall?.copyWith(color: color ?? context.palette.textPrimary, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 1),
          Text(label, textAlign: TextAlign.center, style: text.labelSmall?.copyWith(letterSpacing: 0)),
        ],
      ),
    );
  }

  String _timeAgo(DateTime at) {
    final diff = DateTime.now().difference(at);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 30) return '${diff.inDays}d ago';
    return '${(diff.inDays / 30).floor()}mo ago';
  }
}
