import '../models/concept.dart';

/// A group needs this many active concepts before it can make a question:
/// one right answer and at least two wrong ones, so three options.
const int kMinConceptsPerGroup = 3;

/// True when every concept in [group] has a legal basis and no basis is equal
/// to, or contained in, another one (ignoring letter case).
///
/// This is the rule the database applies before it makes a "legal basis"
/// question (`group_bases_distinct` in `supabase_concept_bank.sql`). It is
/// needed because two answers could otherwise both be right: "RA 6975,
/// Sec. 60" is inside "RA 6975". The app uses it only to explain to Faculty
/// why those forms are unavailable; the database makes the real decision.
///
/// Only active concepts count, as in the database.
bool groupBasesDistinct(Iterable<Concept> group) {
  final bases = <String>[];
  for (final c in group) {
    if (!c.isActive) continue;
    final b = (c.legalBasis ?? '').trim().toLowerCase();
    if (b.isEmpty) return false;
    bases.add(b);
  }
  for (var i = 0; i < bases.length; i++) {
    for (var j = 0; j < bases.length; j++) {
      if (i != j && bases[j].contains(bases[i])) return false;
    }
  }
  return true;
}

/// What Faculty need to know about one topic.
class TopicReadiness {
  /// Active concepts in the topic.
  final int active;

  /// True when at least one group has [kMinConceptsPerGroup] or more active
  /// concepts, so term and definition questions can be made.
  final bool canMakeQuestions;

  /// True when every group that can make questions also passes
  /// [groupBasesDistinct], so the two legal-basis forms are available.
  final bool basisFormsReady;

  const TopicReadiness({
    required this.active,
    required this.canMakeQuestions,
    required this.basisFormsReady,
  });
}

/// Works out [TopicReadiness] from all the concepts of one topic.
TopicReadiness topicReadiness(Iterable<Concept> topicConcepts) {
  final byGroup = <String, List<Concept>>{};
  var active = 0;
  for (final c in topicConcepts) {
    if (!c.isActive) continue;
    active++;
    byGroup.putIfAbsent(c.siblingGroup, () => []).add(c);
  }
  final usable = byGroup.values.where((g) => g.length >= kMinConceptsPerGroup).toList();
  return TopicReadiness(
    active: active,
    canMakeQuestions: usable.isNotEmpty,
    basisFormsReady: usable.isNotEmpty && usable.every(groupBasesDistinct),
  );
}

/// The distinct sibling groups already used by [topic] in [subjectId]
/// (topic compared ignoring letter case), sorted.
List<String> conceptGroupsFor(Iterable<Concept> all, String subjectId, String topic) {
  final wanted = topic.trim().toLowerCase();
  final groups = <String>{
    for (final c in all)
      if (c.subjectId == subjectId && c.topic.trim().toLowerCase() == wanted) c.siblingGroup,
  };
  return groups.toList()..sort();
}
