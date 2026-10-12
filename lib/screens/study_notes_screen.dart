import 'package:flutter/material.dart';
import '../models/subject.dart';
import '../models/question.dart';
import '../models/user_progress.dart';
import '../utils/page_transitions.dart';
import '../utils/responsive.dart';
import '../widgets/ui/ui.dart';
import 'quiz_screen.dart';

class StudyNotesScreen extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final notes = _getStudyNotes(subject.id, difficulty);
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
                    Appear(index: 1, child: _buildNotesSection(context, notes)),
                    const SizedBox(height: AppSpace.section),
                    Appear(index: 2, child: _buildKeyTerms(context)),
                    const SizedBox(height: AppSpace.section),
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

  Widget _buildNotesSection(BuildContext context, List<StudyNote> notes) {
    final p = context.palette;
    final text = context.textStyles;
    final color = AppColors.subjectColor(subject.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: 'Key concepts', subtitle: '${notes.length} things to remember'),
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

  Widget _buildKeyTerms(BuildContext context) {
    final p = context.palette;
    final text = context.textStyles;
    final terms = _getKeyTerms(subject.id);

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

  List<StudyNote> _getStudyNotes(String subjectId, Difficulty diff) {
    final notes = <String, List<StudyNote>>{
      'criminal_jurisprudence': [
        StudyNote('Revised Penal Code (RPC)', 'The main source of criminal law in the Philippines. Contains Book I (general provisions) and Book II (specific crimes and penalties).'),
        StudyNote('Elements of a Crime', '1. Act or omission 2. Punishable by law 3. Performed with dolo (intent) or culpa (negligence)'),
        StudyNote('Justifying Circumstances', 'Self-defense, Defense of relatives, Defense of stranger, Fulfillment of duty, Obedience to lawful order. These EXEMPT from criminal AND civil liability.'),
        StudyNote('Exempting Circumstances', 'Insanity, Minority (below 15), Accident, Irresistible force, Uncontrollable fear. Exempt from criminal liability but NOT civil liability.'),
        StudyNote('Mitigating Circumstances', 'Reduce the penalty: Voluntary surrender, Passion/obfuscation, Sufficient provocation, Plea of guilty.'),
      ],
      'criminalistics': [
        StudyNote('Forensic Science Branches', 'Forensic Chemistry, Forensic Biology, Forensic Medicine, Questioned Documents, Ballistics, Dactyloscopy (fingerprints).'),
        StudyNote('Chain of Custody', 'Documentation of evidence from collection to presentation in court. Must be unbroken to ensure integrity.'),
        StudyNote('Types of Fingerprints', 'Loops (60-65%), Whorls (30-35%), Arches (5%). Used for positive identification.'),
        StudyNote('Ballistics', 'Study of firearms and projectiles. Includes internal, external, and terminal ballistics.'),
        StudyNote('DNA Evidence', 'Genetic material used for identification. Nuclear DNA from both parents, Mitochondrial DNA from mother only.'),
      ],
      'law_enforcement': [
        StudyNote('PNP Organization', 'Under DILG. National headquarters, Regional offices, Provincial offices, City/Municipal stations.'),
        StudyNote('Police Powers', 'Power to arrest, Search and seizure, Use of force (only when necessary and reasonable).'),
        StudyNote('RA 6975', 'DILG Act - Established PNP as the primary law enforcement agency.'),
        StudyNote('Community Policing', 'Partnership between police and community to prevent crime and maintain peace.'),
        StudyNote('Human Rights in Policing', 'Miranda Rights, Right against torture, Right to counsel, Presumption of innocence.'),
      ],
      'corrections': [
        StudyNote('Bureau of Corrections (BuCor)', 'Manages national penitentiaries for those sentenced to more than 3 years.'),
        StudyNote('BJMP', 'Bureau of Jail Management and Penology - Manages city/municipal jails for those awaiting trial or sentenced to 3 years or less.'),
        StudyNote('Types of Release', 'Parole (conditional), Probation (instead of imprisonment), Pardon (executive clemency), Amnesty (group pardon for political offenses).'),
        StudyNote('Rehabilitation Programs', 'Education, Vocational training, Therapeutic communities, Religious programs, Sports/recreation.'),
        StudyNote('Prisoner Classification', 'By security risk: Maximum, Medium, Minimum. By sentence: Insular, Provincial, City/Municipal.'),
      ],
      'criminology': [
        StudyNote('Classical School', 'Beccaria & Bentham - Free will, Rational choice, Punishment should fit the crime.'),
        StudyNote('Positivist School', 'Lombroso - Criminal behavior determined by biological, psychological, or social factors.'),
        StudyNote('Strain Theory', 'Merton - Crime results from gap between cultural goals and legitimate means to achieve them.'),
        StudyNote('Social Learning Theory', 'Sutherland - Criminal behavior is learned through interaction with others.'),
        StudyNote('Labeling Theory', 'Being labeled as criminal leads to more criminal behavior (self-fulfilling prophecy).'),
      ],
      'crime_detection': [
        StudyNote('Criminal Investigation', 'Systematic inquiry to determine facts about a crime - who, what, when, where, why, how.'),
        StudyNote('Crime Scene Management', '1. Secure the scene 2. Document everything 3. Collect evidence 4. Process evidence 5. Release scene.'),
        StudyNote('Types of Evidence', 'Physical, Documentary, Testimonial. Direct vs Circumstantial evidence.'),
        StudyNote('Interviewing vs Interrogation', 'Interview: gather information from witnesses. Interrogation: question suspects to obtain confession.'),
        StudyNote('Modus Operandi', 'Method of operation - Pattern or technique used by criminal. Helps link crimes.'),
      ],
    };

    return notes[subjectId] ?? [
      StudyNote('General Tips', 'Focus on key concepts and definitions. Practice with multiple choice questions.'),
    ];
  }

  List<String> _getKeyTerms(String subjectId) {
    final terms = <String, List<String>>{
      'criminal_jurisprudence': ['RPC', 'Mala in se', 'Mala prohibita', 'Dolo', 'Culpa', 'Felony', 'Recidivism', 'Treachery', 'Evident premeditation'],
      'criminalistics': ['Forensics', 'DNA', 'Ballistics', 'Dactyloscopy', 'Chain of custody', 'Autopsy', 'Toxicology'],
      'law_enforcement': ['PNP', 'DILG', 'RA 6975', 'Miranda rights', 'Arrest', 'Search warrant', 'Hot pursuit'],
      'corrections': ['BuCor', 'BJMP', 'Parole', 'Probation', 'Pardon', 'Amnesty', 'Rehabilitation'],
      'criminology': ['Classical', 'Positivist', 'Strain theory', 'Anomie', 'Deviance', 'Recidivism'],
      'crime_detection': ['Investigation', 'Evidence', 'Modus operandi', 'Crime scene', 'Witness', 'Suspect'],
    };

    return terms[subjectId] ?? ['Study', 'Review', 'Practice'];
  }
}

class StudyNote {
  final String title;
  final String content;

  StudyNote(this.title, this.content);
}
