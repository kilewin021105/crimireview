import 'package:flutter/material.dart';
import '../models/subject.dart';
import '../services/theme_service.dart';
import '../utils/page_transitions.dart';
import 'flashcard_screen.dart';

/// Tab root for Flashcards: pick a subject, then study its deck.
///
/// `FlashcardScreen` itself needs a subject to know which questions to pull
/// from `QuestionRepository`, so this screen is the subject picker in front
/// of it -- the same role `SubjectsScreen` plays for the Quiz tab. Pushing
/// `FlashcardScreen` via [Navigator] (rather than swapping it directly into
/// the tab's `IndexedStack`) keeps its existing back button working exactly
/// as it already does everywhere else it's used.
class FlashcardsHomeScreen extends StatelessWidget {
  const FlashcardsHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Flashcards',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Choose a subject to review',
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                itemCount: CriminologySubjects.all.length,
                itemBuilder: (context, index) {
                  final subject = CriminologySubjects.all[index];
                  return _buildSubjectCard(context, subject, isDark);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubjectCard(BuildContext context, Subject subject, bool isDark) {
    final icon = AppTheme.subjectIcons[subject.id] ?? Icons.book_rounded;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          SlidePageRoute(page: FlashcardScreen(subject: subject)),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkCard : AppColors.lightCard,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppColors.accent, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    subject.name,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Study Flashcards',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: isDark ? Colors.grey.shade600 : Colors.grey.shade400),
          ],
        ),
      ),
    );
  }
}
