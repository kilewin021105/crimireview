enum Difficulty { easy, medium, hard }

class Question {
  final String id;
  final String subject;
  final String topic;
  final String questionText;
  final List<String> options;
  final int correctAnswerIndex;
  final String explanation;
  final Difficulty difficulty;

  const Question({
    required this.id,
    required this.subject,
    required this.topic,
    required this.questionText,
    required this.options,
    required this.correctAnswerIndex,
    required this.explanation,
    required this.difficulty,
  });

  String get correctAnswer => options[correctAnswerIndex];

  Map<String, dynamic> toJson() => {
        'id': id,
        'subject': subject,
        'topic': topic,
        'questionText': questionText,
        'options': options,
        'correctAnswerIndex': correctAnswerIndex,
        'explanation': explanation,
        'difficulty': difficulty.index,
      };

  factory Question.fromJson(Map<String, dynamic> json) => Question(
        id: json['id'],
        subject: json['subject'],
        topic: json['topic'],
        questionText: json['questionText'],
        options: List<String>.from(json['options']),
        correctAnswerIndex: json['correctAnswerIndex'],
        explanation: json['explanation'],
        difficulty: Difficulty.values[json['difficulty']],
      );
}
