/// Reads concepts pasted from Excel, Word or a text file.
///
/// One concept per line, columns separated by a Tab (what Excel and Word give
/// you when you copy table cells) or by a `|` sign:
///
///     Term <Tab> Definition <Tab> Legal basis (optional)
///
/// The checks here mirror the database's own checks (`validate_concept_fields`
/// in `supabase_concept_bank.sql`), so most mistakes are caught on the phone
/// before anything is sent. The database stays the authority.
library;

/// Same limits as the database.
const int kConceptMaxTermLength = 200;
const int kConceptMinDefinitionLength = 10;
const int kConceptMaxDefinitionLength = 1500;
const int kConceptMaxBasisLength = 200;
const int kConceptMaxImportRows = 200;

/// One concept that passed the checks.
class ConceptDraft {
  /// The line of the pasted text it came from (counting from 1), so a message
  /// can point back to it.
  final int line;
  final String term;
  final String definition;
  final String? legalBasis;

  const ConceptDraft({
    required this.line,
    required this.term,
    required this.definition,
    this.legalBasis,
  });

  Map<String, dynamic> toJson() => {
        'term': term,
        'definition': definition,
        'legal_basis': legalBasis,
      };
}

/// A line that could not be used, with the reason in plain words.
class ImportProblem {
  final int line;
  final String message;
  const ImportProblem(this.line, this.message);

  @override
  String toString() => 'Line $line: $message';
}

class ConceptImportParse {
  final List<ConceptDraft> rows;
  final List<ImportProblem> problems;

  const ConceptImportParse(this.rows, this.problems);

  bool get tooMany => rows.length > kConceptMaxImportRows;
}

/// Returns the concepts found in [text] and the lines that could not be used.
ConceptImportParse parseConceptImport(String text) {
  final rows = <ConceptDraft>[];
  final problems = <ImportProblem>[];
  final lines = text.split(RegExp(r'\r\n|\r|\n'));

  final termLines = <String, int>{};
  final definitionLines = <String, int>{};
  var seenFirstLine = false;

  for (var i = 0; i < lines.length; i++) {
    final lineNo = i + 1;
    final raw = lines[i];
    if (raw.trim().isEmpty) continue;

    final isFirstLine = !seenFirstLine;
    seenFirstLine = true;

    final String separator;
    if (raw.contains('\t')) {
      separator = '\t';
    } else if (raw.contains('|')) {
      separator = '|';
    } else {
      problems.add(ImportProblem(lineNo,
          'Separate the columns with a Tab (copy the cells from Excel or Word) or with the | sign.'));
      continue;
    }

    var cells = raw.split(separator).map(_cleanCell).toList();
    while (cells.length > 3 && cells.last.isEmpty) {
      cells.removeLast();
    }

    // A header row such as "Term | Definition | Legal basis" is skipped.
    if (isFirstLine && cells.length >= 2 && _looksLikeHeader(cells)) continue;

    if (cells.length < 2) {
      problems.add(ImportProblem(lineNo, 'Needs a term and a definition.'));
      continue;
    }
    if (cells.length > 3) {
      problems.add(ImportProblem(lineNo,
          'Has more than 3 columns. Use: term, definition, legal basis (optional).'));
      continue;
    }

    final term = cells[0];
    final definition = cells[1];
    final basis = cells.length == 3 && cells[2].isNotEmpty ? cells[2] : null;

    final error = _fieldError(term, definition, basis);
    if (error != null) {
      problems.add(ImportProblem(lineNo, error));
      continue;
    }

    final termKey = term.toLowerCase();
    final seenTerm = termLines[termKey];
    if (seenTerm != null) {
      problems.add(ImportProblem(lineNo, '"$term" is already on line $seenTerm.'));
      continue;
    }
    final definitionKey = definition.toLowerCase();
    final seenDefinition = definitionLines[definitionKey];
    if (seenDefinition != null) {
      problems.add(ImportProblem(
          lineNo, 'This definition is already used on line $seenDefinition.'));
      continue;
    }

    termLines[termKey] = lineNo;
    definitionLines[definitionKey] = lineNo;
    rows.add(ConceptDraft(
        line: lineNo, term: term, definition: definition, legalBasis: basis));
  }

  return ConceptImportParse(rows, problems);
}

/// The same rules the database applies to one concept. Null when fine.
/// Used by the single-concept form as well.
String? conceptFieldError(String term, String definition, String? legalBasis) =>
    _fieldError(term.trim(), definition.trim(), legalBasis?.trim());

String? _fieldError(String term, String definition, String? basis) {
  if (term.isEmpty) return 'The term is required.';
  if (definition.isEmpty) return 'The definition is required.';
  if (term.length < 2) return 'The term is too short.';
  if (term.length > kConceptMaxTermLength) {
    return 'The term is too long ($kConceptMaxTermLength characters at most).';
  }
  if (definition.length < kConceptMinDefinitionLength) {
    return 'The definition is too short. Write the full meaning '
        '(at least $kConceptMinDefinitionLength characters).';
  }
  if (definition.length > kConceptMaxDefinitionLength) {
    return 'The definition is too long ($kConceptMaxDefinitionLength characters at most).';
  }
  if (basis != null && basis.length > kConceptMaxBasisLength) {
    return 'The legal basis is too long ($kConceptMaxBasisLength characters at most).';
  }
  final all = '$term$definition${basis ?? ''}';
  if (all.contains('{{') || all.contains('}}')) {
    return 'Text cannot contain {{ or }}.';
  }
  return null;
}

bool _looksLikeHeader(List<String> cells) {
  final first = cells[0].toLowerCase();
  final second = cells[1].toLowerCase();
  return (first == 'term' || first == 'terms' || first == 'concept') &&
      second.startsWith('definition');
}

/// Trims a cell and removes the quotes Excel puts around cells that contain
/// commas or quote marks.
String _cleanCell(String value) {
  var v = value.trim();
  if (v.length >= 2 && v.startsWith('"') && v.endsWith('"')) {
    v = v.substring(1, v.length - 1).replaceAll('""', '"').trim();
  }
  return v;
}
