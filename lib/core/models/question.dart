class Question {
  final String id;
  final int year;
  final int questionNumber;
  final String specialty;
  final String statement;
  final List<String> options;
  final int correctIndex;
  final String explanation;

  Question({
    required this.id,
    required this.year,
    required this.questionNumber,
    required this.specialty,
    required this.statement,
    required this.options,
    required this.correctIndex,
    required this.explanation,
  });

  factory Question.fromJson(Map<String, dynamic> json) {
    return Question(
      id: json['id'] as String,
      year: json['year'] as int,
      questionNumber: json['questionNumber'] as int,
      specialty: json['specialty'] as String,
      statement: json['statement'] as String,
      options: List<String>.from(json['options']),
      correctIndex: json['correctIndex'] as int,
      explanation: json['explanation'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'year': year,
      'questionNumber': questionNumber,
      'specialty': specialty,
      'statement': statement,
      'options': options,
      'correctIndex': correctIndex,
      'explanation': explanation,
    };
  }

  int get optionCount => options.length;
  
  String get formattedYear => 'MIR $year';
  
  String getOptionLetter(int index) {
    return String.fromCharCode(65 + index); // A, B, C, D, E
  }
}
