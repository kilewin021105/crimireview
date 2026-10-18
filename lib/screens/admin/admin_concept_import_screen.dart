import 'package:flutter/material.dart';

import '../../models/concept.dart';
import '../../models/subject.dart';
import '../../services/concept_service.dart';
import '../../utils/concept_import_parser.dart';
import '../../utils/concept_rules.dart';
import '../../utils/responsive.dart';
import '../../widgets/ui/ui.dart';
import 'concept_subject_topic_fields.dart';

/// Add many concepts to one topic in one go, by pasting rows copied from
/// Excel or Word (term, definition, legal basis).
///
/// The text is checked on the phone first and the result is shown before
/// anything is sent. The database then checks again and reports any row it
/// cannot save (for example a term the topic already has).
class AdminConceptImportScreen extends StatefulWidget {
  /// Every concept, used to suggest topics and to find a topic's groups.
  final List<Concept> concepts;
  final String? presetSubjectId;
  final String? presetTopic;

  /// Pre-fills the text box (used by the screenshot tests).
  @visibleForTesting
  final String? initialText;

  const AdminConceptImportScreen({
    super.key,
    this.concepts = const [],
    this.presetSubjectId,
    this.presetTopic,
    this.initialText,
  });

  @override
  State<AdminConceptImportScreen> createState() => _AdminConceptImportScreenState();
}

class _AdminConceptImportScreenState extends State<AdminConceptImportScreen> {
  static const int _maxProblemsShown = 6;

  late final TextEditingController _paste;
  late String _subjectId;
  late String _topic;
  String? _group;
  late ConceptImportParse _parsed;

  bool _importing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _paste = TextEditingController(text: widget.initialText ?? '');
    _subjectId = widget.presetSubjectId ?? CriminologySubjects.all.first.id;
    _topic = widget.presetTopic ?? '';
    _parsed = parseConceptImport(_paste.text);
  }

  @override
  void dispose() {
    _paste.dispose();
    super.dispose();
  }

  List<String> get _groups => conceptGroupsFor(widget.concepts, _subjectId, _topic);

  bool get _needsGroup => _groups.length > 1 && _group == null;

  bool get _canImport =>
      !_importing &&
      _parsed.rows.isNotEmpty &&
      !_parsed.tooMany &&
      _topic.trim().isNotEmpty &&
      !_needsGroup;

  Future<void> _import() async {
    setState(() {
      _importing = true;
      _error = null;
    });
    final rows = _parsed.rows;
    final result = await ConceptService.instance.importConcepts(
      subjectId: _subjectId,
      topic: _topic,
      siblingGroup: _group,
      rows: rows,
    );
    if (!mounted) return;

    if (!result.success) {
      setState(() {
        _importing = false;
        _error = result.error ?? 'Could not import the concepts.';
      });
      return;
    }

    if (result.rejected.isEmpty) {
      showAppSnack(
        context,
        '${result.inserted} concept${result.inserted == 1 ? '' : 's'} added',
        tone: BannerTone.success,
      );
      Navigator.pop(context, true);
      return;
    }

    // Some rows were refused: say which, using the original line numbers.
    await showDialog<void>(
      context: context,
      builder: (ctx) => _ResultDialog(
        inserted: result.inserted,
        rejected: [
          for (final r in result.rejected)
            (
              r.row >= 1 && r.row <= rows.length ? rows[r.row - 1].line : 0,
              r.term,
              r.reason,
            ),
        ],
      ),
    );
    if (!mounted) return;
    if (result.inserted > 0) {
      Navigator.pop(context, true);
    } else {
      setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = context.textStyles;
    final padding = Responsive.horizontalPadding(context);
    final groups = _groups;
    final count = _parsed.rows.length;

    return Scaffold(
      appBar: const AppTopBar(
        title: 'Import concepts',
        subtitle: 'Paste rows from Excel or Word',
        backIcon: Icons.close_rounded,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(padding, 4, padding, 32),
              children: [
                ContentWidth(
                  maxWidth: 760,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_error != null) ...[
                        InlineBanner(tone: BannerTone.danger, message: _error!),
                        const SizedBox(height: 14),
                      ],
                      AppCard(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text('1. Where they belong', style: text.titleMedium),
                            const SizedBox(height: 14),
                            ConceptSubjectTopicFields(
                              subjectId: _subjectId,
                              topic: _topic,
                              concepts: widget.concepts,
                              enabled: !_importing,
                              onSubjectChanged: (v) => setState(() {
                                _subjectId = v;
                                _group = null;
                              }),
                              onTopicChanged: (v) => setState(() {
                                _topic = v;
                                _group = null;
                              }),
                            ),
                            if (groups.length > 1) ...[
                              const SizedBox(height: 16),
                              Padding(
                                padding: const EdgeInsets.only(left: 2, bottom: 7),
                                child: Text('Group', style: text.labelMedium?.copyWith(color: p.textPrimary)),
                              ),
                              DropdownButtonFormField<String>(
                                key: ValueKey('group-$_subjectId-$_topic'),
                                initialValue: _group,
                                isExpanded: true,
                                hint: const Text('Choose a group'),
                                icon: const Icon(Icons.keyboard_arrow_down_rounded),
                                borderRadius: BorderRadius.circular(AppSpace.radiusMd),
                                items: [for (final g in groups) DropdownMenuItem(value: g, child: Text(g))],
                                onChanged: _importing ? null : (v) => setState(() => _group = v),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      AppCard(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text('2. Paste the rows', style: text.titleMedium),
                            const SizedBox(height: 6),
                            Text(
                              'One concept per line with three columns: term, definition, legal basis (optional). '
                              'Copy the cells from Excel or Word, or separate the columns with the | sign.',
                              style: text.bodySmall,
                            ),
                            const SizedBox(height: 14),
                            TextField(
                              controller: _paste,
                              enabled: !_importing,
                              minLines: 8,
                              maxLines: 14,
                              keyboardType: TextInputType.multiline,
                              style: text.bodyMedium,
                              decoration: const InputDecoration(
                                hintText: 'Parole | The conditional release of a prisoner… | Act 4103, Sec. 5\n'
                                    'Pardon | An act of grace by the Chief Executive… | Const. Art. VII, Sec. 19',
                              ),
                              onChanged: (v) => setState(() => _parsed = parseConceptImport(v)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      _buildPreview(),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: p.surface,
              border: Border(top: BorderSide(color: p.border)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: ContentWidth(
                  maxWidth: 760,
                  child: Row(
                    children: [
                      Expanded(
                        child: SecondaryButton(
                          label: 'Cancel',
                          onPressed: _importing ? null : () => Navigator.pop(context),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: PrimaryButton(
                          label: count == 0 ? 'Import' : 'Import $count',
                          icon: Icons.file_download_done_rounded,
                          loading: _importing,
                          onPressed: _canImport ? _import : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    final p = context.palette;
    final text = context.textStyles;
    final rows = _parsed.rows;
    final problems = _parsed.problems;

    if (rows.isEmpty && problems.isEmpty) {
      return const InlineBanner(
        tone: BannerTone.info,
        message: 'Nothing to check yet. Paste your rows above.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (rows.isNotEmpty)
          InlineBanner(
            tone: _parsed.tooMany ? BannerTone.danger : BannerTone.success,
            title: _parsed.tooMany
                ? 'Too many concepts'
                : '${rows.length} concept${rows.length == 1 ? '' : 's'} ready',
            message: _parsed.tooMany
                ? 'Import at most $kConceptMaxImportRows at a time. This has ${rows.length}.'
                : 'Check the first ones below, then press Import.',
          ),
        if (problems.isNotEmpty) ...[
          if (rows.isNotEmpty) const SizedBox(height: 10),
          InlineBanner(
            tone: BannerTone.warning,
            title: '${problems.length} line${problems.length == 1 ? '' : 's'} will be skipped',
            message: [
              for (final pr in problems.take(_maxProblemsShown)) pr.toString(),
              if (problems.length > _maxProblemsShown) '…and ${problems.length - _maxProblemsShown} more.',
            ].join('\n'),
          ),
        ],
        if (rows.isNotEmpty) ...[
          const SizedBox(height: 10),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                for (var i = 0; i < rows.length && i < 4; i++) ...[
                  if (i > 0) Divider(height: 1, color: p.border),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(rows[i].term, style: text.titleSmall),
                        const SizedBox(height: 2),
                        Text(rows[i].definition, style: text.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                        if (rows[i].legalBasis != null) ...[
                          const SizedBox(height: 6),
                          Pill(label: rows[i].legalBasis!, icon: Icons.gavel_rounded, color: p.info, fontSize: 10.5),
                        ],
                      ],
                    ),
                  ),
                ],
                if (rows.length > 4)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                    child: Text('…and ${rows.length - 4} more', style: text.bodySmall),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Shown when the database refused some rows: what was saved, and which
/// lines were not, with the reason for each.
class _ResultDialog extends StatelessWidget {
  final int inserted;
  final List<(int line, String term, String reason)> rejected;

  const _ResultDialog({required this.inserted, required this.rejected});

  @override
  Widget build(BuildContext context) {
    final text = context.textStyles;
    final p = context.palette;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconBadge(
              icon: inserted > 0 ? Icons.rule_rounded : Icons.error_outline_rounded,
              color: inserted > 0 ? p.warning : p.danger,
              size: 46,
            ),
            const SizedBox(height: 16),
            Text(
              inserted > 0
                  ? '$inserted added, ${rejected.length} skipped'
                  : 'Nothing was added',
              style: text.titleLarge,
            ),
            const SizedBox(height: 6),
            Text('These lines could not be saved:', style: text.bodyMedium),
            const SizedBox(height: 10),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final r in rejected)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          '${r.$1 > 0 ? 'Line ${r.$1}' : 'A line'}${r.$2.isEmpty ? '' : ' (${r.$2})'}: ${r.$3}',
                          style: text.bodySmall?.copyWith(color: p.textPrimary),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            PrimaryButton(label: 'OK', height: 48, onPressed: () => Navigator.of(context).pop()),
          ],
        ),
      ),
    );
  }
}
