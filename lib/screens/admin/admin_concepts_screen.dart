import 'package:flutter/material.dart';

import '../../models/concept.dart';
import '../../models/subject.dart';
import '../../services/concept_service.dart';
import '../../utils/concept_rules.dart';
import '../../utils/error_messages.dart';
import '../../utils/page_transitions.dart';
import '../../utils/responsive.dart';
import '../../widgets/ui/ui.dart';
import 'admin_concept_csv_import_screen.dart';
import 'admin_concept_editor_screen.dart';
import 'admin_concept_import_screen.dart';

/// The concept bank: the terms and meanings that question templates turn into
/// questions (Automatic Item Generation, panel note 1).
///
/// Before this screen, concepts could only be added with SQL, so Faculty could
/// not feed the generator. Every change here goes through a database function
/// that checks the caller is an admin and writes the audit log.
class AdminConceptsScreen extends StatefulWidget {
  const AdminConceptsScreen({super.key});

  @override
  State<AdminConceptsScreen> createState() => _AdminConceptsScreenState();
}

class _AdminConceptsScreenState extends State<AdminConceptsScreen> {
  final TextEditingController _search = TextEditingController();
  String? _subjectId;
  bool _showInactive = true;

  List<Concept> _concepts = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await ConceptService.instance.listConcepts();
      if (!mounted) return;
      setState(() {
        _concepts = list;
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

  void _snack(String message, {bool isError = false}) {
    if (!mounted) return;
    showAppSnack(context, message, tone: isError ? BannerTone.danger : BannerTone.success);
  }

  Future<void> _openEditor({Concept? existing, String? subjectId, String? topic}) async {
    final saved = await Navigator.push<bool>(
      context,
      SlidePageRoute(
        page: AdminConceptEditorScreen(
          existing: existing,
          concepts: _concepts,
          presetSubjectId: subjectId ?? _subjectId,
          presetTopic: topic,
        ),
      ),
    );
    if (saved == true) _load();
  }

  Future<void> _openImport({String? subjectId, String? topic}) async {
    final changed = await Navigator.push<bool>(
      context,
      SlidePageRoute(
        page: AdminConceptImportScreen(
          concepts: _concepts,
          presetSubjectId: subjectId ?? _subjectId,
          presetTopic: topic,
        ),
      ),
    );
    if (changed == true) _load();
  }

  Future<void> _openCsvImport() async {
    final changed = await Navigator.push<bool>(
      context,
      SlidePageRoute(page: AdminConceptCsvImportScreen(concepts: _concepts)),
    );
    if (changed == true) _load();
  }

  Future<void> _toggleActive(Concept c) async {
    final goingActive = !c.isActive;
    if (!goingActive) {
      final ok = await showConfirmDialog(
        context,
        title: 'Deactivate this concept?',
        message: '"${c.term}" will stop making new questions and stop being used as a wrong answer. '
            'Questions already made from it are kept. You can restore it later.',
        confirmLabel: 'Deactivate',
        icon: Icons.visibility_off_rounded,
      );
      if (!ok) return;
    }
    final result = await ConceptService.instance.setActive(c.id, goingActive);
    if (!mounted) return;
    if (result.success) {
      _snack(goingActive ? 'Concept restored' : 'Concept deactivated');
      _load();
    } else {
      _snack(result.error ?? 'Could not update the concept.', isError: true);
    }
  }

  List<Concept> get _filtered {
    final q = _search.text.trim().toLowerCase();
    return _concepts.where((c) {
      if (_subjectId != null && c.subjectId != _subjectId) return false;
      if (!_showInactive && !c.isActive) return false;
      if (q.isEmpty) return true;
      return c.term.toLowerCase().contains(q) ||
          c.topic.toLowerCase().contains(q) ||
          (c.legalBasis ?? '').toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final padding = Responsive.horizontalPadding(context);
    final active = _concepts.where((c) => c.isActive).length;
    final topics = {for (final c in _concepts) '${c.subjectId}::${c.topic}'}.length;

    return Scaffold(
      appBar: AppTopBar(
        title: 'Concepts',
        subtitle: _loading ? 'Loading...' : '$active active · $topics topic${topics == 1 ? '' : 's'}',
        actions: [
          ToolbarIconButton(
            icon: Icons.upload_file_rounded,
            tooltip: 'Upload a CSV file (many topics)',
            size: 40,
            onPressed: _loading || _error != null ? null : _openCsvImport,
          ),
          const SizedBox(width: 8),
          ToolbarIconButton(
            icon: Icons.content_paste_rounded,
            tooltip: 'Paste rows (one topic)',
            size: 40,
            onPressed: _loading ? null : () => _openImport(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading ? null : () => _openEditor(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New concept'),
      ),
      body: _loading
          ? const LoadingView(label: 'Loading concepts...')
          : _error != null
              ? Center(
                  child: EmptyState(
                    icon: Icons.error_outline_rounded,
                    title: "Couldn't load concepts",
                    message: _error,
                    actionLabel: 'Try again',
                    onAction: _load,
                    color: context.palette.danger,
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _buildList(padding),
                ),
    );
  }

  Widget _buildList(double padding) {
    final text = context.textStyles;
    final filtered = _filtered;

    // subject -> topic -> concepts, in the order the subjects are listed.
    final bySubject = <String, Map<String, List<Concept>>>{};
    for (final c in filtered) {
      bySubject.putIfAbsent(c.subjectId, () => {}).putIfAbsent(c.topic, () => []).add(c);
    }
    final subjectOrder = [
      for (final s in CriminologySubjects.all)
        if (bySubject.containsKey(s.id)) s.id,
      ...bySubject.keys.where((id) => !CriminologySubjects.all.any((s) => s.id == id)),
    ];

    final children = <Widget>[
      ContentWidth(
        maxWidth: 900,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const InlineBanner(
              tone: BannerTone.info,
              icon: Icons.auto_fix_high_rounded,
              title: 'How concepts become questions',
              message: 'Each concept can become up to 4 questions to review. '
                  'A group needs at least 3 concepts, because the other concepts become the wrong answers.',
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                hintText: 'Search term, topic or legal basis',
                prefixIcon: Icon(Icons.search_rounded),
                contentPadding: EdgeInsets.symmetric(vertical: 12),
              ),
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ChoiceChip(
                    label: const Text('All subjects'),
                    selected: _subjectId == null,
                    onSelected: (_) => setState(() => _subjectId = null),
                  ),
                  for (final s in CriminologySubjects.all) ...[
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: Text(s.shortName),
                      selected: _subjectId == s.id,
                      onSelected: (_) => setState(() => _subjectId = s.id),
                    ),
                  ],
                  const SizedBox(width: 8),
                  FilterChip(
                    label: const Text('Inactive'),
                    selected: _showInactive,
                    onSelected: (v) => setState(() => _showInactive = v),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],
        ),
      ),
    ];

    if (_concepts.isEmpty) {
      children.add(EmptyState(
        icon: Icons.menu_book_rounded,
        title: 'No concepts yet',
        message: 'Add a term and its meaning, or paste many rows from Excel or Word.',
        actionLabel: 'New concept',
        onAction: () => _openEditor(),
      ));
    } else if (filtered.isEmpty) {
      children.add(const EmptyState(
        icon: Icons.search_off_rounded,
        title: 'Nothing matches',
        message: 'Try clearing the search or the filters.',
        compact: true,
      ));
    }

    var index = 0;
    for (final subjectId in subjectOrder) {
      final subject = CriminologySubjects.all.where((s) => s.id == subjectId).firstOrNull;
      final topicMap = bySubject[subjectId]!;
      final topicNames = topicMap.keys.toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      children.add(ContentWidth(
        maxWidth: 900,
        child: Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 10),
          child: Row(
            children: [
              IconBadge(
                icon: AppTheme.subjectIcons[subjectId] ?? subject?.icon ?? Icons.folder_rounded,
                color: AppColors.subjectColor(subjectId),
                size: 30,
                iconSize: 16,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(subject?.name ?? subjectId, style: text.titleSmall),
              ),
            ],
          ),
        ),
      ));
      for (final topic in topicNames) {
        children.add(ContentWidth(
          maxWidth: 900,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Appear(
              index: index++,
              child: _buildTopicCard(subjectId, topic, topicMap[topic]!),
            ),
          ),
        ));
      }
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(padding, 4, padding, 100),
      children: children,
    );
  }

  Widget _buildTopicCard(String subjectId, String topic, List<Concept> concepts) {
    final p = context.palette;
    final text = context.textStyles;
    // Readiness is judged on the whole topic, not on what the filter shows.
    final whole = _concepts.where((c) => c.subjectId == subjectId && c.topic == topic);
    final ready = topicReadiness(whole);
    final sorted = [...concepts]..sort((a, b) => a.term.toLowerCase().compareTo(b.term.toLowerCase()));

    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 6, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(topic, style: text.titleMedium),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          Pill(
                            label: '${ready.active} active',
                            color: p.textSecondary,
                            fontSize: 10.5,
                          ),
                          if (ready.canMakeQuestions)
                            Pill(
                              label: 'Ready for questions',
                              icon: Icons.check_circle_rounded,
                              color: p.success,
                              fontSize: 10.5,
                            )
                          else
                            Pill(
                              label: 'Needs $kMinConceptsPerGroup or more',
                              icon: Icons.info_outline_rounded,
                              color: p.warning,
                              fontSize: 10.5,
                            ),
                          if (ready.canMakeQuestions)
                            Pill(
                              label: ready.basisFormsReady ? 'Legal-basis forms on' : 'Legal-basis forms off',
                              icon: Icons.gavel_rounded,
                              color: ready.basisFormsReady ? p.info : p.textTertiary,
                              fontSize: 10.5,
                            ),
                        ],
                      ),
                      if (ready.canMakeQuestions && !ready.basisFormsReady) ...[
                        const SizedBox(height: 6),
                        Text(
                          'To turn the legal-basis forms on, give every concept its own legal basis.',
                          style: text.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Topic actions',
                  icon: Icon(Icons.more_horiz_rounded, size: 22, color: p.textSecondary),
                  onSelected: (v) {
                    if (v == 'add') _openEditor(subjectId: subjectId, topic: topic);
                    if (v == 'import') _openImport(subjectId: subjectId, topic: topic);
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'add',
                      child: ListTile(leading: Icon(Icons.add_rounded), title: Text('Add a concept here'), dense: true),
                    ),
                    PopupMenuItem(
                      value: 'import',
                      child: ListTile(
                          leading: Icon(Icons.content_paste_rounded), title: Text('Import many here'), dense: true),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          for (var i = 0; i < sorted.length; i++) ...[
            Divider(height: 1, color: p.border),
            _buildConceptRow(sorted[i]),
          ],
        ],
      ),
    );
  }

  Widget _buildConceptRow(Concept c) {
    final p = context.palette;
    final text = context.textStyles;
    return Opacity(
      opacity: c.isActive ? 1 : 0.6,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpace.radiusSm),
        onTap: () => _openEditor(existing: c),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 10, 0, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.term, style: text.titleSmall),
                    const SizedBox(height: 2),
                    Text(c.definition, style: text.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                    if (c.legalBasis != null || !c.isActive) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (c.legalBasis != null)
                            Pill(label: c.legalBasis!, icon: Icons.gavel_rounded, color: p.info, fontSize: 10.5),
                          if (!c.isActive)
                            Pill(
                              label: 'Inactive',
                              icon: Icons.visibility_off_rounded,
                              color: p.textTertiary,
                              fontSize: 10.5,
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Actions',
                icon: Icon(Icons.more_vert_rounded, size: 20, color: p.textTertiary),
                onSelected: (v) {
                  if (v == 'edit') _openEditor(existing: c);
                  if (v == 'toggle') _toggleActive(c);
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: ListTile(leading: Icon(Icons.edit_rounded), title: Text('Edit'), dense: true),
                  ),
                  PopupMenuItem(
                    value: 'toggle',
                    child: ListTile(
                      leading: Icon(c.isActive ? Icons.visibility_off_rounded : Icons.restore_rounded),
                      title: Text(c.isActive ? 'Deactivate' : 'Restore'),
                      dense: true,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
