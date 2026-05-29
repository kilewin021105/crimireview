import 'question.dart';

class ModuleSection {
  final String title;
  final String? subtitle;
  final List<String> content;
  final List<String>? bulletPoints;
  final bool isKeyConcept;
  final bool isSummary;

  const ModuleSection({
    required this.title,
    this.subtitle,
    this.content = const [],
    this.bulletPoints,
    this.isKeyConcept = false,
    this.isSummary = false,
  });
}

class Module {
  final String id;
  final String subjectId;
  final String title;
  final String subtitle;
  final String description;
  final List<String> learningObjectives;
  final List<ModuleSection> sections;
  final List<Question> practiceQuestions;

  const Module({
    required this.id,
    required this.subjectId,
    required this.title,
    required this.subtitle,
    required this.description,
    this.learningObjectives = const [],
    this.sections = const [],
    this.practiceQuestions = const [],
  });
}
