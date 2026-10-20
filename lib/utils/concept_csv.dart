/// Reads a CSV file of concepts for many topics at once, so Faculty can keep
/// their concept bank in Excel or Google Sheets and upload it in one step.
///
/// One row per concept, with a header row naming the columns:
///
///     subject, topic, term, definition, legal_basis (optional), group (optional)
///
/// Topics are taken from the file. A topic that does not exist yet is created
/// by the database on import, together with its four question forms
/// (`admin_import_concepts` in `supabase_concept_bank.sql`). The checks here
/// mirror the database's checks so the preview can say, before anything is
/// sent, which lines will be saved and which will be skipped, and why. The
/// database stays the authority and checks everything again.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../models/concept.dart';
import '../models/subject.dart';
import 'concept_import_parser.dart';
import 'concept_rules.dart';

/// Concepts accepted in one file. The database takes 200 per request, so a
/// bigger file is sent in several requests.
const int kConceptCsvMaxRows = 1000;

/// Files larger than this are refused before reading (a 1000-row concept
/// file is far smaller).
const int kConceptCsvMaxBytes = 2 * 1024 * 1024;

/// Same limit as the database (`resolve_concept_target`).
const int kConceptMaxTopicLength = 120;

/// The columns, in the order the template uses.
const List<String> kConceptCsvColumns = [
  'subject',
  'topic',
  'term',
  'definition',
  'legal_basis',
  'group',
];

/// File name for the template Faculty can download.
const String kConceptCsvTemplateName = 'crimireview_concepts_template.csv';

/// The template: the header row and three example rows. The examples are
/// seeded concepts (RPC Art. 11), so a template uploaded unchanged only
/// reports them as already in the bank.
String conceptCsvTemplate() {
  final rows = <List<String>>[
    kConceptCsvColumns,
    [
      'Criminal Law and Jurisprudence',
      'Justifying Circumstances',
      'Self-Defense',
      "Acting in defense of one's own person or rights, provided there is unlawful aggression, "
          'reasonable necessity of the means employed to prevent or repel it, and lack of sufficient '
          'provocation on the part of the person defending himself.',
      'RPC Art. 11(1)',
      '',
    ],
    [
      'Criminal Law and Jurisprudence',
      'Justifying Circumstances',
      'Defense of a Stranger',
      'Acting in defense of the person or rights of a person who is not a relative, provided there '
          'is unlawful aggression and reasonable necessity of the means employed, and the person '
          'defending is not induced by revenge, resentment, or other evil motive.',
      'RPC Art. 11(3)',
      '',
    ],
    [
      'Criminal Law and Jurisprudence',
      'Justifying Circumstances',
      'Obedience to a Lawful Order of a Superior',
      'Acting in obedience to an order issued by a superior for some lawful purpose, provided the '
          'order is lawful both in itself and in the means used to carry it out.',
      'RPC Art. 11(6)',
      '',
    ],
  ];
  return '${rows.map((r) => r.map(_csvCell).join(',')).join('\r\n')}\r\n';
}

/// The template as file bytes, with the UTF-8 mark Excel needs to show
/// letters such as ñ correctly.
Uint8List conceptCsvTemplateBytes() =>
    Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(conceptCsvTemplate())]);

String _csvCell(String value) {
  if (value.contains(RegExp(r'[",\r\n]'))) {
    return '"${value.replaceAll('"', '""')}"';
  }
  return value;
}

// ---------------------------------------------------------------------------
// Reading the bytes
// ---------------------------------------------------------------------------

/// Turns the file's bytes into text.
///
/// Handles what real files contain: UTF-8 with or without the mark Excel adds,
/// UTF-16 (Excel's "Unicode Text"), and the older Windows character set that
/// Excel's plain "CSV (Comma delimited)" uses, where ñ and curly quotes are
/// single bytes that are not valid UTF-8.
String decodeConceptCsv(Uint8List bytes) {
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    return _decodeUtf16(bytes.sublist(2), littleEndian: true);
  }
  if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
    return _decodeUtf16(bytes.sublist(2), littleEndian: false);
  }
  var body = bytes;
  if (body.length >= 3 && body[0] == 0xEF && body[1] == 0xBB && body[2] == 0xBF) {
    body = body.sublist(3);
  }
  try {
    return utf8.decode(body);
  } on FormatException {
    return _decodeWindows1252(body);
  }
}

String _decodeUtf16(Uint8List bytes, {required bool littleEndian}) {
  final units = <int>[];
  for (var i = 0; i + 1 < bytes.length; i += 2) {
    units.add(littleEndian ? bytes[i] | (bytes[i + 1] << 8) : (bytes[i] << 8) | bytes[i + 1]);
  }
  return String.fromCharCodes(units);
}

/// Windows-1252: the same as Latin-1 except 0x80 to 0x9F.
const Map<int, int> _cp1252High = {
  0x80: 0x20AC, 0x82: 0x201A, 0x83: 0x0192, 0x84: 0x201E, 0x85: 0x2026,
  0x86: 0x2020, 0x87: 0x2021, 0x88: 0x02C6, 0x89: 0x2030, 0x8A: 0x0160,
  0x8B: 0x2039, 0x8C: 0x0152, 0x8E: 0x017D, 0x91: 0x2018, 0x92: 0x2019,
  0x93: 0x201C, 0x94: 0x201D, 0x95: 0x2022, 0x96: 0x2013, 0x97: 0x2014,
  0x98: 0x02DC, 0x99: 0x2122, 0x9A: 0x0161, 0x9B: 0x203A, 0x9C: 0x0153,
  0x9E: 0x017E, 0x9F: 0x0178,
};

String _decodeWindows1252(Uint8List bytes) =>
    String.fromCharCodes(bytes.map((b) => _cp1252High[b] ?? b));

// ---------------------------------------------------------------------------
// Splitting into rows and cells
// ---------------------------------------------------------------------------

/// One row of the file and the line it starts on (counting from 1).
class CsvRecord {
  final int line;
  final List<String> cells;
  const CsvRecord(this.line, this.cells);
}

/// The rows of a CSV file and any quote that was opened but never closed.
class CsvTable {
  final List<CsvRecord> records;

  /// The line where an unclosed quote starts, or null.
  final int? unclosedQuoteLine;

  /// The separator used: `,`, `;` or a Tab.
  final String delimiter;

  const CsvTable(this.records, this.unclosedQuoteLine, this.delimiter);
}

/// Splits [text] into rows and cells (RFC 4180, as Excel and Google Sheets
/// write it): a cell in double quotes may contain the separator, line breaks
/// and doubled quotes (`""` stands for one `"`).
///
/// The separator is taken from the first non-empty line: a comma, a semicolon
/// (Excel in some regions) or a Tab, whichever appears most outside quotes.
CsvTable parseCsvTable(String text) {
  final delimiter = _detectDelimiter(text);
  final records = <CsvRecord>[];
  var cells = <String>[];
  final cell = StringBuffer();
  var inQuotes = false;
  var line = 1;
  var recordLine = 1;
  int? quoteStartLine;

  void endCell() {
    cells.add(cell.toString());
    cell.clear();
  }

  void endRecord() {
    endCell();
    records.add(CsvRecord(recordLine, cells));
    cells = <String>[];
  }

  var i = 0;
  while (i < text.length) {
    final ch = text[i];
    if (inQuotes) {
      if (ch == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          cell.write('"');
          i += 2;
          continue;
        }
        inQuotes = false;
        i++;
        continue;
      }
      if (ch == '\r' || ch == '\n') {
        cell.write('\n');
        if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
        line++;
        i++;
        continue;
      }
      cell.write(ch);
      i++;
      continue;
    }

    if (ch == '"' && cell.toString().trim().isEmpty) {
      // A quote that opens the cell (spaces before it are dropped).
      cell.clear();
      inQuotes = true;
      quoteStartLine = line;
      i++;
      continue;
    }
    if (ch == delimiter) {
      endCell();
      i++;
      continue;
    }
    if (ch == '\r' || ch == '\n') {
      if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      endRecord();
      line++;
      recordLine = line;
      i++;
      continue;
    }
    cell.write(ch);
    i++;
  }

  if (cell.isNotEmpty || cells.isNotEmpty || inQuotes) endRecord();
  return CsvTable(records, inQuotes ? quoteStartLine : null, delimiter);
}

String _detectDelimiter(String text) {
  var comma = 0, semicolon = 0, tab = 0;
  var inQuotes = false;
  var sawContent = false;
  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (ch == '"') {
      inQuotes = !inQuotes;
      continue;
    }
    if (inQuotes) continue;
    if (ch == '\r' || ch == '\n') {
      if (sawContent) break;
      continue;
    }
    if (ch.trim().isNotEmpty) sawContent = true;
    if (ch == ',') comma++;
    if (ch == ';') semicolon++;
    if (ch == '\t') tab++;
  }
  if (tab > comma && tab >= semicolon) return '\t';
  if (semicolon > comma) return ';';
  return ',';
}

// ---------------------------------------------------------------------------
// Columns and subjects
// ---------------------------------------------------------------------------

String _normName(String value) => value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

const Map<String, String> _columnAliases = {
  'subject': 'subject',
  'subjects': 'subject',
  'subjectname': 'subject',
  'subjectid': 'subject',
  'topic': 'topic',
  'topics': 'topic',
  'topicname': 'topic',
  'term': 'term',
  'terms': 'term',
  'concept': 'term',
  'keyterm': 'term',
  'definition': 'definition',
  'definitions': 'definition',
  'meaning': 'definition',
  'legalbasis': 'legal_basis',
  'basis': 'legal_basis',
  'law': 'legal_basis',
  'legalreference': 'legal_basis',
  'group': 'group',
  'siblinggroup': 'group',
  'groupname': 'group',
};

const List<String> _requiredColumns = ['subject', 'topic', 'term', 'definition'];

/// Other ways Faculty write a subject: the 2018 names, the usual reviewer
/// abbreviations, and the internal ids. Only names that point to exactly one
/// subject are listed.
const Map<String, String> _subjectAliases = {
  'criminaljurisprudenceandprocedure': 'criminal_jurisprudence',
  'criminallawjurisprudenceandprocedure': 'criminal_jurisprudence',
  'criminallawandjurisprudence': 'criminal_jurisprudence',
  'criminaljurisprudence': 'criminal_jurisprudence',
  'criminallaw': 'criminal_jurisprudence',
  'clj': 'criminal_jurisprudence',
  'lawenforcementadministration': 'law_enforcement',
  'lawenforcement': 'law_enforcement',
  'lea': 'law_enforcement',
  'forensicscience': 'criminalistics',
  'criminalistics': 'criminalistics',
  'crimedetectionandinvestigation': 'crime_detection',
  'crimedetection': 'crime_detection',
  'cdi': 'crime_detection',
  'criminalsociology': 'criminology',
  'criminology': 'criminology',
  'correctionaladministration': 'corrections',
  'corrections': 'corrections',
};

/// The subject id for [raw] (its name, short name, id, or a known other
/// name, ignoring letter case, spaces and punctuation), or null.
String? resolveConceptSubject(String raw) {
  final key = _normName(raw);
  if (key.isEmpty) return null;
  for (final s in CriminologySubjects.all) {
    if (_normName(s.id) == key || _normName(s.name) == key || _normName(s.shortName) == key) {
      return s.id;
    }
  }
  return _subjectAliases[key];
}

/// The group name the database accepts: lower case letters, digits and
/// underscores. "PNP vs BJMP" becomes "pnp_vs_bjmp".
String normalizeConceptGroup(String raw) => raw
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
    .replaceAll(RegExp(r'^_+|_+$'), '');

final RegExp _validGroup = RegExp(r'^[a-z0-9_]{3,80}$');

/// The group the database gives a brand-new topic when no group is named
/// (same steps as `resolve_concept_target`).
String defaultConceptGroup(String subjectId, String topic) {
  var slug = '${subjectId}_$topic'.replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_').toLowerCase();
  slug = slug.replaceAll(RegExp(r'^_+|_+$'), '');
  return slug.length > 80 ? slug.substring(0, 80) : slug;
}

String _collapseSpaces(String value) => value.replaceAll(RegExp(r'\s+'), ' ').trim();

// ---------------------------------------------------------------------------
// The plan: what will be imported, and what will be skipped
// ---------------------------------------------------------------------------

/// Concepts to send in one database request: one subject, one topic, one
/// group (or none, so the database picks it).
class ConceptCsvBatch {
  final String subjectId;
  final String topic;

  /// Sent as the group; null lets the database choose (the topic's only
  /// group, or a new one for a new topic).
  final String? group;

  /// The concepts, each with its line in the file.
  final List<ConceptDraft> rows;

  const ConceptCsvBatch({
    required this.subjectId,
    required this.topic,
    required this.group,
    required this.rows,
  });
}

/// One topic as it will look after the import, for the preview.
class ConceptCsvTopic {
  final String subjectId;
  final String topic;
  final bool isNew;
  final int newConcepts;

  /// The topic's readiness counting its existing active concepts and the new
  /// ones together.
  final TopicReadiness after;

  const ConceptCsvTopic({
    required this.subjectId,
    required this.topic,
    required this.isNew,
    required this.newConcepts,
    required this.after,
  });
}

class ConceptCsvPlan {
  final List<ConceptCsvBatch> batches;
  final List<ConceptCsvTopic> topics;

  /// Lines that will be skipped, with the reason.
  final List<ImportProblem> problems;

  /// A problem with the whole file (for example a missing column). Nothing
  /// can be imported while this is set.
  final String? fileError;

  /// Header names that are not one of the known columns (ignored).
  final List<String> ignoredColumns;

  const ConceptCsvPlan({
    this.batches = const [],
    this.topics = const [],
    this.problems = const [],
    this.fileError,
    this.ignoredColumns = const [],
  });

  int get conceptCount => batches.fold(0, (sum, b) => sum + b.rows.length);
  int get newTopicCount => topics.where((t) => t.isNew).length;
  bool get tooMany => conceptCount > kConceptCsvMaxRows;
  bool get canImport => fileError == null && conceptCount > 0 && !tooMany;
}

/// Reads [text] (the decoded file) and works out what an import would do,
/// given the concepts already in the bank ([existing], active and inactive).
ConceptCsvPlan planConceptCsv(String text, {required List<Concept> existing}) {
  final table = parseCsvTable(text);
  final records = table.records
      .where((r) => r.cells.any((c) => c.trim().isNotEmpty))
      .toList();

  if (records.isEmpty) {
    return const ConceptCsvPlan(fileError: 'The file is empty.');
  }

  // ---- Header ------------------------------------------------------------
  final header = records.first;
  final columnIndex = <String, int>{};
  final ignored = <String>[];
  for (var i = 0; i < header.cells.length; i++) {
    final name = header.cells[i].trim();
    if (name.isEmpty) continue;
    final column = _columnAliases[_normName(name)];
    if (column == null) {
      ignored.add(name);
      continue;
    }
    if (columnIndex.containsKey(column)) {
      return ConceptCsvPlan(fileError: 'The column "$name" appears twice in the first row.');
    }
    columnIndex[column] = i;
  }
  if (columnIndex.isEmpty) {
    return const ConceptCsvPlan(
      fileError: 'The first row must name the columns: subject, topic, term, definition, '
          'legal_basis, group. Get the template to see the format.',
    );
  }
  final missing = _requiredColumns.where((c) => !columnIndex.containsKey(c)).toList();
  if (missing.isNotEmpty) {
    return ConceptCsvPlan(
      fileError: 'The file needs these columns: ${_requiredColumns.join(', ')}. '
          'Missing: ${missing.join(', ')}.',
      ignoredColumns: ignored,
    );
  }

  String cellOf(CsvRecord r, String column) {
    final index = columnIndex[column];
    if (index == null || index >= r.cells.length) return '';
    return r.cells[index].trim();
  }

  // ---- What the bank already has ------------------------------------------
  String topicKey(String subjectId, String topic) => '$subjectId::${topic.toLowerCase()}';

  final existingTopicName = <String, String>{};
  final existingGroups = <String, Set<String>>{};
  final existingTerms = <String>{};
  final existingDefinitions = <String>{};
  for (final c in existing) {
    final key = topicKey(c.subjectId, c.topic.trim());
    existingTopicName.putIfAbsent(key, () => c.topic);
    existingGroups.putIfAbsent(key, () => <String>{}).add(c.siblingGroup);
    existingTerms.add('$key::${c.term.trim().toLowerCase()}');
    existingDefinitions.add('${c.siblingGroup}::${c.definition.trim().toLowerCase()}');
  }

  // ---- Rows ---------------------------------------------------------------
  final problems = <ImportProblem>[];
  if (table.unclosedQuoteLine != null) {
    problems.add(ImportProblem(table.unclosedQuoteLine!,
        'A quote mark (") opened on this line is never closed, so the rest of the file was read as one cell.'));
  }

  final fileTopicName = <String, String>{};
  final termLines = <String, int>{};
  final definitionLines = <String, int>{};
  // Batch key -> rows; the blank-group batch of a topic is sent first (see below).
  final batchRows = <String, List<ConceptDraft>>{};
  final batchInfo = <String, (String subjectId, String topicKey, String? group)>{};
  final newConceptsByTopic = <String, List<Concept>>{};

  for (final r in records.skip(1)) {
    final line = r.line;
    final subjectRaw = cellOf(r, 'subject');
    final topicRaw = _collapseSpaces(cellOf(r, 'topic'));
    final term = cellOf(r, 'term');
    final definition = cellOf(r, 'definition');
    final basisRaw = cellOf(r, 'legal_basis');
    final groupRaw = cellOf(r, 'group');
    final basis = basisRaw.isEmpty ? null : basisRaw;

    if (subjectRaw.isEmpty) {
      problems.add(ImportProblem(line, 'The subject is empty.'));
      continue;
    }
    final subjectId = resolveConceptSubject(subjectRaw);
    if (subjectId == null) {
      problems.add(ImportProblem(line,
          '"$subjectRaw" is not one of the six subjects. Write it like "Criminal Law and Jurisprudence".'));
      continue;
    }
    if (topicRaw.isEmpty) {
      problems.add(ImportProblem(line, 'The topic is empty.'));
      continue;
    }
    if (topicRaw.length > kConceptMaxTopicLength) {
      problems.add(ImportProblem(
          line, 'The topic is too long ($kConceptMaxTopicLength characters at most).'));
      continue;
    }
    if (topicRaw.contains('{{') || topicRaw.contains('}}')) {
      problems.add(ImportProblem(line, 'Text cannot contain {{ or }}.'));
      continue;
    }

    final fieldError = conceptFieldError(term, definition, basis);
    if (fieldError != null) {
      problems.add(ImportProblem(line, fieldError));
      continue;
    }

    final tKey = topicKey(subjectId, topicRaw);
    final topicName = existingTopicName[tKey] ?? fileTopicName.putIfAbsent(tKey, () => topicRaw);

    // The group this concept will end up in.
    String? groupToSend;
    String effectiveGroup;
    if (groupRaw.isNotEmpty) {
      final normalized = normalizeConceptGroup(groupRaw);
      if (!_validGroup.hasMatch(normalized)) {
        problems.add(ImportProblem(line,
            'The group "$groupRaw" is too short or too long. Use 3 to 80 letters, numbers or underscores.'));
        continue;
      }
      groupToSend = normalized;
      effectiveGroup = normalized;
    } else {
      final groups = existingGroups[tKey];
      if (groups == null || groups.isEmpty) {
        effectiveGroup = defaultConceptGroup(subjectId, topicName);
      } else if (groups.length == 1) {
        effectiveGroup = groups.first;
      } else {
        problems.add(ImportProblem(line,
            '"$topicName" has more than one group. Fill in the group column (${(groups.toList()..sort()).join(', ')}).'));
        continue;
      }
    }

    final termKey = '$tKey::${term.toLowerCase()}';
    if (existingTerms.contains(termKey)) {
      problems.add(ImportProblem(line, '"$term" is already in "$topicName".'));
      continue;
    }
    final seenTerm = termLines[termKey];
    if (seenTerm != null) {
      problems.add(ImportProblem(line, '"$term" is already on line $seenTerm for the same topic.'));
      continue;
    }
    final definitionKey = '$effectiveGroup::${definition.toLowerCase()}';
    if (existingDefinitions.contains(definitionKey)) {
      problems.add(ImportProblem(line, 'Another concept in this group already has this definition.'));
      continue;
    }
    final seenDefinition = definitionLines[definitionKey];
    if (seenDefinition != null) {
      problems.add(ImportProblem(line, 'This definition is already used on line $seenDefinition.'));
      continue;
    }

    termLines[termKey] = line;
    definitionLines[definitionKey] = line;

    final batchKey = '$tKey::${groupToSend ?? ''}';
    batchInfo[batchKey] = (subjectId, tKey, groupToSend);
    batchRows.putIfAbsent(batchKey, () => []).add(
          ConceptDraft(line: line, term: term, definition: definition, legalBasis: basis),
        );
    newConceptsByTopic.putIfAbsent(tKey, () => []).add(Concept(
          id: 'new-$line',
          subjectId: subjectId,
          topic: topicName,
          term: term,
          definition: definition,
          legalBasis: basis,
          siblingGroup: effectiveGroup,
        ));
  }

  // ---- Batches, in the same order as the preview ------------------------
  // Subjects in their usual order, then topics by name. Within a topic, the
  // batch without a group goes first, so that for a new topic the database
  // gives it the default group the preview assumed.
  int subjectOrder(String id) => CriminologySubjects.all.indexWhere((s) => s.id == id);
  final keys = batchRows.keys.toList()
    ..sort((a, b) {
      final ia = batchInfo[a]!, ib = batchInfo[b]!;
      final bySubject = subjectOrder(ia.$1).compareTo(subjectOrder(ib.$1));
      if (bySubject != 0) return bySubject;
      final byTopic = ia.$2.compareTo(ib.$2);
      if (byTopic != 0) return byTopic;
      if (ia.$3 == null) return -1;
      if (ib.$3 == null) return 1;
      return ia.$3!.compareTo(ib.$3!);
    });
  final batches = [
    for (final key in keys)
      ConceptCsvBatch(
        subjectId: batchInfo[key]!.$1,
        topic: existingTopicName[batchInfo[key]!.$2] ?? fileTopicName[batchInfo[key]!.$2]!,
        group: batchInfo[key]!.$3,
        rows: batchRows[key]!,
      ),
  ];

  // ---- Topics as they will be after the import ----------------------------
  final topics = <ConceptCsvTopic>[];
  for (final entry in newConceptsByTopic.entries) {
    final tKey = entry.key;
    final added = entry.value;
    final first = added.first;
    final before = existing.where((c) => topicKey(c.subjectId, c.topic.trim()) == tKey);
    topics.add(ConceptCsvTopic(
      subjectId: first.subjectId,
      topic: first.topic,
      isNew: !existingTopicName.containsKey(tKey),
      newConcepts: added.length,
      after: topicReadiness([...before, ...added]),
    ));
  }
  topics.sort((a, b) {
    final bySubject = subjectOrder(a.subjectId).compareTo(subjectOrder(b.subjectId));
    return bySubject != 0 ? bySubject : a.topic.toLowerCase().compareTo(b.topic.toLowerCase());
  });

  problems.sort((a, b) => a.line.compareTo(b.line));
  return ConceptCsvPlan(
    batches: batches,
    topics: topics,
    problems: problems,
    ignoredColumns: ignored,
  );
}
