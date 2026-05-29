import 'package:flutter/material.dart';
import '../models/subject.dart';
import '../models/question.dart';
import '../services/theme_service.dart';
import '../utils/page_transitions.dart';
import 'quiz_screen.dart';

class StudyNotesScreen extends StatelessWidget {
  final Subject subject;
  final Difficulty difficulty;
  final List<Question> questions;

  const StudyNotesScreen({
    super.key,
    required this.subject,
    required this.difficulty,
    required this.questions,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final notes = _getStudyNotes(subject.id, difficulty);

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context, isDark),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSubjectCard(isDark),
                    const SizedBox(height: 20),
                    _buildNotesSection(isDark, notes),
                    const SizedBox(height: 24),
                    _buildKeyTerms(isDark),
                    const SizedBox(height: 24),
                    _buildTips(isDark),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
            _buildStartButton(context, isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool isDark) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkCard : AppColors.lightCard,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.arrow_back_ios_rounded,
                color: isDark ? Colors.white70 : Colors.black54,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Study Notes',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                  ),
                ),
                Text(
                  'Review before taking the quiz',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubjectCard(bool isDark) {
    final icon = AppTheme.subjectIcons[subject.id] ?? Icons.book_rounded;
    final diffColor = difficulty == Difficulty.easy
        ? const Color(0xFF22C55E)
        : difficulty == Difficulty.medium
            ? const Color(0xFFF59E0B)
            : const Color(0xFFEF4444);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: AppColors.accent, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  subject.name,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: diffColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        difficulty.name.toUpperCase(),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: diffColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${questions.length} questions',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                      ),
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

  Widget _buildNotesSection(bool isDark, List<StudyNote> notes) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.menu_book_rounded, color: AppColors.accent, size: 20),
            const SizedBox(width: 8),
            Text(
              'Key Concepts',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : const Color(0xFF1A1A2E),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ...notes.map((note) => _buildNoteCard(note, isDark)),
      ],
    );
  }

  Widget _buildNoteCard(StudyNote note, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.accent.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            note.title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            note.content,
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKeyTerms(bool isDark) {
    final terms = _getKeyTerms(subject.id);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.lightbulb_rounded, color: Colors.amber, size: 20),
            const SizedBox(width: 8),
            Text(
              'Key Terms',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : const Color(0xFF1A1A2E),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: terms.map((term) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkCard : AppColors.lightCard,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              term,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
          )).toList(),
        ),
      ],
    );
  }

  Widget _buildTips(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.accent.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.tips_and_updates_rounded, color: AppColors.accent, size: 20),
              const SizedBox(width: 8),
              Text(
                'Exam Tips',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildTipItem('Read each question carefully before answering', isDark),
          _buildTipItem('Eliminate obviously wrong answers first', isDark),
          _buildTipItem('Look for keywords that hint at the answer', isDark),
          _buildTipItem('Trust your first instinct unless you\'re sure', isDark),
        ],
      ),
    );
  }

  Widget _buildTipItem(String tip, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.check_circle_rounded,
            color: AppColors.accent,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              tip,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStartButton(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Ready?',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                  ),
                ),
                Text(
                  '10 questions await',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          ElevatedButton(
            onPressed: () {
              Navigator.pushReplacement(
                context,
                SlidePageRoute(
                  page: QuizScreen(
                    subject: subject,
                    questions: questions,
                    difficulty: difficulty,
                  ),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Start Quiz',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                SizedBox(width: 8),
                Icon(Icons.arrow_forward_rounded, size: 18),
              ],
            ),
          ),
        ],
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
