import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/question.dart';
import '../models/subject.dart';
import '../services/adaptive_learning_service.dart';
import '../services/feedback_service.dart';
import '../services/theme_service.dart';
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

  @override
  void initState() {
    super.initState();
    _stopwatch = Stopwatch()..start();
    _shuffleAllOptions();
  }

  void _shuffleAllOptions() {
    final random = Random();
    _shuffledOptions = [];
    _shuffledCorrectIndices = [];
    
    for (final question in widget.questions) {
      final indices = List.generate(question.options.length, (i) => i);
      indices.shuffle(random);
      final shuffled = indices.map((i) => question.options[i]).toList();
      _shuffledOptions.add(shuffled);
      _shuffledCorrectIndices.add(indices.indexOf(question.correctAnswerIndex));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final question = widget.questions[_currentIndex];
    final progress = (_currentIndex + 1) / widget.questions.length;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop) {
          final shouldExit = await _showExitDialog(isDark);
          if (shouldExit && context.mounted) Navigator.pop(context);
        }
      },
      child: Scaffold(
        backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
        body: SafeArea(
          child: Column(
            children: [

              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Row(
                      children: [
                        GestureDetector(
                          onTap: () => _showExitDialog(isDark).then((exit) {
                            if (exit) Navigator.pop(context);
                          }),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: isDark ? AppColors.darkCard : AppColors.lightCard,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              Icons.close_rounded,
                              color: isDark ? Colors.white70 : Colors.black54,
                              size: 20,
                            ),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${_currentIndex + 1} / ${widget.questions.length}',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                          ),
                        ),
                        const Spacer(),
                        const SizedBox(width: 36),
                      ],
                    ),
                    const SizedBox(height: 16),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress,
                        backgroundColor: isDark ? Colors.white12 : Colors.grey.shade200,
                        valueColor: AlwaysStoppedAnimation(AppColors.accent),
                        minHeight: 6,
                      ),
                    ),
                  ],
                ),
              ),


              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [

                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: isDark ? AppColors.darkCard : AppColors.lightCard,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                _buildTag(question.difficulty.name.toUpperCase(), _getDifficultyColor(question.difficulty), isDark),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    question.topic,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              question.questionText,
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),


                      ...List.generate(_shuffledOptions[_currentIndex].length, (index) {
                        return _buildOption(index, isDark);
                      }),


                      if (_hasAnswered) ...[
                        const SizedBox(height: 16),
                        _buildExplanation(question, isDark),
                      ],
                    ],
                  ),
                ),
              ),


              Padding(
                padding: const EdgeInsets.all(20),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _selectedAnswer == null ? null : (_hasAnswered ? _nextQuestion : _submitAnswer),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: isDark ? Colors.white12 : Colors.grey.shade200,
                      disabledForegroundColor: isDark ? Colors.white30 : Colors.grey.shade400,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text(
                      _hasAnswered
                          ? (_currentIndex < widget.questions.length - 1 ? 'Next' : 'See Results')
                          : 'Check',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTag(String text, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Color _getDifficultyColor(Difficulty difficulty) {
    switch (difficulty) {
      case Difficulty.easy:
        return AppColors.success;
      case Difficulty.medium:
        return Colors.orange;
      case Difficulty.hard:
        return AppColors.error;
    }
  }

  Widget _buildOption(int index, bool isDark) {
    final options = _shuffledOptions[_currentIndex];
    final correctIndex = _shuffledCorrectIndices[_currentIndex];
    final isSelected = _selectedAnswer == index;
    final isCorrect = index == correctIndex;
    final letters = ['A', 'B', 'C', 'D'];

    Color bgColor, borderColor, letterBgColor, letterColor;

    if (_hasAnswered) {
      if (isSelected && isCorrect) {
        // User got it right - green
        bgColor = AppColors.success.withValues(alpha: 0.1);
        borderColor = AppColors.success;
        letterBgColor = AppColors.success;
        letterColor = Colors.white;
      } else if (isSelected && !isCorrect) {
        // User got it wrong - red (don't reveal which is correct)
        bgColor = AppColors.error.withValues(alpha: 0.1);
        borderColor = AppColors.error;
        letterBgColor = AppColors.error;
        letterColor = Colors.white;
      } else {
        // Not selected - neutral, don't highlight correct answer
        bgColor = isDark ? AppColors.darkCard : AppColors.lightCard;
        borderColor = Colors.transparent;
        letterBgColor = isDark ? Colors.white10 : Colors.grey.shade100;
        letterColor = isDark ? Colors.white38 : Colors.grey.shade400;
      }
    } else {
      if (isSelected) {
        bgColor = AppColors.accent.withValues(alpha: 0.1);
        borderColor = AppColors.accent;
        letterBgColor = AppColors.accent;
        letterColor = Colors.white;
      } else {
        bgColor = isDark ? AppColors.darkCard : AppColors.lightCard;
        borderColor = Colors.transparent;
        letterBgColor = isDark ? Colors.white10 : Colors.grey.shade100;
        letterColor = isDark ? Colors.white54 : Colors.grey.shade600;
      }
    }

    return GestureDetector(
      onTap: _hasAnswered ? null : () {
        HapticFeedback.selectionClick();
        setState(() => _selectedAnswer = index);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor, width: 2),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: letterBgColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: _hasAnswered && isSelected
                    ? Icon(
                        isCorrect ? Icons.check_rounded : Icons.close_rounded,
                        color: Colors.white,
                        size: 20,
                      )
                    : Text(
                        letters[index],
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: letterColor,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                options[index],
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: _hasAnswered && !isSelected
                      ? (isDark ? Colors.white38 : Colors.grey.shade400)
                      : (isDark ? Colors.white : const Color(0xFF1A1A2E)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExplanation(Question question, bool isDark) {
    final isCorrect = _selectedAnswer == _shuffledCorrectIndices[_currentIndex];
    final color = isCorrect ? AppColors.success : AppColors.accent;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isCorrect ? Icons.check_circle_outline_rounded : Icons.info_outline_rounded,
            color: color,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isCorrect ? 'Correct!' : 'Not quite!',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
                if (isCorrect) ...[
                  const SizedBox(height: 4),
                  Text(
                    question.explanation,
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white70 : Colors.black87,
                      height: 1.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _submitAnswer() {
    if (_selectedAnswer == null) return;
    _stopwatch.stop();
    
    final isCorrect = _selectedAnswer == _shuffledCorrectIndices[_currentIndex];
    _results.add(isCorrect);
    _responseTimes.add(_stopwatch.elapsedMilliseconds);
    

    if (isCorrect) {
      FeedbackService.instance.onCorrectAnswer();
    } else {
      FeedbackService.instance.onWrongAnswer();
    }
    
    setState(() => _hasAnswered = true);
  }

  void _nextQuestion() {
    if (_currentIndex < widget.questions.length - 1) {
      setState(() {
        _currentIndex++;
        _selectedAnswer = null;
        _hasAnswered = false;
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

  Future<bool> _showExitDialog(bool isDark) async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? AppColors.darkCard : AppColors.lightCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Exit Quiz?',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : const Color(0xFF1A1A2E),
          ),
        ),
        content: Text(
          'Your progress will not be saved.',
          style: TextStyle(color: isDark ? Colors.white60 : Colors.black54),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: TextStyle(color: isDark ? Colors.white54 : Colors.black45),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Exit',
              style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    ) ?? false;
  }
}
