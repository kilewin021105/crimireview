import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../models/question.dart';

/// One key point shown before a quiz: a TOS competency's note from the study
/// module.
class StudyNote {
  /// The TOS competency, e.g. `CLJ-3.4`.
  final String code;
  final String title;
  final String content;

  const StudyNote({required this.code, required this.title, required this.content});
}

/// What the study notes screen shows for one quiz.
class StudyNotesContent {
  final List<StudyNote> notes;
  final List<String> keyTerms;

  /// The TOS topics the notes come from, e.g. `Criminal Law (Book 1)`.
  final List<String> topics;

  const StudyNotesContent({required this.notes, required this.keyTerms, required this.topics});

  static const empty = StudyNotesContent(notes: [], keyTerms: [], topics: []);
}

/// Reads the study modules (`assets/modules/<subject>_module.json`, built from
/// the PRC TOS by tools/tos/build_modules.py) and picks the key points that
/// match the questions of a quiz.
class StudyNotesService {
  StudyNotesService._();
  static final StudyNotesService instance = StudyNotesService._();

  final Map<String, Map<String, dynamic>> _modules = {};

  Future<Map<String, dynamic>?> module(String subjectId) async {
    final cached = _modules[subjectId];
    if (cached != null) return cached;
    try {
      final raw = await rootBundle.loadString('assets/modules/${subjectId}_module.json');
      return _modules[subjectId] = jsonDecode(raw) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('StudyNotesService: no module for $subjectId ($e)');
      return null;
    }
  }

  Future<StudyNotesContent> forQuiz(String subjectId, List<Question> questions) async {
    final m = await module(subjectId);
    return m == null ? StudyNotesContent.empty : pick(m, questions);
  }

  /// The key points for [questions]: first the competencies the questions are
  /// linked to (most questions first), then the rest of their topics, then,
  /// if nothing matches, the first point of each chapter.
  @visibleForTesting
  static StudyNotesContent pick(Map<String, dynamic> module, List<Question> questions,
      {int maxNotes = 6, int maxTerms = 12}) {
    final chapters = [
      for (final c in (module['chapters'] as List? ?? const []))
        if (c is Map) c.map((k, v) => MapEntry(k.toString(), v)),
    ];
    final competencyCount = <String, int>{};
    final topicCodes = <String>{};
    final topicTitles = <String>{};
    for (final q in questions) {
      final code = q.tosCode;
      if (code != null && code.isNotEmpty) {
        topicCodes.add(code.split('.').first);
        if (code.contains('.')) competencyCount[code] = (competencyCount[code] ?? 0) + 1;
      }
      topicTitles.add(q.topic.trim().toLowerCase());
    }

    final relevant = chapters
        .where((c) =>
            topicCodes.contains(c['code']) ||
            topicTitles.contains((c['title'] ?? '').toString().trim().toLowerCase()))
        .toList();
    final pool = relevant.isEmpty ? chapters : relevant;

    final points = <Map<String, dynamic>>[];
    for (final c in pool) {
      for (final p in (c['keyPoints'] as List? ?? const [])) {
        if (p is Map) points.add(p.map((k, v) => MapEntry(k.toString(), v)));
      }
    }

    final chosen = <Map<String, dynamic>>[];
    void take(Iterable<Map<String, dynamic>> from) {
      for (final p in from) {
        if (chosen.length >= maxNotes) return;
        if (!chosen.any((x) => x['code'] == p['code'])) chosen.add(p);
      }
    }

    final linked = points.where((p) => competencyCount.containsKey(p['code'])).toList()
      ..sort((a, b) => (competencyCount[b['code']] ?? 0).compareTo(competencyCount[a['code']] ?? 0));
    take(linked);
    if (relevant.isNotEmpty) {
      take(points);
    } else {
      // Nothing matched: one point from each chapter, then the rest.
      take([
        for (final c in chapters)
          if ((c['keyPoints'] as List? ?? const []).isNotEmpty)
            ((c['keyPoints'] as List).first as Map).map((k, v) => MapEntry(k.toString(), v)),
      ]);
      take(points);
    }

    final terms = <String>[];
    for (final c in pool) {
      for (final t in (c['keyTerms'] as List? ?? const [])) {
        final term = t.toString();
        if (terms.length < maxTerms && !terms.contains(term)) terms.add(term);
      }
    }

    return StudyNotesContent(
      notes: [
        for (final p in chosen)
          StudyNote(
            code: (p['code'] ?? '').toString(),
            title: (p['title'] ?? '').toString(),
            content: (p['note'] ?? '').toString(),
          ),
      ],
      keyTerms: terms,
      topics: [for (final c in relevant) (c['title'] ?? '').toString()],
    );
  }
}
