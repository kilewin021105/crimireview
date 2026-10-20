import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/concept.dart';
import '../../models/subject.dart';
import '../../services/concept_service.dart';
import '../../utils/concept_csv.dart';
import '../../utils/concept_rules.dart';
import '../../utils/page_transitions.dart';
import '../../utils/responsive.dart';
import '../../widgets/ui/ui.dart';
import 'admin_template_generation_screen.dart';

/// Upload a CSV file of concepts for many topics at once.
///
/// The file names the subject and topic of every concept, so Faculty can keep
/// their whole concept bank in Excel or Google Sheets. A topic that does not
/// exist yet is created on import, with its four question forms. Everything
/// is checked on the phone first and shown before anything is sent; the
/// database checks again (`admin_import_concepts`).
class AdminConceptCsvImportScreen extends StatefulWidget {
  /// Every concept in the bank (active and inactive), to spot duplicates and
  /// tell new topics from existing ones.
  final List<Concept> concepts;

  /// A file's text to start with (used by the screenshot tests).
  @visibleForTesting
  final String? initialCsvText;

  @visibleForTesting
  final String? initialFileName;

  const AdminConceptCsvImportScreen({
    super.key,
    this.concepts = const [],
    this.initialCsvText,
    this.initialFileName,
  });

  @override
  State<AdminConceptCsvImportScreen> createState() => _AdminConceptCsvImportScreenState();
}

class _AdminConceptCsvImportScreenState extends State<AdminConceptCsvImportScreen> {
  static const int _maxProblemsShown = 6;
  static const int _maxTopicsShown = 30;

  String? _fileName;
  ConceptCsvPlan? _plan;
  bool _picking = false;
  bool _importing = false;
  int _done = 0;
  int _total = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    final text = widget.initialCsvText;
    if (text != null) {
      _fileName = widget.initialFileName ?? 'concepts.csv';
      _plan = planConceptCsv(text, existing: widget.concepts);
    }
  }

  Future<void> _shareTemplate() async {
    try {
      await SharePlus.instance.share(ShareParams(
        files: [
          XFile.fromData(conceptCsvTemplateBytes(), mimeType: 'text/csv', name: kConceptCsvTemplateName),
        ],
        fileNameOverrides: const [kConceptCsvTemplateName],
        subject: 'CrimiReview concepts template',
      ));
    } catch (_) {
      if (!mounted) return;
      showAppSnack(
        context,
        "Couldn't share the template. Make a sheet whose first row is: ${kConceptCsvColumns.join(', ')}",
        tone: BannerTone.danger,
      );
    }
  }

  Future<void> _pickFile() async {
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      // Any file type: some phones do not label .csv files, and a filter
      // would grey them out. The name and contents are checked below.
      final result = await FilePicker.pickFiles(type: FileType.any, withData: true);
      if (!mounted) return;
      if (result == null || result.files.isEmpty) {
        setState(() => _picking = false);
        return;
      }
      final file = result.files.single;
      final name = file.name;
      final lower = name.toLowerCase();
      String? problem;
      if (!lower.endsWith('.csv') && !lower.endsWith('.txt')) {
        problem = '"$name" is not a CSV file. In Excel use File › Save As › CSV UTF-8; '
            'in Google Sheets use File › Download › Comma-separated values (.csv).';
      } else if (file.size > kConceptCsvMaxBytes) {
        problem = 'The file is too big (2 MB at most). Split it into smaller files.';
      } else if (file.bytes == null) {
        problem = "Couldn't read that file. Save it again, or choose another one.";
      }
      if (problem != null) {
        setState(() {
          _picking = false;
          _error = problem;
        });
        return;
      }
      final text = decodeConceptCsv(file.bytes!);
      setState(() {
        _picking = false;
        _fileName = name;
        _plan = planConceptCsv(text, existing: widget.concepts);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _picking = false;
        _error = "Couldn't open that file. Please try again.";
      });
    }
  }

  Future<void> _import() async {
    final plan = _plan;
    if (plan == null || !plan.canImport || _importing) return;
    setState(() {
      _importing = true;
      _error = null;
      _done = 0;
      _total = 0;
    });

    final report = await ConceptService.instance.importCsvPlan(
      plan,
      onProgress: (done, total) {
        if (mounted) {
          setState(() {
            _done = done;
            _total = total;
          });
        }
      },
    );
    if (!mounted) return;
    setState(() => _importing = false);

    final newTopics = plan.topics
        .where((t) => t.isNew && report.topicsUpdated.contains('${t.subjectId}::${t.topic.toLowerCase()}'))
        .length;
    final action = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _CsvResultDialog(report: report, newTopics: newTopics),
    );
    if (!mounted) return;
    if (action == 'generate') {
      Navigator.pushReplacement(
        context,
        SlidePageRoute(page: const AdminTemplateGenerationScreen()),
        result: report.inserted > 0,
      );
    } else if (report.inserted > 0) {
      Navigator.pop(context, true);
    }
    // Nothing was saved: stay, so the file can be fixed and chosen again.
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final padding = Responsive.horizontalPadding(context);
    final plan = _plan;
    final count = plan?.conceptCount ?? 0;
    final busy = _importing || _picking;

    return Scaffold(
      appBar: const AppTopBar(
        title: 'Upload a CSV file',
        subtitle: 'Concepts for many topics at once',
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
                      _buildFormatCard(),
                      const SizedBox(height: 14),
                      _buildFileCard(busy),
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
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_importing) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: _total == 0 ? null : _done / _total,
                            minHeight: 6,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _total == 0
                              ? 'Saving…'
                              : 'Saving part ${(_done + 1).clamp(1, _total)} of $_total…',
                          style: context.textStyles.bodySmall,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 10),
                      ],
                      Row(
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
                              onPressed: plan != null && plan.canImport && !busy ? _import : null,
                            ),
                          ),
                        ],
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

  Widget _buildFormatCard() {
    final p = context.palette;
    final text = context.textStyles;
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('1. Prepare the file', style: text.titleMedium),
          const SizedBox(height: 6),
          Text(
            'One concept per row. The first row names the columns. A topic that is not in the '
            'concept bank yet is created for you, with its four question forms.',
            style: text.bodySmall,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final column in kConceptCsvColumns)
                Pill(
                  label: column == 'legal_basis' || column == 'group' ? '$column (optional)' : column,
                  color: column == 'legal_basis' || column == 'group' ? p.textSecondary : p.info,
                  fontSize: 11,
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Subject: one of ${CriminologySubjects.all.map((s) => s.name).join(', ')}. '
            'Group: only when a topic has more than one set of related concepts.',
            style: text.bodySmall,
          ),
          const SizedBox(height: 6),
          Text(
            'Save from Excel with File › Save As › CSV UTF-8, or from Google Sheets with '
            'File › Download › Comma-separated values (.csv).',
            style: text.bodySmall,
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: SecondaryButton(
              label: 'Get the template',
              icon: Icons.download_rounded,
              expand: false,
              height: 44,
              onPressed: _importing ? null : _shareTemplate,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileCard(bool busy) {
    final p = context.palette;
    final text = context.textStyles;
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('2. Choose the file', style: text.titleMedium),
          const SizedBox(height: 12),
          if (_fileName != null) ...[
            Row(
              children: [
                IconBadge(icon: Icons.description_rounded, color: p.success, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _fileName!,
                    style: text.titleSmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: SecondaryButton(
              label: _picking
                  ? 'Opening…'
                  : _fileName == null
                      ? 'Choose CSV file'
                      : 'Choose another file',
              icon: Icons.upload_file_rounded,
              expand: false,
              height: 44,
              onPressed: busy ? null : _pickFile,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    final plan = _plan;
    if (plan == null) {
      return const InlineBanner(
        tone: BannerTone.info,
        message: 'Choose a file to see what will be imported. Nothing is saved until you press Import.',
      );
    }
    if (plan.fileError != null) {
      return InlineBanner(
        tone: BannerTone.danger,
        title: "This file can't be imported",
        message: plan.fileError!,
      );
    }

    final count = plan.conceptCount;
    final topics = plan.topics;
    final problems = plan.problems;
    final children = <Widget>[];

    if (count > 0) {
      final newTopics = plan.newTopicCount;
      children.add(InlineBanner(
        tone: plan.tooMany ? BannerTone.danger : BannerTone.success,
        title: plan.tooMany
            ? 'Too many concepts'
            : '$count concept${count == 1 ? '' : 's'} in ${topics.length} topic${topics.length == 1 ? '' : 's'}',
        message: plan.tooMany
            ? 'Upload at most $kConceptCsvMaxRows concepts at a time. This file has $count; split it into smaller files.'
            : [
                if (newTopics == 1) '1 new topic will be created, with its four question forms.',
                if (newTopics > 1) '$newTopics new topics will be created, each with its four question forms.',
                'Check the list below, then press Import.',
              ].join(' '),
      ));
    } else {
      children.add(const InlineBanner(
        tone: BannerTone.warning,
        title: 'Nothing to import',
        message: 'No row of this file can be imported. The reasons are below.',
      ));
    }

    if (plan.ignoredColumns.isNotEmpty) {
      children.addAll([
        const SizedBox(height: 10),
        InlineBanner(
          tone: BannerTone.neutral,
          message: 'Not used: ${plan.ignoredColumns.join(', ')}.',
        ),
      ]);
    }

    if (problems.isNotEmpty) {
      children.addAll([
        const SizedBox(height: 10),
        InlineBanner(
          tone: BannerTone.warning,
          title: '${problems.length} line${problems.length == 1 ? '' : 's'} will be skipped',
          message: [
            for (final pr in problems.take(_maxProblemsShown)) pr.toString(),
            if (problems.length > _maxProblemsShown) '…and ${problems.length - _maxProblemsShown} more.',
          ].join('\n'),
        ),
      ]);
    }

    if (topics.isNotEmpty) {
      children.addAll([
        const SizedBox(height: 10),
        _TopicList(topics: topics, maxShown: _maxTopicsShown),
      ]);
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }
}

/// The topics the file adds to, with what each will be able to do afterwards.
class _TopicList extends StatelessWidget {
  final List<ConceptCsvTopic> topics;
  final int maxShown;

  const _TopicList({required this.topics, required this.maxShown});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = context.textStyles;
    final shown = topics.take(maxShown).toList();
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          for (var i = 0; i < shown.length; i++) ...[
            if (i > 0) Divider(height: 1, color: p.border),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(shown[i].topic, style: text.titleSmall),
                  const SizedBox(height: 2),
                  // The subject id was already checked by resolveConceptSubject.
                  Text(CriminologySubjects.getById(shown[i].subjectId).name, style: text.bodySmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (shown[i].isNew)
                        Pill(label: 'New topic', icon: Icons.add_rounded, color: p.gold, fontSize: 10.5),
                      Pill(
                        label: '+${shown[i].newConcepts} concept${shown[i].newConcepts == 1 ? '' : 's'}',
                        color: p.info,
                        fontSize: 10.5,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _ReadinessLine(readiness: shown[i].after),
                ],
              ),
            ),
          ],
          if (topics.length > maxShown)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
              child: Text('…and ${topics.length - maxShown} more topics', style: text.bodySmall),
            ),
        ],
      ),
    );
  }
}

class _ReadinessLine extends StatelessWidget {
  final TopicReadiness readiness;
  const _ReadinessLine({required this.readiness});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = context.textStyles;
    final (IconData icon, Color color, String message) = !readiness.canMakeQuestions
        ? (
            Icons.hourglass_empty_rounded,
            p.warning,
            'Not ready for questions yet: a group needs at least $kMinConceptsPerGroup concepts.',
          )
        : readiness.basisFormsReady
            ? (Icons.check_circle_rounded, p.success, 'Ready for questions: all four forms.')
            : (
                Icons.check_circle_outline_rounded,
                p.success,
                'Ready for questions: term and definition forms. The legal-basis forms need a '
                    'different legal basis on every concept.',
              );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 6),
        Expanded(child: Text(message, style: text.bodySmall?.copyWith(color: p.textPrimary))),
      ],
    );
  }
}

/// What the import did: concepts and topics added, lines the database
/// refused, and topics that could not be sent.
class _CsvResultDialog extends StatelessWidget {
  final ConceptCsvImportReport report;
  final int newTopics;

  const _CsvResultDialog({required this.report, required this.newTopics});

  static const int _maxLinesShown = 50;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = context.textStyles;
    final inserted = report.inserted;
    final clean = report.rejected.isEmpty && report.failedTopics.isEmpty;
    final topicCount = report.topicsUpdated.length;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconBadge(
              icon: inserted == 0
                  ? Icons.error_outline_rounded
                  : clean
                      ? Icons.check_rounded
                      : Icons.rule_rounded,
              color: inserted == 0
                  ? p.danger
                  : clean
                      ? p.success
                      : p.warning,
              size: 46,
            ),
            const SizedBox(height: 16),
            Text(
              inserted == 0 ? 'Nothing was added' : '$inserted concept${inserted == 1 ? '' : 's'} added',
              style: text.titleLarge,
            ),
            if (topicCount > 0) ...[
              const SizedBox(height: 6),
              Text(
                '$topicCount topic${topicCount == 1 ? '' : 's'} updated'
                '${newTopics > 0 ? ', $newTopics of them new' : ''}. '
                'New questions are made on the Generate screen and stay hidden from students until you approve them.',
                style: text.bodyMedium,
              ),
            ],
            if (!clean) ...[
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (report.failedTopics.isNotEmpty) ...[
                        Text('Not sent:', style: text.labelLarge),
                        const SizedBox(height: 6),
                        for (final f in report.failedTopics)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Text(f, style: text.bodySmall?.copyWith(color: p.textPrimary)),
                          ),
                        Text(
                          'You can upload the same file again: concepts already saved are skipped.',
                          style: text.bodySmall,
                        ),
                        const SizedBox(height: 10),
                      ],
                      if (report.rejected.isNotEmpty) ...[
                        Text('Not saved:', style: text.labelLarge),
                        const SizedBox(height: 6),
                        for (final r in report.rejected.take(_maxLinesShown))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Text(
                              r.line > 0 ? r.toString() : r.message,
                              style: text.bodySmall?.copyWith(color: p.textPrimary),
                            ),
                          ),
                        if (report.rejected.length > _maxLinesShown)
                          Text('…and ${report.rejected.length - _maxLinesShown} more.', style: text.bodySmall),
                      ],
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 18),
            if (inserted > 0) ...[
              PrimaryButton(
                label: 'Generate questions',
                icon: Icons.auto_awesome_rounded,
                height: 48,
                onPressed: () => Navigator.of(context).pop('generate'),
              ),
              const SizedBox(height: 8),
              SecondaryButton(
                label: 'Done',
                height: 48,
                onPressed: () => Navigator.of(context).pop('done'),
              ),
            ] else
              PrimaryButton(label: 'OK', height: 48, onPressed: () => Navigator.of(context).pop('done')),
          ],
        ),
      ),
    );
  }
}
