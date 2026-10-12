import 'package:flutter/material.dart';

import '../../models/question.dart';
import '../../models/subject.dart';
import '../../services/question_generation_service.dart';
import '../../utils/error_messages.dart';
import '../../widgets/ui/ui.dart';
import '../../utils/page_transitions.dart';
import '../../utils/responsive.dart';
import 'admin_questions_screen.dart';

/// "Generate from Templates" -- the free, no-API-key path of Automatic Item
/// Generation (panel note 1): slot-filling over `question_templates` +
/// `concept_bank`, entirely inside the database, no LLM call. See
/// `supabase_template_generation.sql` for the actual algorithm.
///
/// One card per active template, each showing how many of its concepts
/// haven't produced a question yet -- that count is also the hard ceiling
/// on this run (a concept can only ever generate one question, since its
/// stem is deterministic). Reviewing what comes out is deliberately not a
/// new screen here either, same reasoning as the document-generation path:
/// it's [AdminQuestionsScreen] filtered to `source: generated`.
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

  Future<void> _generate(TemplateStatus template) async {
    if (template.conceptsRemaining <= 0) {
      _showSnack(
        'Every concept for "${template.topic}" already has a question. '
        'Add more concepts to public.concept_bank to generate more here.',
      );
      return;
    }

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
      _showSnack('Nothing new -- every concept here already has a question.');
    } else {
      _showSnack(
          'Generated $inserted question${inserted == 1 ? '' : 's'} -- ready for your review.');
      _openReview(template);
    }
    _load();
  }

  void _openReview(TemplateStatus template) {
    Navigator.push(
      context,
      SlidePageRoute(
        page: AdminQuestionsScreen(
          initialSource: QuestionSource.generated,
          initialTemplateId: template.id,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final padding = Responsive.horizontalPadding(context);

    return Scaffold(
      appBar: const AppTopBar(
        title: 'Generate questions',
        subtitle: 'From templates · no AI key needed',
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
                    children: [
                      const ContentWidth(
                        maxWidth: 820,
                        child: InlineBanner(
                          tone: BannerTone.info,
                          icon: Icons.auto_fix_high_rounded,
                          title: 'How it works',
                          message:
                              'Each concept in a template produces exactly one question. Generated questions go into the bank as "generated" so you can review them before students rely on them.',
                        ),
                      ),
                      const SizedBox(height: 18),
                      if (_templates.isEmpty)
                        const EmptyState(
                          icon: Icons.inventory_2_outlined,
                          title: 'No active templates',
                          message: 'Add rows to public.question_templates and public.concept_bank to use this generator.',
                        ),
                      for (var i = 0; i < _templates.length; i++)
                        ContentWidth(
                          maxWidth: 820,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Appear(index: i, child: _buildTemplateCard(_templates[i])),
                          ),
                        ),
                    ],
                  ),
      ),
    );
  }

  Widget _buildTemplateCard(TemplateStatus template) {
    final p = context.palette;
    final text = context.textStyles;
    final subject = CriminologySubjects.all.firstWhere(
        (s) => s.id == template.subjectId,
        orElse: () => CriminologySubjects.all.first);
    final color = AppColors.subjectColor(subject.id);
    final isGenerating = _generating.contains(template.id);
    final exhausted = template.conceptsRemaining <= 0;
    final used = template.totalConcepts - template.conceptsRemaining;
    final difficultyIndex = Difficulty.values.indexWhere((d) => d.name == template.difficulty.toLowerCase());

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(icon: AppTheme.subjectIcons[subject.id] ?? Icons.auto_fix_high_rounded, color: color, size: 42),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(template.topic, style: text.titleSmall),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        Pill(label: subject.shortName, color: color, fontSize: 10.5),
                        Pill(
                          label: template.difficulty,
                          color: difficultyIndex >= 0 ? p.forDifficulty(difficultyIndex) : p.textSecondary,
                          fontSize: 10.5,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
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
            value: template.totalConcepts == 0 ? 0 : used / template.totalConcepts,
            color: exhausted ? p.textTertiary : color,
            height: 6,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(
                  exhausted
                      ? 'All concepts used. Add more to concept_bank to generate again.'
                      : '${template.conceptsRemaining} new question${template.conceptsRemaining == 1 ? '' : 's'} can be generated.',
                  style: text.bodySmall,
                ),
              ),
              const SizedBox(width: 12),
              if (exhausted)
                SecondaryButton(
                  label: 'Review batch',
                  icon: Icons.visibility_rounded,
                  expand: false,
                  height: 42,
                  onPressed: () => _openReview(template),
                )
              else
                PrimaryButton(
                  label: 'Generate',
                  icon: Icons.auto_awesome_rounded,
                  expand: false,
                  height: 42,
                  loading: isGenerating,
                  onPressed: () => _generate(template),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
