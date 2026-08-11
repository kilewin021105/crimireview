import '../models/question.dart';
import 'question_repository.dart';

/// DEPRECATED -- use [QuestionRepository] instead.
///
/// This class used to talk to Supabase itself and, whenever that failed, fell
/// back to `QuestionsDatabase` -- 6045 lines of questions compiled into the
/// app. Panel note 7 ("Do NOT put your questions in your code. It should have
/// an ADMIN to add questions, or you automate everything") rules that out, so
/// the fetching/caching/offline logic now lives in exactly one place,
/// [QuestionRepository], and the hardcoded fallback is gone.
///
/// What survives here is only the old method surface, so nothing that already
/// imports this file breaks. Every call is forwarded verbatim:
///
/// ```dart
/// // old
/// final qs = await QuestionService.instance.getQuestionsBySubject('criminology');
/// // new
/// final qs = await QuestionRepository.instance.bySubject('criminology');
/// ```
///
/// New code must call [QuestionRepository] directly -- it exposes topic,
/// difficulty and id lookups, offline state ([QuestionRepository.hasCachedQuestions]),
/// and change notifications that this facade cannot.
@Deprecated(
  'Use QuestionRepository.instance instead. QuestionService is a thin '
  'delegating facade kept only for source compatibility and will be removed.',
)
class QuestionService {
  QuestionService._();

  static QuestionService? _instance;
  static QuestionService get instance => _instance ??= QuestionService._();

  QuestionRepository get _repo => QuestionRepository.instance;

  /// Every active question. Delegates to [QuestionRepository.all].
  ///
  /// Returns `[]` when the device is offline and no snapshot has ever been
  /// downloaded. It never returns compiled-in content, because there is none.
  Future<List<Question>> getAllQuestions({bool forceRefresh = false}) {
    return _repo.all(forceRefresh: forceRefresh);
  }

  /// Questions for one subject, optionally narrowed to a difficulty tier.
  /// Delegates to [QuestionRepository.bySubject] / [QuestionRepository.byDifficulty].
  Future<List<Question>> getQuestionsBySubject(
    String subject, {
    Difficulty? difficulty,
  }) {
    if (difficulty == null) return _repo.bySubject(subject);
    return _repo.byDifficulty(subject, difficulty);
  }

  /// A random mix for the daily challenge.
  ///
  /// Note: this is a plain shuffle with no exposure tracking. The adaptive
  /// path (panel note 3, "repeat the topic but NOT the same question") goes
  /// through `QuestionSelectionService` instead.
  Future<List<Question>> getDailyChallengeQuestions({int count = 10}) async {
    final all = await _repo.all();
    all.shuffle();
    return all.take(count).toList();
  }

  /// Every active question at one difficulty tier, across all subjects.
  Future<List<Question>> getQuestionsByDifficulty(Difficulty difficulty) async {
    final all = await _repo.all();
    return all.where((q) => q.difficulty == difficulty).toList();
  }

  /// Subject ids that currently have content.
  Future<List<String>> getAvailableSubjects() => _repo.subjects();

  /// `{subjectId: activeQuestionCount}`.
  Future<Map<String, int>> getQuestionCountBySubject() =>
      _repo.countBySubject();

  /// Marks the bank stale and triggers a background refresh. The current
  /// content keeps serving until the new content lands.
  void clearCache() => _repo.invalidate();
}
