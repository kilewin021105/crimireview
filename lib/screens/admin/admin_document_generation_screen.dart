import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../models/question.dart';
import '../../models/subject.dart';
import '../../models/tos.dart';
import '../../services/document_generation_service.dart';
import '../../utils/error_messages.dart';
import '../../utils/page_transitions.dart';
import '../../utils/responsive.dart';
import '../../widgets/ui/ui.dart';
import 'admin_document_review_screen.dart';

/// Faculty upload a PDF (a reviewer, a new law, a revised syllabus) and
/// Google Gemini writes questions from it. Every question waits, inactive,
/// until a faculty member approves it in [AdminDocumentReviewScreen] --
/// this is how the question bank keeps up when the curriculum changes.
class AdminDocumentGenerationScreen extends StatefulWidget {
  const AdminDocumentGenerationScreen({super.key});

  @override
  State<AdminDocumentGenerationScreen> createState() => _AdminDocumentGenerationScreenState();
}

class _AdminDocumentGenerationScreenState extends State<AdminDocumentGenerationScreen> {
  static const _counts = [5, 10, 15, 20];
  static const _difficultyLabels = ['Mixed', 'Easy', 'Medium', 'Hard'];

  final _topicController = TextEditingController();
  String _subjectId = CriminologySubjects.all.first.id;

  /// The TOS topic or competency the questions should test; null lets
  /// Gemini pick topics from the PDF (the free-text topic is used then).
  String? _tosCode;
  int _difficultyIndex = 0;
  int _countIndex = 1;

  PlatformFile? _file;
  String? _fileProblem;
  bool _picking = false;
  bool _sending = false;

  List<DocumentUpload> _uploads = const [];
  bool _loading = true;
  String? _loadError;
  Timer? _poll;

  DocumentGenerationService get _service => DocumentGenerationService.instance;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _topicController.dispose();
    super.dispose();
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    try {
      final uploads = await _service.recentUploads();
      if (!mounted) return;
      setState(() {
        _uploads = uploads;
        _loading = false;
        _loadError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!quiet) _loadError = friendlyError(e, fallback: "Couldn't load the uploads.");
      });
    }
    _schedulePoll();
  }

  /// While Gemini is still working on an upload, check again every few
  /// seconds; stop as soon as nothing is pending.
  void _schedulePoll() {
    _poll?.cancel();
    final now = DateTime.now();
    if (!mounted || !_uploads.any((u) => u.isWorking && !u.isStuck(now))) return;
    _poll = Timer(const Duration(seconds: 6), () => _load(quiet: true));
  }

  Future<void> _pickFile() async {
    setState(() => _picking = true);
    try {
      final result = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['pdf'], withData: true);
      if (!mounted) return;
      if (result == null || result.files.isEmpty) {
        setState(() => _picking = false);
        return;
      }
      final file = result.files.single;
      setState(() {
        _picking = false;
        _fileProblem = pdfProblem(name: file.name, size: file.size, bytes: file.bytes);
        _file = _fileProblem == null ? file : null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _picking = false;
        _fileProblem = "Couldn't open the file picker. Try again.";
      });
    }
  }

  Future<void> _send() async {
    final file = _file;
    if (file == null || file.bytes == null || _sending) return;
    setState(() => _sending = true);
    try {
      final tosTopic = TosCatalog.loaded?.topicOf(_tosCode);
      await _service.upload(
        filename: file.name,
        bytes: file.bytes!,
        subjectId: _subjectId,
        topic: tosTopic?.title ?? _topicController.text,
        tosCode: tosTopic == null ? null : _tosCode,
        targetDifficulty: _difficultyIndex == 0 ? null : Difficulty.values[_difficultyIndex - 1],
        requestedCount: _counts[_countIndex],
      );
      if (!mounted) return;
      setState(() {
        _sending = false;
        _file = null;
      });
      showAppSnack(
          context,
          'Uploaded. CrimiReview writes ${DocumentUpload.questionsPerStep} questions at a time; '
          'each part takes a minute or two.',
          tone: BannerTone.success, icon: Icons.auto_awesome_rounded);
      _load(quiet: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      final message = e is StateError ? e.message : friendlyError(e, fallback: "Couldn't upload the PDF.");
      showAppSnack(context, message, tone: BannerTone.danger);
      _load(quiet: true);
    }
  }

  Future<void> _openReview(DocumentUpload upload) async {
    await Navigator.push(context, SlidePageRoute(page: AdminDocumentReviewScreen(upload: upload)));
    if (mounted) _load(quiet: true);
  }

  Future<void> _delete(DocumentUpload upload) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Remove this upload?',
      message: 'The PDF and this entry are removed. Questions already generated from it stay in the '
          'question bank, where you can approve or delete them.',
      confirmLabel: 'Remove',
      destructive: true,
      icon: Icons.delete_outline_rounded,
    );
    if (!ok) return;
    try {
      await _service.deleteUpload(upload);
      if (mounted) _load(quiet: true);
    } catch (e) {
      if (mounted) showAppSnack(context, friendlyError(e, fallback: "Couldn't remove the upload."), tone: BannerTone.danger);
    }
  }

  @override
  Widget build(BuildContext context) {
    final padding = Responsive.horizontalPadding(context);
    return Scaffold(
      appBar: const AppTopBar(title: 'Generate from PDF', subtitle: 'Google Gemini · you approve every question'),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.fromLTRB(padding, 4, padding, 40),
          children: [
            ContentWidth(maxWidth: 820, child: _buildForm()),
            const SizedBox(height: 22),
            const ContentWidth(
              maxWidth: 820,
              child: SectionHeader(title: 'Recent uploads', subtitle: 'Newest first'),
            ),
            const SizedBox(height: 8),
            ..._buildUploads(),
          ],
        ),
      ),
    );
  }

  /// "Target in the TOS": any part of the subject, one whole topic, or one
  /// competency. Gemini then writes at that competency's Bloom levels.
  List<Widget> _buildTosTarget() {
    final subject = TosCatalog.loaded?.subject(_subjectId);
    if (subject == null) return const [];
    final text = context.textStyles;
    final p = context.palette;
    final competency = TosCatalog.loaded?.competency(_tosCode ?? '');
    return [
      Text('Target in the TOS', style: text.labelLarge),
      const SizedBox(height: 6),
      DropdownButtonFormField<String?>(
        key: ValueKey('tos-target-$_subjectId'),
        initialValue: _tosCode,
        isExpanded: true,
        decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12)),
        items: [
          const DropdownMenuItem(value: null, child: Text('Any part of the subject')),
          for (final topic in subject.topics) ...[
            DropdownMenuItem(
              value: topic.code,
              child: Text('${topic.number}. ${topic.title} (whole topic)', overflow: TextOverflow.ellipsis),
            ),
            for (final c in topic.competencies)
              DropdownMenuItem(
                value: c.code,
                child: Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Text('${c.number}  ${c.text}', overflow: TextOverflow.ellipsis),
                ),
              ),
          ],
        ],
        onChanged: _sending ? null : (v) => setState(() => _tosCode = v),
      ),
      if (competency != null) ...[
        const SizedBox(height: 6),
        Text(
          'Gemini will write at the TOS Bloom levels of ${competency.code}: '
          '${competency.bloom.entries.map((e) => '${e.key.label} ${e.value}').join(', ')}.',
          style: text.bodySmall?.copyWith(color: p.textSecondary),
        ),
      ],
      const SizedBox(height: 14),
    ];
  }

  Widget _buildForm() {
    final p = context.palette;
    final text = context.textStyles;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const InlineBanner(
          tone: BannerTone.info,
          icon: Icons.picture_as_pdf_rounded,
          title: 'How it works',
          message: 'Upload a PDF such as a reviewer or a new law. Gemini writes questions only from what the '
              'PDF says. Students do not see them until you approve them. Upload review material only, '
              'never student records.',
        ),
        const SizedBox(height: 16),
        Text('Subject', style: text.labelLarge),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          initialValue: _subjectId,
          isExpanded: true,
          decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12)),
          items: [
            for (final s in CriminologySubjects.all)
              DropdownMenuItem(
                value: s.id,
                child: Row(
                  children: [
                    Icon(AppTheme.subjectIcons[s.id] ?? Icons.menu_book_rounded, size: 18, color: AppColors.subjectColor(s.id)),
                    const SizedBox(width: 10),
                    Expanded(child: Text(s.name, overflow: TextOverflow.ellipsis)),
                  ],
                ),
              ),
          ],
          onChanged: _sending
              ? null
              : (v) => setState(() {
                    if (v == null || v == _subjectId) return;
                    _subjectId = v;
                    _tosCode = null;
                  }),
        ),
        const SizedBox(height: 14),
        ..._buildTosTarget(),
        if (_tosCode == null) ...[
          AppTextField(
            controller: _topicController,
            label: 'Topic (optional)',
            hint: 'e.g. Justifying Circumstances',
            icon: Icons.label_outline_rounded,
            maxLength: 120,
          ),
          const SizedBox(height: 6),
        ],
        Text('Difficulty', style: text.labelLarge),
        const SizedBox(height: 6),
        PillTabs(
          labels: _difficultyLabels,
          index: _difficultyIndex,
          onChanged: (i) => setState(() => _difficultyIndex = i),
        ),
        const SizedBox(height: 14),
        Text('Number of questions', style: text.labelLarge),
        const SizedBox(height: 6),
        PillTabs(
          labels: [for (final c in _counts) '$c'],
          index: _countIndex,
          onChanged: (i) => setState(() => _countIndex = i),
        ),
        const SizedBox(height: 16),
        AppCard(
          onTap: _sending || _picking ? null : _pickFile,
          padding: const EdgeInsets.all(14),
          borderColor: _fileProblem != null ? p.danger : null,
          child: Row(
            children: [
              IconBadge(icon: Icons.picture_as_pdf_rounded, color: p.danger, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_file?.name ?? 'Choose a PDF', style: text.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(
                      _file != null
                          ? '${(_file!.size / (1024 * 1024)).toStringAsFixed(1)} MB · tap to choose another'
                          : 'PDF only, up to 20 MB',
                      style: text.bodySmall,
                    ),
                  ],
                ),
              ),
              if (_picking)
                const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              else
                Icon(Icons.folder_open_rounded, color: p.textSecondary),
            ],
          ),
        ),
        if (_fileProblem != null) ...[
          const SizedBox(height: 8),
          InlineBanner(tone: BannerTone.danger, icon: Icons.error_outline_rounded, message: _fileProblem!),
        ],
        const SizedBox(height: 16),
        PrimaryButton(
          label: 'Generate ${_counts[_countIndex]} questions',
          icon: Icons.auto_awesome_rounded,
          height: 50,
          loading: _sending,
          onPressed: _file != null && !_sending ? _send : null,
        ),
      ],
    );
  }

  List<Widget> _buildUploads() {
    if (_loading) return const [Padding(padding: EdgeInsets.all(24), child: LoadingView(label: 'Loading uploads...'))];
    if (_loadError != null) {
      return [
        EmptyState(
          icon: Icons.error_outline_rounded,
          title: "Couldn't load the uploads",
          message: _loadError,
          actionLabel: 'Try again',
          onAction: _load,
          color: context.palette.danger,
          compact: true,
        ),
      ];
    }
    if (_uploads.isEmpty) {
      return const [
        EmptyState(
          icon: Icons.upload_file_rounded,
          title: 'No uploads yet',
          message: 'Your PDFs and the questions made from them appear here.',
          compact: true,
        ),
      ];
    }
    final now = DateTime.now();
    return [
      for (var i = 0; i < _uploads.length; i++)
        ContentWidth(
          maxWidth: 820,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Appear(index: i, child: _buildUploadCard(_uploads[i], now)),
          ),
        ),
    ];
  }

  Widget _buildUploadCard(DocumentUpload u, DateTime now) {
    final p = context.palette;
    final text = context.textStyles;
    final subject = CriminologySubjects.getById(u.subjectId);
    final stuck = u.isStuck(now);
    final (String label, Color color, IconData icon) = u.isWorking && !stuck
        ? (
            u.generatedCount > 0 ? 'Writing questions... ${u.generatedCount} of ${u.requestedCount}' : 'Writing questions...',
            p.info,
            Icons.hourglass_top_rounded,
          )
        : u.hasQuestions
            ? ('${u.generatedCount} question${u.generatedCount == 1 ? '' : 's'} to review', p.success, Icons.task_alt_rounded)
            : ('Failed', p.danger, Icons.error_outline_rounded);
    final message = stuck
        ? 'This took too long and probably stopped. Remove it and upload the PDF again.'
        : u.errorMessage;

    return AppCard(
      onTap: u.hasQuestions ? () => _openReview(u) : null,
      padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(
                icon: AppTheme.subjectIcons[u.subjectId] ?? Icons.picture_as_pdf_rounded,
                color: AppColors.subjectColor(u.subjectId),
                size: 38,
                iconSize: 19,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(u.filename, style: text.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(
                      [subject.shortName, u.tosCode ?? u.topic, '${u.requestedCount} asked'].whereType<String>().join(' · '),
                      style: text.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Remove',
                icon: Icon(Icons.delete_outline_rounded, color: p.textSecondary, size: 21),
                onPressed: u.isWorking && !stuck ? null : () => _delete(u),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Pill(label: label, icon: icon, color: color),
                if (u.hasQuestions)
                  TextButton.icon(
                    onPressed: () => _openReview(u),
                    icon: const Icon(Icons.fact_check_rounded, size: 18),
                    label: const Text('Review'),
                  ),
              ],
            ),
          ),
          if (message != null && message.isNotEmpty) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Text(message, style: text.bodySmall?.copyWith(color: u.hasQuestions ? p.textSecondary : p.danger)),
            ),
          ],
        ],
      ),
    );
  }
}
