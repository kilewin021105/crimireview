import 'package:flutter/material.dart';

import '../../models/concept.dart';
import '../../models/subject.dart';
import '../../widgets/ui/ui.dart';

/// The Subject and Topic fields shared by the concept form and the import
/// screen.
///
/// The topic list offers the topics already used by concepts in that subject
/// plus the topics the app lists for the subject, and "New topic…" for
/// anything else. Offering the existing spelling matters: the database
/// matches topics by name, and a second spelling would start an empty topic.
class ConceptSubjectTopicFields extends StatefulWidget {
  final String subjectId;
  final String topic;
  final List<Concept> concepts;
  final ValueChanged<String> onSubjectChanged;
  final ValueChanged<String> onTopicChanged;
  final bool enabled;

  const ConceptSubjectTopicFields({
    super.key,
    required this.subjectId,
    required this.topic,
    required this.concepts,
    required this.onSubjectChanged,
    required this.onTopicChanged,
    this.enabled = true,
  });

  @override
  State<ConceptSubjectTopicFields> createState() => _ConceptSubjectTopicFieldsState();
}

class _ConceptSubjectTopicFieldsState extends State<ConceptSubjectTopicFields> {
  static const String _newTopic = '\u0000new';

  late final TextEditingController _newTopicController;
  bool _newMode = false;

  @override
  void initState() {
    super.initState();
    _newTopicController = TextEditingController();
    _syncFromWidget();
  }

  @override
  void didUpdateWidget(covariant ConceptSubjectTopicFields oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.subjectId != widget.subjectId) {
      _newMode = false;
      _newTopicController.clear();
    }
  }

  @override
  void dispose() {
    _newTopicController.dispose();
    super.dispose();
  }

  /// A topic that is not in the list (for example one handed in by the screen)
  /// is shown in the "new topic" box.
  void _syncFromWidget() {
    final topic = widget.topic.trim();
    if (topic.isEmpty) return;
    if (_optionFor(topic) == null) {
      _newMode = true;
      _newTopicController.text = topic;
    }
  }

  List<String> _options() {
    final byKey = <String, String>{};
    for (final s in CriminologySubjects.all) {
      if (s.id != widget.subjectId) continue;
      for (final t in s.topics) {
        byKey.putIfAbsent(t.trim().toLowerCase(), () => t.trim());
      }
    }
    // The database spelling wins over the app's list.
    for (final c in widget.concepts) {
      if (c.subjectId == widget.subjectId && c.topic.trim().isNotEmpty) {
        byKey[c.topic.trim().toLowerCase()] = c.topic.trim();
      }
    }
    final list = byKey.values.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  String? _optionFor(String topic) {
    final key = topic.trim().toLowerCase();
    for (final o in _options()) {
      if (o.toLowerCase() == key) return o;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final text = context.textStyles;
    final options = _options();
    final selected = _newMode ? _newTopic : _optionFor(widget.topic);

    Widget label(String value) => Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 7),
          child: Text(value, style: text.labelMedium?.copyWith(color: context.palette.textPrimary)),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        label('Subject'),
        DropdownButtonFormField<String>(
          key: ValueKey('subject-${widget.subjectId}-${widget.enabled}'),
          initialValue: widget.subjectId,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
          borderRadius: BorderRadius.circular(AppSpace.radiusMd),
          items: [
            for (final s in CriminologySubjects.all)
              DropdownMenuItem(
                value: s.id,
                child: Row(
                  children: [
                    Icon(AppTheme.subjectIcons[s.id] ?? s.icon, size: 18, color: AppColors.subjectColor(s.id)),
                    const SizedBox(width: 10),
                    Flexible(child: Text(s.name, overflow: TextOverflow.ellipsis)),
                  ],
                ),
              ),
          ],
          onChanged: widget.enabled
              ? (v) {
                  if (v == null || v == widget.subjectId) return;
                  widget.onSubjectChanged(v);
                  widget.onTopicChanged('');
                }
              : null,
        ),
        const SizedBox(height: 16),
        label('Topic'),
        DropdownButtonFormField<String>(
          key: ValueKey('topic-${widget.subjectId}-$selected-${widget.enabled}'),
          initialValue: selected,
          isExpanded: true,
          hint: const Text('Choose a topic'),
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
          borderRadius: BorderRadius.circular(AppSpace.radiusMd),
          items: [
            for (final t in options) DropdownMenuItem(value: t, child: Text(t, overflow: TextOverflow.ellipsis)),
            const DropdownMenuItem(
              value: _newTopic,
              child: Row(
                children: [
                  Icon(Icons.add_rounded, size: 18),
                  SizedBox(width: 10),
                  Flexible(child: Text('New topic…', overflow: TextOverflow.ellipsis)),
                ],
              ),
            ),
          ],
          onChanged: widget.enabled
              ? (v) {
                  if (v == null) return;
                  if (v == _newTopic) {
                    setState(() => _newMode = true);
                    widget.onTopicChanged(_newTopicController.text.trim());
                  } else {
                    setState(() => _newMode = false);
                    widget.onTopicChanged(v);
                  }
                }
              : null,
        ),
        if (_newMode) ...[
          const SizedBox(height: 16),
          AppTextField(
            controller: _newTopicController,
            label: 'New topic name',
            hint: 'e.g. Probation Law',
            enabled: widget.enabled,
            maxLength: 120,
            textCapitalization: TextCapitalization.words,
            onChanged: (v) => widget.onTopicChanged(v.trim()),
          ),
        ],
      ],
    );
  }
}
