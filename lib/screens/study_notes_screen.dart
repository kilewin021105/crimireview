import 'package:flutter/material.dart';
import '../models/subject.dart';
import '../models/question.dart';
import '../models/user_progress.dart';
import '../services/study_notes_service.dart';
import '../utils/page_transitions.dart';
import '../utils/responsive.dart';
import '../widgets/ui/ui.dart';
import 'quiz_screen.dart';

/// Key points to review before a quiz, taken from the study module of the
/// quiz's TOS topics and competencies (assets/modules, built from the PRC
/// Tables of Specifications).
class StudyNotesScreen extends StatefulWidget {
  final Subject subject;
  final Difficulty difficulty;
  final List<Question> questions;
  final int segmentIndex;

  const StudyNotesScreen({
    super.key,
    required this.subject,
    required this.difficulty,
    required this.questions,
    required this.segmentIndex,
  });

  @override
  State<StudyNotesScreen> createState() => _StudyNotesScreenState();
}

class _StudyNotesScreenState extends State<StudyNotesScreen> {
  late final Future<StudyNotesContent> _content =
      StudyNotesService.instance.forQuiz(widget.subject.id, widget.questions);

  Subject get subject => widget.subject;
  Difficulty get difficulty => widget.difficulty;
  List<Question> get questions => widget.questions;
  int get segmentIndex => widget.segmentIndex;

  @override
  Widget build(BuildContext context) {
    final padding = Responsive.horizontalPadding(context);

    return Scaffold(
      appBar: const AppTopBar(title: 'Study notes', subtitle: 'Review before you start'),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(padding, 4, padding, 24),
              child: ContentWidth(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Appear(index: 0, child: _buildSubjectCard(context)),
                    const SizedBox(height: AppSpace.section),
                    FutureBuilder<StudyNotesContent>(
                      future: _content,
                      builder: (context, snap) {
                        if (snap.connectionState != ConnectionState.done) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 32),
                            child: LoadingView(label: 'Opening your notes...'),
                          );
                        }
                        final content = snap.data ?? StudyNotesContent.empty;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (content.notes.isNotEmpty) ...[
                              Appear(index: 1, child: _buildNotesSection(context, content)),
                              const SizedBox(height: AppSpace.section),
                            ],
                            if (content.keyTerms.isNotEmpty) ...[
                              Appear(index: 2, child: _buildKeyTerms(context, content.keyTerms)),
                              const SizedBox(height: AppSpace.section),
                            ],
                          ],
                        );
                      },
                    ),
                    Appear(index: 3, child: _buildTips(context)),
                  ],
                ),
              ),
            ),
          ),
          _buildStartButton(context),
        ],
      ),
    );
  }

  Widget _buildSubjectCard(BuildContext context) {
    final p = context.palette;
    final text = context.textStyles;
    final icon = AppTheme.subjectIcons[subject.id] ?? Icons.book_rounded;
    final color = AppColors.subjectColor(subject.id);
    final diffColor = p.forDifficulty(difficulty.index);

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          IconBadge(icon: icon, color: color, size: 52, iconSize: 26),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(subject.name, style: text.titleMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Pill(label: _difficultyLabel, color: diffColor),
                    Pill(label: SegmentProgress.rangeLabelFor(segmentIndex), color: p.primary),
                    Pill(
                      label: '${questions.length} questions',
                      icon: Icons.help_outline_rounded,
                      color: p.textSecondary,
                      background: p.surfaceAlt,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String get _difficultyLabel =>
      difficulty.name[0].toUpperCase() + difficulty.name.substring(1);

  Widget _buildNotesSection(BuildContext context, StudyNotesContent content) {
    final p = context.palette;
    final text = context.textStyles;
    final color = AppColors.subjectColor(subject.id);
    final notes = content.notes;
    final from = content.topics.isEmpty ? 'the study module' : content.topics.join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: 'Key concepts', subtitle: 'From the PRC TOS: $from'),
        const SizedBox(height: 12),
        for (var i = 0; i < notes.length; i++) ...[
          AppCard(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: context.isDarkMode ? 0.2 : 0.12),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(
                    '${i + 1}',
                    style: text.labelMedium?.copyWith(color: color, fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(notes[i].title, style: text.titleSmall),
                      const SizedBox(height: 2),
                      Text(notes[i].code, style: text.labelSmall?.copyWith(color: color)),
                      const SizedBox(height: 6),
                      Text(
                        notes[i].content,
                        style: text.bodyMedium?.copyWith(color: p.textPrimary.withValues(alpha: 0.82)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (i < notes.length - 1) const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _buildKeyTerms(BuildContext context, List<String> terms) {
    final p = context.palette;
    final text = context.textStyles;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Key terms'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: terms
              .map((term) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: p.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: p.border),
                    ),
                    child: Text(term, style: text.labelMedium?.copyWith(color: p.textPrimary)),
                  ))
              .toList(),
        ),
      ],
    );
  }

  Widget _buildTips(BuildContext context) {
    final p = context.palette;
    final text = context.textStyles;
    const tips = [
      'Read each question carefully before answering',
      'Eliminate obviously wrong answers first',
      'Look for keywords that hint at the answer',
      "Trust your first instinct unless you're sure",
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.primarySoft,
        borderRadius: BorderRadius.circular(AppSpace.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.tips_and_updates_rounded, color: p.onPrimarySoft, size: 20),
              const SizedBox(width: 8),
              Text('Exam tips', style: text.titleSmall?.copyWith(color: p.onPrimarySoft)),
            ],
          ),
          const SizedBox(height: 12),
          for (final tip in tips)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(Icons.check_circle_rounded, color: p.primary, size: 17),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(tip, style: text.bodyMedium?.copyWith(color: p.textPrimary)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStartButton(BuildContext context) {
    final p = context.palette;
    final text = context.textStyles;
    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(top: BorderSide(color: p.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
          child: ContentWidth(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Ready?', style: text.titleMedium),
                      Text('${questions.length} questions await', style: text.bodySmall),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                PrimaryButton(
                  label: 'Start quiz',
                  icon: Icons.arrow_forward_rounded,
                  trailingIcon: true,
                  expand: false,
                  onPressed: () {
                    Navigator.pushReplacement(
                      context,
                      SlidePageRoute(
                        page: QuizScreen(
                          subject: subject,
                          questions: questions,
                          difficulty: difficulty,
                          segmentIndex: segmentIndex,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
