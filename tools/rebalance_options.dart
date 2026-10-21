// tools/rebalance_options.dart
//
// Checks and packages the rewritten WRONG answer options for the imported
// question bank. Run with:
//
//   dart run tools/rebalance_options.dart
//
// WHY THIS EXISTS
// ---------------
// In the 759 imported questions the correct option was the longest one 84% of
// the time (Easy 78%, Medium 86%, Hard 91%; by chance it would be 25%), and many
// wrong options were obviously wrong ("No moral issues", "Simple decisions").
// A student could pass a segment without knowing the material. The wrong
// options are being rewritten, level by level, as real look-alikes of the same
// length (CHANGELOG Session 62).
//
// INPUT
//   content_review/snapshot_imported.jsonl   the questions exactly as they are
//                                            live (exported 2026-10-22; its
//                                            fingerprint matched the live table)
//   content_review/rewrites/<level>_NN.jsonl  one line per question, either
//       {"id": "...", "wrong": [["option text", "why it is wrong"], x3]}
//     (the new wrong options replace the old ones in the same positions), or
//       {"id": "...", "keep": "why the existing options are already fair"}
//     for a question reviewed and left as it is. Either form may add
//       "flag": "a note for Faculty", e.g. when the CORRECT answer itself may
//     be disputed. The correct option, the question and its explanation are
//     never changed by this tool.
//
// OUTPUT (only when every check passes)
//   content_review/rebalance_review.html          the review page: old vs new
//   supabase_rebalance_options_<level>.sql           applies one level's rewrites
//   supabase_rebalance_options_<level>_rollback.sql  puts that level back
//   (one pair per level, so each file stays small enough to paste into the
//   Supabase SQL Editor; the levels are independent and can run in any order)
//
// The apply file changes a question only if its options are still exactly the
// snapshot, so an edit Faculty made in the meantime is never overwritten.

import 'dart:convert';
import 'dart:io';

const _snapshotPath = 'content_review/snapshot_imported.jsonl';
const _rewritesDir = 'content_review/rewrites';
const _reviewPath = 'content_review/rebalance_review.html';
String _applyPath(String level) => 'supabase_rebalance_options_$level.sql';
String _rollbackPath(String level) => 'supabase_rebalance_options_${level}_rollback.sql';
const _levels = ['easy', 'medium', 'hard'];

/// The correct option "stands out" when it is the longest and at least this
/// many times longer than the longest wrong option. This is the giveaway being
/// removed; any rewritten question that still has it fails the check.
const double standOutRatio = 1.4;

/// A wrong option shorter than this share of the correct option is reported
/// (it can make the others look obviously right), but is not an error.
const double shortWarningRatio = 0.45;

const _banned = ['all of the above', 'none of the above', 'both a and b', 'all of these', 'none of these'];
const _sqlTag = r'$opt$';

class SnapshotQuestion {
  final Map<String, dynamic> raw;
  SnapshotQuestion(this.raw);

  String get id => raw['id'] as String;
  String get level => raw['difficulty'] as String;
  String get subject => raw['subject_id'] as String;
  String get topic => raw['topic'] as String;
  String get question => raw['question'] as String;
  String get explanation => (raw['explanation'] ?? '') as String;
  List<Map<String, dynamic>> get options =>
      (raw['options'] as List).map((o) => Map<String, dynamic>.from(o as Map)).toList();

  int get correctIndex => options.indexWhere((o) => o['is_correct'] == true);
  String get correctText => (options[correctIndex]['text'] as String).trim();
  List<int> get wrongIndexes => [
        for (var i = 0; i < options.length; i++)
          if (options[i]['is_correct'] != true) i,
      ];
}

class Rewrite {
  final String id;
  final List<(String, String)> wrong;
  final String file;
  final int line;
  Rewrite(this.id, this.wrong, this.file, this.line);
}

/// A question reviewed and left as it is.
class Kept {
  final String id;
  final String reason;
  final String file;
  final int line;
  Kept(this.id, this.reason, this.file, this.line);
}

/// Length signals for one set of options.
class Cue {
  final bool correctLongest;
  final bool correctShortest;
  final bool standsOut;
  Cue(this.correctLongest, this.correctShortest, this.standsOut);

  factory Cue.of(String correct, List<String> wrong) {
    final c = correct.trim().length;
    final lengths = wrong.map((w) => w.trim().length).toList();
    final maxW = lengths.reduce((a, b) => a > b ? a : b);
    final minW = lengths.reduce((a, b) => a < b ? a : b);
    return Cue(c > maxW, c < minW, c > maxW && c >= standOutRatio * maxW);
  }
}

void main() {
  final errors = <String>[];
  final warnings = <String>[];

  // ---- snapshot
  final snapshot = <String, SnapshotQuestion>{};
  for (final line in File(_snapshotPath).readAsLinesSync()) {
    if (line.trim().isEmpty) continue;
    final q = SnapshotQuestion(jsonDecode(line) as Map<String, dynamic>);
    snapshot[q.id] = q;
  }

  // ---- rewrites, kept questions and flags
  final rewrites = <String, Rewrite>{};
  final kept = <String, Kept>{};
  final flags = <String, String>{};
  final seenAt = <String, String>{};
  final dir = Directory(_rewritesDir);
  final files = dir.existsSync()
      ? (dir.listSync().whereType<File>().where((f) => f.path.endsWith('.jsonl')).toList()
        ..sort((a, b) => a.path.compareTo(b.path)))
      : <File>[];
  for (final f in files) {
    final name = f.uri.pathSegments.last;
    final lines = f.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final text = lines[i].trim();
      if (text.isEmpty) continue;
      final where = '$name:${i + 1}';
      Map<String, dynamic> obj;
      try {
        obj = jsonDecode(text) as Map<String, dynamic>;
      } catch (e) {
        errors.add('$where: not valid JSON ($e)');
        continue;
      }
      final id = obj['id'];
      final wrong = obj['wrong'];
      final keep = obj['keep'];
      final flag = obj['flag'];
      if (id is! String || (wrong is! List && keep is! String) || (wrong != null && keep != null)) {
        errors.add('$where: needs "id" and either a "wrong" list or a "keep" reason');
        continue;
      }
      if (seenAt.containsKey(id)) {
        errors.add('$where: $id appears twice (also ${seenAt[id]})');
        continue;
      }
      seenAt[id] = where;
      if (flag != null) {
        if (flag is! String || flag.trim().length < 15) {
          errors.add('$where: "flag" must be a sentence for Faculty');
        } else {
          flags[id] = flag.trim();
        }
      }
      if (keep is String) {
        if (keep.trim().length < 10) errors.add('$where: say briefly why the options are kept');
        kept[id] = Kept(id, keep.trim(), name, i + 1);
        continue;
      }
      wrong as List;
      final pairs = <(String, String)>[];
      for (final w in wrong) {
        if (w is List && w.length == 2 && w[0] is String && w[1] is String) {
          pairs.add(((w[0] as String).trim(), (w[1] as String).trim()));
        } else {
          errors.add('$where: each wrong option must be ["text", "why"]');
        }
      }
      rewrites[id] = Rewrite(id, pairs, name, i + 1);
    }
  }

  // ---- checks per kept question: it must not have the length giveaway
  for (final k in kept.values) {
    final where = '${k.file}:${k.line} (${k.id})';
    final q = snapshot[k.id];
    if (q == null) {
      errors.add('$where: no such question in the snapshot');
      continue;
    }
    if (!k.file.startsWith(q.level)) {
      errors.add('$where: question is ${q.level}, but it is in ${k.file}');
    }
    final cue = Cue.of(q.correctText, [for (final i in q.wrongIndexes) q.options[i]['text'] as String]);
    if (cue.standsOut) {
      errors.add('$where: kept, but its answer stands out by length; rewrite it instead');
    }
  }
  for (final id in flags.keys) {
    if (!snapshot.containsKey(id)) errors.add('flag for unknown question $id');
  }

  // ---- checks per question
  for (final r in rewrites.values) {
    final where = '${r.file}:${r.line} (${r.id})';
    final q = snapshot[r.id];
    if (q == null) {
      errors.add('$where: no such question in the snapshot');
      continue;
    }
    if (!r.file.startsWith(q.level)) {
      errors.add('$where: question is ${q.level}, but it is in ${r.file}');
    }
    if (q.correctIndex < 0) {
      errors.add('$where: the snapshot question has no correct option');
      continue;
    }
    if (r.wrong.length != q.wrongIndexes.length) {
      errors.add('$where: needs ${q.wrongIndexes.length} wrong options, has ${r.wrong.length}');
      continue;
    }
    final correct = q.correctText;
    final seen = <String>{correct.toLowerCase()};
    for (final (text, why) in r.wrong) {
      final lower = text.toLowerCase();
      if (text.isEmpty) errors.add('$where: an empty option');
      if (text.length > 200) errors.add('$where: option over 200 characters: "$text"');
      if (why.length < 15) errors.add('$where: reason too short for "$text"');
      if (why.length > 400) errors.add('$where: reason over 400 characters for "$text"');
      if (!seen.add(lower)) errors.add('$where: option repeats another option: "$text"');
      for (final b in _banned) {
        if (lower.contains(b)) errors.add('$where: "$b" is not allowed: "$text"');
      }
      for (final s in [text, why]) {
        if (s.contains('{{') || s.contains('}}')) errors.add('$where: "{{" or "}}" in "$s"');
        if (s.contains(_sqlTag)) errors.add('$where: "$_sqlTag" in "$s"');
      }
      if (text.length < shortWarningRatio * correct.length) {
        warnings.add('$where: "$text" is much shorter than the answer "$correct"');
      }
    }
    final cue = Cue.of(correct, r.wrong.map((w) => w.$1).toList());
    if (cue.standsOut) {
      errors.add('$where: the answer still stands out by length ("$correct")');
    }
  }

  // ---- metrics, before and after, per level
  final report = StringBuffer();
  String pct(int n, int d) => d == 0 ? '-' : '${(100 * n / d).toStringAsFixed(1)}%';
  for (final level in _levels) {
    final qs = snapshot.values.where((q) => q.level == level).toList();
    final done = qs.where((q) => rewrites.containsKey(q.id)).toList();
    final keptHere = qs.where((q) => kept.containsKey(q.id)).length;
    final reviewed = done.length + keptHere;
    if (reviewed == 0) {
      report.writeln('$level: ${qs.length} questions, none reviewed yet');
      continue;
    }
    // The whole level as it would be after applying: rewritten questions with
    // their new options, every other question as it is now.
    final whole = qs.map((q) => rewrites.containsKey(q.id)
        ? Cue.of(q.correctText, rewrites[q.id]!.wrong.map((w) => w.$1).toList())
        : Cue.of(q.correctText, [for (final i in q.wrongIndexes) q.options[i]['text'] as String])).toList();
    final wholeBefore = qs.map((q) => Cue.of(q.correctText, [for (final i in q.wrongIndexes) q.options[i]['text'] as String])).toList();
    report.writeln('$level: ${qs.length} questions -- $reviewed reviewed ($keptHere kept as they are, ${done.length} rewritten), '
        '${qs.length - reviewed} not reviewed yet');
    report.writeln('  WHOLE LEVEL answer is the longest: ${pct(wholeBefore.where((c) => c.correctLongest).length, qs.length)} -> '
        '${pct(whole.where((c) => c.correctLongest).length, qs.length)}; stands out: '
        '${pct(wholeBefore.where((c) => c.standsOut).length, qs.length)} -> ${pct(whole.where((c) => c.standsOut).length, qs.length)}');
    if (done.isEmpty) continue;
    final before = done.map((q) => Cue.of(q.correctText, [for (final i in q.wrongIndexes) q.options[i]['text'] as String])).toList();
    final after = done.map((q) => Cue.of(q.correctText, rewrites[q.id]!.wrong.map((w) => w.$1).toList())).toList();
    report.writeln('  rewritten questions only:');
    report.writeln('  answer is the longest option : ${pct(before.where((c) => c.correctLongest).length, done.length)} -> '
        '${pct(after.where((c) => c.correctLongest).length, done.length)} (chance 25%)');
    report.writeln('  answer is the shortest option: ${pct(before.where((c) => c.correctShortest).length, done.length)} -> '
        '${pct(after.where((c) => c.correctShortest).length, done.length)} (chance 25%)');
    report.writeln('  answer stands out (>= ${standOutRatio}x): ${pct(before.where((c) => c.standsOut).length, done.length)} -> '
        '${pct(after.where((c) => c.standsOut).length, done.length)}');
  }

  stdout.writeln(report);
  for (final w in warnings) {
    stdout.writeln('WARNING $w');
  }
  if (errors.isNotEmpty) {
    for (final e in errors) {
      stderr.writeln('ERROR $e');
    }
    stderr.writeln('${errors.length} error(s). Nothing was written.');
    exit(1);
  }

  // ---- outputs
  final ordered = rewrites.values.toList()
    ..sort((a, b) {
      final qa = snapshot[a.id]!, qb = snapshot[b.id]!;
      final l = _levels.indexOf(qb.level).compareTo(_levels.indexOf(qa.level));
      if (l != 0) return l;
      final s = qa.subject.compareTo(qb.subject);
      if (s != 0) return s;
      final t = qa.topic.compareTo(qb.topic);
      return t != 0 ? t : qa.id.compareTo(qb.id);
    });

  List<Map<String, dynamic>> newOptions(SnapshotQuestion q, Rewrite r) {
    final opts = q.options;
    final idx = q.wrongIndexes;
    for (var k = 0; k < idx.length; k++) {
      opts[idx[k]] = {'text': r.wrong[k].$1, 'is_correct': false, 'rationale': r.wrong[k].$2};
    }
    return opts;
  }

  String sqlFile(String level, List<Rewrite> rows, {required bool rollback}) {
    final b = StringBuffer();
    final name = level[0].toUpperCase() + level.substring(1);
    b.writeln('-- ================================================================');
    b.writeln(rollback
        ? '-- CrimiReview -- UNDO the rewritten wrong answer options ($name)'
        : '-- CrimiReview -- rewritten wrong answer options ($name, imported questions)');
    b.writeln('-- ================================================================');
    b.writeln('-- GENERATED by: dart run tools/rebalance_options.dart  (do not edit by hand)');
    b.writeln('-- Questions in this file: ${rows.length} ($level level only; each level has its own file)');
    b.writeln('--');
    if (rollback) {
      b.writeln('-- Puts back the options a question had before the rewrite, but only if');
      b.writeln('-- its options are still exactly the rewritten ones.');
    } else {
      b.writeln('-- Replaces ONLY the wrong options (text and reason). The question, the');
      b.writeln('-- correct option and the explanation stay as they are.');
      b.writeln('-- A question is changed only if its options are still exactly as they');
      b.writeln('-- were when the rewrite was made, so a Faculty edit is never overwritten.');
      b.writeln('-- Its version goes up by 1, so phones download the new options.');
      b.writeln('-- Safe to run more than once. To undo: ${_rollbackPath(level)}');
    }
    b.writeln('--');
    b.writeln('-- HOW TO RUN: Supabase Dashboard > SQL Editor > New query > paste > Run.');
    b.writeln('-- The result shows how many questions were changed and how many were skipped.');
    b.writeln('-- ================================================================');
    b.writeln();
    b.writeln('CREATE TEMP TABLE IF NOT EXISTS rebalance_input (');
    b.writeln('  id          TEXT PRIMARY KEY,');
    b.writeln('  old_options JSONB NOT NULL,');
    b.writeln('  new_options JSONB NOT NULL');
    b.writeln(');');
    b.writeln('TRUNCATE rebalance_input;');
    b.writeln();
    b.writeln('INSERT INTO rebalance_input (id, old_options, new_options) VALUES');
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      final q = snapshot[r.id]!;
      final before = jsonEncode(q.options);
      final after = jsonEncode(newOptions(q, r));
      final from = rollback ? after : before;
      final to = rollback ? before : after;
      b.writeln("  ('${r.id.replaceAll("'", "''")}', $_sqlTag$from$_sqlTag::jsonb, $_sqlTag$to$_sqlTag::jsonb)"
          '${i == rows.length - 1 ? ';' : ','}');
    }
    b.writeln();
    b.writeln('WITH changed AS (');
    b.writeln('  UPDATE public.questions q');
    b.writeln('  SET options = r.new_options,');
    b.writeln('      version = COALESCE(q.version, 1) + 1');
    b.writeln('  FROM rebalance_input r');
    b.writeln('  WHERE q.id = r.id');
    b.writeln('    AND q.options = r.old_options');
    b.writeln('  RETURNING q.id');
    b.writeln(')');
    b.writeln('SELECT');
    b.writeln('  (SELECT count(*) FROM changed) AS changed_now,');
    // The subqueries below see the table as it was before this statement's
    // UPDATE (one statement, one snapshot), so "already done" counts rows that
    // had the new options before this run.
    b.writeln('  (SELECT count(*) FROM rebalance_input r JOIN public.questions q ON q.id = r.id');
    b.writeln('     WHERE q.options = r.new_options) AS already_done_before,');
    b.writeln('  (SELECT count(*) FROM rebalance_input r LEFT JOIN public.questions q ON q.id = r.id');
    b.writeln('     WHERE q.id IS NULL OR (q.options <> r.new_options AND q.options <> r.old_options))');
    b.writeln('     AS skipped_edited_or_missing;');
    return b.toString();
  }

  final written = <String>[];
  for (final level in _levels.reversed) {
    final rows = ordered.where((r) => snapshot[r.id]!.level == level).toList();
    if (rows.isEmpty) continue;
    File(_applyPath(level)).writeAsStringSync(sqlFile(level, rows, rollback: false));
    File(_rollbackPath(level)).writeAsStringSync(sqlFile(level, rows, rollback: true));
    written.add('${_applyPath(level)} (${rows.length})');
  }
  File(_reviewPath).writeAsStringSync(_reviewHtml(ordered, snapshot, report.toString(), kept, flags));
  stdout.writeln('Wrote ${written.join(', ')}, each with a _rollback file, and $_reviewPath '
      '(${ordered.length} questions).');
}

String _esc(String s) => const HtmlEscape().convert(s);

String _reviewHtml(List<Rewrite> ordered, Map<String, SnapshotQuestion> snapshot, String report,
    Map<String, Kept> kept, Map<String, String> flags) {
  const subjectNames = {
    'criminal_jurisprudence': 'Criminal Law and Jurisprudence',
    'law_enforcement': 'Law Enforcement Administration',
    'crime_detection': 'Crime Detection and Investigation',
    'criminalistics': 'Forensic Science',
    'criminology': 'Criminology',
    'corrections': 'Correctional Administration',
  };
  final b = StringBuffer();
  b.writeln('<!doctype html><html lang="en"><head><meta charset="utf-8">'
      '<meta name="viewport" content="width=device-width, initial-scale=1">'
      '<title>Answer options review</title><style>'
      ':root{--bg:#fafafa;--card:#fff;--ink:#161213;--muted:#5f5759;--line:#e6e0e1;--good:#1b7f47;--goodbg:#e3f4ea;--old:#8a8486;--new:#2457c5}'
      '@media (prefers-color-scheme:dark){:root{--bg:#0e0c0c;--card:#181515;--ink:#f4f0f0;--muted:#aba2a3;--line:#2e2929;--good:#48c985;--goodbg:#10291c;--old:#8f8789;--new:#7fa6ff}}'
      'body{background:var(--bg);color:var(--ink);font:15px/1.5 system-ui,Segoe UI,Roboto,sans-serif;margin:0;padding:16px}'
      '.wrap{max-width:900px;margin:0 auto}h1{font-size:22px;margin:8px 0}h2{font-size:18px;margin:28px 0 8px}'
      'pre{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:12px;white-space:pre-wrap}'
      '.q{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:12px 14px;margin:10px 0}'
      '.meta{color:var(--muted);font-size:12px}.stem{font-weight:600;margin:4px 0 8px}'
      '.ok{background:var(--goodbg);color:var(--good);border-radius:8px;padding:4px 8px;display:inline-block;margin-bottom:6px}'
      'table{width:100%;border-collapse:collapse;font-size:14px}td{border-top:1px solid var(--line);padding:6px 4px;vertical-align:top}'
      '.oldt{color:var(--old);text-decoration:line-through}.newt{color:var(--new);font-weight:600}.why{color:var(--muted);font-size:13px}'
      '.flag{background:#fcefd9;color:#7a4a00;border-radius:8px;padding:6px 10px;margin-top:8px;font-size:13px}'
      '@media (prefers-color-scheme:dark){.flag{background:#33240f;color:#e9a84a}}'
      '</style></head><body><div class="wrap">');
  b.writeln('<h1>Answer options review</h1>');
  b.writeln('<p>Only the wrong options change. The question, the correct answer and the explanation stay the same. '
      'Check that every new wrong option is really wrong for the question, and that its reason is accurate.</p>');
  b.writeln('<pre>${_esc(report)}</pre>');
  if (flags.isNotEmpty) {
    b.writeln('<h2>Flags for Faculty (${flags.length})</h2><p>The correct answer of these questions may be disputed. '
        'This review did not change any correct answer; please check these.</p>');
    for (final e in flags.entries) {
      final q = snapshot[e.key]!;
      b.writeln('<div class="q"><div class="meta">${_esc(q.id)} · ${_esc(q.level)} · ${_esc(q.topic)}</div>'
          '<div class="stem">${_esc(q.question)}</div><div class="ok">✓ ${_esc(q.correctText)}</div>'
          '<div class="flag">${_esc(e.value)}</div></div>');
    }
  }
  String? lastHeader;
  for (final r in ordered) {
    final q = snapshot[r.id]!;
    final header = '${q.level[0].toUpperCase()}${q.level.substring(1)} · ${subjectNames[q.subject] ?? q.subject}';
    if (header != lastHeader) {
      b.writeln('<h2>${_esc(header)}</h2>');
      lastHeader = header;
    }
    final oldWrong = [for (final i in q.wrongIndexes) q.options[i]['text'] as String];
    b.writeln('<div class="q"><div class="meta">${_esc(q.id)} · ${_esc(q.topic)}</div>'
        '<div class="stem">${_esc(q.question)}</div>'
        '<div class="ok">✓ ${_esc(q.correctText)}</div><table>');
    for (var k = 0; k < r.wrong.length; k++) {
      b.writeln('<tr><td class="oldt">${_esc(k < oldWrong.length ? oldWrong[k] : '')}</td>'
          '<td><span class="newt">${_esc(r.wrong[k].$1)}</span><br><span class="why">${_esc(r.wrong[k].$2)}</span></td></tr>');
    }
    b.writeln('</table>${flags.containsKey(r.id) ? '<div class="flag">${_esc(flags[r.id]!)}</div>' : ''}</div>');
  }
  if (kept.isNotEmpty) {
    b.writeln('<h2>Kept as they are (${kept.length})</h2><p>Reviewed: the options are already of similar length and plausible.</p>');
    final keptList = kept.values.toList()..sort((a, b) => a.id.compareTo(b.id));
    for (final k in keptList) {
      final q = snapshot[k.id]!;
      final wrong = [for (final i in q.wrongIndexes) q.options[i]['text'] as String];
      b.writeln('<div class="q"><div class="meta">${_esc(q.id)} · ${_esc(q.level)} · ${_esc(q.topic)}</div>'
          '<div class="stem">${_esc(q.question)}</div><div class="ok">✓ ${_esc(q.correctText)}</div>'
          '<div class="why">${wrong.map(_esc).join(' · ')}</div><div class="why">Kept: ${_esc(k.reason)}</div>'
          '${flags.containsKey(k.id) ? '<div class="flag">${_esc(flags[k.id]!)}</div>' : ''}</div>');
    }
  }
  b.writeln('</div></body></html>');
  return b.toString();
}
