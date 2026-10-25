import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'question.dart';

/// The PRC Tables of Specifications (TOS) for the Criminologist Licensure
/// Examination, as the app uses them.
///
/// Source: PRB of Criminology Resolution No. 02, Series of 2024 (annexes
/// "as of January 22, 2024"), as amended by Resolution No. 06, Series of 2025
/// (Criminology Topic 4). The data lives in `assets/tos/tos_2024.json`, made
/// from the official annex PDFs by `tools/tos/`; see `content/tos/SOURCES.md`.
///
/// Every subject has 100 items. Each topic is split into competencies, and
/// each competency has a fixed number of items at each Bloom's taxonomy level.

/// Bloom's taxonomy levels, in the order of the TOS columns.
enum BloomLevel {
  remembering,
  understanding,
  applying,
  analyzing,
  evaluating,
  creating;

  /// The column heading used in the TOS and in `questions.bloom_level`.
  String get label => name[0].toUpperCase() + name.substring(1);

  /// The app's difficulty tier for items at this level: Remembering and
  /// Understanding are easy, Applying is medium, and Analyzing, Evaluating and
  /// Creating are hard. Grouped this way, every subject's TOS comes to about
  /// 30% easy, 50% medium and 20% hard (see [TosDifficultyMix]).
  Difficulty get difficulty {
    switch (this) {
      case BloomLevel.remembering:
      case BloomLevel.understanding:
        return Difficulty.easy;
      case BloomLevel.applying:
        return Difficulty.medium;
      case BloomLevel.analyzing:
      case BloomLevel.evaluating:
      case BloomLevel.creating:
        return Difficulty.hard;
    }
  }

  /// Parses `Applying`, `applying` or `Ap`; null when unknown.
  static BloomLevel? tryParse(String? value) {
    final v = (value ?? '').trim().toLowerCase();
    if (v.isEmpty) return null;
    for (final level in BloomLevel.values) {
      if (level.name == v) return level;
    }
    const short = {'r': 0, 'u': 1, 'ap': 2, 'an': 3, 'e': 4, 'c': 5};
    final i = short[v];
    return i == null ? null : BloomLevel.values[i];
  }
}

/// How a subject's 100 TOS items fall into the app's three difficulty tiers
/// once the Bloom levels are grouped as in [BloomLevel.difficulty].
///
/// These numbers are taken from the TOS (a test checks them against
/// `assets/tos/tos_2024.json`). The board-exam readiness score weights each
/// tier by them, so a subject with more Applying items counts medium
/// questions more.
class TosDifficultyMix {
  final int easy;
  final int medium;
  final int hard;

  const TosDifficultyMix(this.easy, this.medium, this.hard);

  double weightOf(Difficulty d) {
    final total = easy + medium + hard;
    switch (d) {
      case Difficulty.easy:
        return easy / total;
      case Difficulty.medium:
        return medium / total;
      case Difficulty.hard:
        return hard / total;
    }
  }

  /// Per subject id. Criminal Law: Rem 11 + Und 19 = 30 easy, App 50 medium,
  /// Ana 18 + Eva 2 = 20 hard; and so on for the others.
  static const Map<String, TosDifficultyMix> bySubject = {
    'criminal_jurisprudence': TosDifficultyMix(30, 50, 20),
    'law_enforcement': TosDifficultyMix(31, 49, 20),
    'criminalistics': TosDifficultyMix(30, 51, 19),
    'crime_detection': TosDifficultyMix(30, 50, 20),
    'criminology': TosDifficultyMix(31, 51, 18),
    'corrections': TosDifficultyMix(30, 50, 20),
  };

  /// The mix for [subjectId], or 30/50/20 for an unknown id.
  static TosDifficultyMix forSubject(String subjectId) =>
      bySubject[subjectId] ?? const TosDifficultyMix(30, 50, 20);
}

class TosCompetency {
  /// e.g. `CLJ-3.4`.
  final String code;
  final String topicCode;
  final String subjectId;

  /// The number as printed in the TOS, e.g. `3.4`.
  final String number;

  /// The competency as written in the TOS.
  final String text;
  final int items;
  final Map<BloomLevel, int> bloom;

  const TosCompetency({
    required this.code,
    required this.topicCode,
    required this.subjectId,
    required this.number,
    required this.text,
    required this.items,
    required this.bloom,
  });
}

class TosTopic {
  /// e.g. `CLJ-3`.
  final String code;
  final String subjectId;
  final int number;

  /// The topic title as written in the TOS. Questions, study modules and the
  /// student's topic mastery all use this exact title.
  final String title;
  final int items;
  final Map<BloomLevel, int> bloom;
  final List<TosCompetency> competencies;

  /// Set when a later resolution replaced the topic (Criminology Topic 4).
  final String? amendedBy;

  const TosTopic({
    required this.code,
    required this.subjectId,
    required this.number,
    required this.title,
    required this.items,
    required this.bloom,
    required this.competencies,
    this.amendedBy,
  });
}

class TosSubject {
  final String subjectId;

  /// Short code used in competency codes: CLJ, LEA, FS, CDI, CRIM, CA.
  final String code;
  final String name;

  /// Percentage of the whole examination.
  final int weight;
  final List<TosTopic> topics;

  const TosSubject({
    required this.subjectId,
    required this.code,
    required this.name,
    required this.weight,
    required this.topics,
  });

  Iterable<TosCompetency> get competencies => topics.expand((t) => t.competencies);
}

/// The whole TOS, loaded once from `assets/tos/tos_2024.json`.
class TosCatalog {
  static const String assetPath = 'assets/tos/tos_2024.json';

  final String resolution;
  final String amendment;
  final List<TosSubject> subjects;

  final Map<String, TosTopic> _topics;
  final Map<String, TosCompetency> _competencies;

  TosCatalog._(this.resolution, this.amendment, this.subjects)
      : _topics = {for (final s in subjects) for (final t in s.topics) t.code: t},
        _competencies = {
          for (final s in subjects)
            for (final c in s.competencies) c.code: c,
        };

  static TosCatalog? _loaded;
  static Future<TosCatalog>? _loading;

  /// The catalog, once [load] has finished; null before that.
  static TosCatalog? get loaded => _loaded;

  /// Loads the catalog from the asset bundle (once).
  static Future<TosCatalog> load() {
    final existing = _loaded;
    if (existing != null) return Future.value(existing);
    return _loading ??= rootBundle.loadString(assetPath).then((raw) {
      final catalog = TosCatalog.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      _loaded = catalog;
      return catalog;
    }).whenComplete(() => _loading = null);
  }

  @visibleForTesting
  static set debugLoaded(TosCatalog? value) => _loaded = value;

  factory TosCatalog.fromJson(Map<String, dynamic> json) {
    final source = (json['source'] as Map?) ?? const {};
    final amendment = (source['amendment'] as Map?) ?? const {};
    final subjects = <TosSubject>[];
    for (final s in (json['subjects'] as List? ?? const [])) {
      final subjectId = s['subject_id'] as String;
      final topics = <TosTopic>[];
      for (final t in (s['topics'] as List? ?? const [])) {
        final topicCode = t['code'] as String;
        topics.add(TosTopic(
          code: topicCode,
          subjectId: subjectId,
          number: (t['no'] as num).toInt(),
          title: t['title'] as String,
          items: (t['items'] as num).toInt(),
          bloom: _bloom(t['bloom']),
          amendedBy: t['amended_by'] as String?,
          competencies: [
            for (final c in (t['competencies'] as List? ?? const []))
              TosCompetency(
                code: c['code'] as String,
                topicCode: topicCode,
                subjectId: subjectId,
                number: c['no'].toString(),
                text: c['text'] as String,
                items: (c['items'] as num).toInt(),
                bloom: _bloom(c['bloom']),
              ),
          ],
        ));
      }
      subjects.add(TosSubject(
        subjectId: subjectId,
        code: s['code'] as String,
        name: s['name'] as String,
        weight: (s['weight'] as num).toInt(),
        topics: topics,
      ));
    }
    return TosCatalog._(
      (source['resolution'] ?? '').toString(),
      (amendment['resolution'] ?? '').toString(),
      subjects,
    );
  }

  static Map<BloomLevel, int> _bloom(dynamic raw) {
    final out = <BloomLevel, int>{};
    if (raw is Map) {
      raw.forEach((k, v) {
        final level = BloomLevel.tryParse(k.toString());
        if (level != null && v is num && v > 0) out[level] = v.toInt();
      });
    }
    return out;
  }

  /// Short citation for screens: "PRB Crim. Res. No. 02 s. 2024, as amended
  /// by Res. No. 06 s. 2025".
  String get citation => 'PRB Crim. Res. No. 02 s. 2024, as amended by Res. No. 06 s. 2025';

  TosSubject? subject(String subjectId) {
    for (final s in subjects) {
      if (s.subjectId == subjectId) return s;
    }
    return null;
  }

  TosTopic? topic(String code) => _topics[code];

  TosCompetency? competency(String code) => _competencies[code];

  /// The topic of a topic or competency code (`CLJ-3.4` -> `CLJ-3`).
  TosTopic? topicOf(String? code) {
    if (code == null || code.isEmpty) return null;
    return _topics[code] ?? _topics[_competencies[code]?.topicCode];
  }

  /// The TOS topic of [subjectId] titled [title] (case and spacing ignored).
  TosTopic? topicByTitle(String subjectId, String title) {
    final wanted = title.trim().toLowerCase();
    for (final t in subject(subjectId)?.topics ?? const <TosTopic>[]) {
      if (t.title.toLowerCase() == wanted) return t;
    }
    return null;
  }

  /// True when [code] is a topic or competency code of the TOS.
  bool isKnownCode(String? code) =>
      code != null && (_topics.containsKey(code) || _competencies.containsKey(code));
}

/// Maps the topic names used before the TOS alignment onto TOS topics.
///
/// Loaded from `assets/tos/topic_map.json`, the same file that generated
/// `supabase_tos_alignment.sql`, so the app renames a student's saved topics
/// exactly as the database did.
class TosTopicMap {
  static const String assetPath = 'assets/tos/topic_map.json';

  /// `subjectId::old topic (lower case)` -> TOS topic code, or null when the
  /// TOS has no such topic.
  final Map<String, String?> _byOldTopic;
  final TosCatalog catalog;

  TosTopicMap._(this._byOldTopic, this.catalog);

  factory TosTopicMap.fromJson(Map<String, dynamic> json, TosCatalog catalog) {
    final map = <String, String?>{};
    final topics = (json['topics'] as Map?) ?? const {};
    topics.forEach((subjectId, entries) {
      if (entries is! Map) return;
      entries.forEach((old, code) {
        map['$subjectId::${old.toString().trim().toLowerCase()}'] = code?.toString();
      });
    });
    return TosTopicMap._(map, catalog);
  }

  static Future<TosTopicMap> load() async {
    final catalog = await TosCatalog.load();
    final raw = await rootBundle.loadString(assetPath);
    return TosTopicMap.fromJson(jsonDecode(raw) as Map<String, dynamic>, catalog);
  }

  /// Where a saved topic belongs now: the TOS topic it maps to, the same
  /// topic when it is already a TOS title or not in the map, or null when the
  /// TOS dropped it.
  ({String subjectId, String topic})? resolve(String subjectId, String topic) {
    if (catalog.topicByTitle(subjectId, topic) != null) {
      return (subjectId: subjectId, topic: topic);
    }
    final key = '$subjectId::${topic.trim().toLowerCase()}';
    if (!_byOldTopic.containsKey(key)) return (subjectId: subjectId, topic: topic);
    final target = catalog.topic(_byOldTopic[key] ?? '');
    if (target == null) return null;
    return (subjectId: target.subjectId, topic: target.title);
  }
}
