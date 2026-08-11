import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/question.dart';
import '../../models/subject.dart';
import '../../services/admin_service.dart';
import '../../services/theme_service.dart';
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
      if (_correctIndex >= _options.length) _correctIndex = 0;
      if (_correctIndex == index) _correctIndex = 0;
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
      _showSnack('Save failed: $e', isError: true);
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
            if (_isEditing) _buildReadOnlyId(isDark),
            _buildSectionLabel('Subject', isDark),
            _buildSubjectDropdown(isDark),
            const SizedBox(height: 16),
            _buildSectionLabel('Topic', isDark),
            _buildTextField(_topicController, isDark, hint: 'e.g. Justifying Circumstances'),
            const SizedBox(height: 16),
            _buildSectionLabel('Difficulty', isDark),
            _buildDifficultySelector(isDark),
            const SizedBox(height: 16),
            _buildSectionLabel('Question', isDark),
            _buildTextField(_questionController, isDark, maxLines: 4, hint: 'The stem shown to the student'),
            const SizedBox(height: 20),
            _buildSectionLabel('Answer Options', isDark),
            Text(
              'Pick the correct option, and write a rationale for as many as you can -- that rationale is what the app shows a student who picks that wrong answer.',
              style: TextStyle(fontSize: 12, color: isDark ? Colors.grey.shade500 : Colors.grey.shade600),
            ),
            const SizedBox(height: 10),
            for (var i = 0; i < _options.length; i++) _buildOptionCard(i, isDark),
            if (_options.length < _maxOptions)
              TextButton.icon(
                onPressed: _addOption,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add option'),
                style: TextButton.styleFrom(foregroundColor: AppColors.accent),
              ),
            const SizedBox(height: 16),
            _buildSectionLabel('Overall Explanation', isDark),
            _buildTextField(_explanationController, isDark, maxLines: 3, hint: 'Shown alongside the rationale, optional'),
            const SizedBox(height: 16),
            _buildSectionLabel('Legal Basis (optional)', isDark),
            _buildTextField(_legalBasisController, isDark, hint: 'e.g. RPC Art. 11(1)'),
            const SizedBox(height: 16),
            _buildSectionLabel('Remediation Hint (optional)', isDark),
            _buildTextField(_remediationController, isDark, maxLines: 2, hint: 'What to re-read before retrying this topic'),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text(
                        _isEditing ? 'Save Changes' : 'Create Question',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16),
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
        _isEditing ? 'Edit Question' : 'New Question',
        style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w600, color: isDark ? Colors.white : const Color(0xFF1A1A2E)),
      ),
      centerTitle: true,
    );
  }

  Widget _buildReadOnlyId(bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Text(
        'ID: ${_idController.text}',
        style: TextStyle(fontSize: 12, color: isDark ? Colors.grey.shade600 : Colors.grey.shade500),
      ),
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

  Widget _buildTextField(TextEditingController controller, bool isDark, {int maxLines = 1, String? hint}) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
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
    return Row(
      children: [
        for (final d in Difficulty.values) ...[
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _difficulty = d),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                margin: EdgeInsets.only(right: d != Difficulty.values.last ? 8 : 0),
                decoration: BoxDecoration(
                  color: _difficulty == d ? AppColors.accent : (isDark ? AppColors.darkCard : AppColors.lightCard),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  d.name[0].toUpperCase() + d.name.substring(1),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _difficulty == d ? Colors.white : (isDark ? Colors.grey.shade400 : Colors.grey.shade700),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildOptionCard(int index, bool isDark) {
    final isCorrect = _correctIndex == index;
    final letter = String.fromCharCode(65 + index); // A, B, C, ...

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isCorrect ? AppColors.success : Colors.transparent, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => setState(() => _correctIndex = index),
                child: Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isCorrect ? AppColors.success : Colors.transparent,
                    border: Border.all(color: isCorrect ? AppColors.success : Colors.grey.shade400, width: 1.5),
                  ),
                  child: isCorrect
                      ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
                      : Text(letter, style: TextStyle(fontSize: 12, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _options[index].text,
                  style: TextStyle(fontSize: 14, color: isDark ? Colors.white : const Color(0xFF1A1A2E)),
                  decoration: InputDecoration(
                    hintText: 'Option $letter text',
                    hintStyle: TextStyle(color: isDark ? Colors.grey.shade600 : Colors.grey.shade400, fontSize: 13),
                    border: InputBorder.none,
                    isDense: true,
                  ),
                ),
              ),
              if (_options.length > _minOptions)
                IconButton(
                  icon: Icon(Icons.close_rounded, size: 18, color: isDark ? Colors.grey.shade600 : Colors.grey.shade400),
                  onPressed: () => _removeOption(index),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 38),
            child: TextField(
              controller: _options[index].rationale,
              maxLines: 2,
              style: TextStyle(fontSize: 12, color: isDark ? Colors.grey.shade300 : Colors.grey.shade700),
              decoration: InputDecoration(
                hintText: isCorrect ? 'Why this option is correct (optional)' : 'Why this option is wrong (optional)',
                hintStyle: TextStyle(color: isDark ? Colors.grey.shade600 : Colors.grey.shade400, fontSize: 12),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
