import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/question.dart';
import '../models/subject.dart';
import '../data/questions_database.dart';
import '../services/theme_service.dart';
import '../utils/page_transitions.dart';

// Entry: Module list for a subject
class ModulesScreen extends StatefulWidget {
  final Subject? subject;
  final String? subjectId;
  final String? subjectName;

  const ModulesScreen({
    super.key,
    this.subject,
    this.subjectId,
    this.subjectName,
  });

  @override
  State<ModulesScreen> createState() => _ModulesScreenState();
}

class _ModulesScreenState extends State<ModulesScreen> {
  String get _effectiveSubjectId => widget.subject?.id ?? widget.subjectId ?? '';
  String get _effectiveSubjectName => widget.subject?.name ?? widget.subjectName ?? '';

  late Subject _subject;
  List<Question> _allQuestions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    try {
      _subject = widget.subject ?? CriminologySubjects.getById(_effectiveSubjectId);
    } catch (_) {
      _subject = CriminologySubjects.all[0];
    }

    _allQuestions = QuestionsDatabase.getBySubject(_subject.id);
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : const Color(0xFFF5F5F5),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.darkCard : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 10,
                          ),
                        ],
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
                          'Study Modules',
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                          ),
                        ),
                        Text(
                          _effectiveSubjectName,
                          style: GoogleFonts.poppins(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            if (_isLoading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (_allQuestions.isEmpty)
              Expanded(
                child: Center(
                  child: Text(
                    'No modules available yet',
                    style: GoogleFonts.poppins(fontSize: 16, color: Colors.grey),
                  ),
                ),
              )
            else
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  children: [
                    // View All Module
                    _buildModuleCard(
                      context,
                      icon: Icons.menu_book_rounded,
                      title: 'Complete Study Guide',
                      subtitle: 'All topics combined',
                      count: _allQuestions.length,
                      color: const Color(0xFF8B5CF6),
                      isDark: isDark,
                      onTap: () => _openReader(context, null, _allQuestions),
                    ),

                    const SizedBox(height: 8),

                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
                      child: Text(
                        'TOPICS',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),

                    // Topic modules
                    ..._buildTopicCards(isDark),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildTopicCards(bool isDark) {
    final List<Widget> cards = [];
    final colors = [
      const Color(0xFF3B82F6),
      const Color(0xFF10B981),
      const Color(0xFFF59E0B),
      const Color(0xFFEF4444),
      const Color(0xFF8B5CF6),
      const Color(0xFFEC4899),
      const Color(0xFF06B6D4),
      const Color(0xFF84CC16),
    ];

    for (int i = 0; i < _subject.topics.length; i++) {
      final topic = _subject.topics[i];
      final topicQuestions = _allQuestions.where((q) => q.topic == topic).toList();

      if (topicQuestions.isEmpty) continue;

      final color = colors[i % colors.length];

      cards.add(
        _buildModuleCard(
          context,
          icon: Icons.folder_outlined,
          title: topic,
          subtitle: '${topicQuestions.length} review items',
          count: topicQuestions.length,
          color: color,
          isDark: isDark,
          onTap: () => _openReader(context, topic, topicQuestions),
        ),
      );
      cards.add(const SizedBox(height: 10));
    }

    return cards;
  }

  Widget _buildModuleCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required int count,
    required Color color,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.shade200,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      color: isDark ? Colors.grey.shade500 : Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$count',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
            ),
          ],
        ),
      ),
    );
  }

  void _openReader(BuildContext context, String? topic, List<Question> questions) {
    Navigator.push(
      context,
      SlidePageRoute(
        page: ModuleReaderScreen(
          subject: _subject,
          topic: topic,
          questions: questions,
        ),
      ),
    );
  }
}

// PDF-like reader view
class ModuleReaderScreen extends StatefulWidget {
  final Subject subject;
  final String? topic;
  final List<Question> questions;

  const ModuleReaderScreen({
    super.key,
    required this.subject,
    this.topic,
    required this.questions,
  });

  @override
  State<ModuleReaderScreen> createState() => _ModuleReaderScreenState();
}

class _ModuleReaderScreenState extends State<ModuleReaderScreen> {
  final ScrollController _scrollController = ScrollController();
  int _currentPage = 1;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    // Rough page estimation based on scroll position
    final maxScroll = _scrollController.position.maxScrollExtent;
    if (maxScroll > 0) {
      final page = ((_scrollController.offset / maxScroll) * widget.questions.length).ceil();
      if (page != _currentPage && page > 0 && page <= widget.questions.length) {
        setState(() => _currentPage = page);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF1A1A2E) : const Color(0xFFE8E8E8),
      body: SafeArea(
        child: Column(
          children: [
            // Top bar
            Container(
              color: isDark ? const Color(0xFF1A1A2E) : const Color(0xFFE8E8E8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Icon(
                      Icons.arrow_back_ios_rounded,
                      color: isDark ? Colors.white70 : Colors.black54,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.topic ?? widget.subject.shortName,
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                      ),
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Text(
                    '$_currentPage/${widget.questions.length}',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),

            // PDF-like page
            Expanded(
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 600),
                  margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF252542) : Colors.white,
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 20,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Scrollbar(
                      controller: _scrollController,
                      child: ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(32),
                        itemCount: widget.questions.length + 1, // +1 for header
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            return _buildDocumentHeader(isDark);
                          }
                          return _buildDocumentItem(index - 1, isDark);
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDocumentHeader(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Subject badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            widget.subject.shortName.toUpperCase(),
            style: GoogleFonts.poppins(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.accent,
              letterSpacing: 1.5,
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Title
        Text(
          widget.topic ?? 'Complete Study Guide',
          style: GoogleFonts.poppins(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : const Color(0xFF1A1A2E),
            height: 1.3,
          ),
        ),
        const SizedBox(height: 12),

        // Description
        Text(
          widget.subject.description,
          style: GoogleFonts.poppins(
            fontSize: 15,
            color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
            height: 1.6,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${widget.questions.length} review items',
          style: GoogleFonts.poppins(
            fontSize: 13,
            color: isDark ? Colors.grey.shade500 : Colors.grey.shade500,
          ),
        ),

        // Divider
        Container(
          margin: const EdgeInsets.symmetric(vertical: 32),
          height: 1,
          color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.shade200,
        ),
      ],
    );
  }

  Widget _buildDocumentItem(int index, bool isDark) {
    final q = widget.questions[index];
    final letters = ['A', 'B', 'C', 'D'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header with number
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${index + 1}.',
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.accent,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    q.questionText,
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: [
                      _buildTag(q.difficulty.name, isDark),
                      if (widget.topic == null)
                        _buildTag(q.topic, isDark, isTopic: true),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),

        // Options - clean list format
        Padding(
          padding: const EdgeInsets.only(left: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: List.generate(q.options.length, (optIndex) {
              final isCorrect = optIndex == q.correctAnswerIndex;

              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      margin: const EdgeInsets.only(top: 2),
                      decoration: BoxDecoration(
                        color: isCorrect
                            ? AppColors.success.withValues(alpha: 0.15)
                            : Colors.transparent,
                        border: Border.all(
                          color: isCorrect
                              ? AppColors.success
                              : (isDark
                                  ? Colors.white.withValues(alpha: 0.15)
                                  : Colors.grey.shade300),
                          width: isCorrect ? 2 : 1,
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Center(
                        child: isCorrect
                            ? Icon(
                                Icons.check_rounded,
                                size: 14,
                                color: AppColors.success,
                              )
                            : Text(
                                letters[optIndex],
                                style: GoogleFonts.poppins(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: isDark
                                      ? Colors.white50
                                      : Colors.grey.shade500,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        q.options[optIndex],
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          color: isCorrect
                              ? (isDark ? Colors.white : const Color(0xFF1A1A2E))
                              : (isDark ? Colors.white70 : Colors.black87),
                          fontWeight: isCorrect ? FontWeight.w500 : FontWeight.normal,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
        ),

        const SizedBox(height: 16),

        // Explanation / Rationale - like a textbook sidebar
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(left: 32),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF1E3A5F).withValues(alpha: 0.15)
                : const Color(0xFFEEF2FF),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isDark
                  ? const Color(0xFF8B5CF6).withValues(alpha: 0.2)
                  : const Color(0xFF8B5CF6).withValues(alpha: 0.15),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.auto_stories_rounded,
                size: 18,
                color: const Color(0xFF8B5CF6),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  q.explanation,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: isDark ? Colors.white70 : Colors.black87,
                    height: 1.7,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Page break divider
        Container(
          margin: const EdgeInsets.symmetric(vertical: 32),
          height: 1,
          color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.grey.shade200,
        ),
      ],
    );
  }

  Widget _buildTag(String text, bool isDark, {bool isTopic = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: isTopic
            ? (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.shade100)
            : _getDifficultyColor(text).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        isTopic ? text : text.toUpperCase(),
        style: GoogleFonts.poppins(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: isTopic
              ? (isDark ? Colors.grey.shade400 : Colors.grey.shade600)
              : _getDifficultyColor(text),
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Color _getDifficultyColor(String difficulty) {
    switch (difficulty.toLowerCase()) {
      case 'easy':
        return AppColors.success;
      case 'hard':
        return AppColors.error;
      default:
        return Colors.orange;
    }
  }
}
