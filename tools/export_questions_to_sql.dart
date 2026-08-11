// tools/export_questions_to_sql.dart
//
// ONE-WAY CONTENT MIGRATION TOOL  --  run with:  dart run tools/export_questions_to_sql.dart
//
// WHY THIS EXISTS
// ---------------
// Pre-oral defense panel note #7: "Do NOT put your questions in your code. It should have an ADMIN
// to add questions, or you automate everything."
//
// All quiz content currently lives as hardcoded `Question(...)` constructors inside
//   lib/data/questions_database.dart   (the live source)
//   lib/data/question_bank.dart        (dead code, nothing imports it)
// Both files are being DELETED. This script lifts every question out of Dart and emits
// `supabase_seed_questions.sql`, a set of idempotent INSERT ... ON CONFLICT (id) DO UPDATE
// statements for `public.questions`, which becomes the single source of truth.
//
// HARD CONSTRAINT: this script must NEVER `import` the two data files -- they are scheduled for
// deletion and importing them would make the migration tool die with the thing it is migrating.
// The files are read as PLAIN TEXT and parsed with a small hand-rolled Dart-literal scanner.
//
// The two files are formatted differently:
//   * questions_database.dart packs several fields onto one line, order: id/subject/topic,
//     questionText, options, correctAnswerIndex + difficulty, explanation.
//   * question_bank.dart uses one field per line and puts `difficulty` AFTER `explanation`.
// Therefore every field is resolved by NAME, never by position.
//
// It also synthesizes, for every option, the per-option rationale required by panel note #5
// ("Your App can explain WHY the answer is wrong"), and derives a Philippine legal citation
// (`legal_basis`) by regex-scanning the explanation and stem.

import 'dart:convert';
import 'dart:io';

// ---------------------------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------------------------

const String kQuestionsDatabasePath = 'lib/data/questions_database.dart';
const String kQuestionBankPath = 'lib/data/question_bank.dart';
const String kOutputPath = 'supabase_seed_questions.sql';

/// question_bank.dart ids (cl_001, fs_001, ...) are prefixed so they can never collide with
/// questions_database.dart ids (cj_001, lea_001, ...).
const String kQuestionBankIdPrefix = 'qb_';

/// Mirrors SegmentProgress in lib/models/user_progress.dart -- 4 segments of 10 questions per
/// difficulty. Used only to report content coverage in the generated header.
const int kQuestionsPerSegment = 10; // SegmentProgress.questionsPerSegment
const int kSegmentsPerDifficulty = 4; // SegmentProgress.segmentCount
const int kQuestionsNeededPerBucket = kQuestionsPerSegment * kSegmentsPerDifficulty;

/// question_bank.dart invented subject slugs that the app's Subject catalogue
/// (lib/models/subject.dart) does not know about. Left as-is those questions would be
/// orphaned -- present in the table but unreachable from any subject tile. They are folded
/// into the six canonical board-exam subjects.
const Map<String, String> kSubjectAliases = {
  'criminal_law': 'criminal_jurisprudence',
  'jurisprudence': 'criminal_jurisprudence',
  'forensic_science': 'criminalistics',
};

/// The six canonical subjects, from lib/models/subject.dart. Used for remediation hints and
/// to flag anything that would land outside the app's navigation.
const Map<String, String> kSubjectNames = {
  'criminal_jurisprudence': 'Criminal Jurisprudence',
  'law_enforcement': 'Law Enforcement Administration',
  'criminalistics': 'Criminalistics',
  'crime_detection': 'Crime Detection and Investigation',
  'criminology': 'Criminology',
  'corrections': 'Correctional Administration',
};

// ---------------------------------------------------------------------------------------------
// Parsed model
// ---------------------------------------------------------------------------------------------

class ParsedQuestion {
  final String id;
  final String rawSubject;
  final String subject;
  final String topic;
  final String questionText;
  final List<String> options;
  final int correctAnswerIndex;
  final String difficulty;
  final String explanation;
  final String originFile;

  ParsedQuestion({
    required this.id,
    required this.rawSubject,
    required this.subject,
    required this.topic,
    required this.questionText,
    required this.options,
    required this.correctAnswerIndex,
    required this.difficulty,
    required this.explanation,
    required this.originFile,
  });

  String get correctOption =>
      (correctAnswerIndex >= 0 && correctAnswerIndex < options.length)
          ? options[correctAnswerIndex]
          : (options.isNotEmpty ? options.first : '');
}

// ---------------------------------------------------------------------------------------------
// Dart source scanner
// ---------------------------------------------------------------------------------------------

/// Walks forward from [start] (which sits just INSIDE an opening paren/bracket) and returns the
/// index of the matching closer. String literals are respected so that a `)` or `,` living inside
/// 'Bachelor\'s degree' or '5\'4" or 162 cm' never confuses the nesting count.
int _findMatching(String src, int start, String open, String close) {
  var depth = 1;
  var i = start;
  while (i < src.length) {
    final c = src[i];
    if (c == r'\') {
      i += 2;
      continue;
    }
    if (c == "'" || c == '"') {
      i = _skipString(src, i);
      continue;
    }
    if (c == open) {
      depth++;
    } else if (c == close) {
      depth--;
      if (depth == 0) return i;
    }
    i++;
  }
  throw StateError('Unbalanced $open$close starting at offset $start');
}

/// [i] points at the opening quote. Returns the index just AFTER the closing quote.
int _skipString(String src, int i) {
  final quote = src[i];
  i++;
  while (i < src.length) {
    final c = src[i];
    if (c == r'\') {
      i += 2;
      continue;
    }
    if (c == quote) return i + 1;
    i++;
  }
  throw StateError('Unterminated string literal at offset $i');
}

/// Splits an argument list body on top-level commas only.
List<String> _splitTopLevel(String body) {
  final parts = <String>[];
  final buf = StringBuffer();
  var depth = 0;
  var i = 0;
  while (i < body.length) {
    final c = body[i];
    if (c == r'\') {
      buf.write(body.substring(i, (i + 2).clamp(0, body.length)));
      i += 2;
      continue;
    }
    if (c == "'" || c == '"') {
      final end = _skipString(body, i);
      buf.write(body.substring(i, end));
      i = end;
      continue;
    }
    if (c == '(' || c == '[' || c == '{') depth++;
    if (c == ')' || c == ']' || c == '}') depth--;
    if (c == ',' && depth == 0) {
      parts.add(buf.toString());
      buf.clear();
      i++;
      continue;
    }
    buf.write(c);
    i++;
  }
  if (buf.toString().trim().isNotEmpty) parts.add(buf.toString());
  return parts;
}

/// Unescapes a Dart string literal, including Dart's implicit adjacent-literal concatenation
/// ('foo' 'bar'). Handles \' \" \\ \n \r \t \b \f \$ \uXXXX and \u{XXXX}.
String _parseDartString(String raw) {
  final src = raw.trim();
  final out = StringBuffer();
  var i = 0;
  var sawAny = false;
  while (i < src.length) {
    final c = src[i];
    if (c == ' ' || c == '\n' || c == '\r' || c == '\t') {
      i++;
      continue;
    }
    if (c != "'" && c != '"') {
      if (sawAny) break;
      throw FormatException('Not a string literal: $raw');
    }
    sawAny = true;
    final quote = c;
    i++;
    while (i < src.length && src[i] != quote) {
      if (src[i] == r'\') {
        i++;
        if (i >= src.length) break;
        final e = src[i];
        switch (e) {
          case 'n':
            out.write('\n');
            break;
          case 'r':
            out.write('\r');
            break;
          case 't':
            out.write('\t');
            break;
          case 'b':
            out.write('\b');
            break;
          case 'f':
            out.write('\f');
            break;
          case 'v':
            out.write('\v');
            break;
          case 'u':
            i++;
            if (i < src.length && src[i] == '{') {
              final close = src.indexOf('}', i);
              out.writeCharCode(int.parse(src.substring(i + 1, close), radix: 16));
              i = close;
            } else {
              out.writeCharCode(int.parse(src.substring(i, i + 4), radix: 16));
              i += 3;
            }
            break;
          default:
            // \' \" \\ \$ and anything else -> the literal character
            out.write(e);
        }
        i++;
        continue;
      }
      out.write(src[i]);
      i++;
    }
    i++; // consume closing quote
  }
  if (!sawAny) throw FormatException('Not a string literal: $raw');
  return out.toString();
}

/// Parses a `[ 'a', 'b', 'c' ]` literal into its unescaped strings.
List<String> _parseStringList(String raw) {
  final s = raw.trim();
  final open = s.indexOf('[');
  final close = s.lastIndexOf(']');
  if (open < 0 || close < 0) throw FormatException('Not a list literal: $raw');
  final inner = s.substring(open + 1, close);
  return _splitTopLevel(inner)
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .map(_parseDartString)
      .toList();
}

final RegExp _fieldRe = RegExp(r'^\s*([A-Za-z_][A-Za-z0-9_]*)\s*:\s*([\s\S]*)$');
final RegExp _difficultyRe = RegExp(r'Difficulty\.([A-Za-z]+)');

/// Extracts every `Question( ... )` constructor body from a Dart source file, as raw text.
List<String> _extractQuestionBlocks(String src) {
  final blocks = <String>[];
  const needle = 'Question(';
  final identChar = RegExp(r'[A-Za-z0-9_$]');
  var i = 0;
  while (true) {
    final idx = src.indexOf(needle, i);
    if (idx < 0) break;
    // Reject QuestionsDatabase(, buildQuestion(, etc. -- the char before must not be an
    // identifier character.
    if (idx > 0 && identChar.hasMatch(src[idx - 1])) {
      i = idx + needle.length;
      continue;
    }
    final bodyStart = idx + needle.length;
    final bodyEnd = _findMatching(src, bodyStart, '(', ')');
    blocks.add(src.substring(bodyStart, bodyEnd));
    i = bodyEnd + 1;
  }
  return blocks;
}

class ParseReport {
  final List<ParsedQuestion> questions = [];
  final List<String> warnings = [];
  int blockCount = 0;
}

ParseReport parseFile(String path, {String idPrefix = ''}) {
  final report = ParseReport();
  final file = File(path);
  if (!file.existsSync()) {
    report.warnings.add('MISSING FILE: $path');
    return report;
  }
  final src = file.readAsStringSync();
  final blocks = _extractQuestionBlocks(src);
  report.blockCount = blocks.length;

  for (final block in blocks) {
    final fields = <String, String>{};
    for (final arg in _splitTopLevel(block)) {
      if (arg.trim().isEmpty) continue;
      final m = _fieldRe.firstMatch(arg);
      if (m == null) continue;
      fields[m.group(1)!] = m.group(2)!.trim();
    }

    // Every field is looked up BY NAME, so the differing field order between the two source
    // files is irrelevant.
    String? need(String key) => fields[key];

    final rawId = need('id');
    if (rawId == null) {
      report.warnings.add('$path: a Question() block has no id; skipped');
      continue;
    }

    try {
      final id = idPrefix + _parseDartString(rawId);
      final rawSubject = _parseDartString(need('subject')!);
      final subject = kSubjectAliases[rawSubject] ?? rawSubject;
      final topic = _parseDartString(need('topic')!);
      final questionText = _parseDartString(need('questionText')!);
      final options = _parseStringList(need('options')!);
      final correctAnswerIndex = int.parse(need('correctAnswerIndex')!.trim());
      final diffMatch = _difficultyRe.firstMatch(need('difficulty') ?? '');
      final difficulty = diffMatch?.group(1) ?? 'medium';
      final explanation =
          need('explanation') == null ? '' : _parseDartString(need('explanation')!);

      if (options.length < 2) {
        report.warnings.add('$path: $id has only ${options.length} option(s)');
      }
      if (correctAnswerIndex < 0 || correctAnswerIndex >= options.length) {
        report.warnings.add(
            '$path: $id correctAnswerIndex=$correctAnswerIndex is out of range (${options.length} options)');
      }
      if (!const ['easy', 'medium', 'hard'].contains(difficulty)) {
        report.warnings.add('$path: $id has unknown difficulty "$difficulty"');
      }
      if (!kSubjectNames.containsKey(subject)) {
        report.warnings.add('$path: $id maps to unknown subject "$subject"');
      }

      report.questions.add(ParsedQuestion(
        id: id,
        rawSubject: rawSubject,
        subject: subject,
        topic: topic,
        questionText: questionText,
        options: options,
        correctAnswerIndex: correctAnswerIndex,
        difficulty: difficulty,
        explanation: explanation,
        originFile: path,
      ));
    } catch (e) {
      report.warnings.add('$path: failed to parse block starting id=$rawId -> $e');
    }
  }
  return report;
}

// ---------------------------------------------------------------------------------------------
// Duplicate-stem collapsing
// ---------------------------------------------------------------------------------------------
//
// supabase_schema_v2.sql guards the table with
//     UNIQUE INDEX uq_questions_subject_stem ON questions(subject_id, md5(lower(question_text)))
// and questions_database.dart genuinely repeats itself: e.g. cdi_064 and cdi_123 are both
// "What is trace evidence?" under crime_detection with reworded options. Emitting both would
// raise a unique_violation and roll back the ENTIRE seed transaction.
//
// Duplicates are also a product defect in their own right: QuestionSelectionService rule R1
// ("never serve a question the learner has already seen") is defeated by the same stem wearing
// two different ids, which is precisely panel note #3's "repeat the topic but NOT the same
// question". So the surplus copies are collapsed rather than merely reordered.

class DedupeResult {
  final List<ParsedQuestion> kept = [];
  /// dropped question -> the question that superseded it
  final List<MapEntry<ParsedQuestion, ParsedQuestion>> dropped = [];
  int get groupsCollapsed =>
      dropped.map((e) => e.value.id).toSet().length;
}

/// The key mirrors the database index EXACTLY -- `lower(question_text)` scoped to the subject.
/// Deliberately no trimming or whitespace collapsing: matching the index precisely means we
/// drop the minimum number of rows that still guarantees the index accepts the seed.
String _stemKey(ParsedQuestion q) => '${q.subject} ${q.questionText.toLowerCase()}';

/// Richness score -- when two copies collide we keep the more useful one.
int _richness(ParsedQuestion q) {
  var score = q.options.length * 1000;
  score += q.explanation.length;
  if (extractLegalBasis(q) != null) score += 500;
  return score;
}

DedupeResult dedupeByStem(List<ParsedQuestion> all) {
  final result = DedupeResult();
  final winners = <String, ParsedQuestion>{};
  final groups = <String, List<ParsedQuestion>>{};

  for (final q in all) {
    groups.putIfAbsent(_stemKey(q), () => []).add(q);
  }

  for (final entry in groups.entries) {
    final group = entry.value;
    if (group.length == 1) {
      winners[entry.key] = group.first;
      continue;
    }
    // Deterministic: richest first, then lowest id, so re-running the export is stable.
    final sorted = List<ParsedQuestion>.from(group)
      ..sort((a, b) {
        final r = _richness(b).compareTo(_richness(a));
        return r != 0 ? r : a.id.compareTo(b.id);
      });
    winners[entry.key] = sorted.first;
    for (final loser in sorted.skip(1)) {
      result.dropped.add(MapEntry(loser, sorted.first));
    }
  }

  // Preserve the original source-file order for the surviving rows.
  final winnerIds = winners.values.map((q) => q.id).toSet();
  for (final q in all) {
    if (winnerIds.contains(q.id)) result.kept.add(q);
  }
  return result;
}

// ---------------------------------------------------------------------------------------------
// Per-option rationale synthesis  (panel note #5: explain WHY the answer is wrong)
// ---------------------------------------------------------------------------------------------

/// Guarantees the text reads as a finished sentence so the synthesized rationales never produce
/// run-ons or ".." artefacts.
String _asSentence(String s) {
  final t = s.trim();
  if (t.isEmpty) return '';
  return RegExp(r'[.!?]$').hasMatch(t) ? t : '$t.';
}

/// The correct option's rationale is the question's own explanation (contract: "correct option ->
/// rationale = the question's existing explanation string").
String buildCorrectRationale(ParsedQuestion q) {
  final expl = _asSentence(q.explanation);
  if (expl.isNotEmpty) return expl;
  return "'${q.correctOption}' is the correct answer for ${q.topic}.";
}

/// The distractor's rationale names the distractor, points back to the key, restates the
/// explanation, and tells the student which topic to re-read. Built deterministically -- it is
/// never left blank, because a blank here is exactly the bug panel note #5 called out.
String buildWrongRationale(ParsedQuestion q, String wrongOption) {
  final expl = _asSentence(q.explanation);
  final buf = StringBuffer("'$wrongOption' is incorrect.");
  if (q.correctOption.isNotEmpty) {
    buf.write(" The correct answer is '${q.correctOption}'.");
  }
  if (expl.isNotEmpty) buf.write(' $expl');
  buf.write(' Review: ${q.topic}.');
  return buf.toString();
}

// ---------------------------------------------------------------------------------------------
// Philippine legal citation extraction  ->  legal_basis
// ---------------------------------------------------------------------------------------------

class _CitationPattern {
  final RegExp re;
  final String Function(RegExpMatch) format;
  const _CitationPattern(this.re, this.format);
}

final List<_CitationPattern> _citationPatterns = [
  // Republic Act
  _CitationPattern(
    RegExp(r'\bRepublic\s+Act(?:\s+No\.?)?\s*(\d{3,5})', caseSensitive: false),
    (m) => 'RA ${m.group(1)}',
  ),
  _CitationPattern(
    RegExp(r'\bR\.?A\.?\s*(?:No\.?\s*)?(\d{3,5})\b'),
    (m) => 'RA ${m.group(1)}',
  ),
  // Presidential Decree
  _CitationPattern(
    RegExp(r'\bPresidential\s+Decree(?:\s+No\.?)?\s*(\d{1,4})', caseSensitive: false),
    (m) => 'PD ${m.group(1)}',
  ),
  _CitationPattern(
    RegExp(r'\bP\.?D\.?\s*(?:No\.?\s*)?(\d{1,4})\b'),
    (m) => 'PD ${m.group(1)}',
  ),
  // Batas Pambansa
  _CitationPattern(
    RegExp(r'\bBatas\s+Pambansa(?:\s+(?:Blg\.?|Bilang))?\s*(\d{1,4})', caseSensitive: false),
    (m) => 'BP ${m.group(1)}',
  ),
  _CitationPattern(
    RegExp(r'\bB\.?P\.?\s*(?:Blg\.?\s*)?(\d{1,4})\b'),
    (m) => 'BP ${m.group(1)}',
  ),
  // Executive Order
  _CitationPattern(
    RegExp(r'\bExecutive\s+Order(?:\s+No\.?)?\s*(\d{1,4})', caseSensitive: false),
    (m) => 'EO ${m.group(1)}',
  ),
  _CitationPattern(
    RegExp(r'\bE\.?O\.?\s*(?:No\.?\s*)?(\d{1,4})\b'),
    (m) => 'EO ${m.group(1)}',
  ),
  // Article / Art. (an optional letter suffix covers e.g. Art. 266-A)
  _CitationPattern(
    RegExp(r'\bArt(?:icles?|s?\.)\s*(\d{1,4}(?:\s*-\s*[A-Z])?)', caseSensitive: false),
    (m) => 'Art. ${m.group(1)!.replaceAll(RegExp(r'\s*-\s*'), '-')}',
  ),
  // Rules of Court
  _CitationPattern(
    RegExp(r'\bRule\s+(\d{1,3})\b', caseSensitive: false),
    (m) => 'Rule ${m.group(1)}',
  ),
  // Section
  _CitationPattern(
    RegExp(r'\bSec(?:tions?|s?\.)\s*(\d{1,3})\b', caseSensitive: false),
    (m) => 'Sec. ${m.group(1)}',
  ),
];

final RegExp _rpcMentionRe =
    RegExp(r'\bRevised\s+Penal\s+Code\b|\bRPC\b', caseSensitive: false);

/// Scans explanation first, then the stem, then the options, and returns up to three deduped
/// citations in order of first appearance. Bare "Art. N" is qualified as "RPC Art. N" only when
/// the surrounding text actually mentions the Revised Penal Code, so we never invent a source.
String? extractLegalBasis(ParsedQuestion q) {
  final haystack =
      '${q.explanation} ${q.questionText} ${q.options.join(' ')}';
  final mentionsRpc = _rpcMentionRe.hasMatch(haystack);

  final hits = <_Hit>[];
  for (final p in _citationPatterns) {
    for (final m in p.re.allMatches(haystack)) {
      var label = p.format(m);
      if (label.startsWith('Art. ') && mentionsRpc) label = 'RPC $label';
      hits.add(_Hit(m.start, label));
    }
  }
  if (hits.isEmpty) return null;

  hits.sort((a, b) => a.start.compareTo(b.start));
  final seen = <String>{};
  final ordered = <String>[];
  for (final h in hits) {
    if (seen.add(h.label)) ordered.add(h.label);
    if (ordered.length == 3) break;
  }
  return ordered.join('; ');
}

class _Hit {
  final int start;
  final String label;
  const _Hit(this.start, this.label);
}

/// What to re-read when this question is missed (Question.remediationHint in the model contract).
String buildRemediationHint(ParsedQuestion q, String? legalBasis) {
  final subjectName = kSubjectNames[q.subject] ?? q.subject;
  final buf = StringBuffer(
      'Re-read the "${q.topic}" section of your $subjectName reviewer before retrying this topic.');
  if (legalBasis != null && legalBasis.isNotEmpty) {
    buf.write(' Focus on $legalBasis.');
  }
  return buf.toString();
}

// ---------------------------------------------------------------------------------------------
// SQL emission
// ---------------------------------------------------------------------------------------------

/// Postgres string literal. standard_conforming_strings is ON in Supabase, so a backslash is an
/// ordinary character and ONLY the single quote needs doubling.
String sqlStr(String s) => "'${s.replaceAll("'", "''")}'";

String sqlStrOrNull(String? s) => (s == null || s.isEmpty) ? 'NULL' : sqlStr(s);

/// Builds the options JSONB payload. Each entry carries both `isCorrect` (camelCase, matching
/// AnswerOption.toJson()) and `is_correct` (snake_case) so the Dart model parses it whichever
/// convention Question.fromJson settles on for the Supabase row shape.
String buildOptionsJson(ParsedQuestion q) {
  final list = <Map<String, dynamic>>[];
  for (var i = 0; i < q.options.length; i++) {
    final text = q.options[i];
    final isCorrect = i == q.correctAnswerIndex;
    list.add({
      'text': text,
      'isCorrect': isCorrect,
      'is_correct': isCorrect,
      'rationale':
          isCorrect ? buildCorrectRationale(q) : buildWrongRationale(q, text),
    });
  }
  return jsonEncode(list);
}

const List<String> kColumns = [
  'id',
  'subject_id',
  'topic',
  'question_text',
  'options',
  'correct_answer_index',
  'difficulty',
  'explanation',
  'legal_basis',
  'remediation_hint',
  'source',
  'version',
  'is_active',
];

String buildInsert(ParsedQuestion q) {
  final legalBasis = extractLegalBasis(q);
  final remediation = buildRemediationHint(q, legalBasis);
  final optionsJson = buildOptionsJson(q);

  final values = <String>[
    sqlStr(q.id),
    sqlStr(q.subject),
    sqlStr(q.topic),
    sqlStr(q.questionText),
    '${sqlStr(optionsJson)}::jsonb',
    '${q.correctAnswerIndex}',
    sqlStr(q.difficulty),
    sqlStr(q.explanation),
    sqlStrOrNull(legalBasis),
    sqlStr(remediation),
    "'imported'",
    '1',
    'true',
  ];

  final updates = kColumns
      .where((c) => c != 'id')
      .map((c) => '  $c = EXCLUDED.$c')
      .join(',\n');

  final buf = StringBuffer();
  buf.writeln('-- ${q.id}  |  ${q.subject}  |  ${q.topic}  |  ${q.difficulty}');
  buf.writeln('INSERT INTO public.questions (');
  buf.writeln('  ${kColumns.join(', ')}');
  buf.writeln(') VALUES (');
  for (var i = 0; i < values.length; i++) {
    buf.writeln('  ${values[i]}${i == values.length - 1 ? '' : ','}');
  }
  buf.writeln(')');
  buf.writeln('ON CONFLICT (id) DO UPDATE SET');
  buf.writeln('$updates,');
  buf.writeln('  updated_at = now();');
  return buf.toString();
}

// ---------------------------------------------------------------------------------------------
// Header / breakdown
// ---------------------------------------------------------------------------------------------

String buildHeader({
  required List<ParsedQuestion> questions,
  required Map<String, int> perFileBlocks,
  required Map<String, int> perFileParsed,
  required int withLegalBasis,
  required Map<String, int> rawSubjectCounts,
  required DedupeResult dedupe,
}) {
  final bySubject = <String, int>{};
  final byDifficulty = <String, int>{};
  final bySubjectDifficulty = <String, Map<String, int>>{};
  final topics = <String, Set<String>>{};

  for (final q in questions) {
    bySubject[q.subject] = (bySubject[q.subject] ?? 0) + 1;
    byDifficulty[q.difficulty] = (byDifficulty[q.difficulty] ?? 0) + 1;
    bySubjectDifficulty.putIfAbsent(q.subject, () => {});
    bySubjectDifficulty[q.subject]![q.difficulty] =
        (bySubjectDifficulty[q.subject]![q.difficulty] ?? 0) + 1;
    topics.putIfAbsent(q.subject, () => <String>{}).add(q.topic);
  }

  final subjects = bySubject.keys.toList()..sort();
  final b = StringBuffer();

  b.writeln('-- =============================================================================');
  b.writeln('-- supabase_seed_questions.sql');
  b.writeln('--');
  b.writeln('-- GENERATED FILE -- DO NOT EDIT BY HAND.');
  b.writeln('-- Regenerate with:  dart run tools/export_questions_to_sql.dart');
  b.writeln('--');
  b.writeln('-- Migrates every hardcoded Question() constructor out of Dart and into');
  b.writeln('-- public.questions, satisfying pre-oral defense panel note #7');
  b.writeln('-- ("Do NOT put your questions in your code").');
  b.writeln('--');
  b.writeln('-- Every statement is INSERT ... ON CONFLICT (id) DO UPDATE, so this file is');
  b.writeln('-- idempotent and safe to re-run after regeneration.');
  b.writeln('-- =============================================================================');
  b.writeln('--');
  b.writeln('-- TOTAL QUESTIONS SEEDED: ${questions.length}');
  b.writeln('--');
  b.writeln('-- SOURCE FILES');
  var totalBlocks = 0;
  perFileBlocks.forEach((path, blocks) {
    final parsed = perFileParsed[path] ?? 0;
    totalBlocks += blocks;
    b.writeln('--   $path');
    b.writeln('--     Question() constructors found: $blocks');
    b.writeln('--     parsed successfully:           $parsed');
  });
  b.writeln('--');
  b.writeln('-- RECONCILIATION (every constructor is accounted for)');
  b.writeln('--   Question() constructors in Dart : $totalBlocks');
  b.writeln('--   - duplicate stems collapsed     : ${dedupe.dropped.length}');
  b.writeln('--   = INSERT statements in this file: ${questions.length}');
  b.writeln('--');
  b.writeln('-- DUPLICATE-STEM COLLAPSING');
  b.writeln('--   questions_database.dart repeats itself: ${dedupe.groupsCollapsed} question stems');
  b.writeln('--   appear more than once within the same subject (e.g. cdi_064 and cdi_123 are');
  b.writeln('--   both "What is trace evidence?" under crime_detection, with reworded options).');
  b.writeln('--   supabase_schema_v2.sql enforces');
  b.writeln('--     UNIQUE INDEX uq_questions_subject_stem ON questions(subject_id, md5(lower(question_text)))');
  b.writeln('--   so shipping every copy would raise unique_violation and roll back this entire');
  b.writeln('--   transaction. Duplicates also defeat QuestionSelectionService rule R1 ("never');
  b.writeln('--   serve a question the learner has already seen") -- the same stem under two ids');
  b.writeln('--   is exactly what panel note #3 forbids. The richest copy of each stem is kept');
  b.writeln('--   (most options, then longest explanation, then a legal citation, then lowest id);');
  b.writeln('--   the ${dedupe.dropped.length} surplus copies are listed at the foot of this file.');
  b.writeln('--');
  b.writeln('-- PER-SUBJECT BREAKDOWN');
  b.writeln('--   ${'subject_id'.padRight(26)}${'total'.padLeft(6)}'
      '${'easy'.padLeft(8)}${'medium'.padLeft(8)}${'hard'.padLeft(8)}   topics');
  for (final s in subjects) {
    final d = bySubjectDifficulty[s]!;
    b.writeln('--   ${s.padRight(26)}'
        '${bySubject[s].toString().padLeft(6)}'
        '${(d['easy'] ?? 0).toString().padLeft(8)}'
        '${(d['medium'] ?? 0).toString().padLeft(8)}'
        '${(d['hard'] ?? 0).toString().padLeft(8)}'
        '   ${topics[s]!.length}');
  }
  b.writeln('--   ${'-' * 56}');
  b.writeln('--   ${'ALL'.padRight(26)}'
      '${questions.length.toString().padLeft(6)}'
      '${(byDifficulty['easy'] ?? 0).toString().padLeft(8)}'
      '${(byDifficulty['medium'] ?? 0).toString().padLeft(8)}'
      '${(byDifficulty['hard'] ?? 0).toString().padLeft(8)}');
  b.writeln('--');
  b.writeln('-- SEGMENT COVERAGE  (the existing flow serves $kSegmentsPerDifficulty segments of');
  b.writeln('-- $kQuestionsPerSegment questions per difficulty, so each subject x difficulty bucket needs');
  b.writeln('-- $kQuestionsNeededPerBucket distinct items). Collapsing the duplicate stems above exposed a real');
  b.writeln('-- content gap that was previously masked by repeated questions -- the shortfall is');
  b.writeln('-- what QuestionGenerationService (Automatic Item Generation, panel note #1) has to');
  b.writeln('-- fill. Buckets marked SHORT cannot currently fill all $kSegmentsPerDifficulty segments.');
  b.writeln('--   ${'subject_id'.padRight(26)}${'easy'.padLeft(8)}${'medium'.padLeft(8)}'
      '${'hard'.padLeft(8)}    needs generating');
  var totalDeficit = 0;
  for (final s in subjects) {
    final d = bySubjectDifficulty[s]!;
    final cells = <String>[];
    final gaps = <String>[];
    for (final diff in const ['easy', 'medium', 'hard']) {
      final n = d[diff] ?? 0;
      final deficit = kQuestionsNeededPerBucket - n;
      cells.add(n.toString().padLeft(8));
      if (deficit > 0) {
        gaps.add('$diff +$deficit');
        totalDeficit += deficit;
      }
    }
    b.writeln('--   ${s.padRight(26)}${cells.join()}'
        '    ${gaps.isEmpty ? 'ok' : 'SHORT: ${gaps.join(', ')}'}');
  }
  b.writeln('--   ${'-' * 56}');
  b.writeln('--   items to auto-generate before every segment is fillable: $totalDeficit');
  b.writeln('--');
  b.writeln('-- PER-DIFFICULTY BREAKDOWN');
  for (final d in const ['easy', 'medium', 'hard']) {
    final n = byDifficulty[d] ?? 0;
    final pct = questions.isEmpty ? 0 : (n * 100 / questions.length).round();
    b.writeln('--   ${d.padRight(10)}${n.toString().padLeft(6)}  ($pct%)');
  }
  b.writeln('--');
  b.writeln('-- SUBJECT SLUG NORMALISATION (question_bank.dart used non-canonical slugs;');
  b.writeln('-- they are folded into the six board-exam subjects in lib/models/subject.dart)');
  final aliasKeys = kSubjectAliases.keys.toList()..sort();
  for (final k in aliasKeys) {
    final n = rawSubjectCounts[k] ?? 0;
    if (n == 0) continue;
    b.writeln('--   ${k.padRight(20)} -> ${kSubjectAliases[k]}  ($n questions)');
  }
  b.writeln('--');
  b.writeln('-- ID NAMESPACING');
  b.writeln('--   questions_database.dart ids are kept verbatim (cj_001, lea_001, ...).');
  b.writeln('--   question_bank.dart ids are prefixed "$kQuestionBankIdPrefix" to avoid collisions.');
  b.writeln('--');
  b.writeln('-- DERIVED CONTENT');
  b.writeln('--   options            jsonb array of {text, isCorrect, is_correct, rationale}.');
  b.writeln('--                      Panel note #5 -- the WRONG options carry a rationale too,');
  b.writeln('--                      so the app can explain why the chosen answer is wrong.');
  b.writeln('--   legal_basis        regex-derived Philippine citation (Art./RA/PD/BP/EO/Rule/Sec).');
  b.writeln('--                      Populated for $withLegalBasis of ${questions.length} questions; NULL when none found.');
  b.writeln('--   remediation_hint   what to re-read when the question is missed (panel note #3).');
  b.writeln('--   source             \'imported\' for everything in this file.');
  b.writeln('-- =============================================================================');
  b.writeln();
  b.writeln('BEGIN;');
  b.writeln();
  b.writeln('-- -----------------------------------------------------------------------------');
  b.writeln('-- Safety net. The authoritative definition of public.questions lives in the');
  b.writeln('-- schema migration; every statement below is idempotent and is a no-op when the');
  b.writeln('-- table already exists with these columns. It only exists so this seed file can');
  b.writeln('-- be pasted into the Supabase SQL editor and work on its own.');
  b.writeln('-- -----------------------------------------------------------------------------');
  b.writeln('CREATE TABLE IF NOT EXISTS public.questions (');
  b.writeln('  id                   text PRIMARY KEY,');
  b.writeln('  subject_id           text NOT NULL,');
  b.writeln('  topic                text NOT NULL,');
  b.writeln('  question_text        text NOT NULL,');
  b.writeln('  options              jsonb NOT NULL DEFAULT \'[]\'::jsonb,');
  b.writeln('  correct_answer_index integer NOT NULL DEFAULT 0,');
  b.writeln('  difficulty           text NOT NULL DEFAULT \'medium\',');
  b.writeln('  explanation          text NOT NULL DEFAULT \'\',');
  b.writeln('  legal_basis          text,');
  b.writeln('  remediation_hint     text,');
  b.writeln('  source               text NOT NULL DEFAULT \'admin\',');
  b.writeln('  version              integer NOT NULL DEFAULT 1,');
  b.writeln('  template_id          text,');
  b.writeln('  is_active            boolean NOT NULL DEFAULT true,');
  b.writeln('  created_at           timestamptz NOT NULL DEFAULT now(),');
  b.writeln('  updated_at           timestamptz NOT NULL DEFAULT now()');
  b.writeln(');');
  b.writeln();
  for (final col in const [
    'subject_id text',
    'topic text',
    'question_text text',
    "options jsonb DEFAULT '[]'::jsonb",
    'correct_answer_index integer DEFAULT 0',
    "difficulty text DEFAULT 'medium'",
    "explanation text DEFAULT ''",
    'legal_basis text',
    'remediation_hint text',
    "source text DEFAULT 'admin'",
    'version integer DEFAULT 1',
    'template_id text',
    'is_active boolean DEFAULT true',
    'created_at timestamptz DEFAULT now()',
    'updated_at timestamptz DEFAULT now()',
  ]) {
    b.writeln('ALTER TABLE public.questions ADD COLUMN IF NOT EXISTS $col;');
  }
  b.writeln();
  b.writeln('CREATE INDEX IF NOT EXISTS questions_subject_idx  ON public.questions (subject_id);');
  b.writeln('CREATE INDEX IF NOT EXISTS questions_topic_idx    ON public.questions (subject_id, topic);');
  b.writeln('CREATE INDEX IF NOT EXISTS questions_active_idx   ON public.questions (is_active);');
  b.writeln('CREATE INDEX IF NOT EXISTS questions_difficulty_idx ON public.questions (subject_id, difficulty);');
  b.writeln();
  b.writeln('-- -----------------------------------------------------------------------------');
  b.writeln('-- Seed data (${questions.length} questions)');
  b.writeln('-- -----------------------------------------------------------------------------');
  b.writeln();
  return b.toString();
}

// ---------------------------------------------------------------------------------------------
// Self-verification of the emitted file
// ---------------------------------------------------------------------------------------------

class Verification {
  int insertCount = 0;
  int jsonValues = 0;
  int jsonValid = 0;
  int rationaleTotal = 0;
  int rationaleBlank = 0;
  final List<String> errors = [];
}

/// Re-reads the emitted SQL as text and proves three things the task requires:
///   1. one INSERT per Question() constructor,
///   2. every quoted literal is well formed (odd/unescaped quotes are impossible),
///   3. every options payload is valid JSON with a non-empty rationale on every option.
Verification verifyOutput(String path, int expectedInserts) {
  final v = Verification();
  final lines = File(path).readAsStringSync().split('\n');

  // A well-formed Postgres literal: opening quote, a body in which every quote is doubled,
  // closing quote. If any apostrophe had escaped un-doubled, this regex would fail to match.
  final literalLine = RegExp(r"^  '((?:[^']|'')*)'(::jsonb)?,?$");
  final numericLine = RegExp(r'^  (?:\d+|true|false|NULL),?$');

  var inValues = false;
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i].replaceAll('\r', '');
    if (line.startsWith('INSERT INTO public.questions (')) {
      v.insertCount++;
      continue;
    }
    if (line == ') VALUES (') {
      inValues = true;
      continue;
    }
    if (inValues && line == ')') {
      inValues = false;
      continue;
    }
    if (!inValues) continue;

    final m = literalLine.firstMatch(line);
    if (m == null) {
      if (!numericLine.hasMatch(line)) {
        v.errors.add('line ${i + 1}: malformed SQL value -> $line');
      }
      continue;
    }
    // Un-double the quotes to recover the real value.
    final raw = m.group(1)!.replaceAll("''", "'");
    if (m.group(2) == '::jsonb') {
      v.jsonValues++;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! List || decoded.isEmpty) {
          v.errors.add('line ${i + 1}: options JSON is not a non-empty array');
        } else {
          var correctCount = 0;
          for (final o in decoded) {
            final map = o as Map<String, dynamic>;
            v.rationaleTotal++;
            if ((map['rationale'] as String?)?.trim().isEmpty ?? true) {
              v.rationaleBlank++;
              v.errors.add('line ${i + 1}: an option has a blank rationale');
            }
            if (map['isCorrect'] == true) correctCount++;
            if (map['isCorrect'] != map['is_correct']) {
              v.errors.add('line ${i + 1}: isCorrect / is_correct disagree');
            }
          }
          if (correctCount != 1) {
            v.errors.add('line ${i + 1}: expected exactly 1 correct option, found $correctCount');
          }
          v.jsonValid++;
        }
      } catch (e) {
        v.errors.add('line ${i + 1}: invalid JSON -> $e');
      }
    }
  }

  if (v.insertCount != expectedInserts) {
    v.errors.add(
        'INSERT count ${v.insertCount} does not match the $expectedInserts Question() constructors found in the source files');
  }
  if (v.jsonValues != expectedInserts) {
    v.errors.add('found ${v.jsonValues} options payloads, expected $expectedInserts');
  }
  return v;
}

// ---------------------------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------------------------

void main(List<String> args) {
  // Resolve paths relative to the project root regardless of where dart was invoked from.
  var root = Directory.current;
  if (!File('${root.path}/pubspec.yaml').existsSync() &&
      File('${root.parent.path}/pubspec.yaml').existsSync()) {
    root = root.parent;
  }
  String p(String rel) => '${root.path}/$rel'.replaceAll(r'\', '/');

  stdout.writeln('CrimiReview :: question export  (Dart -> Supabase SQL)');
  stdout.writeln('project root : ${root.path}');
  stdout.writeln('');

  final reports = <String, ParseReport>{
    kQuestionsDatabasePath: parseFile(p(kQuestionsDatabasePath)),
    kQuestionBankPath: parseFile(p(kQuestionBankPath), idPrefix: kQuestionBankIdPrefix),
  };

  final perFileBlocks = <String, int>{};
  final perFileParsed = <String, int>{};
  final all = <ParsedQuestion>[];
  final warnings = <String>[];

  reports.forEach((path, r) {
    perFileBlocks[path] = r.blockCount;
    perFileParsed[path] = r.questions.length;
    all.addAll(r.questions);
    warnings.addAll(r.warnings);
    stdout.writeln('parsed $path : ${r.blockCount} Question() constructors '
        '-> ${r.questions.length} exported');
  });

  final expectedInserts = perFileBlocks.values.fold<int>(0, (a, b) => a + b);

  // Duplicate id guard. Two rows with the same id inside one transaction would make Postgres
  // reject the second ON CONFLICT DO UPDATE ("cannot affect row a second time").
  final seenIds = <String, ParsedQuestion>{};
  final duplicates = <String>[];
  for (final q in all) {
    if (seenIds.containsKey(q.id)) {
      duplicates.add('${q.id} (${seenIds[q.id]!.originFile} and ${q.originFile})');
    } else {
      seenIds[q.id] = q;
    }
  }
  if (duplicates.isNotEmpty) {
    stderr.writeln('FATAL: duplicate question ids detected:');
    for (final d in duplicates) {
      stderr.writeln('  $d');
    }
    exitCode = 1;
    return;
  }

  // Collapse stems that repeat inside a subject -- see dedupeByStem() for why this is required.
  final dedupe = dedupeByStem(all);
  final seeded = dedupe.kept;
  stdout.writeln('deduplicated: ${all.length} parsed -> ${seeded.length} seeded '
      '(${dedupe.dropped.length} duplicate stems collapsed across '
      '${dedupe.groupsCollapsed} groups)');

  final rawSubjectCounts = <String, int>{};
  var withLegalBasis = 0;
  for (final q in seeded) {
    rawSubjectCounts[q.rawSubject] = (rawSubjectCounts[q.rawSubject] ?? 0) + 1;
    if (extractLegalBasis(q) != null) withLegalBasis++;
  }

  final buf = StringBuffer();
  buf.write(buildHeader(
    questions: seeded,
    perFileBlocks: perFileBlocks,
    perFileParsed: perFileParsed,
    withLegalBasis: withLegalBasis,
    rawSubjectCounts: rawSubjectCounts,
    dedupe: dedupe,
  ));
  for (final q in seeded) {
    buf.write(buildInsert(q));
    buf.writeln();
  }
  buf.writeln('COMMIT;');
  buf.writeln();
  buf.writeln('-- Sanity check after running this file:');
  buf.writeln('--   SELECT subject_id, difficulty, count(*) FROM public.questions');
  buf.writeln('--   WHERE is_active GROUP BY 1,2 ORDER BY 1,2;');
  buf.writeln('--   -- expected total: ${seeded.length}');
  buf.writeln();

  // Full manifest so no constructor disappears silently.
  buf.writeln('-- =============================================================================');
  buf.writeln('-- COLLAPSED DUPLICATE STEMS (${dedupe.dropped.length})');
  buf.writeln('--');
  buf.writeln('-- Each line is a Question() constructor from the Dart sources that was NOT');
  buf.writeln('-- seeded because an identical question stem already exists in the same subject.');
  buf.writeln('-- Format:  dropped_id  ->  kept_id   |  subject  |  stem');
  buf.writeln('-- =============================================================================');
  final droppedSorted = List<MapEntry<ParsedQuestion, ParsedQuestion>>.from(dedupe.dropped)
    ..sort((a, b) => a.key.id.compareTo(b.key.id));
  for (final e in droppedSorted) {
    final stem = e.key.questionText.replaceAll('\n', ' ');
    buf.writeln('--   ${e.key.id.padRight(20)} -> ${e.value.id.padRight(20)}'
        ' | ${e.key.subject} | $stem');
  }

  final outPath = p(kOutputPath);
  File(outPath).writeAsStringSync(buf.toString());

  // ---- verify -------------------------------------------------------------------------------
  final v = verifyOutput(outPath, seeded.length);

  stdout.writeln('');
  stdout.writeln('wrote $outPath');
  stdout.writeln('  ${(File(outPath).lengthSync() / 1024).toStringAsFixed(1)} KB');
  stdout.writeln('');
  // Prove the seed cannot trip uq_questions_subject_stem.
  final stemKeys = <String>{};
  var stemCollisions = 0;
  for (final q in seeded) {
    if (!stemKeys.add(_stemKey(q))) stemCollisions++;
  }
  if (stemCollisions > 0) {
    v.errors.add('$stemCollisions rows still collide on (subject_id, lower(question_text))');
  }
  if (expectedInserts != seeded.length + dedupe.dropped.length) {
    v.errors.add('reconciliation failed: $expectedInserts constructors != '
        '${seeded.length} seeded + ${dedupe.dropped.length} collapsed');
  }

  stdout.writeln('VERIFICATION');
  stdout.writeln('  Question() constructors in source : $expectedInserts');
  stdout.writeln('  duplicate stems collapsed         : ${dedupe.dropped.length}');
  stdout.writeln('  INSERT statements emitted         : ${v.insertCount}'
      '   (${seeded.length} + ${dedupe.dropped.length} = $expectedInserts, reconciled)');
  stdout.writeln('  options JSONB payloads            : ${v.jsonValues}');
  stdout.writeln('  options JSONB that parse as JSON  : ${v.jsonValid}');
  stdout.writeln('  option rationales written         : ${v.rationaleTotal}');
  stdout.writeln('  option rationales left blank      : ${v.rationaleBlank}');
  stdout.writeln('  legal_basis populated             : $withLegalBasis / ${seeded.length}');
  stdout.writeln('  malformed SQL string literals     : '
      '${v.errors.where((e) => e.contains('malformed')).length}');
  stdout.writeln('  (subject_id, lower(stem)) clashes : $stemCollisions'
      '   [uq_questions_subject_stem safe]');

  // ---- breakdown ----------------------------------------------------------------------------
  final bySubject = <String, Map<String, int>>{};
  for (final q in seeded) {
    bySubject.putIfAbsent(q.subject, () => {'easy': 0, 'medium': 0, 'hard': 0, 'total': 0});
    bySubject[q.subject]![q.difficulty] = (bySubject[q.subject]![q.difficulty] ?? 0) + 1;
    bySubject[q.subject]!['total'] = bySubject[q.subject]!['total']! + 1;
  }
  stdout.writeln('');
  stdout.writeln('PER-SUBJECT BREAKDOWN');
  stdout.writeln('  ${'subject_id'.padRight(26)}${'total'.padLeft(6)}'
      '${'easy'.padLeft(8)}${'medium'.padLeft(8)}${'hard'.padLeft(8)}');
  final subjects = bySubject.keys.toList()..sort();
  for (final s in subjects) {
    final d = bySubject[s]!;
    stdout.writeln('  ${s.padRight(26)}${d['total'].toString().padLeft(6)}'
        '${d['easy'].toString().padLeft(8)}${d['medium'].toString().padLeft(8)}'
        '${d['hard'].toString().padLeft(8)}');
  }
  stdout.writeln('  ${'TOTAL'.padRight(26)}${seeded.length.toString().padLeft(6)}');

  if (warnings.isNotEmpty) {
    stdout.writeln('');
    stdout.writeln('WARNINGS (${warnings.length})');
    for (final w in warnings.take(40)) {
      stdout.writeln('  $w');
    }
  }

  if (v.errors.isNotEmpty) {
    stdout.writeln('');
    stdout.writeln('ERRORS (${v.errors.length})');
    for (final e in v.errors.take(40)) {
      stdout.writeln('  $e');
    }
    exitCode = 1;
    return;
  }

  stdout.writeln('');
  stdout.writeln('OK -- export complete and verified.');
}
