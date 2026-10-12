import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/subject.dart';
import '../utils/page_transitions.dart';
import '../utils/responsive.dart';
import '../widgets/ui/ui.dart';

// Module list screen
class ModulesScreen extends StatefulWidget {
  final Subject? subject;
  final String? subjectId;
  final String? subjectName;

  const ModulesScreen({super.key, this.subject, this.subjectId, this.subjectName});

  @override
  State<ModulesScreen> createState() => _ModulesScreenState();
}

class _ModulesScreenState extends State<ModulesScreen> {
  String get _sid => widget.subject?.id ?? widget.subjectId ?? '';
  String get _name => widget.subject?.name ?? widget.subjectName ?? '';
  Map<String, dynamic>? _moduleData;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadModule();
  }

  Future<void> _loadModule() async {
    try {
      final jsonString = await rootBundle.loadString('assets/modules/${_sid}_module.json');
      if (!mounted) return;
      setState(() {
        _moduleData = jsonDecode(jsonString);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final padding = Responsive.horizontalPadding(context);
    final color = AppColors.subjectColor(_sid);

    return Scaffold(
      appBar: AppTopBar(title: _name, subtitle: 'Study module'),
      body: _loading
          ? const LoadingView(label: 'Opening module...')
          : _moduleData == null
              ? Center(
                  child: EmptyState(
                    icon: Icons.menu_book_rounded,
                    title: 'No module yet',
                    message: 'The study module for this subject is not available yet.',
                    color: color,
                  ),
                )
              : ListView(
                  padding: EdgeInsets.fromLTRB(padding, 4, padding, 28),
                  children: [
                    ContentWidth(child: _buildHero(color)),
                    const SizedBox(height: AppSpace.section),
                    ContentWidth(
                      child: SectionHeader(
                        title: 'Chapters',
                        subtitle: '${(_moduleData!['chapters'] as List).length} chapters in this module',
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...(_moduleData!['chapters'] as List).asMap().entries.map((entry) {
                      final ch = entry.value;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: ContentWidth(
                          child: Appear(
                            index: entry.key,
                            child: _buildChapterCard(ch, color),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
    );
  }

  Widget _buildHero(Color color) {
    final text = context.textStyles;
    final chapters = (_moduleData!['chapters'] as List).length;
    return GradientCard(
      gradient: LinearGradient(
        colors: [Color.lerp(color, Colors.white, 0.06)!, Color.lerp(color, Colors.black, 0.35)!],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      onTap: () {
        HapticFeedback.lightImpact();
        _openReader(context, null);
      },
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Pill(
                  label: '${_moduleData!['totalItems']} review items · $chapters chapters',
                  color: Colors.white,
                  background: Colors.white.withValues(alpha: 0.16),
                ),
                const SizedBox(height: 12),
                Text(
                  'Read the full module',
                  style: text.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  'Start from chapter 1 and work through it in order.',
                  style: text.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.78)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(Icons.auto_stories_rounded, color: Colors.white, size: 28),
          ),
        ],
      ),
    );
  }

  Widget _buildChapterCard(dynamic ch, Color color) {
    final p = context.palette;
    final text = context.textStyles;
    return AppCard(
      padding: const EdgeInsets.all(14),
      onTap: () {
        HapticFeedback.lightImpact();
        _openReader(context, ch['number'] - 1);
      },
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: context.isDarkMode ? 0.2 : 0.11),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Text(
              '${ch['number']}',
              style: text.titleMedium?.copyWith(color: color, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(ch['title'], style: text.titleSmall),
                const SizedBox(height: 2),
                Text('${ch['itemCount']} items', style: text.bodySmall),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: p.textTertiary),
        ],
      ),
    );
  }

  void _openReader(BuildContext ctx, int? startChapter) {
    Navigator.push(
      ctx,
      SlidePageRoute(
        page: ModuleReaderScreen(
          moduleData: _moduleData!,
          startChapter: startChapter,
          accent: AppColors.subjectColor(_sid),
        ),
      ),
    );
  }
}

// Chapter reader
class ModuleReaderScreen extends StatefulWidget {
  final Map<String, dynamic> moduleData;
  final int? startChapter;
  final Color? accent;

  const ModuleReaderScreen({super.key, required this.moduleData, this.startChapter, this.accent});

  @override
  State<ModuleReaderScreen> createState() => _ModuleReaderScreenState();
}

class _ModuleReaderScreenState extends State<ModuleReaderScreen> {
  late final List<dynamic> _chapters;
  int _currentChapter = 0;
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<double> _readProgress = ValueNotifier(0);

  @override
  void initState() {
    super.initState();
    _chapters = widget.moduleData['chapters'];
    _currentChapter = widget.startChapter ?? 0;
    _scrollController.addListener(_updateProgress);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _readProgress.dispose();
    super.dispose();
  }

  void _updateProgress() {
    if (!_scrollController.hasClients) return;
    final max = _scrollController.position.maxScrollExtent;
    _readProgress.value = max <= 0 ? 1 : (_scrollController.offset / max).clamp(0.0, 1.0);
  }

  void _goToChapter(int index) {
    if (index >= 0 && index < _chapters.length) {
      setState(() => _currentChapter = index);
      _scrollController.jumpTo(0);
      _readProgress.value = 0;
    }
  }

  Color get _accent => widget.accent ?? context.palette.primary;

  void _showContents() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        final p = sheetContext.palette;
        final text = sheetContext.textStyles;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(sheetContext).size.height * 0.7),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Text('Contents', style: text.titleLarge),
                ),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    itemCount: _chapters.length,
                    itemBuilder: (context, i) {
                      final selected = i == _currentChapter;
                      return ListTile(
                        selected: selected,
                        selectedTileColor: p.primarySoft,
                        leading: Text(
                          '${i + 1}',
                          style: text.titleSmall?.copyWith(color: selected ? p.primary : p.textTertiary),
                        ),
                        minLeadingWidth: 20,
                        title: Text(
                          _chapters[i]['title'],
                          style: text.titleSmall?.copyWith(color: selected ? p.onPrimarySoft : p.textPrimary),
                        ),
                        trailing: selected ? Icon(Icons.bookmark_rounded, color: p.primary, size: 20) : null,
                        onTap: () {
                          Navigator.pop(sheetContext);
                          _goToChapter(i);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = context.textStyles;
    final chapter = _chapters[_currentChapter];
    final isLast = _currentChapter == _chapters.length - 1;

    return Scaffold(
      appBar: AppTopBar(
        title: chapter['title'],
        subtitle: 'Chapter ${_currentChapter + 1} of ${_chapters.length}',
        actions: [
          ToolbarIconButton(
            icon: Icons.format_list_bulleted_rounded,
            tooltip: 'Contents',
            size: 40,
            onPressed: _showContents,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(3),
          child: ValueListenableBuilder<double>(
            valueListenable: _readProgress,
            builder: (context, value, _) => LinearProgressIndicator(
              value: value,
              minHeight: 3,
              color: _accent,
              backgroundColor: p.border,
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: Scrollbar(
              controller: _scrollController,
              child: ListView(
                controller: _scrollController,
                padding: EdgeInsets.fromLTRB(
                  Responsive.horizontalPadding(context) + 4,
                  24,
                  Responsive.horizontalPadding(context) + 4,
                  32,
                ),
                children: [
                  ContentWidth(
                    maxWidth: 680,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Pill(
                          label: (widget.moduleData['title'] as String).toUpperCase(),
                          color: _accent,
                          fontSize: 10.5,
                        ),
                        const SizedBox(height: 18),
                        Text(
                          'Chapter ${chapter['number']}',
                          style: text.labelLarge?.copyWith(color: _accent),
                        ),
                        const SizedBox(height: 6),
                        Text(chapter['title'], style: text.headlineMedium),
                        const SizedBox(height: 14),
                        Text(
                          chapter['introduction'],
                          style: text.bodyLarge?.copyWith(color: p.textSecondary, height: 1.7),
                        ),
                        const SizedBox(height: 20),
                        Divider(color: p.border),
                        const SizedBox(height: 20),
                        _buildChapterContent(chapter['content'] as String),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: p.surface,
              border: Border(top: BorderSide(color: p.border)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: ContentWidth(
                  maxWidth: 680,
                  child: Row(
                    children: [
                      if (_currentChapter > 0) ...[
                        Expanded(
                          child: SecondaryButton(
                            label: 'Previous',
                            icon: Icons.arrow_back_rounded,
                            onPressed: () => _goToChapter(_currentChapter - 1),
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: isLast
                            ? PrimaryButton(
                                label: 'Finish',
                                icon: Icons.check_circle_rounded,
                                color: p.success,
                                onPressed: () => Navigator.pop(context),
                              )
                            : PrimaryButton(
                                label: 'Next chapter',
                                icon: Icons.arrow_forward_rounded,
                                trailingIcon: true,
                                onPressed: () => _goToChapter(_currentChapter + 1),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChapterContent(String content) {
    final p = context.palette;
    final text = context.textStyles;
    final body = text.bodyLarge?.copyWith(color: p.textPrimary.withValues(alpha: 0.86), height: 1.75);
    final lines = content.split('\n');
    final widgets = <Widget>[];
    int i = 0;

    while (i < lines.length) {
      final line = lines[i];
      final stripped = line.trim();

      // Skip Review Items section (empty since questions removed)
      if (stripped.startsWith('### Review Items')) {
        i++;
        continue;
      }

      // Heading ##
      if (stripped.startsWith('## ')) {
        widgets.add(const SizedBox(height: 8));
        widgets.add(Text(stripped.substring(3), style: text.headlineSmall));
        widgets.add(const SizedBox(height: 12));
        i++;
        continue;
      }

      // Subheading ###
      if (stripped.startsWith('### ')) {
        widgets.add(const SizedBox(height: 18));
        widgets.add(Row(
          children: [
            Container(
              width: 4,
              height: 20,
              decoration: BoxDecoration(color: _accent, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                stripped.substring(4).replaceFirst(':', ''),
                style: text.titleLarge,
              ),
            ),
          ],
        ));
        widgets.add(const SizedBox(height: 12));
        i++;
        continue;
      }

      // Bullet point
      if (stripped.startsWith('- ')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              margin: const EdgeInsets.only(top: 10),
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: _accent, shape: BoxShape.circle),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(stripped.substring(2), style: body)),
          ]),
        ));
        i++;
        continue;
      }

      // Empty line
      if (stripped.isEmpty) {
        i++;
        continue;
      }

      // Regular paragraph
      widgets.add(Text(stripped, style: body));
      widgets.add(const SizedBox(height: 10));
      i++;
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: widgets);
  }
}
