import 'package:flutter/material.dart';

import '../../models/question.dart';
import '../../models/student_record.dart';
import '../../models/subject.dart';
import '../../models/user_progress.dart';
import '../../services/admin_service.dart';
import '../../utils/error_messages.dart';
import '../../utils/responsive.dart';
import '../../widgets/ui/ui.dart';

/// One student's full record, opened from Admin Panel > Students.
///
/// Shows what the Students list cannot: the level each subject has reached
/// (with the 4 segments of every level), each topic's mastery, and the
/// recent quizzes. Read-only: nothing here can change a student's data.
///
/// The figures are what the student's phone last synced, read through
/// `admin_student_record` (supabase_student_record.sql).
class AdminStudentRecordScreen extends StatefulWidget {
  final String userId;

  /// Shown in the top bar while the record loads.
  final String name;
  final String email;

  const AdminStudentRecordScreen({
    super.key,
    required this.userId,
    required this.name,
    this.email = '',
  });

  @override
  State<AdminStudentRecordScreen> createState() => _AdminStudentRecordScreenState();
}

class _AdminStudentRecordScreenState extends State<AdminStudentRecordScreen> {
  static const int _topicsShownAtFirst = 12;

  StudentRecord? _record;
  bool _loading = true;
  String? _error;
  bool _showAllTopics = false;

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
      final record = await AdminService.instance.studentRecord(widget.userId);
      if (!mounted) return;
      setState(() {
        _record = record;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyError(e, fallback: "Couldn't load this student's record. Please try again.");
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final padding = Responsive.horizontalPadding(context);
    final record = _record;

    return Scaffold(
      appBar: AppTopBar(
        title: record?.displayName ?? widget.name,
        subtitle: record?.email ?? widget.email,
        actions: [
          ToolbarIconButton(
            icon: Icons.refresh_rounded,
            tooltip: 'Refresh',
            size: 40,
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const LoadingView(label: 'Loading record...')
          : _error != null || record == null
              ? Center(
                  child: EmptyState(
                    icon: Icons.error_outline_rounded,
                    title: "Couldn't load the record",
                    message: _error,
                    actionLabel: 'Try again',
                    onAction: _load,
                    color: context.palette.danger,
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(padding, 4, padding, 32),
                    children: [
                      ContentWidth(
                        maxWidth: 900,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildSummary(record),
                            const SizedBox(height: AppSpace.section),
                            const SectionHeader(
                              title: 'Level reached',
                              subtitle: 'A level opens when all 4 segments of the one before are passed at 75%.',
                            ),
                            const SizedBox(height: 12),
                            for (final subject in CriminologySubjects.all) ...[
                              _buildSubjectCard(subject, record.subjects[subject.id]),
                              const SizedBox(height: 10),
                            ],
                            const SizedBox(height: AppSpace.section - 10),
                            SectionHeader(
                              title: 'Topic mastery',
                              subtitle: record.topics.isEmpty
                                  ? null
                                  : '${record.topics.length} topic${record.topics.length == 1 ? '' : 's'} · weakest first',
                            ),
                            const SizedBox(height: 12),
                            _buildTopics(record),
                            const SizedBox(height: AppSpace.section),
                            SectionHeader(
                              title: 'Recent quizzes',
                              subtitle: record.quizCount > record.recentQuizzes.length
                                  ? 'Last ${record.recentQuizzes.length} of ${record.quizCount}'
                                  : null,
                            ),
                            const SizedBox(height: 12),
                            _buildQuizzes(record),
                            const SizedBox(height: 20),
                            const InlineBanner(
                              tone: BannerTone.neutral,
                              icon: Icons.lock_outline_rounded,
                              message: "Read-only. These figures come from the student's phone and "
                                  'update each time it syncs.',
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  // ---------------------------------------------------------------------------
  // Summary
  // ---------------------------------------------------------------------------

  Widget _buildSummary(StudentRecord r) {
    final p = context.palette;
    final text = context.textStyles;
    final accuracy = r.accuracy;
    final lastActive = r.lastActive;

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              UserAvatar(
                name: r.displayName,
                size: 48,
                color: r.role == 'admin' ? p.primary : const Color(0xFF0E9F9A),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.displayName, style: text.titleMedium, overflow: TextOverflow.ellipsis),
                    if (r.school != null)
                      Text(r.school!, style: text.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        Pill(label: '${r.totalPoints} pts', icon: Icons.stars_rounded, color: p.gold, fontSize: 10.5),
                        Pill(label: r.rank, icon: Icons.military_tech_rounded, color: p.gold, fontSize: 10.5),
                        if (r.role == 'admin')
                          Pill(label: 'Admin', icon: Icons.shield_rounded, color: p.primary, fontSize: 10.5),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _metricStrip([
            ('${r.quizCount}', 'Quizzes', null),
            (accuracy == null ? '—' : '${(accuracy * 100).round()}%', 'Accuracy',
                accuracy == null ? null : p.forScore(accuracy * 100)),
            ('${r.currentStreak}d', 'Streak', null),
            (lastActive == null ? '—' : _timeAgo(lastActive), 'Last active', null),
          ]),
          const SizedBox(height: 8),
          _metricStrip([
            ('${r.topicsMastered}', 'Mastered', r.topicsMastered > 0 ? p.success : null),
            ('${r.topicsNeedingReview}', 'Needs review', r.topicsNeedingReview > 0 ? p.warning : null),
            ('${r.dailyChallenges}', 'Challenges', null),
            ('${r.achievements}', 'Badges', null),
          ]),
          const SizedBox(height: 10),
          Text(
            [
              '${r.questionsAnswered} questions answered',
              'best streak ${r.bestStreak} day${r.bestStreak == 1 ? '' : 's'}',
              if (r.joinedAt != null) 'joined ${_date(r.joinedAt!)}',
            ].join(' · '),
            style: text.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _metricStrip(List<(String, String, Color?)> items) {
    final p = context.palette;
    final text = context.textStyles;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: p.surfaceAlt,
        borderRadius: BorderRadius.circular(AppSpace.radiusSm),
      ),
      child: Row(
        children: [
          for (final (value, label, color) in items)
            Expanded(
              child: Column(
                children: [
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleSmall?.copyWith(color: color ?? p.textPrimary, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.labelSmall?.copyWith(letterSpacing: 0),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Level reached
  // ---------------------------------------------------------------------------

  Widget _buildSubjectCard(Subject subject, SubjectRecord? s) {
    final p = context.palette;
    final text = context.textStyles;
    final color = AppColors.subjectColor(subject.id);
    final started = s != null && s.started;

    final String status;
    final Color statusColor;
    if (!started) {
      status = 'Not started';
      statusColor = p.textTertiary;
    } else if (s.allPassed) {
      status = 'All levels passed';
      statusColor = p.success;
    } else {
      status = 'On ${_levelName(s.levelReached)}';
      statusColor = p.forDifficulty(s.levelReached.index);
    }

    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconBadge(
                icon: AppTheme.subjectIcons[subject.id] ?? subject.icon,
                color: color,
                size: 34,
                iconSize: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(subject.name, style: text.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              Pill(label: status, color: statusColor, fontSize: 10.5),
            ],
          ),
          if (started) ...[
            const SizedBox(height: 12),
            for (final d in Difficulty.values) ...[
              _buildLevelRow(s, d),
              if (d != Difficulty.hard) const SizedBox(height: 8),
            ],
            const SizedBox(height: 10),
            Text(
              [
                '${s.correctAnswers} of ${s.questionsAnswered} correct'
                    '${s.questionsAnswered > 0 ? ' (${(s.correctAnswers * 100 / s.questionsAnswered).round()}%)' : ''}',
                if (s.lastStudyDate != null) 'last studied ${_timeAgo(s.lastStudyDate!)}',
              ].join(' · '),
              style: text.bodySmall,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLevelRow(SubjectRecord s, Difficulty d) {
    final p = context.palette;
    final text = context.textStyles;
    final level = s.level(d);
    final unlocked = s.isUnlocked(d);
    final showSegments = unlocked || level.attempted;

    return Row(
      children: [
        SizedBox(
          width: 62,
          child: Text(
            _levelName(d),
            style: text.labelMedium?.copyWith(
              color: unlocked ? p.forDifficulty(d.index) : p.textTertiary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (showSegments)
          for (var i = 0; i < level.segments.length; i++) ...[
            if (i > 0) const SizedBox(width: 5),
            Expanded(child: _segmentChip(level.segments[i], i)),
          ]
        else
          Expanded(
            child: Row(
              children: [
                Icon(Icons.lock_rounded, size: 14, color: p.textTertiary),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    'Locked',
                    style: text.bodySmall?.copyWith(color: p.textTertiary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(width: 8),
        SizedBox(
          width: 30,
          child: Text(
            showSegments ? '${level.segmentsPassed}/4' : '',
            textAlign: TextAlign.right,
            style: text.labelSmall?.copyWith(
              color: level.passed ? p.success : p.textSecondary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }

  /// One segment of 10 questions. Green when passed, amber when tried but not
  /// yet at 75%, plain when not tried.
  Widget _segmentChip(SegmentProgress seg, int index) {
    final p = context.palette;
    final text = context.textStyles;
    final Color bg;
    final Color fg;
    if (seg.isPassed) {
      bg = p.successSoft;
      fg = p.success;
    } else if (seg.isAttempted) {
      bg = p.warningSoft;
      fg = p.warning;
    } else {
      bg = p.surfaceAlt;
      fg = p.textTertiary;
    }
    final label = seg.isAttempted ? '${seg.correctAnswers}/${seg.questionsAnswered}' : '–';
    return Tooltip(
      message: 'Segment ${index + 1} (questions ${SegmentProgress.rangeLabelFor(index)}): '
          '${seg.isAttempted ? '${seg.correctAnswers} of ${seg.questionsAnswered} correct' : 'not tried'}'
          '${seg.isPassed ? ', passed' : ''}',
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 3),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(label, style: text.labelSmall?.copyWith(color: fg, fontWeight: FontWeight.w800)),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Topic mastery
  // ---------------------------------------------------------------------------

  Widget _buildTopics(StudentRecord r) {
    final p = context.palette;
    if (r.topics.isEmpty) {
      return const EmptyState(
        icon: Icons.insights_rounded,
        title: 'No topics yet',
        message: 'Mastery appears after the student answers quiz questions.',
        compact: true,
      );
    }
    final shown = _showAllTopics ? r.topics : r.topics.take(_topicsShownAtFirst).toList();

    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < shown.length; i++) ...[
            if (i > 0) Divider(height: 1, color: p.border),
            _buildTopicRow(shown[i]),
          ],
          if (r.topics.length > _topicsShownAtFirst)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() => _showAllTopics = !_showAllTopics),
                child: Text(_showAllTopics ? 'Show fewer' : 'Show all ${r.topics.length} topics'),
              ),
            ),
          if (r.topics.length <= _topicsShownAtFirst) const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _buildTopicRow(TopicRecord t) {
    final p = context.palette;
    final text = context.textStyles;
    final subject = CriminologySubjects.all.where((s) => s.id == t.subjectId).firstOrNull;
    final percent = t.pKnown * 100;
    final barColor = p.forScore(percent);

    final String label;
    final Color labelColor;
    if (t.isMastered) {
      label = 'Mastered';
      labelColor = p.success;
    } else if (t.needsReview) {
      label = 'Needs review';
      labelColor = p.warning;
    } else {
      label = t.bandLabel;
      labelColor = p.textSecondary;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.topic, style: text.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                    Text(
                      '${subject?.shortName ?? t.subjectId} · ${t.correct} of ${t.attempts} correct',
                      style: text.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${percent.round()}%',
                    style: text.titleSmall?.copyWith(color: barColor, fontWeight: FontWeight.w800),
                  ),
                  Pill(label: label, color: labelColor, fontSize: 10),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          AppProgressBar(value: t.pKnown, color: barColor, height: 6),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Recent quizzes
  // ---------------------------------------------------------------------------

  Widget _buildQuizzes(StudentRecord r) {
    final p = context.palette;
    final text = context.textStyles;
    if (r.recentQuizzes.isEmpty) {
      return const EmptyState(
        icon: Icons.quiz_outlined,
        title: 'No quizzes yet',
        message: 'Finished quizzes appear here once the phone syncs.',
        compact: true,
      );
    }
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Column(
        children: [
          for (var i = 0; i < r.recentQuizzes.length; i++) ...[
            if (i > 0) Divider(height: 1, color: p.border),
            _buildQuizRow(r.recentQuizzes[i], text, p),
          ],
        ],
      ),
    );
  }

  Widget _buildQuizRow(QuizRecord q, TextTheme text, AppPalette p) {
    final subject = CriminologySubjects.all.where((s) => s.id == q.subjectId).firstOrNull;
    final scoreColor = p.forScore(q.score.toDouble());
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  subject?.name ?? q.subjectId,
                  style: text.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (q.difficulty != null)
                      Pill(
                        label: _levelName(q.difficulty!),
                        color: p.forDifficulty(q.difficulty!.index),
                        fontSize: 10,
                      ),
                    if (q.takenAt != null) Text(_timeAgo(q.takenAt!), style: text.bodySmall),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${q.score}%', style: text.titleSmall?.copyWith(color: scoreColor, fontWeight: FontWeight.w800)),
              Text('${q.correct}/${q.total}', style: text.bodySmall),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static String _levelName(Difficulty d) => switch (d) {
        Difficulty.easy => 'Easy',
        Difficulty.medium => 'Medium',
        Difficulty.hard => 'Hard',
      };

  static const List<String> _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String _date(DateTime d) => '${_months[d.month - 1]} ${d.day}, ${d.year}';

  /// "now", "5m ago", "3h ago", "6d ago", then the date.
  static String _timeAgo(DateTime at) {
    final diff = DateTime.now().difference(at);
    if (diff.isNegative || diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return _date(at);
  }
}
