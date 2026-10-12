import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/answer_feedback.dart';
import '../models/question.dart';
import '../models/subject.dart';
import '../services/adaptive_learning_service.dart';
import '../services/explanation_service.dart';
import '../services/feedback_service.dart';
import '../services/mastery_service.dart';
import '../services/question_selection_service.dart';
import '../widgets/ui/ui.dart';
import '../utils/page_transitions.dart';
import 'results_screen.dart';

class QuizScreen extends StatefulWidget {
  final Subject subject;
  final List<Question> questions;
  final Difficulty? difficulty;
  final int? segmentIndex;

  const QuizScreen({
    super.key,
    required this.subject,
    required this.questions,
    this.difficulty,
    this.segmentIndex,
  });

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  int _currentIndex = 0;
  int? _selectedAnswer;
  bool _hasAnswered = false;
  final List<bool> _results = [];
  final List<int> _responseTimes = [];
  late Stopwatch _stopwatch;

  late List<List<String>> _shuffledOptions;
  late List<int> _shuffledCorrectIndices;

  /// The shuffle permutation itself, per question: `_shuffledIndexMap[q][k]`
  /// is the ORIGINAL `Question.answerOptions` index behind shuffled slot
  /// `k`. Needed because `Question.rationaleFor()` and
  /// `MasteryService.recordAttempt()` both key off the original,
  /// stem-order index -- not the shuffled position the student tapped --
  /// and that mapping is otherwise lost once the options are shuffled for
  /// display.
  late List<List<int>> _shuffledIndexMap;

  /// Built fresh per answered question by `ExplanationService`. Panel note
  /// 5's whole guarantee -- a non-empty reason on a wrong answer -- lives in
  /// this object, not in a hand-written if/else in the widget tree.
  AnswerFeedback? _currentFeedback;

  @override
  void initState() {
    super.initState();
    _stopwatch = Stopwatch()..start();
    _shuffleAllOptions();

    // Panel note 3, rule R1 ("never repeat while unseen items remain"): the
    // exposure ledger only knows a question was "seen" if something tells
    // it so. This is that one call -- once per quiz, for the whole set, per
    // QuestionSelectionService's own contract. Fire-and-forget: a slow or
    // offline device must never delay the first question.
    unawaited(QuestionSelectionService.instance.markServed(widget.questions));
  }

  void _shuffleAllOptions() {
    final random = Random();
    _shuffledOptions = [];
    _shuffledCorrectIndices = [];
    _shuffledIndexMap = [];

    for (final question in widget.questions) {
      final indices = List.generate(question.options.length, (i) => i);
      indices.shuffle(random);
      _shuffledIndexMap.add(indices);
      final shuffled = indices.map((i) => question.options[i]).toList();
      _shuffledOptions.add(shuffled);
      _shuffledCorrectIndices.add(indices.indexOf(question.correctAnswerIndex));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = context.textStyles;
    final question = widget.questions[_currentIndex];
    final total = widget.questions.length;
    final correctSoFar = _results.where((r) => r).length;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop) {
          final shouldExit = await _showExitDialog();
          if (shouldExit && context.mounted) Navigator.pop(context);
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: ContentWidth(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Row(
                    children: [
                      ToolbarIconButton(
                        icon: Icons.close_rounded,
                        size: 40,
                        tooltip: 'Leave quiz',
                        onPressed: () => _showExitDialog().then((exit) {
                          if (exit && context.mounted) Navigator.pop(context);
                        }),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.subject.shortName,
                              style: text.labelSmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text('Question ${_currentIndex + 1} of $total', style: text.titleSmall),
                          ],
                        ),
                      ),
                      Pill(
                        label: '$correctSoFar correct',
                        icon: Icons.check_rounded,
                        color: p.success,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  child: _buildProgressStrip(total),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 260),
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween(begin: const Offset(0.04, 0), end: Offset.zero).animate(animation),
                          child: child,
                        ),
                      ),
                      child: Column(
                        key: ValueKey(_currentIndex),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AppCard(
                            padding: const EdgeInsets.all(18),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Pill(
                                      label: _difficultyLabel(question.difficulty),
                                      color: p.forDifficulty(question.difficulty.index),
                                    ),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Pill(
                                        label: question.topic,
                                        color: p.textSecondary,
                                        background: p.surfaceAlt,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  question.questionText,
                                  style: text.titleMedium?.copyWith(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                    height: 1.45,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          ...List.generate(_shuffledOptions[_currentIndex].length, _buildOption),
                          if (_hasAnswered && _currentFeedback != null) ...[
                            const SizedBox(height: 6),
                            _buildExplanation(_currentFeedback!),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: p.surface,
                    border: Border(top: BorderSide(color: p.border)),
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: PrimaryButton(
                    label: _hasAnswered
                        ? (_currentIndex < total - 1 ? 'Next question' : 'See results')
                        : 'Check answer',
                    icon: _hasAnswered ? Icons.arrow_forward_rounded : null,
                    trailingIcon: true,
                    color: _hasAnswered && _currentFeedback != null
                        ? (_currentFeedback!.isCorrect ? p.success : null)
                        : null,
                    onPressed: _selectedAnswer == null
                        ? null
                        : (_hasAnswered ? _nextQuestion : () { _submitAnswer(); }),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _difficultyLabel(Difficulty d) => d.name[0].toUpperCase() + d.name.substring(1);

  /// One segment per question (green right, red wrong, blue current),
  /// or a plain bar for long sets.
  Widget _buildProgressStrip(int total) {
    final p = context.palette;
    if (total > 20) {
      return AppProgressBar(value: (_currentIndex + 1) / total, height: 6);
    }
    return Row(
      children: List.generate(total, (i) {
        final Color color;
        if (i < _results.length) {
          color = _results[i] ? p.success : p.danger;
        } else if (i == _currentIndex) {
          color = p.primary;
        } else {
          color = p.surfaceAlt;
        }
        return Expanded(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            height: 6,
            margin: EdgeInsets.only(right: i == total - 1 ? 0 : 4),
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
          ),
        );
      }),
    );
  }

  Widget _buildOption(int index) {
    final p = context.palette;
    final text = context.textStyles;
    final options = _shuffledOptions[_currentIndex];
    final correctIndex = _shuffledCorrectIndices[_currentIndex];
    final isSelected = _selectedAnswer == index;
    final isCorrect = index == correctIndex;
    final letter = String.fromCharCode(65 + index);

    Color bg = p.surface;
    Color border = p.border;
    Color badgeBg = p.surfaceAlt;
    Color badgeFg = p.textSecondary;
    Color labelColor = p.textPrimary;
    IconData? badgeIcon;

    if (_hasAnswered) {
      if (isSelected && isCorrect) {
        // Right answer: green.
        bg = p.successSoft;
        border = p.success;
        badgeBg = p.success;
        badgeFg = Colors.white;
        badgeIcon = Icons.check_rounded;
      } else if (isSelected) {
        // Wrong answer: red, without revealing which option is correct.
        bg = p.dangerSoft;
        border = p.danger;
        badgeBg = p.danger;
        badgeFg = Colors.white;
        badgeIcon = Icons.close_rounded;
      } else {
        labelColor = p.textTertiary;
        badgeFg = p.textTertiary;
      }
    } else if (isSelected) {
      bg = p.primarySoft;
      border = p.primary;
      badgeBg = p.primary;
      badgeFg = Colors.white;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _hasAnswered
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  setState(() => _selectedAnswer = index);
                },
          borderRadius: BorderRadius.circular(AppSpace.radiusMd + 2),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(AppSpace.radiusMd + 2),
              border: Border.all(color: border, width: isSelected ? 1.8 : 1.2),
            ),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: badgeBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: badgeIcon != null
                      ? Icon(badgeIcon, color: badgeFg, size: 19)
                      : Text(letter, style: text.labelLarge?.copyWith(color: badgeFg)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    options[index],
                    style: text.bodyLarge?.copyWith(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: labelColor,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Panel note 5, verbatim: *"Your App can explain WHY the answer is
  /// wrong."* [feedback.primaryReason] is guaranteed non-empty on BOTH
  /// branches by `ExplanationService` -- there is no `if (isCorrect)` gate
  /// here anymore, on purpose. A wrong answer used to render "Not quite!"
  /// and stop; it now always renders the specific reason that option fails.
  Widget _buildExplanation(AnswerFeedback feedback) {
    final p = context.palette;
    final text = context.textStyles;
    final color = feedback.isCorrect ? p.success : p.danger;
    final soft = feedback.isCorrect ? p.successSoft : p.dangerSoft;

    return AppCard(
      padding: EdgeInsets.zero,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 5,
              decoration: BoxDecoration(
                color: color,
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(AppSpace.radiusLg)),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 16, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(color: soft, shape: BoxShape.circle),
                          child: Icon(
                            feedback.isCorrect ? Icons.check_rounded : Icons.lightbulb_outline_rounded,
                            color: color,
                            size: 16,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(feedback.headline, style: text.titleSmall?.copyWith(color: color)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      feedback.primaryReason,
                      style: text.bodyMedium?.copyWith(color: p.textPrimary.withValues(alpha: 0.85)),
                    ),
                    if (feedback.hasLegalBasis) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: p.surfaceAlt,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.gavel_rounded, size: 14, color: p.textSecondary),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'Basis: ${feedback.legalBasis}',
                                style: text.labelMedium,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    // Panel note 2: progress must be visible, not just tracked
                    // internally. This is the BKT model's estimate moving,
                    // shown at the moment it changes.
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Icon(Icons.psychology_rounded, size: 16, color: p.primary),
                        const SizedBox(width: 6),
                        Text('Topic mastery', style: text.labelMedium),
                        const Spacer(),
                        Text(
                          '${feedback.masteryPercent.round()}%',
                          style: text.labelMedium?.copyWith(color: p.textPrimary, fontWeight: FontWeight.w800),
                        ),
                        if (feedback.masteryDelta != 0) ...[
                          const SizedBox(width: 6),
                          Pill(
                            label: '${feedback.masteryDeltaPercent >= 0 ? '+' : ''}${feedback.masteryDeltaPercent.round()}%',
                            color: feedback.masteryDeltaPercent >= 0 ? p.success : p.danger,
                            fontSize: 10.5,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    AppProgressBar(value: feedback.masteryPercent / 100, height: 6),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Scores the answer, updates the Bayesian Knowledge Tracing model for
  /// this topic (panel notes 2 & 4 -- `MasteryService.recordAttempt`, the
  /// only place `topic_mastery` and `question_attempts` are ever written),
  /// and builds the feedback card (panel note 5). All local computation --
  /// this never blocks on the network.
  Future<void> _submitAnswer() async {
    if (_selectedAnswer == null) return;
    _stopwatch.stop();

    final question = widget.questions[_currentIndex];
    final selectedShuffledIndex = _selectedAnswer!;
    final originalIndex = _shuffledIndexMap[_currentIndex][selectedShuffledIndex];
    final isCorrect = selectedShuffledIndex == _shuffledCorrectIndices[_currentIndex];
    _results.add(isCorrect);
    _responseTimes.add(_stopwatch.elapsedMilliseconds);


    if (isCorrect) {
      FeedbackService.instance.onCorrectAnswer();
    } else {
      FeedbackService.instance.onWrongAnswer();
    }

    final masteryBefore = MasteryService.instance
        .masteryFor(widget.subject.id, question.topic)
        .pKnown;

    final updated = await MasteryService.instance.recordAttempt(
      subjectId: widget.subject.id,
      topic: question.topic,
      isCorrect: isCorrect,
      difficulty: question.difficulty,
      responseTimeMs: _responseTimes.last,
      questionId: question.id,
      selectedIndex: originalIndex,
      optionCount: question.answerOptions.length,
    );

    final feedback = ExplanationService.instance.build(
      question: question,
      selectedIndex: originalIndex,
      masteryBefore: masteryBefore,
      masteryAfter: updated.pKnown,
    );

    if (!mounted) return;
    setState(() {
      _hasAnswered = true;
      _currentFeedback = feedback;
    });
  }

  void _nextQuestion() {
    if (_currentIndex < widget.questions.length - 1) {
      setState(() {
        _currentIndex++;
        _selectedAnswer = null;
        _hasAnswered = false;
        _currentFeedback = null;
        _stopwatch.reset();
        _stopwatch.start();
      });
    } else {
      _finishQuiz();
    }
  }

  Future<void> _finishQuiz() async {
    await Provider.of<AdaptiveLearningService>(context, listen: false).recordQuizResult(
      subjectId: widget.subject.id,
      questions: widget.questions,
      results: _results,
      responseTimes: _responseTimes,
      segmentIndex: widget.segmentIndex,
    );
    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      ScalePageRoute(
        page: ResultsScreen(
          subject: widget.subject,
          questions: widget.questions,
          results: _results,
          responseTimes: _responseTimes,
          difficulty: widget.difficulty,
          segmentIndex: widget.segmentIndex,
        ),
      ),
    );
  }

  Future<bool> _showExitDialog() {
    return showConfirmDialog(
      context,
      title: 'Leave this quiz?',
      message: 'Your answers in this quiz will not be saved.',
      confirmLabel: 'Leave',
      cancelLabel: 'Keep going',
      destructive: true,
      icon: Icons.logout_rounded,
    );
  }
}
