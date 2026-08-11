import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/question.dart';
import '../../models/subject.dart';
import '../../services/document_generation_service.dart';
import '../../services/theme_service.dart';
import '../../utils/page_transitions.dart';
import '../../utils/responsive.dart';
import 'admin_questions_screen.dart';

/// "Generate from Document" -- the LLM path of Automatic Item Generation
/// (panel note 1): an admin uploads a reviewer PDF and the system reads it
/// and drafts multiple-choice questions from it.
///
/// This screen only does two things: submit an upload request, and show the
/// live queue of past requests (`DocumentGenerationService.watchUploads()`,
/// Supabase Realtime -- no polling). Reviewing what came out of a completed
/// upload is deliberately NOT a new screen here: it navigates into
/// [AdminQuestionsScreen] filtered to that upload's batch, because approving
/// a generated question is the exact same "restore" action as any other
/// deactivated question, and rejecting one is the exact same delete. See
/// `supabase_document_generation.sql` for why `is_active = false` is the
/// whole review gate.
class AdminDocumentGenerationScreen extends StatefulWidget {
  const AdminDocumentGenerationScreen({super.key});

  @override
  State<AdminDocumentGenerationScreen> createState() => _AdminDocumentGenerationScreenState();
}

class _AdminDocumentGenerationScreenState extends State<AdminDocumentGenerationScreen> {
  final TextEditingController _topicController = TextEditingController();
  final TextEditingController _countController = TextEditingController(text: '10');

  String _subjectId = CriminologySubjects.all.first.id;
  Difficulty? _targetDifficulty; // null = mixed
  bool _submitting = false;

  @override
  void dispose() {
    _topicController.dispose();
    _countController.dispose();
    super.dispose();
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.error : AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<void> _submit() async {
    final count = int.tryParse(_countController.text.trim()) ?? 10;
    if (count < 1 || count > 30) {
      _showSnack('Question count must be between 1 and 30.', isError: true);
      return;
    }

    setState(() => _submitting = true);
    try {
      final upload = await DocumentGenerationService.instance.pickAndGenerate(
        subjectId: _subjectId,
        topic: _topicController.text,
        targetDifficulty: _targetDifficulty,
        requestedCount: count,
      );
      if (upload == null) {
        // Admin cancelled the file picker -- not an error.
        return;
      }
      _showSnack('"${upload.filename}" queued -- check the list below for progress.');
    } catch (e) {
      _showSnack('Could not start generation: $e', isError: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _openReview(DocumentUpload upload) {
    Navigator.push(
      context,
      SlidePageRoute(
        page: AdminQuestionsScreen(
          initialSource: QuestionSource.generated,
          initialTemplateId: upload.id,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final padding = Responsive.horizontalPadding(context);

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      appBar: _buildAppBar(isDark),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(padding, 8, padding, 40),
          children: [
            Text(
              'Upload a reviewer PDF and Claude will draft multiple-choice questions '
              'from its content. Generated items are never published automatically -- '
              'review, edit and approve each one from the list below before students '
              'can see it.',
              style: TextStyle(fontSize: 13, color: isDark ? Colors.grey.shade500 : Colors.grey.shade600),
            ),
            const SizedBox(height: 20),
            _buildSectionLabel('Subject', isDark),
            _buildSubjectDropdown(isDark),
            const SizedBox(height: 16),
            _buildSectionLabel('Topic hint (optional)', isDark),
            _buildTextField(
              _topicController,
              isDark,
              hint: 'Leave blank to let the model pick topics from the document',
            ),
            const SizedBox(height: 16),
            _buildSectionLabel('Target difficulty', isDark),
            _buildDifficultySelector(isDark),
            const SizedBox(height: 16),
            _buildSectionLabel('Number of questions (1-30)', isDark),
            _buildTextField(_countController, isDark, keyboardType: TextInputType.number),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _submitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: _submitting
                    ? const SizedBox(
                        width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.upload_file_rounded, color: Colors.white),
                label: Text(
                  _submitting ? 'Uploading...' : 'Choose PDF & Generate',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
                ),
              ),
            ),
            const SizedBox(height: 32),
            Text(
              'Upload History',
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : const Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 12),
            _buildUploadList(isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildUploadList(bool isDark) {
    return StreamBuilder<List<DocumentUpload>>(
      stream: DocumentGenerationService.instance.watchUploads(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final uploads = snapshot.data ?? const <DocumentUpload>[];
        if (uploads.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'No uploads yet.',
              style: TextStyle(color: isDark ? Colors.grey.shade500 : Colors.grey.shade600),
            ),
          );
        }
        return Column(children: [for (final u in uploads) _buildUploadCard(u, isDark)]);
      },
    );
  }

  Widget _buildUploadCard(DocumentUpload upload, bool isDark) {
    final subjectName = CriminologySubjects.all
        .firstWhere((s) => s.id == upload.subjectId, orElse: () => CriminologySubjects.all.first)
        .name;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  upload.filename,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$subjectName${upload.topic != null ? ' - ${upload.topic}' : ''}',
                  style: TextStyle(fontSize: 12, color: isDark ? Colors.grey.shade500 : Colors.grey.shade600),
                ),
                const SizedBox(height: 6),
                _buildStatusBadge(upload, isDark),
                if (upload.status == 'failed' && upload.errorMessage != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    upload.errorMessage!,
                    style: const TextStyle(fontSize: 11, color: AppColors.error),
                  ),
                ],
              ],
            ),
          ),
          if (upload.hasReviewableQuestions)
            TextButton(
              onPressed: () => _openReview(upload),
              child: Text('Review ${upload.generatedCount}'),
            ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(DocumentUpload upload, bool isDark) {
    final (label, color) = switch (upload.status) {
      'pending' => ('Queued', Colors.grey),
      'processing' => ('Generating...', AppColors.accent),
      'completed' => ('Ready for review', AppColors.success),
      'failed' => ('Failed', AppColors.error),
      _ => (upload.status, Colors.grey),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    );
  }

  PreferredSizeWidget _buildAppBar(bool isDark) {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      leading: IconButton(
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
      ),
      title: Text(
        'Generate from Document',
        style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: isDark ? Colors.white : const Color(0xFF1A1A2E)),
      ),
      centerTitle: true,
    );
  }

  Widget _buildSectionLabel(String text, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isDark ? Colors.grey.shade400 : Colors.grey.shade700),
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    bool isDark, {
    int maxLines = 1,
    String? hint,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      style: TextStyle(fontSize: 14, color: isDark ? Colors.white : const Color(0xFF1A1A2E)),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: isDark ? Colors.grey.shade600 : Colors.grey.shade400, fontSize: 13),
        filled: true,
        fillColor: isDark ? AppColors.darkCard : AppColors.lightCard,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      ),
    );
  }

  Widget _buildSubjectDropdown(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(color: isDark ? AppColors.darkCard : AppColors.lightCard, borderRadius: BorderRadius.circular(12)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _subjectId,
          isExpanded: true,
          items: [
            for (final s in CriminologySubjects.all) DropdownMenuItem(value: s.id, child: Text(s.name)),
          ],
          onChanged: (v) => setState(() => _subjectId = v ?? _subjectId),
          style: TextStyle(fontSize: 14, color: isDark ? Colors.white : const Color(0xFF1A1A2E)),
          dropdownColor: isDark ? AppColors.darkCard : Colors.white,
        ),
      ),
    );
  }

  Widget _buildDifficultySelector(bool isDark) {
    // null (mixed) plus the three explicit tiers.
    final options = <Difficulty?>[null, ...Difficulty.values];

    Widget chip(Difficulty? d) {
      final selected = _targetDifficulty == d;
      final label = d == null ? 'Mixed' : d.name[0].toUpperCase() + d.name.substring(1);
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _targetDifficulty = d),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            margin: EdgeInsets.only(right: d != options.last ? 8 : 0),
            decoration: BoxDecoration(
              color: selected ? AppColors.accent : (isDark ? AppColors.darkCard : AppColors.lightCard),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : (isDark ? Colors.grey.shade400 : Colors.grey.shade700),
              ),
            ),
          ),
        ),
      );
    }

    return Row(children: [for (final d in options) chip(d)]);
  }
}
