import 'package:flutter/material.dart';

import '../../models/subject.dart';
import '../../services/admin_service.dart';
import '../../utils/error_messages.dart';
import '../../utils/page_transitions.dart';
import '../../utils/responsive.dart';
import '../../widgets/ui/ui.dart';
import 'admin_questions_screen.dart';
import 'admin_students_screen.dart';

/// Landing screen of the admin panel.
///
/// Answers panel notes 7 ("have an ADMIN add questions") and 2 ("monitor the
/// progress of the students") in one place: content health at a glance, then
/// two doors -- Questions and Students -- into the screens that do the work.
/// Only reachable from Settings when [AdminService.isAdmin] is true; the real
/// gate is Postgres RLS via `is_admin()`, this is just the door.
class AdminDashboardScreen extends StatefulWidget {
  /// False when this screen is a tab root inside [AdminShellScreen] (no
  /// previous route to pop back to); true when it's pushed on top of
  /// something else (e.g. the legacy Settings -> Admin Panel entry point).
  final bool showBackButton;

  /// When set, the "Manage Questions" / "Monitor Students" cards switch the
  /// enclosing shell's tab instead of pushing a new route on top of it.
  /// Left null when this screen is pushed standalone, in which case the
  /// cards fall back to [Navigator.push].
  final ValueChanged<int>? onNavigateToTab;

  /// Extra AppBar actions -- used by `AdminShellScreen` to add "Sign Out"
  /// on the shell's landing tab, the same way the student `HomeScreen`
  /// carries its own profile shortcut rather than repeating it on every tab.
  final List<Widget>? appBarActions;

  const AdminDashboardScreen({
    super.key,
    this.showBackButton = true,
    this.onNavigateToTab,
    this.appBarActions,
  });

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  bool _loading = true;
  String? _error;

  Map<String, dynamic> _questionStats = const {};
  List<Map<String, dynamic>> _students = const [];
  List<Map<String, dynamic>> _auditLog = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        AdminService.instance.questionStats(),
        AdminService.instance.studentProgressOverview(),
        AdminService.instance.recentAuditLog(limit: 8),
      ]);
      if (!mounted) return;
      setState(() {
        _questionStats = results[0] as Map<String, dynamic>;
        _students = results[1] as List<Map<String, dynamic>>;
        _auditLog = results[2] as List<Map<String, dynamic>>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyError(e, fallback: 'Please check your connection and try again.');
        _loading = false;
      });
    }
  }

  void _openQuestions() async {
    if (widget.onNavigateToTab != null) {
      widget.onNavigateToTab!(1);
      return;
    }
    await Navigator.push(context, SlidePageRoute(page: const AdminQuestionsScreen()));
    _load();
  }

  void _openStudents() {
    if (widget.onNavigateToTab != null) {
      widget.onNavigateToTab!(2);
      return;
    }
    Navigator.push(context, SlidePageRoute(page: const AdminStudentsScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final padding = Responsive.horizontalPadding(context);

    return Scaffold(
      appBar: AppTopBar(
        title: 'Dashboard',
        subtitle: 'Content health and student progress',
        showBack: widget.showBackButton,
        actions: [
          ToolbarIconButton(
            icon: Icons.refresh_rounded,
            tooltip: 'Refresh',
            size: 40,
            onPressed: _loading ? null : _load,
          ),
          ...?widget.appBarActions,
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const LoadingView(label: 'Loading dashboard...')
            : _error != null
                ? ListView(
                    children: [
                      const SizedBox(height: 60),
                      EmptyState(
                        icon: Icons.error_outline_rounded,
                        title: "Couldn't load the dashboard",
                        message: _error,
                        actionLabel: 'Try again',
                        onAction: _load,
                        color: context.palette.danger,
                      ),
                    ],
                  )
                : ListView(
                    padding: EdgeInsets.fromLTRB(padding, 4, padding, 32),
                    children: [
                      ContentWidth(
                        maxWidth: 1000,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Appear(index: 0, child: _buildHero()),
                            const SizedBox(height: 14),
                            Appear(index: 1, child: _buildStatGrid()),
                            const SizedBox(height: AppSpace.section),
                            Appear(index: 2, child: _buildShortcuts()),
                            const SizedBox(height: AppSpace.section),
                            Appear(
                              index: 3,
                              child: LayoutBuilder(builder: (context, c) {
                                final wide = c.maxWidth >= 760;
                                final subjects = _section(
                                  'Content by subject',
                                  'Active / total questions',
                                  _buildSubjectBreakdown(),
                                );
                                final audit = _section(
                                  'Recent admin activity',
                                  'Last ${_auditLog.length} changes',
                                  _buildAuditLog(),
                                );
                                if (!wide) {
                                  return Column(
                                    children: [subjects, const SizedBox(height: AppSpace.section), audit],
                                  );
                                }
                                return Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(child: subjects),
                                    const SizedBox(width: 16),
                                    Expanded(child: audit),
                                  ],
                                );
                              }),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _section(String title, String subtitle, Widget child) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title: title, subtitle: subtitle),
          const SizedBox(height: 12),
          child,
        ],
      );

  Widget _buildHero() {
    final text = context.textStyles;
    final total = (_questionStats['total'] as num?)?.toInt() ?? 0;
    final active = (_questionStats['active'] as num?)?.toInt() ?? 0;
    return GradientCard(
      onTap: _openQuestions,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'QUESTION BANK',
                style: text.labelSmall?.copyWith(color: Colors.white.withValues(alpha: 0.75)),
              ),
              const Spacer(),
              Pill(
                label: 'Manage',
                icon: Icons.arrow_forward_rounded,
                color: Colors.white,
                background: Colors.white.withValues(alpha: 0.16),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('$active', style: text.displaySmall?.copyWith(color: Colors.white)),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  'active of $total questions',
                  style: text.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.8)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          AppProgressBar(
            value: total == 0 ? 0 : active / total,
            color: Colors.white,
            trackColor: Colors.white.withValues(alpha: 0.2),
            height: 7,
          ),
        ],
      ),
    );
  }

  Widget _buildStatGrid() {
    final p = context.palette;
    final total = _questionStats['total'] ?? 0;
    final generated = _questionStats['generated'] ?? 0;

    var studentsRemediation = 0;
    var pKnownSum = 0.0;
    var pKnownCount = 0;
    for (final row in _students) {
      studentsRemediation += (row['topics_needing_remediation'] as num?)?.toInt() ?? 0;
      final avg = (row['avg_p_known'] as num?)?.toDouble();
      if (avg != null && ((row['topics_tracked'] as num?)?.toInt() ?? 0) > 0) {
        pKnownSum += avg;
        pKnownCount++;
      }
    }
    final avgMasteryPercent = pKnownCount == 0 ? 0 : ((pKnownSum / pKnownCount) * 100).round();

    final tiles = [
      StatTile(icon: Icons.groups_rounded, value: '${_students.length}', label: 'Students', color: const Color(0xFF0E9F9A)),
      StatTile(icon: Icons.psychology_rounded, value: '$avgMasteryPercent%', label: 'Avg. mastery', color: p.gold),
      StatTile(icon: Icons.flag_rounded, value: '$studentsRemediation', label: 'Topics to review', color: p.danger),
      StatTile(icon: Icons.storage_rounded, value: '$total', label: 'Total in bank', color: p.info),
      StatTile(icon: Icons.auto_awesome_rounded, value: '$generated', label: 'Auto-generated', color: const Color(0xFFE3478C)),
      StatTile(icon: Icons.history_rounded, value: '${_auditLog.length}', label: 'Recent changes', color: p.primary),
    ];

    return LayoutBuilder(builder: (context, c) {
      final columns = c.maxWidth >= 760 ? 6 : (c.maxWidth >= 480 ? 3 : 2);
      // Rows fit their tiles. The old fixed tile shape (width / height)
      // made tiles too short on narrow phones: 6-18 px overflow.
      return AdaptiveGrid(columns: columns, children: tiles);
    });
  }

  Widget _buildShortcuts() {
    final p = context.palette;
    final active = _questionStats['active'] ?? 0;
    final total = _questionStats['total'] ?? 0;
    final cards = [
      _shortcut(
        icon: Icons.quiz_rounded,
        color: p.primary,
        title: 'Manage questions',
        subtitle: '$active active of $total total items',
        onTap: _openQuestions,
      ),
      _shortcut(
        icon: Icons.groups_rounded,
        color: const Color(0xFF0E9F9A),
        title: 'Monitor students',
        subtitle: '${_students.length} student${_students.length == 1 ? '' : 's'} tracked',
        onTap: _openStudents,
      ),
    ];
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth < 560) {
        return Column(children: [cards[0], const SizedBox(height: 10), cards[1]]);
      }
      return Row(children: [
        Expanded(child: cards[0]),
        const SizedBox(width: 10),
        Expanded(child: cards[1]),
      ]);
    });
  }

  Widget _shortcut({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final text = context.textStyles;
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          IconBadge(icon: icon, color: color, size: 46, iconSize: 23),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: text.titleSmall),
                const SizedBox(height: 2),
                Text(subtitle, style: text.bodySmall),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: context.palette.textTertiary),
        ],
      ),
    );
  }

  Widget _buildSubjectBreakdown() {
    final p = context.palette;
    final text = context.textStyles;
    final bySubject = (_questionStats['bySubject'] as Map?) ?? const {};
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          for (var i = 0; i < CriminologySubjects.all.length; i++) ...[
            if (i > 0) Divider(height: 1, color: p.border),
            Builder(builder: (context) {
              final subject = CriminologySubjects.all[i];
              final active = ((bySubject[subject.id]?['active']) as num?)?.toInt() ?? 0;
              final total = ((bySubject[subject.id]?['total']) as num?)?.toInt() ?? 0;
              final color = AppColors.subjectColor(subject.id);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 11),
                child: Row(
                  children: [
                    IconBadge(
                      icon: AppTheme.subjectIcons[subject.id] ?? subject.icon,
                      color: color,
                      size: 34,
                      iconSize: 18,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(child: Text(subject.shortName, style: text.titleSmall)),
                              Text(
                                '$active / $total',
                                style: text.labelMedium?.copyWith(color: p.textPrimary, fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          AppProgressBar(value: total == 0 ? 0 : active / total, color: color, height: 5),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildAuditLog() {
    final p = context.palette;
    if (_auditLog.isEmpty) {
      return const AppCard(
        child: EmptyState(
          compact: true,
          icon: Icons.history_rounded,
          title: 'No activity yet',
          message: 'Changes you make to questions will appear here.',
        ),
      );
    }
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          for (var i = 0; i < _auditLog.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.only(left: 60),
                child: Divider(height: 1, color: p.border),
              ),
            _buildAuditRow(_auditLog[i]),
          ],
        ],
      ),
    );
  }

  Widget _buildAuditRow(Map<String, dynamic> entry) {
    final p = context.palette;
    final text = context.textStyles;
    final action = (entry['action'] ?? '').toString();
    final targetId = (entry['target_id'] ?? '').toString();
    final createdAt = DateTime.tryParse((entry['created_at'] ?? '').toString());

    IconData icon;
    Color color;
    switch (action) {
      case 'create':
        icon = Icons.add_circle_outline_rounded;
        color = p.success;
        break;
      case 'update':
        icon = Icons.edit_rounded;
        color = p.info;
        break;
      case 'delete':
        icon = Icons.delete_outline_rounded;
        color = p.danger;
        break;
      case 'restore':
        icon = Icons.restore_rounded;
        color = p.warning;
        break;
      default:
        icon = Icons.circle_outlined;
        color = p.textTertiary;
    }
    final label = action.isEmpty ? 'Change' : '${action[0].toUpperCase()}${action.substring(1)}';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: [
          IconBadge(icon: icon, color: color, size: 34, iconSize: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: text.titleSmall),
                Text(targetId, style: text.bodySmall, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          if (createdAt != null) Text(_timeAgo(createdAt), style: text.labelSmall),
        ],
      ),
    );
  }

  String _timeAgo(DateTime at) {
    final diff = DateTime.now().difference(at);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
