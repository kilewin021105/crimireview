import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/subject.dart';
import '../../services/admin_service.dart';
import '../../services/theme_service.dart';
import '../../utils/page_transitions.dart';
import '../../utils/responsive.dart';
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

  /// Extra AppBar actions -- used by `AdminShellScreen` to add "View as
  /// Student" / "Sign Out" on the shell's landing tab, the same way the
  /// student `HomeScreen` carries its own profile shortcut rather than
  /// repeating it on every tab.
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
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final padding = Responsive.horizontalPadding(context);

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      appBar: _buildAppBar(isDark),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _load,
          color: AppColors.accent,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? _buildError(isDark)
                  : ListView(
                      padding: EdgeInsets.fromLTRB(padding, 8, padding, 32),
                      children: [
                        _buildStatGrid(isDark),
                        const SizedBox(height: 24),
                        _buildNavCard(
                          isDark: isDark,
                          icon: Icons.quiz_rounded,
                          title: 'Manage Questions',
                          subtitle:
                              '${_questionStats['active'] ?? 0} active of ${_questionStats['total'] ?? 0} total items',
                          color: AppColors.accent,
                          onTap: () async {
                            if (widget.onNavigateToTab != null) {
                              widget.onNavigateToTab!(1);
                              return;
                            }
                            await Navigator.push(
                              context,
                              SlidePageRoute(page: const AdminQuestionsScreen()),
                            );
                            _load();
                          },
                        ),
                        const SizedBox(height: 12),
                        _buildNavCard(
                          isDark: isDark,
                          icon: Icons.groups_rounded,
                          title: 'Monitor Students',
                          subtitle:
                              '${_students.length} student${_students.length == 1 ? '' : 's'} tracked',
                          color: const Color(0xFF14B8A6),
                          onTap: () {
                            if (widget.onNavigateToTab != null) {
                              widget.onNavigateToTab!(2);
                              return;
                            }
                            Navigator.push(
                              context,
                              SlidePageRoute(page: const AdminStudentsScreen()),
                            );
                          },
                        ),
                        const SizedBox(height: 24),
                        _buildSectionHeader('Content by Subject', isDark),
                        const SizedBox(height: 12),
                        _buildSubjectBreakdown(isDark),
                        const SizedBox(height: 24),
                        _buildSectionHeader('Recent Admin Activity', isDark),
                        const SizedBox(height: 12),
                        _buildAuditLog(isDark),
                      ],
                    ),
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
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10),
                  ],
                ),
                child: Icon(
                  Icons.arrow_back_ios_new_rounded,
                  size: 18,
                  color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                ),
              ),
            )
          : null,
      title: Text(
        'Admin Panel',
        style: GoogleFonts.poppins(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.white : const Color(0xFF1A1A2E),
        ),
      ),
      centerTitle: true,
      actions: widget.appBarActions,
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
            Text(
              'Could not load the admin dashboard.\n$_error',
              textAlign: TextAlign.center,
              style: TextStyle(color: isDark ? Colors.grey.shade400 : Colors.grey.shade700),
            ),
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

  Widget _buildStatGrid(bool isDark) {
    final total = _questionStats['total'] ?? 0;
    final active = _questionStats['active'] ?? 0;
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
      _StatTileData('$active', 'Active Questions', Icons.fact_check_rounded, AppColors.accent),
      _StatTileData('$total', 'Total in Bank', Icons.storage_rounded, const Color(0xFF3B82F6)),
      _StatTileData('${_students.length}', 'Students', Icons.groups_rounded, const Color(0xFF14B8A6)),
      _StatTileData('$avgMasteryPercent%', 'Avg. Mastery', Icons.psychology_rounded, const Color(0xFFF59E0B)),
      _StatTileData('$studentsRemediation', 'Topics Needing Review', Icons.report_problem_rounded, AppColors.error),
      _StatTileData('$generated', 'Auto-Generated Items', Icons.auto_awesome_rounded, const Color(0xFFEC4899)),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.5,
      ),
      itemCount: tiles.length,
      itemBuilder: (context, i) => _buildStatTile(tiles[i], isDark),
    );
  }

  Widget _buildStatTile(_StatTileData data, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: data.color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(data.icon, color: data.color, size: 18),
          ),
          const Spacer(),
          Text(
            data.value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : const Color(0xFF1A1A2E),
            ),
          ),
          Text(
            data.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavCard({
    required bool isDark,
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkCard : AppColors.lightCard,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: isDark ? Colors.grey.shade600 : Colors.grey.shade400),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, bool isDark) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
      ),
    );
  }

  Widget _buildSubjectBreakdown(bool isDark) {
    final bySubject = (_questionStats['bySubject'] as Map?) ?? const {};
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          for (final subject in CriminologySubjects.all)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(subject.icon, size: 18, color: subject.color),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      subject.shortName,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                      ),
                    ),
                  ),
                  Text(
                    '${(bySubject[subject.id]?['active']) ?? 0} / ${(bySubject[subject.id]?['total']) ?? 0}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAuditLog(bool isDark) {
    if (_auditLog.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkCard : AppColors.lightCard,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          'No admin activity yet. Actions you take on questions will appear here.',
          style: TextStyle(color: isDark ? Colors.grey.shade500 : Colors.grey.shade600, fontSize: 13),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          for (var i = 0; i < _auditLog.length; i++) ...[
            _buildAuditRow(_auditLog[i], isDark),
            if (i != _auditLog.length - 1)
              Divider(height: 1, color: isDark ? Colors.white10 : Colors.black.withOpacity(0.05)),
          ],
        ],
      ),
    );
  }

  Widget _buildAuditRow(Map<String, dynamic> entry, bool isDark) {
    final action = (entry['action'] ?? '').toString();
    final targetId = (entry['target_id'] ?? '').toString();
    final createdAt = DateTime.tryParse((entry['created_at'] ?? '').toString());

    IconData icon;
    Color color;
    switch (action) {
      case 'create':
        icon = Icons.add_circle_outline_rounded;
        color = AppColors.success;
        break;
      case 'update':
        icon = Icons.edit_rounded;
        color = const Color(0xFF3B82F6);
        break;
      case 'delete':
        icon = Icons.delete_outline_rounded;
        color = AppColors.error;
        break;
      case 'restore':
        icon = Icons.restore_rounded;
        color = const Color(0xFFF59E0B);
        break;
      default:
        icon = Icons.circle_outlined;
        color = Colors.grey;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '${action[0].toUpperCase()}${action.substring(1)} · $targetId',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white : const Color(0xFF1A1A2E),
              ),
            ),
          ),
          if (createdAt != null)
            Text(
              _timeAgo(createdAt),
              style: TextStyle(fontSize: 11, color: isDark ? Colors.grey.shade600 : Colors.grey.shade500),
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
    return '${diff.inDays}d ago';
  }
}

class _StatTileData {
  final String value;
  final String label;
  final IconData icon;
  final Color color;
  _StatTileData(this.value, this.label, this.icon, this.color);
}
