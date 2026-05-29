import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/subject.dart';
import '../services/theme_service.dart';
import '../utils/page_transitions.dart';

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
      setState(() {
        _moduleData = jsonDecode(jsonString);
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
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
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)],
                      ),
                      child: Icon(Icons.arrow_back_ios_rounded, color: isDark ? Colors.white70 : Colors.black54, size: 20),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Study Modules', style: GoogleFonts.poppins(fontSize: 13, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600)),
                        Text(_name, style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w700, color: isDark ? Colors.white : const Color(0xFF1A1A2E)), overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            if (_loading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (_moduleData == null)
              Expanded(child: Center(child: Text('No modules available', style: GoogleFonts.poppins(fontSize: 16, color: Colors.grey))))
            else
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  children: [
                    // Read Full Module card
                    _buildModuleCard(
                      context,
                      icon: Icons.menu_book_rounded,
                      title: 'Read Full Module',
                      subtitle: '${_moduleData!['totalItems']} review items',
                      color: const Color(0xFF8B5CF6),
                      isDark: isDark,
                      onTap: () => _openReader(context, null),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
                      child: Text('CHAPTERS', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: isDark ? Colors.grey.shade500 : Colors.grey.shade600, letterSpacing: 1.2)),
                    ),
                    // Chapter cards
                    ...(_moduleData!['chapters'] as List).map((ch) {
                      final colors = [const Color(0xFF3B82F6), const Color(0xFF10B981), const Color(0xFFF59E0B), const Color(0xFFEF4444), const Color(0xFF8B5CF6), const Color(0xFFEC4899), const Color(0xFF06B6D4), const Color(0xFF84CC16)];
                      final color = colors[(ch['number'] as int - 1) % colors.length];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _buildModuleCard(
                          context,
                          icon: Icons.folder_outlined,
                          title: ch['title'],
                          subtitle: '${ch['itemCount']} items',
                          color: color,
                          isDark: isDark,
                          onTap: () => _openReader(context, ch['number'] - 1),
                        ),
                      );
                    }),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildModuleCard(BuildContext ctx, {required IconData icon, required String title, required String subtitle, required Color color, required bool isDark, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: () { HapticFeedback.lightImpact(); onTap(); },
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.shade200),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Row(
          children: [
            Container(width: 52, height: 52, decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)), child: Icon(icon, color: color, size: 26)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600, color: isDark ? Colors.white : const Color(0xFF1A1A2E))),
                const SizedBox(height: 2),
                Text(subtitle, style: GoogleFonts.poppins(fontSize: 13, color: isDark ? Colors.grey.shade500 : Colors.grey.shade500)),
              ]),
            ),
            Icon(Icons.chevron_right_rounded, color: isDark ? Colors.grey.shade600 : Colors.grey.shade400),
          ],
        ),
      ),
    );
  }

  void _openReader(BuildContext ctx, int? startChapter) {
    Navigator.push(ctx, SlidePageRoute(page: ModuleReaderScreen(moduleData: _moduleData!, startChapter: startChapter)));
  }
}

// PDF-like document reader
class ModuleReaderScreen extends StatefulWidget {
  final Map<String, dynamic> moduleData;
  final int? startChapter;

  const ModuleReaderScreen({super.key, required this.moduleData, this.startChapter});

  @override
  State<ModuleReaderScreen> createState() => _ModuleReaderScreenState();
}

class _ModuleReaderScreenState extends State<ModuleReaderScreen> {
  late final List<dynamic> _chapters;
  int _currentChapter = 0;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _chapters = widget.moduleData['chapters'];
    _currentChapter = widget.startChapter ?? 0;
  }

  void _goToChapter(int index) {
    if (index >= 0 && index < _chapters.length) {
      setState(() => _currentChapter = index);
      _scrollController.jumpTo(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final chapter = _chapters[_currentChapter];

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
                    child: Icon(Icons.arrow_back_ios_rounded, color: isDark ? Colors.white70 : Colors.black54, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      chapter['title'],
                      style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600, color: isDark ? Colors.white : const Color(0xFF1A1A2E)),
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Text('${_currentChapter + 1}/${_chapters.length}', style: GoogleFonts.poppins(fontSize: 13, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600)),
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
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 20, offset: const Offset(0, 4))],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Scrollbar(
                      controller: _scrollController,
                      child: ListView(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(32),
                        children: [
                          // Chapter header
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                            child: Text(
                              widget.moduleData['title'].toUpperCase(),
                              style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.accent, letterSpacing: 1.5),
                            ),
                          ),
                          const SizedBox(height: 20),

                          // Chapter number & title
                          Text(
                            'Chapter ${chapter['number']}',
                            style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.accent),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            chapter['title'],
                            style: GoogleFonts.poppins(fontSize: 26, fontWeight: FontWeight.w700, color: isDark ? Colors.white : const Color(0xFF1A1A2E), height: 1.3),
                          ),
                          const SizedBox(height: 16),

                          // Introduction
                          Text(
                            chapter['introduction'],
                            style: GoogleFonts.poppins(fontSize: 15, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600, height: 1.7),
                          ),
                          const SizedBox(height: 32),

                          // Key Concepts Section
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.white.withValues(alpha: 0.03) : const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.shade200),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.lightbulb_rounded, color: AppColors.accent, size: 20),
                                    const SizedBox(width: 10),
                                    Text('Key Concepts', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700, color: isDark ? Colors.white : const Color(0xFF1A1A2E))),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                ...((chapter['keyConcepts'] as List).map((concept) => Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Container(margin: const EdgeInsets.only(top: 8), width: 6, height: 6, decoration: BoxDecoration(color: AppColors.accent, shape: BoxShape.circle)),
                                    const SizedBox(width: 12),
                                    Expanded(child: Text(concept, style: GoogleFonts.poppins(fontSize: 14, color: isDark ? Colors.white70 : Colors.black87, height: 1.6))),
                                  ]),
                                ))),
                              ],
                            ),
                          ),

                          const SizedBox(height: 32),

                          // Important Points
                          Text('Important Points to Remember', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, color: isDark ? Colors.white : const Color(0xFF1A1A2E))),
                          const SizedBox(height: 16),
                          ...((chapter['keyConcepts'] as List).map((point) => Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF1E3A5F).withValues(alpha: 0.1) : const Color(0xFFEEF2FF),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.15)),
                            ),
                            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Icon(Icons.check_circle_outline_rounded, size: 18, color: const Color(0xFF8B5CF6)),
                              const SizedBox(width: 10),
                              Expanded(child: Text(point, style: GoogleFonts.poppins(fontSize: 14, color: isDark ? Colors.white70 : Colors.black87, height: 1.6))),
                            ]),
                          ))),

                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Bottom navigation
            Container(
              color: isDark ? const Color(0xFF1A1A2E) : const Color(0xFFE8E8E8),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  if (_currentChapter > 0)
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _goToChapter(_currentChapter - 1),
                        icon: const Icon(Icons.arrow_back_rounded, size: 18),
                        label: Text('Prev Chapter', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                        style: ElevatedButton.styleFrom(backgroundColor: isDark ? AppColors.darkCard : Colors.white, foregroundColor: isDark ? Colors.white70 : Colors.black54, elevation: 0, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      ),
                    ),
                  if (_currentChapter > 0) const SizedBox(width: 12),
                  if (_currentChapter < _chapters.length - 1)
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _goToChapter(_currentChapter + 1),
                        icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                        label: Text('Next Chapter', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent, foregroundColor: Colors.white, elevation: 0, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      ),
                    ),
                  if (_currentChapter == _chapters.length - 1)
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.check_circle_rounded, size: 18),
                        label: Text('Finish', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.success, foregroundColor: Colors.white, elevation: 0, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
