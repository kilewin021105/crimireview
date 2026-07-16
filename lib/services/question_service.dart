import '../models/question.dart';
import '../data/questions_database.dart';
import 'supabase_service.dart';

class QuestionService {
  static QuestionService? _instance;
  static QuestionService get instance => _instance ??= QuestionService._();

  QuestionService._();

  List<Question>? _cachedQuestions;
  DateTime? _cacheTime;
  static const _cacheDuration = Duration(hours: 1);

  /// Fetch all questions from Supabase with local fallback
  Future<List<Question>> getAllQuestions({bool forceRefresh = false}) async {
    // Check cache first
    if (!forceRefresh && _cachedQuestions != null && _cacheTime != null) {
      if (DateTime.now().difference(_cacheTime!) < _cacheDuration) {
        return _cachedQuestions!;
      }
    }

    // If Supabase not initialized, use local
    if (!SupabaseService.isInitialized) {
      //return _getLocalQuestions();
    }

    try {
      final response = await SupabaseService.instance.client
          .from('questions')
          .select()
          .eq('is_active', true)
          .timeout(const Duration(seconds: 10));

      if (response.isEmpty) {
        // No questions in database, use local
        // return _getLocalQuestions();
      }

      _cachedQuestions =
          (response as List).map((json) => _fromJson(json)).toList();
      _cacheTime = DateTime.now();
      return _cachedQuestions!;
    } catch (e) {
      // Fallback to local questions
      print('QuestionService: Using local questions (error: $e)');
      return _getLocalQuestions();
    }
  }

  /// Fetch questions by subject
  Future<List<Question>> getQuestionsBySubject(String subject,
      {Difficulty? difficulty}) async {
    final all = await getAllQuestions();
    return all.where((q) {
      final matchSubject = q.subject == subject;
      final matchDifficulty = difficulty == null || q.difficulty == difficulty;
      return matchSubject && matchDifficulty;
    }).toList();
  }

  /// Fetch questions for daily challenge (random mix)
  Future<List<Question>> getDailyChallengeQuestions({int count = 10}) async {
    final all = await getAllQuestions();
    final shuffled = List<Question>.from(all)..shuffle();
    return shuffled.take(count).toList();
  }

  /// Get questions by difficulty
  Future<List<Question>> getQuestionsByDifficulty(Difficulty difficulty) async {
    final all = await getAllQuestions();
    return all.where((q) => q.difficulty == difficulty).toList();
  }

  /// Get available subjects
  Future<List<String>> getAvailableSubjects() async {
    final all = await getAllQuestions();
    return all.map((q) => q.subject).toSet().toList();
  }

  /// Get question count by subject
  Future<Map<String, int>> getQuestionCountBySubject() async {
    final all = await getAllQuestions();
    final counts = <String, int>{};
    for (final q in all) {
      counts[q.subject] = (counts[q.subject] ?? 0) + 1;
    }
    return counts;
  }

  /// Clear cache to force refresh
  void clearCache() {
    _cachedQuestions = null;
    _cacheTime = null;
  }

  /// Convert JSON to Question
  Question _fromJson(Map<String, dynamic> json) {
    final optionsList = (json['options'] as List).cast<String>();
    final diffStr = json['difficulty'] as String;

    return Question(
      id: json['id'] as String,
      subject: json['subject'] as String,
      topic: json['topic'] as String,
      questionText: json['question_text'] as String,
      options: optionsList,
      correctAnswerIndex: json['correct_answer_index'] as int,
      difficulty: _parseDifficulty(diffStr),
      explanation: (json['explanation'] as String?) ?? '',
    );
  }

  Difficulty _parseDifficulty(String s) {
    switch (s.toLowerCase()) {
      case 'easy':
        return Difficulty.easy;
      case 'medium':
        return Difficulty.medium;
      case 'hard':
        return Difficulty.hard;
      default:
        return Difficulty.medium;
    }
  }

  /// Get local questions as fallback
  List<Question> _getLocalQuestions() {
    return QuestionsDatabase.getAllQuestions();
  }
}
