import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/question.dart';
import '../../models/subject.dart';
import '../../services/question_generation_service.dart';
import '../../services/theme_service.dart';
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
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.error : AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
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
                      padding: EdgeInsets.fromLTRB(padding, 8, padding, 40),
                      children: [
                        const SizedBox(height: 20),
                        if (_templates.isEmpty) _buildEmpty(isDark),
                        for (final t in _templates)
                          _buildTemplateCard(t, isDark),
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
      leading: IconButton(
        onPressed: () => Navigator.pop(context),
        icon: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkCard : Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)
            ],
          ),
          child: Icon(Icons.arrow_back_ios_new_rounded,
              size: 18, color: isDark ? Colors.white : const Color(0xFF1A1A2E)),
        ),
      ),
      title: Text(
        'Generate from Templates',
        style: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : const Color(0xFF1A1A2E)),
      ),
      centerTitle: true,
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
            Text('Could not load templates.\n$_error',
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _load,
              style:
                  ElevatedButton.styleFrom(backgroundColor: AppColors.accent),
              child: const Text('Retry', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Text(
        'No active templates. Add rows to public.question_templates and '
        'public.concept_bank to use this generator.',
        style: TextStyle(
            color: isDark ? Colors.grey.shade500 : Colors.grey.shade600),
      ),
    );
  }

  Widget _buildTemplateCard(TemplateStatus template, bool isDark) {
    final subject = CriminologySubjects.all.firstWhere(
        (s) => s.id == template.subjectId,
        orElse: () => CriminologySubjects.all.first);
    final isGenerating = _generating.contains(template.id);
    final exhausted = template.conceptsRemaining <= 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.auto_fix_high_rounded,
                    color: AppColors.accent, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      template.topic,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color:
                              isDark ? Colors.white : const Color(0xFF1A1A2E)),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${subject.name} · ${template.difficulty}',
                      style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? Colors.grey.shade500
                              : Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: (exhausted ? Colors.grey : AppColors.success)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  exhausted
                      ? 'All ${template.totalConcepts} used'
                      : '${template.conceptsRemaining} of ${template.totalConcepts} available',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: exhausted ? Colors.grey.shade600 : AppColors.success,
                  ),
                ),
              ),
              const Spacer(),
              SizedBox(
                height: 36,
                child: ElevatedButton(
                  onPressed: (isGenerating || exhausted)
                      ? null
                      : () => _generate(template),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    disabledBackgroundColor:
                        isDark ? Colors.white12 : Colors.grey.shade200,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  child: isGenerating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : Text(
                          'Generate',
                          style: TextStyle(
                            color: exhausted
                                ? (isDark
                                    ? Colors.white30
                                    : Colors.grey.shade400)
                                : Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
