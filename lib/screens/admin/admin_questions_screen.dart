import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/question.dart';
import '../../models/subject.dart';
import '../../services/admin_service.dart';
import '../../services/theme_service.dart';
import '../../utils/page_transitions.dart';
import '../../utils/responsive.dart';
import 'admin_document_generation_screen.dart';
import 'admin_question_editor_screen.dart';

/// The question bank the admin actually edits.
///
/// Panel note 7: *"Do NOT put your questions in your code. It should have an
/// ADMIN to add questions."* This screen, plus [AdminQuestionEditorScreen],
/// is that admin. Every row here is a live `public.questions` record --
/// deactivating or editing one is visible to students on their next sync
/// (`QuestionRepository.invalidate()` is called after every write).
class AdminQuestionsScreen extends StatefulWidget {
  /// False when this screen is a tab root inside `AdminShellScreen` (no
  /// previous route to pop back to).
  final bool showBackButton;

  /// Pre-seeds the source filter -- set by `AdminDocumentGenerationScreen`'s
  /// "Review N questions" button to `QuestionSource.generated` so the admin
  /// lands directly on the AIG output instead of the full bank.
  final QuestionSource? initialSource;

  /// Pre-seeds the template filter, scoping the list to one upload's batch
  /// (`template_id` on `public.questions` = the `document_uploads.id` that
  /// produced it -- see `supabase_document_generation.sql`). Unlike
  /// [initialSource], this isn't user-togglable from the filter row: it's a
  /// deep link into one specific review batch.
  final String? initialTemplateId;

  const AdminQuestionsScreen({
    super.key,
    this.showBackButton = true,
    this.initialSource,
    this.initialTemplateId,
  });

  @override
  State<AdminQuestionsScreen> createState() => _AdminQuestionsScreenState();
}

class _AdminQuestionsScreenState extends State<AdminQuestionsScreen> {
  static const int _pageSize = 30;

  final TextEditingController _searchController = TextEditingController();
  String? _subjectId;
  Difficulty? _difficulty;
  bool _includeInactive = true;
  late QuestionSource? _source;

  final List<AdminQuestionEntry> _questions = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _source = widget.initialSource;
    _reload();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
      _questions.clear();
      _hasMore = true;
    });
    try {
      final results = await AdminService.instance.listQuestions(
        subjectId: _subjectId,
        difficulty: _difficulty,
        includeInactive: _includeInactive,
        search: _searchController.text,
        source: _source,
        templateId: widget.initialTemplateId,
        limit: _pageSize,
        offset: 0,
      );
      if (!mounted) return;
      setState(() {
        _questions.addAll(results);
        _hasMore = results.length == _pageSize;
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

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final results = await AdminService.instance.listQuestions(
        subjectId: _subjectId,
        difficulty: _difficulty,
        includeInactive: _includeInactive,
        search: _searchController.text,
        source: _source,
        templateId: widget.initialTemplateId,
        limit: _pageSize,
        offset: _questions.length,
      );
      if (!mounted) return;
      setState(() {
        _questions.addAll(results);
        _hasMore = results.length == _pageSize;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      _showSnack(e.toString(), isError: true);
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.error : AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<void> _openEditor([Question? existing]) async {
    final saved = await Navigator.push<bool>(
      context,
      SlidePageRoute(page: AdminQuestionEditorScreen(existing: existing)),
    );
    if (saved == true) _reload();
  }

  Future<void> _toggleActive(AdminQuestionEntry entry) async {
    final goingActive = !entry.isActive;
    try {
      await AdminService.instance.setActive(entry.question.id, goingActive);
      _showSnack(goingActive ? 'Question restored' : 'Question deactivated');
      _reload();
    } catch (e) {
      _showSnack('Failed: $e', isError: true);
    }
  }

  Future<void> _confirmDelete(Question q) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? AppColors.darkCard : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete permanently?'),
        content: Text(
          'This removes "${q.questionText}" from the database entirely. '
          'Prefer deactivating unless this was a mistake -- deactivated items '
          'can be restored, this cannot.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await AdminService.instance.deleteQuestionPermanently(q.id);
      _showSnack('Question deleted');
      _reload();
    } catch (e) {
      _showSnack('Failed: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final padding = Responsive.horizontalPadding(context);

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      appBar: _buildAppBar(isDark),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        backgroundColor: AppColors.accent,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('New Question', style: TextStyle(color: Colors.white)),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(padding, 8, padding, 0),
              child: _buildFilters(isDark),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? _buildError(isDark)
                      : _questions.isEmpty
                          ? _buildEmpty(isDark)
                          : NotificationListener<ScrollNotification>(
                              onNotification: (notification) {
                                if (notification.metrics.pixels >=
                                    notification.metrics.maxScrollExtent - 200) {
                                  _loadMore();
                                }
                                return false;
                              },
                              child: RefreshIndicator(
                                onRefresh: _reload,
                                color: AppColors.accent,
                                child: ListView.builder(
                                  padding: EdgeInsets.fromLTRB(padding, 0, padding, 100),
                                  itemCount: _questions.length + (_hasMore ? 1 : 0),
                                  itemBuilder: (context, i) {
                                    if (i >= _questions.length) {
                                      return const Padding(
                                        padding: EdgeInsets.symmetric(vertical: 16),
                                        child: Center(child: CircularProgressIndicator()),
                                      );
                                    }
                                    return _buildQuestionCard(_questions[i], isDark);
                                  },
                                ),
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(bool isDark) {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      automaticallyImplyLeading: false,
      leading: widget.showBackButton
          ? IconButton(
              onPressed: () => Navigator.pop(context),
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkCard : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)],
                ),
                child: Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: isDark ? Colors.white : const Color(0xFF1A1A2E)),
              ),
            )
          : null,
      title: Text(
        'Questions',
        style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w600, color: isDark ? Colors.white : const Color(0xFF1A1A2E)),
      ),
      centerTitle: true,
      // Only on the tab-root instance -- a screen already deep-linked into
      // one upload's review batch (widget.showBackButton == true) doesn't
      // need a second way to start another upload.
      actions: widget.showBackButton
          ? null
          : [
              IconButton(
                tooltip: 'Generate from Document',
                icon: Icon(Icons.auto_awesome_rounded, color: isDark ? Colors.white : const Color(0xFF1A1A2E)),
                onPressed: () => Navigator.push(
                  context,
                  SlidePageRoute(page: const AdminDocumentGenerationScreen()),
                ),
              ),
            ],
    );
  }

  Widget _buildFilters(bool isDark) {
    return Column(
      children: [
        TextField(
          controller: _searchController,
          onSubmitted: (_) => _reload(),
          style: TextStyle(color: isDark ? Colors.white : const Color(0xFF1A1A2E)),
          decoration: InputDecoration(
            hintText: 'Search question text or topic',
            hintStyle: TextStyle(color: isDark ? Colors.grey.shade500 : Colors.grey.shade500),
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: IconButton(
              icon: const Icon(Icons.arrow_forward_rounded),
              onPressed: _reload,
            ),
            filled: true,
            fillColor: isDark ? AppColors.darkCard : AppColors.lightCard,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(vertical: 0),
          ),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildDropdownChip<String?>(
                isDark: isDark,
                value: _subjectId,
                label: 'All Subjects',
                items: [
                  const DropdownMenuItem(value: null, child: Text('All Subjects')),
                  for (final s in CriminologySubjects.all)
                    DropdownMenuItem(value: s.id, child: Text(s.shortName)),
                ],
                onChanged: (v) {
                  setState(() => _subjectId = v);
                  _reload();
                },
              ),
              const SizedBox(width: 8),
              _buildDropdownChip<Difficulty?>(
                isDark: isDark,
                value: _difficulty,
                label: 'All Difficulties',
                items: [
                  const DropdownMenuItem(value: null, child: Text('All Difficulties')),
                  for (final d in Difficulty.values)
                    DropdownMenuItem(value: d, child: Text(d.name[0].toUpperCase() + d.name.substring(1))),
                ],
                onChanged: (v) {
                  setState(() => _difficulty = v);
                  _reload();
                },
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('Show inactive'),
                selected: _includeInactive,
                onSelected: (v) {
                  setState(() => _includeInactive = v);
                  _reload();
                },
                selectedColor: AppColors.accent.withValues(alpha: 0.18),
                checkmarkColor: AppColors.accent,
                backgroundColor: isDark ? AppColors.darkCard : AppColors.lightCard,
                labelStyle: TextStyle(
                  fontSize: 12,
                  color: _includeInactive ? AppColors.accent : (isDark ? Colors.grey.shade400 : Colors.grey.shade700),
                ),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide.none),
              ),
              // Only offered when the screen wasn't already deep-linked into
              // one upload's batch (widget.initialTemplateId) -- that case
              // is already scoped tighter than this chip would express.
              if (widget.initialTemplateId == null) ...[
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('Generated only'),
                  selected: _source == QuestionSource.generated,
                  onSelected: (v) {
                    setState(() => _source = v ? QuestionSource.generated : null);
                    _reload();
                  },
                  selectedColor: const Color(0xFFEC4899).withValues(alpha: 0.18),
                  checkmarkColor: const Color(0xFFEC4899),
                  backgroundColor: isDark ? AppColors.darkCard : AppColors.lightCard,
                  labelStyle: TextStyle(
                    fontSize: 12,
                    color: _source == QuestionSource.generated
                        ? const Color(0xFFEC4899)
                        : (isDark ? Colors.grey.shade400 : Colors.grey.shade700),
                  ),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide.none),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDropdownChip<T>({
    required bool isDark,
    required T value,
    required String label,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(20),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          items: items,
          onChanged: (v) => onChanged(v as T),
          isDense: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
          style: TextStyle(fontSize: 12, color: isDark ? Colors.white : const Color(0xFF1A1A2E)),
          dropdownColor: isDark ? AppColors.darkCard : Colors.white,
        ),
      ),
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
            Text('Could not load questions.\n$_error', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _reload,
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent),
              child: const Text('Retry', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_rounded, size: 48, color: isDark ? Colors.grey.shade700 : Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              'No questions match these filters.',
              style: TextStyle(color: isDark ? Colors.grey.shade500 : Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestionCard(AdminQuestionEntry entry, bool isDark) {
    final q = entry.question;
    final diffColor = _difficultyColor(q.difficulty);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(16),
        border: entry.isActive ? null : Border.all(color: AppColors.error.withValues(alpha: 0.4)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openEditor(q),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _buildTag(q.subject.replaceAll('_', ' '), AppColors.accent, isDark),
                  const SizedBox(width: 6),
                  _buildTag(q.difficulty.name, diffColor, isDark),
                  const SizedBox(width: 6),
                  if (q.source != QuestionSource.admin) _buildTag(q.source.name, const Color(0xFFEC4899), isDark),
                  if (!entry.isActive) ...[
                    const SizedBox(width: 6),
                    _buildTag('inactive', AppColors.error, isDark),
                  ],
                  const Spacer(),
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert_rounded, size: 20, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                    onSelected: (action) {
                      switch (action) {
                        case 'edit':
                          _openEditor(q);
                          break;
                        case 'deactivate':
                          _toggleActive(entry);
                          break;
                        case 'delete':
                          _confirmDelete(q);
                          break;
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(value: 'edit', child: Text('Edit')),
                      PopupMenuItem(
                        value: 'deactivate',
                        child: Text(entry.isActive ? 'Deactivate' : 'Restore'),
                      ),
                      const PopupMenuItem(value: 'delete', child: Text('Delete permanently')),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                q.topic,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
              ),
              const SizedBox(height: 4),
              Text(
                q.questionText,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, color: isDark ? Colors.white : const Color(0xFF1A1A2E)),
              ),
              const SizedBox(height: 4),
              Text(
                '${q.answerOptions.length} options · v${q.version}${q.hasRationales ? ' · has rationales' : ''}',
                style: TextStyle(fontSize: 11, color: isDark ? Colors.grey.shade600 : Colors.grey.shade500),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTag(String text, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(8)),
      child: Text(text, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color)),
    );
  }

  Color _difficultyColor(Difficulty d) {
    switch (d) {
      case Difficulty.easy:
        return AppColors.success;
      case Difficulty.medium:
        return AppColors.warning;
      case Difficulty.hard:
        return AppColors.error;
    }
  }
}
