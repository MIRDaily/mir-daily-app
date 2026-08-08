class UserProfile {
  String name;
  String email;
  int totalAnswered;
  int totalCorrect;
  int currentStreak;
  int bestStreak;
  List<String> savedQuestionIds;
  DateTime? lastActivityDate;
  bool difficultyDeckEnabled;
  Map<String, String> questionDifficulties; // questionId -> 'easy', 'medium', 'hard'
  String? profileImagePath; // Ruta local de la foto de perfil

  UserProfile({
    this.name = 'Estudiante',
    this.email = '',
    this.totalAnswered = 0,
    this.totalCorrect = 0,
    this.currentStreak = 0,
    this.bestStreak = 0,
    this.savedQuestionIds = const [],
    this.lastActivityDate,
    this.difficultyDeckEnabled = true,
    this.questionDifficulties = const {},
    this.profileImagePath,
  });

  double get accuracy {
    if (totalAnswered == 0) return 0;
    return (totalCorrect / totalAnswered) * 100;
  }

  String get accuracyFormatted => '${accuracy.toStringAsFixed(1)}%';

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      name: json['name'] ?? 'Estudiante',
      email: json['email'] ?? '',
      totalAnswered: json['totalAnswered'] ?? 0,
      totalCorrect: json['totalCorrect'] ?? 0,
      currentStreak: json['currentStreak'] ?? 0,
      bestStreak: json['bestStreak'] ?? 0,
      savedQuestionIds: List<String>.from(json['savedQuestionIds'] ?? []),
      lastActivityDate: json['lastActivityDate'] != null 
          ? DateTime.parse(json['lastActivityDate']) 
          : null,
      difficultyDeckEnabled: json['difficultyDeckEnabled'] ?? true,
      questionDifficulties: Map<String, String>.from(json['questionDifficulties'] ?? {}),
      profileImagePath: json['profileImagePath'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'email': email,
      'totalAnswered': totalAnswered,
      'totalCorrect': totalCorrect,
      'currentStreak': currentStreak,
      'bestStreak': bestStreak,
      'savedQuestionIds': savedQuestionIds,
      'lastActivityDate': lastActivityDate?.toIso8601String(),
      'difficultyDeckEnabled': difficultyDeckEnabled,
      'questionDifficulties': questionDifficulties,
      'profileImagePath': profileImagePath,
    };
  }
}
