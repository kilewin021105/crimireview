import 'package:flutter_test/flutter_test.dart';

import 'package:crimireview/models/concept.dart';
import 'package:crimireview/utils/concept_rules.dart';

Concept c(String term, String? basis, {String group = 'g', bool active = true, String topic = 'T', String subject = 's'}) =>
    Concept(
      id: 'id_$term',
      subjectId: subject,
      topic: topic,
      term: term,
      definition: 'Definition of $term that is long enough.',
      legalBasis: basis,
      siblingGroup: group,
      isActive: active,
    );

void main() {
  group('groupBasesDistinct (mirrors group_bases_distinct in the database)', () {
    test('true when every basis is different and none contains another', () {
      expect(
        groupBasesDistinct([
          c('Self-Defense', 'RPC Art. 11(1)'),
          c('Relative', 'RPC Art. 11(2)'),
          c('Stranger', 'RPC Art. 11(3)'),
        ]),
        isTrue,
      );
    });

    test('false when two concepts share the same basis (PNP and NAPOLCOM)', () {
      expect(
        groupBasesDistinct([
          c('PNP', 'RA 6975, as amended by RA 8551'),
          c('NAPOLCOM', 'RA 6975, as amended by RA 8551'),
          c('BJMP', 'RA 6975, Sec. 60'),
        ]),
        isFalse,
      );
    });

    test('false when one basis is contained in another', () {
      expect(groupBasesDistinct([c('A', 'RA 6975'), c('B', 'RA 6975, Sec. 60')]), isFalse);
      expect(groupBasesDistinct([c('A', 'RPC Art. 11(1)'), c('B', 'rpc art. 11(1)(a)')]), isFalse);
    });

    test('ignores letter case and spaces around the basis', () {
      expect(groupBasesDistinct([c('A', ' RPC Art. 11(1) '), c('B', 'rpc art. 11(1)')]), isFalse);
    });

    test('false when any active concept has no legal basis', () {
      expect(groupBasesDistinct([c('A', 'RPC Art. 11(1)'), c('B', null), c('C', '   ')]), isFalse);
    });

    test('inactive concepts are ignored', () {
      expect(
        groupBasesDistinct([
          c('A', 'RPC Art. 11(1)'),
          c('B', 'RPC Art. 11(2)'),
          c('Gone', null, active: false),
          c('Also gone', 'RPC Art. 11(1)', active: false),
        ]),
        isTrue,
      );
    });
  });

  group('topicReadiness', () {
    test('needs 3 active concepts in one group before questions can be made', () {
      expect(topicReadiness([c('A', null), c('B', null)]).canMakeQuestions, isFalse);
      expect(topicReadiness([c('A', null), c('B', null), c('C', null)]).canMakeQuestions, isTrue);
    });

    test('inactive concepts do not count', () {
      final r = topicReadiness([c('A', null), c('B', null), c('C', null, active: false)]);
      expect(r.active, 2);
      expect(r.canMakeQuestions, isFalse);
    });

    test('concepts spread over groups of 2 cannot make questions', () {
      final r = topicReadiness([
        c('A', null, group: 'x'),
        c('B', null, group: 'x'),
        c('C', null, group: 'y'),
        c('D', null, group: 'y'),
      ]);
      expect(r.canMakeQuestions, isFalse);
    });

    test('legal-basis forms need every usable group to pass', () {
      final good = topicReadiness([c('A', 'Art. 1'), c('B', 'Art. 2'), c('C', 'Art. 3')]);
      expect(good.canMakeQuestions, isTrue);
      expect(good.basisFormsReady, isTrue);

      final missing = topicReadiness([c('A', 'Art. 1'), c('B', 'Art. 2'), c('C', null)]);
      expect(missing.canMakeQuestions, isTrue);
      expect(missing.basisFormsReady, isFalse);
    });
  });

  group('conceptGroupsFor', () {
    test('lists the groups of a topic, ignoring letter case', () {
      final all = [
        c('A', null, group: 'b_group', topic: 'Justifying Circumstances', subject: 'cj'),
        c('B', null, group: 'a_group', topic: 'justifying circumstances', subject: 'cj'),
        c('C', null, group: 'other', topic: 'Other', subject: 'cj'),
        c('D', null, group: 'elsewhere', topic: 'Justifying Circumstances', subject: 'le'),
      ];
      expect(conceptGroupsFor(all, 'cj', 'Justifying circumstances'), ['a_group', 'b_group']);
      expect(conceptGroupsFor(all, 'cj', 'New topic'), isEmpty);
    });
  });
}
