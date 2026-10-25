import 'package:flutter/material.dart';

import '../../models/question.dart';
import '../../models/subject.dart';
import '../../models/tos.dart';
import '../../services/admin_service.dart';
import '../../utils/error_messages.dart';
import '../../utils/page_transitions.dart';
import '../../utils/responsive.dart';
import '../../widgets/ui/ui.dart';
import 'admin_question_editor_screen.dart';

/// How well the question bank covers the PRC Tables of Specifications.
///
/// For one subject at a time, every TOS topic and competency is listed with
/// the number of items the TOS gives it, the active questions linked to it,
/// and the drafts (inactive questions) waiting for review. Tapping a
/// competency opens [AdminTosReviewScreen], where faculty check its drafts
/// and approve them.
///
/// Counts come from `admin_tos_coverage()` (supabase_tos_alignment.sql); the
/// TOS itself from `assets/tos/tos_2024.json`.
class AdminTosCoverageScreen extends StatefulWidget {
  final String? initialSubjectId;
  const AdminTosCoverageScreen({super.key, this.initialSubjectId});

  @override
  State<AdminTosCoverageScreen> createState() => _AdminTosCoverageScreenState();
}

class _AdminTosCoverageScreenState extends State<AdminTosCoverageScreen> {
  late String _subjectId = widget.initialSubjectId ?? CriminologySubjects.all.first.id;
  Map<String, TosCoverageRow> _rows = const {};
  TosCatalog? _tos = TosCatalog.loaded;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final tos = _tos ?? await TosCatalog.load();
      final rows = await AdminService.instance.tosCoverage();
      if (!mounted) return;
      setState(() {
        _tos = tos;
        _rows = {for (final r in rows) r.code: r};
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

  Future<void> _openReview(String code) async {
    await Navigator.push(context, SlidePageRoute(page: AdminTosReviewScreen(tosCode: code)));
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final padding = Responsive.horizontalPadding(context);
    final subject = _tos?.subject(_subjectId);

    return Scaffold(
      appBar: AppTopBar(
        title: 'TOS coverage',
        subtitle: _tos?.citation ?? 'PRC Tables of Specifications',
        actions: [
          ToolbarIconButton(icon: Icons.refresh_rounded, tooltip: 'Refresh', size: 40, onPressed: _reload),
        ],
      ),
      body: _loading
          ? const LoadingView(label: 'Counting questions per competency...')
          : _error != null || subject == null
              ? Center(
                  child: EmptyState(
                    icon: Icons.error_outline_rounded,
                    title: "Couldn't load the TOS coverage",
                    message: _error ?? 'The TOS file could not be read.',
                    actionLabel: 'Try again',
                    onAction: _reload,
                    color: context.palette.danger,
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _reload,
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(padding, 4, padding, 32),
                    children: [
                      ContentWidth(maxWidth: 1000, child: _buildSubjectPicker()),
                      const SizedBox(height: 14),
                      ContentWidth(maxWidth: 1000, child: _buildSummary(subject)),
                      const SizedBox(height: AppSpace.section),
                      for (final topic in subject.topics) ...[
                        ContentWidth(maxWidth: 1000, child: _buildTopic(topic)),
                        const SizedBox(height: 12),
                      ],
                    ],
                  ),
                ),
    );
  }

  Widget _buildSubjectPicker() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final s in CriminologySubjects.all) ...[
            ChoiceChip(
              label: Text(s.shortName),
              selected: s.id == _subjectId,
              onSelected: (_) => setState(() => _subjectId = s.id),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Widget _buildSummary(TosSubject subject) {
    final p = context.palette;
    final text = context.textStyles;
    var active = 0, drafts = 0, covered = 0, total = 0;
    for (final t in subject.topics) {
      final row = _rows[t.code];
      active += row?.active ?? 0;
      drafts += row?.drafts ?? 0;
    }
    for (final c in subject.competencies) {
      total++;
      if ((_rows[c.code]?.active ?? 0) >= c.items) covered++;
    }
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(subject.name, style: text.titleMedium),
          const SizedBox(height: 4),
          Text(
            '${subject.weight}% of the examination · 100 items · ${subject.topics.length} topics · $total competencies',
            style: text.bodySmall,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Pill(label: '$active active questions', icon: Icons.check_circle_rounded, color: p.success),
              Pill(label: '$drafts drafts to review', icon: Icons.rate_review_rounded, color: p.warning),
              Pill(label: '$covered of $total competencies covered', icon: Icons.fact_check_rounded, color: p.primary),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'A competency is covered when its active questions reach the number of items the TOS gives it. '
            'Drafts include the 600 TOS questions written for faculty review; students see a question only after it is approved.',
            style: text.bodySmall?.copyWith(color: p.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildTopic(TosTopic topic) {
    final p = context.palette;
    final text = context.textStyles;
    final row = _rows[topic.code];
    final active = row?.active ?? 0;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(AppSpace.radiusSm),
            onTap: () => _openReview(topic.code),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Pill(label: topic.code, color: AppColors.subjectColor(topic.subjectId), fontSize: 10.5),
                    const SizedBox(width: 8),
                    Expanded(child: Text(topic.title, style: text.titleSmall)),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: AppProgressBar(
                        value: topic.items == 0 ? 0 : active / topic.items,
                        color: active >= topic.items ? p.success : p.primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text('$active / ${topic.items}', style: text.labelMedium),
                  ],
                ),
                if (topic.amendedBy != null) ...[
                  const SizedBox(height: 6),
                  Text('Amended by ${topic.amendedBy}', style: text.bodySmall?.copyWith(color: p.textSecondary)),
                ],
                const SizedBox(height: 6),
              ],
            ),
          ),
          Divider(color: p.border, height: 12),
          for (final c in topic.competencies) _buildCompetency(c),
        ],
      ),
    );
  }

  Widget _buildCompetency(TosCompetency c) {
    final p = context.palette;
    final text = context.textStyles;
    final row = _rows[c.code];
    final active = row?.active ?? 0;
    final drafts = row?.drafts ?? 0;
    final covered = active >= c.items;
    return InkWell(
      borderRadius: BorderRadius.circular(AppSpace.radiusSm),
      onTap: () => _openReview(c.code),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 40,
              child: Text(c.number, style: text.labelLarge?.copyWith(color: p.textSecondary)),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.text, maxLines: 3, overflow: TextOverflow.ellipsis, style: text.bodyMedium),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      Pill(
                        label: '$active / ${c.items} active',
                        icon: covered ? Icons.check_rounded : null,
                        color: covered ? p.success : p.textSecondary,
                        background: covered ? null : p.surfaceAlt,
                        fontSize: 10.5,
                      ),
                      if (drafts > 0)
                        Pill(label: '$drafts to review', color: p.warning, fontSize: 10.5),
                      Pill(
                        label: c.bloom.entries.map((e) => '${e.key.label} ${e.value}').join(' · '),
                        color: p.textSecondary,
                        background: p.surfaceAlt,
                        fontSize: 10.5,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: p.textTertiary),
          ],
        ),
      ),
    );
  }
}

/// The questions linked to one TOS topic or competency, for faculty review.
///
/// Drafts (inactive questions) can be ticked and approved together; any
/// question opens in the editor. The header shows what the TOS asks for:
/// the competency, its number of items and its Bloom levels.
class AdminTosReviewScreen extends StatefulWidget {
  /// A competency code (`CLJ-3.4`) or a topic code (`CLJ-3`, which also lists
  /// the questions of its competencies).
  final String tosCode;
  const AdminTosReviewScreen({super.key, required this.tosCode});

  @override
  State<AdminTosReviewScreen> createState() => _AdminTosReviewScreenState();
}

class _AdminTosReviewScreenState extends State<AdminTosReviewScreen> {
  static const int _limit = 200;

  final List<AdminQuestionEntry> _entries = [];
  final Set<String> _selected = {};
  bool _loading = true;
  bool _approving = false;
  String? _error;

  TosCatalog? get _tos => TosCatalog.loaded;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await AdminService.instance.listQuestions(tosCode: widget.tosCode, limit: _limit);
      // Drafts first, then by Bloom level as in the TOS columns.
      rows.sort((a, b) {
        if (a.isActive != b.isActive) return a.isActive ? 1 : -1;
        final ba = BloomLevel.tryParse(a.question.bloomLevel)?.index ?? 9;
        final bb = BloomLevel.tryParse(b.question.bloomLevel)?.index ?? 9;
        if (ba != bb) return ba.compareTo(bb);
        return a.question.id.compareTo(b.question.id);
      });
      if (!mounted) return;
      setState(() {
        _entries
          ..clear()
          ..addAll(rows);
        _selected.removeWhere((id) => !rows.any((e) => e.question.id == id && !e.isActive));
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

  List<AdminQuestionEntry> get _drafts => _entries.where((e) => !e.isActive).toList();

  Future<void> _approveSelected() async {
    final ids = _selected.toList();
    if (ids.isEmpty) return;
    final confirmed = await showConfirmDialog(
      context,
      title: 'Approve ${ids.length} question${ids.length == 1 ? '' : 's'}?',
      message: 'Approved questions go live for students on their next sync. '
          'Approve only questions you have checked against the current law and rules.',
      confirmLabel: 'Approve',
      icon: Icons.verified_rounded,
    );
    if (!confirmed) return;
    setState(() => _approving = true);
    try {
      final n = await AdminService.instance.setActiveMany(ids, true);
      if (!mounted) return;
      showAppSnack(context, '$n question${n == 1 ? '' : 's'} approved', tone: BannerTone.success);
      _selected.clear();
      await _reload();
    } catch (e) {
      if (!mounted) return;
      showAppSnack(context, friendlyError(e, fallback: 'Could not approve the questions.'), tone: BannerTone.danger);
    } finally {
      if (mounted) setState(() => _approving = false);
    }
  }

  Future<void> _openEditor(Question q) async {
    final saved = await Navigator.push<bool>(context, SlidePageRoute(page: AdminQuestionEditorScreen(existing: q)));
    if (saved == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final padding = Responsive.horizontalPadding(context);
    final competency = _tos?.competency(widget.tosCode);
    final topic = _tos?.topicOf(widget.tosCode);
    final drafts = _drafts;

    return Scaffold(
      appBar: AppTopBar(
        title: widget.tosCode,
        subtitle: competency == null ? (topic?.title ?? 'TOS review') : 'Competency ${competency.number}',
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const LoadingView(label: 'Loading questions...')
                : _error != null
                    ? Center(
                        child: EmptyState(
                          icon: Icons.error_outline_rounded,
                          title: "Couldn't load the questions",
                          message: _error,
                          actionLabel: 'Try again',
                          onAction: _reload,
                          color: context.palette.danger,
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _reload,
                        child: ListView(
                          padding: EdgeInsets.fromLTRB(padding, 4, padding, 24),
                          children: [
                            ContentWidth(maxWidth: 900, child: _buildHeader(competency, topic)),
                            const SizedBox(height: 14),
                            if (drafts.isNotEmpty)
                              ContentWidth(
                                maxWidth: 900,
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${drafts.length} draft${drafts.length == 1 ? '' : 's'} to review',
                                        style: context.textStyles.titleSmall,
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: () => setState(() {
                                        final all = drafts.map((e) => e.question.id).toSet();
                                        if (_selected.containsAll(all)) {
                                          _selected.clear();
                                        } else {
                                          _selected.addAll(all);
                                        }
                                      }),
                                      child: Text(
                                        _selected.length == drafts.length ? 'Clear selection' : 'Select all drafts',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            if (_entries.isEmpty)
                              const EmptyState(
                                icon: Icons.inbox_rounded,
                                title: 'No questions yet',
                                message: 'No question is linked to this part of the TOS. '
                                    'Write one in the editor, or generate drafts from a PDF.',
                              ),
                            for (final e in _entries)
                              ContentWidth(
                                maxWidth: 900,
                                child: Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: _buildQuestion(e),
                                ),
                              ),
                          ],
                        ),
                      ),
          ),
          if (drafts.isNotEmpty) _buildApproveBar(),
        ],
      ),
    );
  }

  Widget _buildHeader(TosCompetency? competency, TosTopic? topic) {
    final p = context.palette;
    final text = context.textStyles;
    final active = _entries.where((e) => e.isActive).length;
    final items = competency?.items ?? topic?.items ?? 0;
    final bloom = competency?.bloom ?? topic?.bloom ?? const <BloomLevel, int>{};
    final activeByBloom = <BloomLevel, int>{};
    for (final e in _entries.where((e) => e.isActive)) {
      final b = BloomLevel.tryParse(e.question.bloomLevel);
      if (b != null) activeByBloom[b] = (activeByBloom[b] ?? 0) + 1;
    }
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (topic != null) Text(topic.title.toUpperCase(), style: text.labelSmall),
          const SizedBox(height: 6),
          Text(competency?.text ?? topic?.title ?? widget.tosCode, style: text.titleSmall?.copyWith(height: 1.45)),
          const SizedBox(height: 12),
          Text('The TOS gives this $items item${items == 1 ? '' : 's'}; $active active now.', style: text.bodySmall),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final entry in bloom.entries)
                Pill(
                  label: '${entry.key.label}: ${activeByBloom[entry.key] ?? 0} / ${entry.value}',
                  color: (activeByBloom[entry.key] ?? 0) >= entry.value ? p.success : p.textSecondary,
                  background: (activeByBloom[entry.key] ?? 0) >= entry.value ? null : p.surfaceAlt,
                  fontSize: 10.5,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuestion(AdminQuestionEntry entry) {
    final p = context.palette;
    final text = context.textStyles;
    final q = entry.question;
    final selected = _selected.contains(q.id);
    return AppCard(
      onTap: () => _openEditor(q),
      padding: const EdgeInsets.fromLTRB(6, 10, 14, 14),
      borderColor: selected ? p.primary : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!entry.isActive)
            Checkbox(
              value: selected,
              onChanged: (v) => setState(() => v == true ? _selected.add(q.id) : _selected.remove(q.id)),
            )
          else
            Padding(
              padding: const EdgeInsets.all(12),
              child: Icon(Icons.check_circle_rounded, color: p.success, size: 22),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (q.tosCode != null) Pill(label: q.tosCode!, color: p.primary, fontSize: 10.5),
                    if (q.bloomLevel != null)
                      Pill(label: q.bloomLevel!, color: p.forDifficulty(q.difficulty.index), fontSize: 10.5),
                    Pill(
                      label: entry.isActive ? 'Active' : 'Draft',
                      color: entry.isActive ? p.success : p.warning,
                      fontSize: 10.5,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(q.questionText, style: text.titleSmall?.copyWith(height: 1.45)),
                const SizedBox(height: 8),
                for (var i = 0; i < q.answerOptions.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          i == q.correctAnswerIndex ? Icons.check_rounded : Icons.remove_rounded,
                          size: 16,
                          color: i == q.correctAnswerIndex ? p.success : p.textTertiary,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            q.answerOptions[i].text,
                            style: text.bodySmall?.copyWith(
                              color: i == q.correctAnswerIndex ? p.textPrimary : p.textSecondary,
                              fontWeight: i == q.correctAnswerIndex ? FontWeight.w700 : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if ((q.legalBasis ?? '').isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text('Basis: ${q.legalBasis}', style: text.bodySmall?.copyWith(color: p.textSecondary)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildApproveBar() {
    final p = context.palette;
    return Container(
      decoration: BoxDecoration(color: p.surface, border: Border(top: BorderSide(color: p.border))),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: ContentWidth(
            maxWidth: 900,
            child: PrimaryButton(
              label: _selected.isEmpty ? 'Tick drafts to approve' : 'Approve ${_selected.length} selected',
              icon: Icons.verified_rounded,
              loading: _approving,
              onPressed: _selected.isEmpty ? null : _approveSelected,
            ),
          ),
        ),
      ),
    );
  }
}
