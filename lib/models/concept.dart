/// One row of `public.concept_bank`: a term with its meaning, the raw
/// material for Automatic Item Generation. Each concept can become up to four
/// questions (see `supabase_concept_bank.sql`).
class Concept {
  final String id;
  final String subjectId;
  final String topic;
  final String term;
  final String definition;
  final String? legalBasis;
  final String siblingGroup;
  final bool isActive;

  const Concept({
    required this.id,
    required this.subjectId,
    required this.topic,
    required this.term,
    required this.definition,
    required this.siblingGroup,
    this.legalBasis,
    this.isActive = true,
  });

  factory Concept.fromJson(Map<String, dynamic> json) {
    final basis = (json['legal_basis'] ?? '').toString().trim();
    return Concept(
      id: (json['id'] ?? '').toString(),
      subjectId: (json['subject_id'] ?? '').toString(),
      topic: (json['topic'] ?? '').toString(),
      term: (json['term'] ?? '').toString(),
      definition: (json['definition'] ?? '').toString(),
      legalBasis: basis.isEmpty ? null : basis,
      siblingGroup: (json['sibling_group'] ?? '').toString(),
      isActive: json['is_active'] != false,
    );
  }
}
