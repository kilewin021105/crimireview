import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../models/question.dart';
import '../models/subject.dart';
import '../services/question_repository.dart';
import '../widgets/ui/ui.dart';
import '../services/feedback_service.dart';

class FlashcardScreen extends StatefulWidget {
  final Subject? subject;
  final String? subjectId;
  final String? subjectName;

  const FlashcardScreen({
    super.key,
    this.subject,
    this.subjectId,
    this.subjectName,
  });

  @override
  State<FlashcardScreen> createState() => _FlashcardScreenState();
}

class _FlashcardScreenState extends State<FlashcardScreen> with SingleTickerProviderStateMixin {
  List<Question> _questions = [];
  bool _isLoading = true;
  int _currentIndex = 0;
  bool _isFlipped = false;
  late AnimationController _flipController;
  late Animation<double> _flipAnimation;
  

  double _dragX = 0;
  double _dragY = 0;
  double _rotation = 0;
  
  int _knownCount = 0;
  int _reviewCount = 0;

  @override
  void initState() {
    super.initState();
    _loadQuestions();
    
    _flipController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    
    _flipAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _flipController, curve: Curves.easeInOut),
    );
  }

  String get _effectiveSubjectId => widget.subject?.id ?? widget.subjectId ?? '';
  String get _effectiveSubjectName => widget.subject?.name ?? widget.subjectName ?? '';

  /// Panel note 7: cards come from `QuestionRepository` (Supabase-backed),
  /// never a compiled-in file.
  Future<void> _loadQuestions() async {
    final questions = await QuestionRepository.instance.bySubject(_effectiveSubjectId);
    if (!mounted) return;
    setState(() {
      _questions = questions..shuffle();
      _isLoading = false;
    });
  }

  void _flipCard() {
    FeedbackService.instance.lightTap();
    if (_isFlipped) {
      _flipController.reverse();
    } else {
      _flipController.forward();
    }
    setState(() => _isFlipped = !_isFlipped);
  }

  void _nextCard({bool known = false}) {

    FeedbackService.instance.onFlashcardSwipe();
    
    if (known) {
      _knownCount++;
    } else {
      _reviewCount++;
    }
    
    setState(() {
      _dragX = 0;
      _dragY = 0;
      _rotation = 0;
      _isFlipped = false;
    });
    _flipController.reset();
    
    if (_currentIndex < _questions.length - 1) {
      setState(() => _currentIndex++);
    } else {
      _showResults();
    }
  }

  void _showResults() {
    final total = _questions.length;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final p = dialogContext.palette;
        final text = dialogContext.textStyles;
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconBadge(icon: Icons.celebration_rounded, color: p.gold, size: 60, radius: 20),
                const SizedBox(height: 16),
                Text('Session complete!', style: text.titleLarge),
                const SizedBox(height: 4),
                Text('You went through all $total cards.', style: text.bodyMedium),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: StatTile(
                        icon: Icons.check_circle_rounded,
                        value: '$_knownCount',
                        label: 'Known',
                        color: p.success,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: StatTile(
                        icon: Icons.refresh_rounded,
                        value: '$_reviewCount',
                        label: 'To review',
                        color: p.warning,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: SecondaryButton(
                        label: 'Done',
                        height: 48,
                        onPressed: () {
                          Navigator.pop(dialogContext);
                          Navigator.pop(context);
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: PrimaryButton(
                        label: 'Study again',
                        height: 48,
                        onPressed: () {
                          Navigator.pop(dialogContext);
                          setState(() {
                            _currentIndex = 0;
                            _knownCount = 0;
                            _reviewCount = 0;
                            _isFlipped = false;
                          });
                          _flipController.reset();
                          _loadQuestions();
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _flipController.dispose();
    super.dispose();
  }

  Color get _subjectColor => AppColors.subjectColor(_effectiveSubjectId);

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = context.textStyles;

    if (_isLoading) {
      return Scaffold(
        appBar: AppTopBar(title: 'Flashcards', subtitle: _effectiveSubjectName),
        body: const LoadingView(label: 'Shuffling your deck...'),
      );
    }

    if (_questions.isEmpty) {
      return Scaffold(
        appBar: AppTopBar(title: 'Flashcards', subtitle: _effectiveSubjectName),
        body: Center(
          child: EmptyState(
            icon: Icons.style_rounded,
            title: 'No cards yet',
            message: 'There are no questions for this subject yet. Check back after your next sync.',
            actionLabel: 'Go back',
            onAction: () => Navigator.pop(context),
          ),
        ),
      );
    }

    final question = _questions[_currentIndex];
    final swipe = (_dragX / 110).clamp(-1.0, 1.0);

    return Scaffold(
      appBar: AppTopBar(
        title: 'Flashcards',
        subtitle: _effectiveSubjectName,
        actions: [
          Pill(label: '${_currentIndex + 1} / ${_questions.length}', color: _subjectColor),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ContentWidth(
          maxWidth: 560,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                child: Column(
                  children: [
                    AppProgressBar(
                      value: (_currentIndex + 1) / _questions.length,
                      color: _subjectColor,
                      height: 6,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Pill(label: '$_reviewCount to review', icon: Icons.refresh_rounded, color: p.warning),
                        const Spacer(),
                        Pill(label: '$_knownCount known', icon: Icons.check_rounded, color: p.success),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: GestureDetector(
                  onTap: _flipCard,
                  onPanUpdate: (details) {
                    setState(() {
                      _dragX += details.delta.dx;
                      _dragY += details.delta.dy;
                      _rotation = _dragX / 300;
                    });
                  },
                  onPanEnd: (details) {
                    if (_dragX > 100) {
                      _nextCard(known: true);
                    } else if (_dragX < -100) {
                      _nextCard(known: false);
                    } else {
                      setState(() {
                        _dragX = 0;
                        _dragY = 0;
                        _rotation = 0;
                      });
                    }
                  },
                  child: AnimatedBuilder(
                    animation: _flipAnimation,
                    builder: (context, child) {
                      return Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.identity()
                          ..translateByDouble(_dragX, _dragY, 0, 1)
                          ..rotateZ(_rotation * 0.3)
                          ..setEntry(3, 2, 0.001)
                          ..rotateY(math.pi * _flipAnimation.value),
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: _flipAnimation.value < 0.5
                                  ? _buildCardFront(question)
                                  : Transform(
                                      alignment: Alignment.center,
                                      transform: Matrix4.rotationY(math.pi),
                                      child: _buildCardBack(question),
                                    ),
                            ),
                            if (swipe.abs() > 0.05)
                              Positioned(
                                top: 18,
                                left: swipe > 0 ? 38 : null,
                                right: swipe < 0 ? 38 : null,
                                child: Opacity(
                                  opacity: swipe.abs(),
                                  child: Transform.rotate(
                                    angle: swipe > 0 ? -0.2 : 0.2,
                                    child: _swipeStamp(
                                      swipe > 0 ? 'KNOW IT' : 'REVIEW',
                                      swipe > 0 ? p.success : p.warning,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: SecondaryButton(
                        label: 'Review again',
                        icon: Icons.refresh_rounded,
                        color: p.warning,
                        onPressed: () => _nextCard(known: false),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: PrimaryButton(
                        label: 'I know it',
                        icon: Icons.check_rounded,
                        color: p.success,
                        onPressed: () => _nextCard(known: true),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text('or swipe the card left / right', style: text.bodySmall),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _swipeStamp(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color, width: 2.5),
        color: context.palette.surface.withValues(alpha: 0.9),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: kAppFontFamily,
          fontSize: 18,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
          color: color,
        ),
      ),
    );
  }

  Widget _buildCardFront(Question question) {
    final text = context.textStyles;
    final color = _subjectColor;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(color, Colors.white, 0.08)!,
            Color.lerp(color, Colors.black, 0.32)!,
          ],
        ),
        borderRadius: BorderRadius.circular(AppSpace.radiusXl),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.3),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Pill(
                label: 'Question ${_currentIndex + 1}',
                color: Colors.white,
                background: Colors.white.withValues(alpha: 0.16),
              ),
              const Spacer(),
              Icon(Icons.style_rounded, color: Colors.white.withValues(alpha: 0.6), size: 20),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                child: Text(
                  question.questionText,
                  textAlign: TextAlign.center,
                  style: text.titleLarge?.copyWith(
                    color: Colors.white,
                    height: 1.45,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.touch_app_rounded, color: Colors.white.withValues(alpha: 0.75), size: 16),
              const SizedBox(width: 6),
              Text(
                'Tap to see the answer',
                style: text.labelMedium?.copyWith(color: Colors.white.withValues(alpha: 0.75)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCardBack(Question question) {
    final p = context.palette;
    final text = context.textStyles;
    final correctAnswer = question.options[question.correctAnswerIndex];
    final hasExplanation = question.explanation.isNotEmpty;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(AppSpace.radiusXl),
        border: Border.all(color: p.border),
        boxShadow: [
          BoxShadow(color: p.shadow, blurRadius: 24, offset: const Offset(0, 12)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: p.successSoft,
              borderRadius: BorderRadius.circular(AppSpace.radiusMd + 2),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle_rounded, color: p.success, size: 17),
                    const SizedBox(width: 6),
                    Text('ANSWER', style: text.labelSmall?.copyWith(color: p.success)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  correctAnswer,
                  textAlign: TextAlign.center,
                  style: text.titleMedium?.copyWith(color: p.textPrimary, height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: hasExplanation
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.lightbulb_outline_rounded, size: 17, color: p.gold),
                          const SizedBox(width: 6),
                          Text('Why', style: text.titleSmall),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Text(
                            question.explanation,
                            style: text.bodyMedium?.copyWith(color: p.textPrimary.withValues(alpha: 0.82)),
                          ),
                        ),
                      ),
                    ],
                  )
                : Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.psychology_rounded, size: 40, color: p.textTertiary),
                        const SizedBox(height: 8),
                        Text('Remember this answer!', style: text.bodyMedium),
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text('Tap to flip back', style: text.bodySmall),
          ),
        ],
      ),
    );
  }
}
