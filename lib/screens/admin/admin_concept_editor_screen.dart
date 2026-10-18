import 'package:flutter/material.dart';

import '../../models/concept.dart';
import '../../models/subject.dart';
import '../../services/concept_service.dart';
import '../../utils/concept_import_parser.dart';
import '../../utils/concept_rules.dart';
import '../../utils/responsive.dart';
import '../../widgets/ui/ui.dart';
import 'concept_subject_topic_fields.dart';

/// Add or edit one concept: a term, its meaning, and optionally its legal
/// basis. The database turns each concept into up to four questions for
/// Faculty to review (`supabase_concept_bank.sql`).
///
/// Editing changes only the term, definition and legal basis. To move a
/// concept to another topic, deactivate it and add it again.
class AdminConceptEditorScreen extends StatefulWidget {
  final Concept? existing;

  /// Every concept, used to suggest topics and to find a topic's groups.
  final List<Concept> concepts;

  /// Pre-fills a new concept's subject and topic (for example when adding to
  /// a topic from the list).
  final String? presetSubjectId;
  final String? presetTopic;

  const AdminConceptEditorScreen({
    super.key,
    this.existing,
    this.concepts = const [],
    this.presetSubjectId,
    this.presetTopic,
  });

  @override
  State<AdminConceptEditorScreen> createState() => _AdminConceptEditorScreenState();
}

class _AdminConceptEditorScreenState extends State<AdminConceptEditorScreen> {
  late final TextEditingController _term;
  late final TextEditingController _definition;
  late final TextEditingController _basis;

  late String _subjectId;
  late String _topic;
  String? _group;

  bool _saving = false;
  String? _error;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final c = widget.existing;
    _term = TextEditingController(text: c?.term ?? '');
    _definition = TextEditingController(text: c?.definition ?? '');
    _basis = TextEditingController(text: c?.legalBasis ?? '');
    _subjectId = c?.subjectId ?? widget.presetSubjectId ?? CriminologySubjects.all.first.id;
    _topic = c?.topic ?? widget.presetTopic ?? '';
  }

  @override
  void dispose() {
    _term.dispose();
    _definition.dispose();
    _basis.dispose();
    super.dispose();
  }

  List<String> get _groups => conceptGroupsFor(widget.concepts, _subjectId, _topic);

  String? _validate() {
    if (!_isEditing && _topic.trim().isEmpty) return 'Choose or type a topic.';
    if (!_isEditing && _groups.length > 1 && _group == null) {
      return 'This topic has more than one group. Choose which group the concept belongs to.';
    }
    return conceptFieldError(_term.text, _definition.text, _basis.text);
  }

  Future<void> _save() async {
    final problem = _validate();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });

    final basis = _basis.text.trim();
    final result = await ConceptService.instance.saveConcept(
      id: widget.existing?.id,
      subjectId: _subjectId,
      topic: _topic,
      term: _term.text.trim(),
      definition: _definition.text.trim(),
      legalBasis: basis.isEmpty ? null : basis,
      siblingGroup: _isEditing ? null : _group,
    );
    if (!mounted) return;

    if (!result.success) {
      setState(() {
        _saving = false;
        _error = result.error ?? 'Could not save the concept.';
      });
      return;
    }
    showAppSnack(
      context,
      _isEditing ? 'Concept updated' : 'Concept added',
      tone: BannerTone.success,
    );
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = context.textStyles;
    final padding = Responsive.horizontalPadding(context);
    final groups = _groups;

    return Scaffold(
      appBar: AppTopBar(
        title: _isEditing ? 'Edit concept' : 'New concept',
        subtitle: _isEditing ? widget.existing!.topic : 'Becomes up to 4 questions to review',
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
                      if (_error != null) ...[
                        InlineBanner(tone: BannerTone.danger, message: _error!),
                        const SizedBox(height: 14),
                      ],
                      AppCard(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                const IconBadge(icon: Icons.folder_open_rounded, size: 32, iconSize: 17),
                                const SizedBox(width: 10),
                                Expanded(child: Text('Where it belongs', style: text.titleMedium)),
                              ],
                            ),
                            const SizedBox(height: 16),
                            ConceptSubjectTopicFields(
                              subjectId: _subjectId,
                              topic: _topic,
                              concepts: widget.concepts,
                              enabled: !_isEditing && !_saving,
                              onSubjectChanged: (v) => setState(() {
                                _subjectId = v;
                                _group = null;
                              }),
                              onTopicChanged: (v) => setState(() {
                                _topic = v;
                                _group = null;
                              }),
                            ),
                            if (!_isEditing && groups.length > 1) ...[
                              const SizedBox(height: 16),
                              Padding(
                                padding: const EdgeInsets.only(left: 2, bottom: 7),
                                child: Text('Group', style: text.labelMedium?.copyWith(color: p.textPrimary)),
                              ),
                              DropdownButtonFormField<String>(
                                key: ValueKey('group-$_subjectId-$_topic'),
                                initialValue: _group,
                                isExpanded: true,
                                hint: const Text('Choose a group'),
                                icon: const Icon(Icons.keyboard_arrow_down_rounded),
                                borderRadius: BorderRadius.circular(AppSpace.radiusMd),
                                items: [for (final g in groups) DropdownMenuItem(value: g, child: Text(g))],
                                onChanged: _saving ? null : (v) => setState(() => _group = v),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Concepts in the same group are used as each other\'s wrong answers.',
                                style: text.bodySmall,
                              ),
                            ],
                            if (_isEditing) ...[
                              const SizedBox(height: 10),
                              Text(
                                'The subject and topic cannot be changed. To move this concept, deactivate it and add it again.',
                                style: text.bodySmall,
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      AppCard(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                const IconBadge(icon: Icons.menu_book_rounded, size: 32, iconSize: 17),
                                const SizedBox(width: 10),
                                Expanded(child: Text('The concept', style: text.titleMedium)),
                              ],
                            ),
                            const SizedBox(height: 16),
                            AppTextField(
                              controller: _term,
                              label: 'Term',
                              hint: 'e.g. Self-Defense',
                              maxLength: kConceptMaxTermLength,
                              enabled: !_saving,
                              textCapitalization: TextCapitalization.sentences,
                            ),
                            const SizedBox(height: 16),
                            AppTextField(
                              controller: _definition,
                              label: 'Definition',
                              hint: 'The full meaning. It becomes the correct answer.',
                              maxLines: 6,
                              maxLength: kConceptMaxDefinitionLength,
                              enabled: !_saving,
                              textCapitalization: TextCapitalization.sentences,
                            ),
                            const SizedBox(height: 6),
                            Padding(
                              padding: const EdgeInsets.only(left: 2),
                              child: Text(
                                'Other concepts in the same group become the wrong answers.',
                                style: text.bodySmall,
                              ),
                            ),
                            const SizedBox(height: 16),
                            AppTextField(
                              controller: _basis,
                              label: 'Legal basis (optional)',
                              hint: 'e.g. RPC Art. 11(1)',
                              icon: Icons.gavel_rounded,
                              maxLength: kConceptMaxBasisLength,
                              enabled: !_saving,
                            ),
                            const SizedBox(height: 6),
                            Padding(
                              padding: const EdgeInsets.only(left: 2),
                              child: Text(
                                'Needed for the two legal-basis question forms. '
                                'Give every concept in the group its own.',
                                style: text.bodySmall,
                              ),
                            ),
                          ],
                        ),
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
                          label: _isEditing ? 'Save changes' : 'Add concept',
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
}
