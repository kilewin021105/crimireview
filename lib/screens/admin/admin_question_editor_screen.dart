import 'package:flutter/material.dart';

import '../../models/question.dart';
import '../../models/subject.dart';
import '../../services/admin_service.dart';
import '../../utils/answer_length_check.dart';
import '../../utils/error_messages.dart';
import '../../widgets/ui/ui.dart';
import '../../utils/responsive.dart';

/// Create/edit form for one `public.questions` row.
///
/// This is the literal answer to panel note 7 ("It should have an ADMIN to
/// add questions") and, because every option carries its own rationale
/// field, it is also what makes panel note 5 ("explain WHY the answer is
/// wrong") authorable rather than something only a script can produce.
///
/// Pass [existing] to edit; leave it null to create a new item.
class AdminQuestionEditorScreen extends StatefulWidget {
  final Question? existing;
  const AdminQuestionEditorScreen({super.key, this.existing});

  @override
  State<AdminQuestionEditorScreen> createState() => _AdminQuestionEditorScreenState();
}

class _OptionDraft {
  final TextEditingController text;
  final TextEditingController rationale;
  _OptionDraft({String text = '', String rationale = ''})
      : text = TextEditingController(text: text),
        rationale = TextEditingController(text: rationale);

  void dispose() {
    text.dispose();
    rationale.dispose();
  }
}

class _AdminQuestionEditorScreenState extends State<AdminQuestionEditorScreen> {
  static const int _minOptions = 2;
  static const int _maxOptions = 6;

  late final TextEditingController _idController;
  late final TextEditingController _topicController;
  late final TextEditingController _questionController;
  late final TextEditingController _explanationController;
  late final TextEditingController _legalBasisController;
  late final TextEditingController _remediationController;

  late String _subjectId;
  late Difficulty _difficulty;
  late int _correctIndex;
  final List<_OptionDraft> _options = [];

  bool get _isEditing => widget.existing != null;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final q = widget.existing;

    _idController = TextEditingController(text: q?.id ?? _generateId());
    _topicController = TextEditingController(text: q?.topic ?? '');
    _questionController = TextEditingController(text: q?.questionText ?? '');
    _explanationController = TextEditingController(text: q?.explanation ?? '');
    _legalBasisController = TextEditingController(text: q?.legalBasis ?? '');
    _remediationController = TextEditingController(text: q?.remediationHint ?? '');

    _subjectId = q?.subject.isNotEmpty == true ? q!.subject : CriminologySubjects.all.first.id;
    _difficulty = q?.difficulty ?? Difficulty.medium;

    if (q != null && q.answerOptions.isNotEmpty) {
      for (final o in q.answerOptions) {
        _options.add(_OptionDraft(text: o.text, rationale: o.rationale));
      }
      _correctIndex = q.correctAnswerIndex.clamp(0, _options.length - 1);
    } else {
      _options.addAll([_OptionDraft(), _OptionDraft()]);
      _correctIndex = 0;
    }
  }

  String _generateId() => 'admin_${DateTime.now().millisecondsSinceEpoch}';

  @override
  void dispose() {
    _idController.dispose();
    _topicController.dispose();
    _questionController.dispose();
    _explanationController.dispose();
    _legalBasisController.dispose();
    _remediationController.dispose();
    for (final o in _options) {
      o.dispose();
    }
    super.dispose();
  }

  void _addOption() {
    if (_options.length >= _maxOptions) return;
    setState(() => _options.add(_OptionDraft()));
  }

  void _removeOption(int index) {
    if (_options.length <= _minOptions) return;
    setState(() {
      _options[index].dispose();
      _options.removeAt(index);
      // Keep the SAME option marked correct: removing one above it shifts
      // it up by one (this used to leave the index where it was, silently
      // marking a different option as the answer).
      if (index == _correctIndex) {
        _correctIndex = 0;
      } else if (index < _correctIndex) {
        _correctIndex--;
      }
    });
  }

  String? _validate() {
    if (_topicController.text.trim().isEmpty) return 'Topic is required.';
    if (_questionController.text.trim().isEmpty) return 'Question text is required.';
    final filled = _options.where((o) => o.text.text.trim().isNotEmpty).length;
    if (filled < _minOptions) return 'At least $_minOptions options are required.';
    if (_options.any((o) => o.text.text.trim().isEmpty)) return 'Every option needs text (remove empty ones).';
    if (_correctIndex < 0 || _correctIndex >= _options.length) return 'Select which option is correct.';
    return null;
  }

  Future<void> _save() async {
    final error = _validate();
    if (error != null) {
      _showSnack(error, isError: true);
      return;
    }

    setState(() => _saving = true);

    final answerOptions = <AnswerOption>[
      for (var i = 0; i < _options.length; i++)
        AnswerOption(
          text: _options[i].text.text.trim(),
          isCorrect: i == _correctIndex,
          rationale: _options[i].rationale.text.trim(),
        ),
    ];

    final question = Question(
      id: _idController.text.trim(),
      subject: _subjectId,
      topic: _topicController.text.trim(),
      questionText: _questionController.text.trim(),
      answerOptions: answerOptions,
      difficulty: _difficulty,
      explanation: _explanationController.text.trim(),
      legalBasis: _legalBasisController.text.trim().isEmpty ? null : _legalBasisController.text.trim(),
      remediationHint: _remediationController.text.trim().isEmpty ? null : _remediationController.text.trim(),
      source: widget.existing?.source ?? QuestionSource.admin,
      version: widget.existing?.version ?? 1,
      templateId: widget.existing?.templateId,
    );

    try {
      if (_isEditing) {
        await AdminService.instance.updateQuestion(question);
        _showSnack('Question updated');
      } else {
        await AdminService.instance.createQuestion(question);
        _showSnack('Question created');
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showSnack(friendlyError(e, fallback: 'Could not save the question. Please try again.'), isError: true);
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    showAppSnack(context, message, tone: isError ? BannerTone.danger : BannerTone.success);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final padding = Responsive.horizontalPadding(context);

    return Scaffold(
      appBar: AppTopBar(
        title: _isEditing ? 'Edit question' : 'New question',
        subtitle: _isEditing ? 'ID ${_idController.text}' : 'Goes live for students when saved',
        backIcon: Icons.close_rounded,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(padding, 4, padding, 32),
              children: [
                ContentWidth(
                  maxWidth: 760,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _sectionCard(
                        icon: Icons.tune_rounded,
                        title: 'Basics',
                        children: [
                          _label('Subject'),
                          DropdownButtonFormField<String>(
                            initialValue: _subjectId,
                            isExpanded: true,
                            icon: const Icon(Icons.keyboard_arrow_down_rounded),
                            borderRadius: BorderRadius.circular(AppSpace.radiusMd),
                            items: [
                              for (final s in CriminologySubjects.all)
                                DropdownMenuItem(
                                  value: s.id,
                                  child: Row(
                                    children: [
                                      Icon(
                                        AppTheme.subjectIcons[s.id] ?? s.icon,
                                        size: 18,
                                        color: AppColors.subjectColor(s.id),
                                      ),
                                      const SizedBox(width: 10),
                                      Flexible(child: Text(s.name, overflow: TextOverflow.ellipsis)),
                                    ],
                                  ),
                                ),
                            ],
                            onChanged: (v) => setState(() => _subjectId = v ?? _subjectId),
                          ),
                          const SizedBox(height: 16),
                          AppTextField(
                            controller: _topicController,
                            label: 'Topic',
                            hint: 'e.g. Justifying Circumstances',
                          ),
                          const SizedBox(height: 16),
                          _label('Difficulty'),
                          PillTabs(
                            labels: const ['Easy', 'Medium', 'Hard'],
                            index: Difficulty.values.indexOf(_difficulty),
                            activeColors: [p.success, p.warning, p.danger],
                            onChanged: (i) => setState(() => _difficulty = Difficulty.values[i]),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _sectionCard(
                        icon: Icons.help_outline_rounded,
                        title: 'Question',
                        children: [
                          AppTextField(
                            controller: _questionController,
                            label: 'Question text',
                            hint: 'The stem shown to the student',
                            maxLines: 4,
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _sectionCard(
                        icon: Icons.checklist_rounded,
                        title: 'Answer options',
                        subtitle:
                            'Tap a letter to mark the correct option. The rationale is what a student sees when they pick that option.',
                        children: [
                          // Live warning while typing: a correct answer much
                          // longer than the others can be guessed by length.
                          ListenableBuilder(
                            listenable: Listenable.merge([for (final o in _options) o.text]),
                            builder: (context, _) {
                              final standsOut = _correctIndex >= 0 &&
                                  _correctIndex < _options.length &&
                                  answerStandsOutByLength(
                                    _options[_correctIndex].text.text,
                                    [
                                      for (var i = 0; i < _options.length; i++)
                                        if (i != _correctIndex) _options[i].text.text,
                                    ],
                                  );
                              if (!standsOut) return const SizedBox.shrink();
                              return const Padding(
                                padding: EdgeInsets.only(bottom: 12),
                                child: InlineBanner(
                                  tone: BannerTone.warning,
                                  icon: Icons.straighten_rounded,
                                  title: 'The correct answer stands out',
                                  message: 'It is much longer than the other options, so students can guess it '
                                      'by length. Make the wrong options about as long, using real look-alike '
                                      'answers from the same topic.',
                                ),
                              );
                            },
                          ),
                          for (var i = 0; i < _options.length; i++) _buildOptionCard(i),
                          if (_options.length < _maxOptions)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                onPressed: _addOption,
                                icon: const Icon(Icons.add_rounded),
                                label: Text('Add option (${_options.length}/$_maxOptions)'),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _sectionCard(
                        icon: Icons.menu_book_rounded,
                        title: 'Explanation & references',
                        children: [
                          AppTextField(
                            controller: _explanationController,
                            label: 'Overall explanation (optional)',
                            hint: 'Shown alongside the rationale',
                            maxLines: 3,
                          ),
                          const SizedBox(height: 16),
                          AppTextField(
                            controller: _legalBasisController,
                            label: 'Legal basis (optional)',
                            hint: 'e.g. RPC Art. 11(1)',
                            icon: Icons.gavel_rounded,
                          ),
                          const SizedBox(height: 16),
                          AppTextField(
                            controller: _remediationController,
                            label: 'Remediation hint (optional)',
                            hint: 'What to re-read before retrying this topic',
                            maxLines: 2,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
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
                  maxWidth: 760,
                  child: Row(
                    children: [
                      Expanded(
                        child: SecondaryButton(
                          label: 'Cancel',
                          onPressed: _saving ? null : () => Navigator.pop(context),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: PrimaryButton(
                          label: _isEditing ? 'Save changes' : 'Create question',
                          icon: Icons.check_rounded,
                          loading: _saving,
                          onPressed: _save,
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

  Widget _label(String label) => Padding(
        padding: const EdgeInsets.only(left: 2, bottom: 7),
        child: Text(label, style: context.textStyles.labelMedium?.copyWith(color: context.palette.textPrimary)),
      );

  Widget _sectionCard({
    required IconData icon,
    required String title,
    String? subtitle,
    required List<Widget> children,
  }) {
    final text = context.textStyles;
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconBadge(icon: icon, size: 32, iconSize: 17),
              const SizedBox(width: 10),
              // Wraps instead of running off the card with large text.
              Expanded(child: Text(title, style: text.titleMedium)),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(subtitle, style: text.bodySmall),
          ],
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _buildOptionCard(int index) {
    final p = context.palette;
    final text = context.textStyles;
    final isCorrect = _correctIndex == index;
    final letter = String.fromCharCode(65 + index); // A, B, C, ...

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      decoration: BoxDecoration(
        color: isCorrect ? p.successSoft : p.surfaceAlt,
        borderRadius: BorderRadius.circular(AppSpace.radiusMd),
        border: Border.all(color: isCorrect ? p.success : Colors.transparent, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Tooltip(
                message: 'Mark as correct',
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => setState(() => _correctIndex = index),
                  child: Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: isCorrect ? p.success : p.surface,
                      border: Border.all(color: isCorrect ? p.success : p.border, width: 1.5),
                    ),
                    child: isCorrect
                        ? const Icon(Icons.check_rounded, size: 18, color: Colors.white)
                        : Text(letter, style: text.labelLarge?.copyWith(color: p.textSecondary)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _options[index].text,
                  style: text.titleSmall,
                  decoration: InputDecoration(
                    hintText: 'Option $letter',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
              if (isCorrect)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Pill(label: 'Correct', color: p.success, fontSize: 10.5),
                ),
              if (_options.length > _minOptions)
                IconButton(
                  tooltip: 'Remove option',
                  icon: Icon(Icons.close_rounded, size: 18, color: p.textTertiary),
                  onPressed: () => _removeOption(index),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 42, right: 10),
            child: TextField(
              controller: _options[index].rationale,
              maxLines: 2,
              minLines: 1,
              style: text.bodySmall?.copyWith(color: p.textPrimary),
              decoration: InputDecoration(
                hintText: isCorrect ? 'Why this option is correct (optional)' : 'Why this option is wrong (optional)',
                hintStyle: text.bodySmall?.copyWith(color: p.textTertiary),
                prefixIcon: Icon(Icons.subdirectory_arrow_right_rounded, size: 16, color: p.textTertiary),
                prefixIconConstraints: const BoxConstraints(minWidth: 24),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 6),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
