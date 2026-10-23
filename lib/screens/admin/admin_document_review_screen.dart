import 'package:flutter/material.dart';

import '../../models/question.dart';
import '../../models/subject.dart';
import '../../services/admin_service.dart';
import '../../services/document_generation_service.dart';
import '../../utils/answer_length_check.dart';
import '../../utils/error_messages.dart';
import '../../utils/page_transitions.dart';
import '../../utils/responsive.dart';
import '../../widgets/ui/ui.dart';
import 'admin_question_editor_screen.dart';

/// The questions Gemini wrote from one PDF. They are inactive until a
/// faculty member reads them and approves the good ones (selection only --
/// nothing is approved in bulk without being looked at). Edit fixes a
/// question first; Delete throws a bad one away.
class AdminDocumentReviewScreen extends StatefulWidget {
  final DocumentUpload upload;
  const AdminDocumentReviewScreen({super.key, required this.upload});

  @override
  State<AdminDocumentReviewScreen> createState() => _AdminDocumentReviewScreenState();
}

class _AdminDocumentReviewScreenState extends State<AdminDocumentReviewScreen> {
  List<AdminQuestionEntry> _entries = const [];
  final Set<String> _selected = {};
  bool _loading = true;
  bool _approving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final entries = await AdminService.instance.listQuestions(
        source: QuestionSource.generated,
        templateId: widget.upload.id,
        limit: 60,
      );
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _selected.removeWhere((id) => !entries.any((e) => e.question.id == id && !e.isActive));
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = friendlyError(e, fallback: "Couldn't load the generated questions.");
      });
    }
  }

  int get _waiting => _entries.where((e) => !e.isActive).length;

  Future<void> _approveSelected() async {
    final ids = _selected.toList();
    if (ids.isEmpty || _approving) return;
    final ok = await showConfirmDialog(
      context,
      title: 'Approve ${ids.length} question${ids.length == 1 ? '' : 's'}?',
      message: 'Students will see them in quizzes after their next refresh. You can still edit or '
          'deactivate them later in the question bank.',
      confirmLabel: 'Approve',
      icon: Icons.task_alt_rounded,
    );
    if (!ok) return;
    setState(() => _approving = true);
    var done = 0;
    for (final id in ids) {
      try {
        await AdminService.instance.setActive(id, true);
        done++;
      } catch (_) {
        // reported below
      }
    }
    if (!mounted) return;
    setState(() {
      _approving = false;
      _selected.clear();
    });
    showAppSnack(
      context,
      done == ids.length
          ? 'Approved $done question${done == 1 ? '' : 's'}.'
          : 'Approved $done of ${ids.length}. Try the rest again.',
      tone: done == ids.length ? BannerTone.success : BannerTone.warning,
    );
    _load();
  }

  Future<void> _edit(Question q) async {
    final changed = await Navigator.push<bool>(context, SlidePageRoute(page: AdminQuestionEditorScreen(existing: q)));
    if (changed == true && mounted) _load();
  }

  Future<void> _delete(Question q) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Delete this question?',
      message: 'It is removed from the question bank for good.',
      confirmLabel: 'Delete',
      destructive: true,
      icon: Icons.delete_outline_rounded,
    );
    if (!ok) return;
    try {
      await AdminService.instance.deleteQuestionPermanently(q.id);
      if (mounted) _load();
    } catch (e) {
      if (mounted) showAppSnack(context, friendlyError(e, fallback: "Couldn't delete the question."), tone: BannerTone.danger);
    }
  }

  @override
  Widget build(BuildContext context) {
    final padding = Responsive.horizontalPadding(context);
    final waiting = _waiting;
    return Scaffold(
      appBar: AppTopBar(
        title: 'Review questions',
        subtitle: _loading ? widget.upload.filename : '$waiting waiting · ${_entries.length - waiting} approved',
      ),
      bottomNavigationBar: _selected.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(padding, 8, padding, 10),
                child: ContentWidth(
                  maxWidth: 820,
                  child: PrimaryButton(
                    label: 'Approve ${_selected.length}',
                    icon: Icons.task_alt_rounded,
                    height: 50,
                    loading: _approving,
                    onPressed: _approving ? null : _approveSelected,
                  ),
                ),
              ),
            ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const LoadingView(label: 'Loading questions...')
            : _error != null
                ? ListView(children: [
                    const SizedBox(height: 60),
                    EmptyState(
                      icon: Icons.error_outline_rounded,
                      title: "Couldn't load the questions",
                      message: _error,
                      actionLabel: 'Try again',
                      onAction: _load,
                      color: context.palette.danger,
                    ),
                  ])
                : _entries.isEmpty
                    ? ListView(children: const [
                        SizedBox(height: 60),
                        EmptyState(
                          icon: Icons.inventory_2_outlined,
                          title: 'No questions left',
                          message: 'They were deleted, or none were generated from this PDF.',
                        ),
                      ])
                    : ListView(
                        padding: EdgeInsets.fromLTRB(padding, 4, padding, 40),
                        children: [
                          ContentWidth(
                            maxWidth: 820,
                            child: InlineBanner(
                              tone: BannerTone.warning,
                              icon: Icons.fact_check_rounded,
                              title: 'Check before approving',
                              message: 'Gemini can make mistakes. Read each question, its answer and the legal '
                                  'basis against the PDF, edit what needs fixing, and tick the ones to approve.',
                              action: waiting == 0
                                  ? null
                                  : TextButton(
                                      onPressed: () => setState(() {
                                        final ids = _entries.where((e) => !e.isActive).map((e) => e.question.id);
                                        final all = ids.every(_selected.contains);
                                        all ? _selected.removeAll(ids) : _selected.addAll(ids);
                                      }),
                                      child: Text(_entries.where((e) => !e.isActive).every((e) => _selected.contains(e.question.id))
                                          ? 'Clear ticks'
                                          : 'Tick all waiting'),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          for (var i = 0; i < _entries.length; i++)
                            ContentWidth(
                              maxWidth: 820,
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Appear(index: i, child: _buildCard(i + 1, _entries[i])),
                              ),
                            ),
                        ],
                      ),
      ),
    );
  }

  Widget _buildCard(int number, AdminQuestionEntry entry) {
    final p = context.palette;
    final text = context.textStyles;
    final q = entry.question;
    final waiting = !entry.isActive;
    final selected = _selected.contains(q.id);
    final subject = CriminologySubjects.getById(q.subject);

    return AppCard(
      onTap: waiting
          ? () => setState(() => selected ? _selected.remove(q.id) : _selected.add(q.id))
          : null,
      padding: const EdgeInsets.fromLTRB(6, 10, 4, 14),
      borderColor: selected ? p.success : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            value: waiting ? selected : true,
            onChanged: waiting
                ? (v) => setState(() => v == true ? _selected.add(q.id) : _selected.remove(q.id))
                : null,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          Pill(label: '#$number · ${subject.shortName}', color: AppColors.subjectColor(subject.id), fontSize: 10.5),
                          Pill(
                            label: q.difficulty.name[0].toUpperCase() + q.difficulty.name.substring(1),
                            color: p.forDifficulty(q.difficulty.index),
                            fontSize: 10.5,
                          ),
                          waiting
                              ? Pill(label: 'Waiting', icon: Icons.hourglass_empty_rounded, color: p.warning, fontSize: 10.5)
                              : Pill(label: 'Approved', icon: Icons.task_alt_rounded, color: p.success, fontSize: 10.5),
                          if (questionAnswerStandsOut(q))
                            Pill(label: 'Answer stands out', icon: Icons.straighten_rounded, color: p.warning, fontSize: 10.5),
                        ],
                      ),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'Actions',
                      icon: Icon(Icons.more_horiz_rounded, size: 22, color: p.textSecondary),
                      onSelected: (a) => a == 'edit' ? _edit(q) : _delete(q),
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'edit',
                          child: ListTile(leading: Icon(Icons.edit_rounded), title: Text('Edit'), dense: true),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: ListTile(
                            leading: Icon(Icons.delete_outline_rounded, color: p.danger),
                            title: Text('Delete', style: TextStyle(color: p.danger)),
                            dense: true,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(q.topic.toUpperCase(), style: text.labelSmall?.copyWith(color: p.textSecondary)),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Text(q.questionText, style: text.titleSmall),
                ),
                const SizedBox(height: 8),
                for (var i = 0; i < q.answerOptions.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4, right: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          q.answerOptions[i].isCorrect ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                          size: 18,
                          color: q.answerOptions[i].isCorrect ? p.success : p.textTertiary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${String.fromCharCode(65 + i)}. ${q.answerOptions[i].text}',
                            style: text.bodyMedium?.copyWith(
                              fontWeight: q.answerOptions[i].isCorrect ? FontWeight.w600 : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (q.legalBasis != null && q.legalBasis!.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text('Basis: ${q.legalBasis}', style: text.bodySmall?.copyWith(color: p.info)),
                ],
                if (q.explanation.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Text(q.explanation, style: text.bodySmall, maxLines: 4, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
