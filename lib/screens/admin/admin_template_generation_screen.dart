import 'package:flutter/material.dart';

import '../../models/question.dart';
import '../../models/subject.dart';
import '../../services/question_generation_service.dart';
import '../../utils/concept_rules.dart';
import '../../utils/error_messages.dart';
import '../../widgets/ui/ui.dart';
import '../../utils/page_transitions.dart';
import '../../utils/responsive.dart';
import 'admin_concepts_screen.dart';
import 'admin_questions_screen.dart';

/// "Generate from Templates" -- the free, no-API-key path of Automatic Item
/// Generation (panel note 1): slot-filling over `question_templates` +
/// `concept_bank`, entirely inside the database, no LLM call. See
/// `supabase_template_generation.sql` and `supabase_concept_bank.sql` for the
/// actual algorithm.
///
/// Each topic shows up to four cards, one per question form (term to
/// definition, definition to term, legal basis to term, term to legal basis).
/// A card shows how many of the topic's concepts have not yet made that kind
/// of question; asking for exactly that number always creates that many.
/// Reviewing what comes out is deliberately not a new screen: it is
/// [AdminQuestionsScreen] filtered to `source: generated`, where Faculty tick
/// the questions they have read and approve them.
class AdminTemplateGenerationScreen extends StatefulWidget {
  const AdminTemplateGenerationScreen({super.key});

  @override
  State<AdminTemplateGenerationScreen> createState() =>
      _AdminTemplateGenerationScreenState();
}

class _AdminTemplateGenerationScreenState
    extends State<AdminTemplateGenerationScreen> {
  List<TemplateStatus> _templates = [];
  bool _loading = true;
  String? _error;
  final Set<String> _generating = {};
  bool _generatingAll = false;

  bool get _busy => _generatingAll || _generating.isNotEmpty;

  int get _totalRemaining =>
      _templates.fold(0, (sum, t) => sum + (t.conceptsRemaining > 0 ? t.conceptsRemaining : 0));

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
      final templates =
          await QuestionGenerationService.instance.listTemplateStatus();
      if (!mounted) return;
      setState(() {
        _templates = templates;
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

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    showAppSnack(context, message, tone: isError ? BannerTone.danger : BannerTone.success);
  }

  Future<void> _openConcepts() async {
    await Navigator.push(
      context,
      SlidePageRoute(page: const AdminConceptsScreen()),
    );
    if (mounted) _load();
  }

  Future<void> _generate(TemplateStatus template) async {
    if (template.conceptsRemaining <= 0 || _busy) return;

    setState(() => _generating.add(template.id));
    final result =
        await QuestionGenerationService.instance.generateFromTemplate(
      templateId: template.id,
      count: template.conceptsRemaining,
    );
    if (!mounted) return;
    setState(() => _generating.remove(template.id));

    if (result['success'] != true) {
      _showSnack('Generation failed: ${result['error'] ?? 'unknown error'}',
          isError: true);
      return;
    }

    final inserted = (result['inserted'] as num?)?.toInt() ?? 0;
    if (inserted == 0) {
      _showSnack('Nothing new -- every concept here already has this question.');
    } else {
      _showSnack(
          'Generated $inserted question${inserted == 1 ? '' : 's'} -- ready for your review.');
      _openReview(template: template);
    }
    _load();
  }

  /// Runs every template that still has concepts left, one after another, then
  /// opens the review list. Nothing becomes visible to students: the questions
  /// are saved inactive until Faculty approve them.
  Future<void> _generateAll() async {
    if (_busy) return;
    final todo = _templates.where((t) => t.conceptsRemaining > 0).toList();
    if (todo.isEmpty) return;

    setState(() => _generatingAll = true);
    var inserted = 0;
    var failed = 0;
    String? firstError;
    for (final t in todo) {
      final result = await QuestionGenerationService.instance.generateFromTemplate(
        templateId: t.id,
        count: t.conceptsRemaining,
      );
      if (result['success'] == true) {
        inserted += (result['inserted'] as num?)?.toInt() ?? 0;
      } else {
        failed++;
        firstError ??= (result['error'] ?? 'unknown error').toString();
      }
      if (!mounted) return;
    }
    setState(() => _generatingAll = false);

    if (failed > 0) {
      _showSnack(
        '$failed of ${todo.length} templates failed: $firstError'
        '${inserted > 0 ? ' ($inserted questions were still made.)' : ''}',
        isError: true,
      );
    } else if (inserted == 0) {
      _showSnack('Nothing new -- every concept already has its questions.');
    } else {
      _showSnack('Generated $inserted question${inserted == 1 ? '' : 's'} -- ready for your review.');
    }
    await _load();
    if (inserted > 0 && mounted) _openReview();
  }

  void _openReview({TemplateStatus? template}) {
    Navigator.push(
      context,
      SlidePageRoute(
        page: AdminQuestionsScreen(
          initialSource: QuestionSource.generated,
          initialTemplateId: template?.id,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final padding = Responsive.horizontalPadding(context);

    return Scaffold(
      appBar: AppTopBar(
        title: 'Generate questions',
        subtitle: 'From templates · no AI key needed',
        actions: [
          ToolbarIconButton(
            icon: Icons.menu_book_rounded,
            tooltip: 'Manage concepts',
            size: 40,
            onPressed: _openConcepts,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const LoadingView(label: 'Loading templates...')
            : _error != null
                ? ListView(
                    children: [
                      const SizedBox(height: 60),
                      EmptyState(
                        icon: Icons.error_outline_rounded,
                        title: "Couldn't load templates",
                        message: _error,
                        actionLabel: 'Try again',
                        onAction: _load,
                        color: context.palette.danger,
                      ),
                    ],
                  )
                : ListView(
                    padding: EdgeInsets.fromLTRB(padding, 4, padding, 40),
                    children: _buildContent(),
                  ),
      ),
    );
  }

  List<Widget> _buildContent() {
    final text = context.textStyles;
    final widgets = <Widget>[
      ContentWidth(
        maxWidth: 820,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const InlineBanner(
              tone: BannerTone.info,
              icon: Icons.auto_fix_high_rounded,
              title: 'How it works',
              message:
                  'Each concept can make up to 4 questions, one for each form below. '
                  'New questions wait for your approval. Students do not see them until you approve them.',
            ),
            const SizedBox(height: 14),
            PrimaryButton(
              label: _totalRemaining > 0 ? 'Generate all ($_totalRemaining)' : 'Generate all',
              icon: Icons.auto_awesome_rounded,
              height: 50,
              loading: _generatingAll,
              onPressed: _totalRemaining > 0 && !_busy ? _generateAll : null,
            ),
            const SizedBox(height: 4),
            Center(
              child: TextButton.icon(
                onPressed: _busy ? null : _openConcepts,
                icon: const Icon(Icons.menu_book_rounded, size: 18),
                label: const Text('Manage concepts'),
              ),
            ),
            const SizedBox(height: 14),
          ],
        ),
      ),
    ];

    if (_templates.isEmpty) {
      widgets.add(EmptyState(
        icon: Icons.inventory_2_outlined,
        title: 'No active templates',
        message: 'Add a concept and its templates are created for you.',
        actionLabel: 'Manage concepts',
        onAction: _openConcepts,
      ));
      return widgets;
    }

    // One block per topic, its forms underneath.
    final topics = <String, List<TemplateStatus>>{};
    for (final t in _templates) {
      topics.putIfAbsent('${t.subjectId}::${t.topic}', () => []).add(t);
    }
    var index = 0;
    for (final group in topics.values) {
      final first = group.first;
      final subject = CriminologySubjects.all.firstWhere(
          (s) => s.id == first.subjectId,
          orElse: () => CriminologySubjects.all.first);
      final color = AppColors.subjectColor(subject.id);
      final remaining = group.fold(0, (s, t) => s + (t.conceptsRemaining > 0 ? t.conceptsRemaining : 0));

      widgets.add(ContentWidth(
        maxWidth: 820,
        child: Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 10),
          child: Row(
            children: [
              IconBadge(
                icon: AppTheme.subjectIcons[subject.id] ?? Icons.auto_fix_high_rounded,
                color: color,
                size: 34,
                iconSize: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(first.topic, style: text.titleMedium),
                    Text(
                      '${subject.shortName} · $remaining new question${remaining == 1 ? '' : 's'} can be made',
                      style: text.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ));
      for (final t in group) {
        widgets.add(ContentWidth(
          maxWidth: 820,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Appear(index: index++, child: _buildTemplateCard(t, color)),
          ),
        ));
      }
      widgets.add(const SizedBox(height: 10));
    }
    return widgets;
  }

  Widget _buildTemplateCard(TemplateStatus template, Color color) {
    final p = context.palette;
    final text = context.textStyles;
    final isGenerating = _generating.contains(template.id);
    final unavailable = template.totalConcepts == 0;
    final exhausted = !unavailable && template.conceptsRemaining <= 0;
    final used = template.totalConcepts - template.conceptsRemaining;
    final difficultyIndex = Difficulty.values.indexWhere((d) => d.name == template.difficulty.toLowerCase());
    final label = templateFormLabels[template.form] ?? template.form;
    final hint = templateFormHints[template.form];

    final String status;
    if (unavailable) {
      status = templateFormNeedsBasis(template.form)
          ? 'Not available yet. It needs a group of $kMinConceptsPerGroup or more concepts, '
              'each with its own legal basis.'
          : 'Not available yet. It needs a group of $kMinConceptsPerGroup or more concepts.';
    } else if (exhausted) {
      status = 'All concepts used. Add more concepts to make more.';
    } else {
      status =
          '${template.conceptsRemaining} new question${template.conceptsRemaining == 1 ? '' : 's'} can be generated.';
    }

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: text.titleSmall)),
              const SizedBox(width: 8),
              Pill(
                label: template.difficulty,
                color: difficultyIndex >= 0 ? p.forDifficulty(difficultyIndex) : p.textSecondary,
                fontSize: 10.5,
              ),
            ],
          ),
          if (hint != null) ...[
            const SizedBox(height: 4),
            Text(hint, style: text.bodySmall),
          ],
          if (!unavailable) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Text('Concepts used', style: text.labelMedium),
                const Spacer(),
                Text(
                  '$used / ${template.totalConcepts}',
                  style: text.labelMedium?.copyWith(color: p.textPrimary, fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 6),
            AppProgressBar(
              value: used / template.totalConcepts,
              color: exhausted ? p.textTertiary : color,
              height: 6,
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: Text(status, style: text.bodySmall)),
              const SizedBox(width: 12),
              if (unavailable)
                SecondaryButton(
                  label: 'Add concepts',
                  icon: Icons.menu_book_rounded,
                  expand: false,
                  height: 42,
                  onPressed: _busy ? null : _openConcepts,
                )
              else if (exhausted)
                SecondaryButton(
                  label: 'Review batch',
                  icon: Icons.visibility_rounded,
                  expand: false,
                  height: 42,
                  onPressed: () => _openReview(template: template),
                )
              else
                PrimaryButton(
                  label: 'Generate',
                  icon: Icons.auto_awesome_rounded,
                  expand: false,
                  height: 42,
                  loading: isGenerating,
                  onPressed: _busy ? null : () => _generate(template),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
