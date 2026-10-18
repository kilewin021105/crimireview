import 'package:flutter/material.dart';

import '../../models/question.dart';
import '../../models/subject.dart';
import '../../services/admin_service.dart';
import '../../utils/error_messages.dart';
import '../../utils/page_transitions.dart';
import '../../utils/responsive.dart';
import '../../widgets/ui/ui.dart';
import 'admin_concepts_screen.dart';
import 'admin_question_editor_screen.dart';
import 'admin_template_generation_screen.dart';

/// The question bank the admin actually edits.
///
/// Panel note 7: *"Do NOT put your questions in your code. It should have an
/// ADMIN to add questions."* This screen, plus [AdminQuestionEditorScreen],
/// is that admin. Every row here is a live `public.questions` record --
/// deactivating or editing one is visible to students on their next sync
/// (`QuestionRepository.invalidate()` is called after every write).
class AdminQuestionsScreen extends StatefulWidget {
  /// False when this screen is a tab root inside `AdminShellScreen` (no
  /// previous route to pop back to).
  final bool showBackButton;

  /// Pre-seeds the source filter -- set by `AdminTemplateGenerationScreen`
  /// after a successful run to `QuestionSource.generated` so the admin
  /// lands directly on the AIG output instead of the full bank.
  final QuestionSource? initialSource;

  /// Pre-seeds the template filter, scoping the list to one template's batch
  /// (`template_id` on `public.questions` = the `question_templates.id` that
  /// produced it -- see `supabase_template_generation.sql`). Unlike
  /// [initialSource], this isn't user-togglable from the filter row: it's a
  /// deep link into one specific review batch.
  final String? initialTemplateId;

  const AdminQuestionsScreen({
    super.key,
    this.showBackButton = true,
    this.initialSource,
    this.initialTemplateId,
  });

  @override
  State<AdminQuestionsScreen> createState() => _AdminQuestionsScreenState();
}

class _AdminQuestionsScreenState extends State<AdminQuestionsScreen> {
  static const int _pageSize = 30;

  final TextEditingController _searchController = TextEditingController();
  String? _subjectId;
  Difficulty? _difficulty;
  bool _includeInactive = true;
  late QuestionSource? _source;

  final List<AdminQuestionEntry> _questions = [];

  /// Ids of generated questions the admin has ticked for approval. Only used
  /// while the list is showing generated questions ([_reviewMode]).
  final Set<String> _selected = {};
  bool _approving = false;

  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _source = widget.initialSource;
    _reload();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
      _questions.clear();
      _selected.clear();
      _hasMore = true;
    });
    try {
      final results = await AdminService.instance.listQuestions(
        subjectId: _subjectId,
        difficulty: _difficulty,
        includeInactive: _includeInactive,
        search: _searchController.text,
        source: _source,
        templateId: widget.initialTemplateId,
        limit: _pageSize,
        offset: 0,
      );
      if (!mounted) return;
      setState(() {
        _questions.addAll(results);
        _hasMore = results.length == _pageSize;
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

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final results = await AdminService.instance.listQuestions(
        subjectId: _subjectId,
        difficulty: _difficulty,
        includeInactive: _includeInactive,
        search: _searchController.text,
        source: _source,
        templateId: widget.initialTemplateId,
        limit: _pageSize,
        offset: _questions.length,
      );
      if (!mounted) return;
      setState(() {
        _questions.addAll(results);
        _hasMore = results.length == _pageSize;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      _showSnack(friendlyError(e, fallback: 'Could not load more questions.'), isError: true);
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    showAppSnack(context, message, tone: isError ? BannerTone.danger : BannerTone.success);
  }

  /// True while the list shows generated questions: the cards get a tick box
  /// and the approve bar appears.
  bool get _reviewMode => _source == QuestionSource.generated;

  /// Generated questions on screen that are still waiting for review.
  List<AdminQuestionEntry> get _pending => _questions
      .where((e) => !e.isActive && e.question.source == QuestionSource.generated)
      .toList();

  bool get _showApproveBar => _reviewMode && !_loading && _error == null && _pending.isNotEmpty;

  Future<void> _approveSelected() async {
    final ids = _selected.toList();
    if (ids.isEmpty || _approving) return;
    final many = ids.length != 1;
    final confirmed = await showConfirmDialog(
      context,
      title: 'Approve ${ids.length} question${many ? 's' : ''}?',
      message: 'Students will see ${many ? 'them' : 'it'} right away. '
          'Only approve questions you have read. You can deactivate any of them later.',
      confirmLabel: 'Approve',
      icon: Icons.verified_rounded,
    );
    if (!confirmed || !mounted) return;

    setState(() => _approving = true);
    try {
      final approved = await AdminService.instance.approveGenerated(ids);
      if (!mounted) return;
      _showSnack(approved == ids.length
          ? 'Approved $approved question${approved == 1 ? '' : 's'}'
          : 'Approved $approved of ${ids.length} (the rest were already active)');
    } catch (e) {
      if (!mounted) return;
      _showSnack(friendlyError(e, fallback: 'Could not approve the questions.'), isError: true);
    }
    if (!mounted) return;
    setState(() => _approving = false);
    _reload();
  }

  Future<void> _openEditor([Question? existing]) async {
    final saved = await Navigator.push<bool>(
      context,
      SlidePageRoute(page: AdminQuestionEditorScreen(existing: existing)),
    );
    if (saved == true) _reload();
  }

  Future<void> _toggleActive(AdminQuestionEntry entry) async {
    final goingActive = !entry.isActive;
    try {
      await AdminService.instance.setActive(entry.question.id, goingActive);
      _showSnack(goingActive ? 'Question restored' : 'Question deactivated');
      _reload();
    } catch (e) {
      _showSnack(friendlyError(e, fallback: 'Could not update the question.'), isError: true);
    }
  }

  Future<void> _confirmDelete(Question q) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete permanently?',
      message: 'This removes "${q.questionText}" from the database entirely. '
          'Prefer deactivating unless this was a mistake -- deactivated items '
          'can be restored, this cannot.',
      confirmLabel: 'Delete',
      destructive: true,
      icon: Icons.delete_forever_rounded,
    );
    if (!confirmed) return;
    try {
      await AdminService.instance.deleteQuestionPermanently(q.id);
      _showSnack('Question deleted');
      _reload();
    } catch (e) {
      _showSnack(friendlyError(e, fallback: 'Could not delete the question.'), isError: true);
    }
  }

  Subject? _subjectFor(String id) {
    for (final s in CriminologySubjects.all) {
      if (s.id == id) return s;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final padding = Responsive.horizontalPadding(context);

    return Scaffold(
      appBar: AppTopBar(
        title: widget.initialTemplateId != null ? 'Generated batch' : 'Question bank',
        subtitle: _loading
            ? 'Loading...'
            : '${_questions.length}${_hasMore ? '+' : ''} question${_questions.length == 1 ? '' : 's'} shown',
        showBack: widget.showBackButton,
        // Only on the tab-root instance -- a screen already deep-linked into
        // one template's review batch (widget.showBackButton == true) doesn't
        // need a second way to start another generation run.
        actions: widget.showBackButton
            ? null
            : [
                ToolbarIconButton(
                  icon: Icons.menu_book_rounded,
                  tooltip: 'Concepts',
                  size: 40,
                  onPressed: () => Navigator.push(
                    context,
                    SlidePageRoute(page: const AdminConceptsScreen()),
                  ),
                ),
                ToolbarIconButton(
                  icon: Icons.auto_fix_high_rounded,
                  tooltip: 'Generate from templates',
                  size: 40,
                  onPressed: () => Navigator.push(
                    context,
                    SlidePageRoute(page: const AdminTemplateGenerationScreen()),
                  ),
                ),
              ],
      ),
      floatingActionButton: _showApproveBar
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _openEditor(),
              icon: const Icon(Icons.add_rounded),
              label: const Text('New question'),
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
                ? const LoadingView(label: 'Loading questions...')
                : _error != null
                    ? Center(
                        child: EmptyState(
                          icon: Icons.error_outline_rounded,
                          title: "Couldn't load questions",
                          message: _error,
                          actionLabel: 'Try again',
                          onAction: _reload,
                          color: context.palette.danger,
                        ),
                      )
                    : _questions.isEmpty
                        ? Center(
                            child: EmptyState(
                              icon: Icons.inbox_rounded,
                              title: 'No questions found',
                              message: 'Nothing matches these filters. Try clearing the search or filters.',
                              actionLabel: 'New question',
                              onAction: () => _openEditor(),
                            ),
                          )
                        : NotificationListener<ScrollNotification>(
                            onNotification: (notification) {
                              if (notification.metrics.pixels >=
                                  notification.metrics.maxScrollExtent - 200) {
                                _loadMore();
                              }
                              return false;
                            },
                            child: RefreshIndicator(
                              onRefresh: _reload,
                              child: ListView.builder(
                                padding: EdgeInsets.fromLTRB(padding, 0, padding, 100),
                                itemCount: _questions.length + (_hasMore ? 1 : 0),
                                itemBuilder: (context, i) {
                                  if (i >= _questions.length) {
                                    return const Padding(
                                      padding: EdgeInsets.symmetric(vertical: 16),
                                      child: LoadingView(),
                                    );
                                  }
                                  return ContentWidth(
                                    maxWidth: 1000,
                                    child: Padding(
                                      padding: const EdgeInsets.only(bottom: 10),
                                      child: _buildQuestionCard(_questions[i]),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
          ),
          if (_showApproveBar) _buildApproveBar(),
        ],
      ),
    );
  }

  Widget _buildApproveBar() {
    final p = context.palette;
    final text = context.textStyles;
    final pending = _pending;
    final allSelected = pending.every((e) => _selected.contains(e.question.id));
    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(top: BorderSide(color: p.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: ContentWidth(
            maxWidth: 1000,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${pending.length} waiting for review', style: text.titleSmall),
                          Text(
                            _selected.isEmpty
                                ? 'Tick the questions you have read.'
                                : '${_selected.length} selected',
                            style: text.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: _approving
                          ? null
                          : () => setState(() {
                                if (allSelected) {
                                  _selected.clear();
                                } else {
                                  _selected.addAll(pending.map((e) => e.question.id));
                                }
                              }),
                      child: Text(allSelected ? 'Clear' : 'Select all'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                PrimaryButton(
                  label: _selected.isEmpty ? 'Approve selected' : 'Approve ${_selected.length}',
                  icon: Icons.verified_rounded,
                  height: 46,
                  loading: _approving,
                  onPressed: _selected.isEmpty || _approving ? null : _approveSelected,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFilters() {
    final p = context.palette;
    final subject = _subjectId == null ? null : _subjectFor(_subjectId!);
    return Column(
      children: [
        TextField(
          controller: _searchController,
          onSubmitted: (_) => _reload(),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Search question text or topic',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: IconButton(
              tooltip: 'Search',
              icon: const Icon(Icons.arrow_forward_rounded),
              onPressed: _reload,
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _MenuChip<String?>(
                icon: Icons.category_rounded,
                label: subject?.shortName ?? 'All subjects',
                active: _subjectId != null,
                options: [
                  const (null, 'All subjects'),
                  for (final s in CriminologySubjects.all) (s.id, s.shortName),
                ],
                onSelected: (v) {
                  setState(() => _subjectId = v);
                  _reload();
                },
              ),
              const SizedBox(width: 8),
              _MenuChip<Difficulty?>(
                icon: Icons.signal_cellular_alt_rounded,
                label: _difficulty == null
                    ? 'All difficulties'
                    : _difficulty!.name[0].toUpperCase() + _difficulty!.name.substring(1),
                active: _difficulty != null,
                options: [
                  const (null, 'All difficulties'),
                  for (final d in Difficulty.values) (d, d.name[0].toUpperCase() + d.name.substring(1)),
                ],
                onSelected: (v) {
                  setState(() => _difficulty = v);
                  _reload();
                },
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('Inactive'),
                selected: _includeInactive,
                onSelected: (v) {
                  setState(() => _includeInactive = v);
                  _reload();
                },
              ),
              // Only offered when the screen wasn't already deep-linked into
              // one upload's batch (widget.initialTemplateId) -- that case
              // is already scoped tighter than this chip would express.
              if (widget.initialTemplateId == null) ...[
                const SizedBox(width: 8),
                FilterChip(
                  avatar: Icon(Icons.auto_awesome_rounded, size: 16, color: p.textSecondary),
                  label: const Text('Generated only'),
                  selected: _source == QuestionSource.generated,
                  onSelected: (v) {
                    setState(() => _source = v ? QuestionSource.generated : null);
                    _reload();
                  },
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildQuestionCard(AdminQuestionEntry entry) {
    final p = context.palette;
    final text = context.textStyles;
    final q = entry.question;
    final subject = _subjectFor(q.subject);
    final subjectColor = AppColors.subjectColor(q.subject);

    return Opacity(
      opacity: entry.isActive ? 1 : 0.72,
      child: AppCard(
        onTap: () => _openEditor(q),
        padding: const EdgeInsets.fromLTRB(14, 12, 4, 14),
        borderColor: entry.isActive ? null : p.danger.withValues(alpha: 0.4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (_reviewMode && !entry.isActive && q.source == QuestionSource.generated)
                  Checkbox(
                    value: _selected.contains(q.id),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onChanged: _approving
                        ? null
                        : (v) => setState(() {
                              if (v == true) {
                                _selected.add(q.id);
                              } else {
                                _selected.remove(q.id);
                              }
                            }),
                  ),
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      Pill(
                        label: subject?.shortName ?? q.subject.replaceAll('_', ' '),
                        color: subjectColor,
                        fontSize: 10.5,
                      ),
                      Pill(
                        label: q.difficulty.name[0].toUpperCase() + q.difficulty.name.substring(1),
                        color: p.forDifficulty(q.difficulty.index),
                        fontSize: 10.5,
                      ),
                      if (q.source != QuestionSource.admin)
                        Pill(
                          label: q.source.name,
                          icon: Icons.auto_awesome_rounded,
                          color: const Color(0xFFE3478C),
                          fontSize: 10.5,
                        ),
                      if (!entry.isActive)
                        Pill(label: 'Inactive', icon: Icons.visibility_off_rounded, color: p.danger, fontSize: 10.5),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Actions',
                  icon: Icon(Icons.more_horiz_rounded, size: 22, color: p.textSecondary),
                  onSelected: (action) {
                    switch (action) {
                      case 'edit':
                        _openEditor(q);
                        break;
                      case 'deactivate':
                        _toggleActive(entry);
                        break;
                      case 'delete':
                        _confirmDelete(q);
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: ListTile(leading: Icon(Icons.edit_rounded), title: Text('Edit'), dense: true),
                    ),
                    PopupMenuItem(
                      value: 'deactivate',
                      child: ListTile(
                        leading: Icon(entry.isActive ? Icons.visibility_off_rounded : Icons.restore_rounded),
                        title: Text(entry.isActive ? 'Deactivate' : 'Restore'),
                        dense: true,
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: ListTile(
                        leading: Icon(Icons.delete_outline_rounded, color: p.danger),
                        title: Text('Delete permanently', style: TextStyle(color: p.danger)),
                        dense: true,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 6),
                  Text(q.topic.toUpperCase(), style: text.labelSmall),
                  const SizedBox(height: 4),
                  Text(
                    q.questionText,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleSmall?.copyWith(height: 1.45),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.list_rounded, size: 15, color: p.textTertiary),
                      const SizedBox(width: 4),
                      Text('${q.answerOptions.length} options', style: text.bodySmall),
                      const SizedBox(width: 12),
                      Icon(Icons.history_rounded, size: 15, color: p.textTertiary),
                      const SizedBox(width: 4),
                      Text('v${q.version}', style: text.bodySmall),
                      if (q.hasRationales) ...[
                        const SizedBox(width: 12),
                        Icon(Icons.check_circle_rounded, size: 15, color: p.success),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            'Rationales',
                            style: text.bodySmall?.copyWith(color: p.success),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A filter chip that opens a menu of choices.
class _MenuChip<T> extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final List<(T, String)> options;
  final ValueChanged<T> onSelected;

  const _MenuChip({
    required this.icon,
    required this.label,
    required this.active,
    required this.options,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = context.textStyles;
    final fg = active ? p.onPrimarySoft : p.textPrimary;
    return PopupMenuButton<int>(
      tooltip: label,
      onSelected: (i) => onSelected(options[i].$1),
      itemBuilder: (context) => [
        for (var i = 0; i < options.length; i++)
          PopupMenuItem(value: i, child: Text(options[i].$2)),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: active ? p.primarySoft : p.surfaceAlt,
          borderRadius: BorderRadius.circular(AppSpace.radiusSm),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: active ? p.primary : p.textSecondary),
            const SizedBox(width: 6),
            Text(label, style: text.labelMedium?.copyWith(color: fg)),
            const SizedBox(width: 2),
            Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: fg),
          ],
        ),
      ),
    );
  }
}
