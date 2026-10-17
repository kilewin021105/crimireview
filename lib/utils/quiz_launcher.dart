import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/question.dart';
import '../models/subject.dart';
import '../models/user_progress.dart';
import '../screens/study_notes_screen.dart';
import '../services/adaptive_learning_service.dart';
import '../widgets/ui/ui.dart';
import 'error_messages.dart';
import 'page_transitions.dart';

/// Starts the student's current segment of [subject] at [difficulty]:
/// builds the question set (unseen first, BKT-weighted), then opens the
/// study notes that lead into the quiz.
///
/// Shared by the Quiz tab's difficulty sheet and the dashboard's
/// "Continue learning" card, so both start a quiz the same way and record
/// progress against the same segment.
///
/// [onPreparing] switches the caller's loading indicator on and off; the
/// caller checks its own `mounted` before calling setState.
Future<void> startSegmentQuiz(
  BuildContext context, {
  required Subject subject,
  required Difficulty difficulty,
  required void Function(bool preparing) onPreparing,
}) async {
  final service = Provider.of<AdaptiveLearningService>(context, listen: false);
  final segmentIndex = service.getCurrentSegmentIndex(
    subjectId: subject.id,
    difficulty: difficulty,
  );

  onPreparing(true);
  List<Question> questions;
  try {
    questions = await service.getQuestionsForSegment(
      subjectId: subject.id,
      difficulty: difficulty,
    );
  } catch (e) {
    if (context.mounted) {
      showAppSnack(
        context,
        friendlyError(e, fallback: "Couldn't load the questions. Please try again."),
        tone: BannerTone.danger,
      );
    }
    return;
  } finally {
    onPreparing(false);
  }

  if (!context.mounted) return;

  if (questions.isEmpty) {
    showAppSnack(
      context,
      'No ${difficulty.name} questions available for ${SegmentProgress.rangeLabelFor(segmentIndex)}',
      tone: BannerTone.danger,
    );
    return;
  }

  Navigator.push(
    context,
    SlidePageRoute(
      page: StudyNotesScreen(
        subject: subject,
        questions: questions,
        difficulty: difficulty,
        segmentIndex: segmentIndex,
      ),
    ),
  );
}
