/// Modelos de datos de la API de MIRDaily.
library;

/// Resuelve la respuesta del backend a un índice 0-based dentro de las
/// opciones. La BD guarda las respuestas en formato 1-based (1..5), pero
/// también puede llegar como letra ('A'..'E'), número en string o el texto
/// literal de la opción — misma lógica que DailyReviewCarousel en la web.
int resolveOptionIndex(dynamic value, List<String> options) {
  if (value == null) return -1;

  if (value is num) {
    final oneBased = value.round() - 1;
    if (oneBased >= 0 && oneBased < options.length) return oneBased;
    final zeroBased = value.round();
    if (zeroBased >= 0 && zeroBased < options.length) return zeroBased;
    return -1;
  }

  final raw = value.toString().trim();
  if (raw.isEmpty) return -1;

  final upper = raw.toUpperCase();
  if (upper.length == 1) {
    final code = upper.codeUnitAt(0) - 65; // 'A' == 0
    if (code >= 0 && code < options.length) return code;
  }

  final numeric = num.tryParse(raw);
  if (numeric != null) {
    final oneBased = numeric.round() - 1;
    if (oneBased >= 0 && oneBased < options.length) return oneBased;
  }

  return options.indexWhere((opt) => opt.trim() == raw);
}

class DailyQuestion {
  final String id;
  final int? year;
  final int? questionNumber;
  final String? subject;
  final String? topic;
  final String statement;
  final List<String> options;

  /// Valor crudo del backend (1-based, letra o texto). Usa [correctIndex].
  final dynamic correctAnswer;
  final String? explanation;
  final bool hasImage;
  final String? imageUrl;

  const DailyQuestion({
    required this.id,
    this.year,
    this.questionNumber,
    this.subject,
    this.topic,
    required this.statement,
    required this.options,
    required this.correctAnswer,
    this.explanation,
    this.hasImage = false,
    this.imageUrl,
  });

  /// Índice 0-based de la opción correcta dentro de [options].
  int get correctIndex => resolveOptionIndex(correctAnswer, options);

  factory DailyQuestion.fromJson(Map<String, dynamic> json) {
    return DailyQuestion(
      id: json['id'].toString(),
      year: json['year'] as int?,
      questionNumber: json['question_number'] as int?,
      subject: json['subject'] as String?,
      topic: json['topic'] as String?,
      statement: (json['statement'] ?? '') as String,
      options: ((json['options'] ?? []) as List).map((e) => '$e').toList(),
      correctAnswer: json['correct_answer'],
      explanation: json['explanation'] as String?,
      hasImage: (json['has_image'] ?? false) as bool,
      imageUrl: json['image_url'] as String?,
    );
  }
}

/// Respuesta del usuario a una pregunta (se envía a /api/submit-answers).
///
/// [selectedIndex] es 0-based dentro de la app; el backend espera el valor
/// 1-based (igual que la web: `selectedOption: index + 1`), de ahí el +1
/// en [toJson].
class UserAnswer {
  final String questionId;

  /// Índice 0-based de la opción elegida, o `null` si se dejó EN BLANCO.
  final int? selectedIndex;
  final int timeSpent;

  const UserAnswer({
    required this.questionId,
    required this.selectedIndex,
    required this.timeSpent,
  });

  bool get isBlank => selectedIndex == null;

  Map<String, dynamic> toJson() => {
        'questionId': questionId,
        // null = en blanco; el backend lo registra sin opción marcada.
        'selectedOption': selectedIndex == null ? null : selectedIndex! + 1,
        'timeSpent': timeSpent,
      };
}

class ScoreBreakdown {
  final int knowledgeScore;
  final int timeBonus;
  final int total;

  const ScoreBreakdown({
    required this.knowledgeScore,
    required this.timeBonus,
    required this.total,
  });

  factory ScoreBreakdown.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const ScoreBreakdown(knowledgeScore: 0, timeBonus: 0, total: 0);
    }
    return ScoreBreakdown(
      knowledgeScore: ((json['knowledgeScore'] ?? 0) as num).round(),
      timeBonus: ((json['timeBonus'] ?? 0) as num).round(),
      total: ((json['total'] ?? 0) as num).round(),
    );
  }
}

/// Resultado inmediato tras enviar respuestas.
class SubmitResult {
  final int correctCount;
  final int totalQuestions;
  final int score;
  final int totalTime;
  final int percentage;
  final ScoreBreakdown breakdown;

  const SubmitResult({
    required this.correctCount,
    required this.totalQuestions,
    required this.score,
    required this.totalTime,
    required this.percentage,
    required this.breakdown,
  });

  factory SubmitResult.fromJson(Map<String, dynamic> json) {
    return SubmitResult(
      correctCount: ((json['correctCount'] ?? 0) as num).round(),
      totalQuestions: ((json['totalQuestions'] ?? 5) as num).round(),
      score: ((json['score'] ?? 0) as num).round(),
      totalTime: ((json['totalTime'] ?? 0) as num).round(),
      percentage: ((json['percentage'] ?? 0) as num).round(),
      breakdown:
          ScoreBreakdown.fromJson(json['breakdown'] as Map<String, dynamic>?),
    );
  }
}

class ReviewQuestion {
  final String? questionId;
  final String statement;
  final List<String> options;

  /// Valores crudos del backend (1-based). Usa [correctIndex]/[selectedIndex].
  final dynamic correctAnswer;
  final dynamic selectedAnswer;
  final bool isCorrect;
  final String? explanation;
  final bool hasImage;
  final String? imageUrl;

  const ReviewQuestion({
    this.questionId,
    required this.statement,
    required this.options,
    required this.correctAnswer,
    required this.selectedAnswer,
    required this.isCorrect,
    this.explanation,
    this.hasImage = false,
    this.imageUrl,
  });

  int get correctIndex => resolveOptionIndex(correctAnswer, options);
  int get selectedIndex => resolveOptionIndex(selectedAnswer, options);

  factory ReviewQuestion.fromJson(Map<String, dynamic> json) {
    return ReviewQuestion(
      questionId: json['questionId']?.toString(),
      statement: (json['statement'] ?? '') as String,
      options: ((json['options'] ?? []) as List).map((e) => '$e').toList(),
      correctAnswer: json['correctAnswer'],
      selectedAnswer: json['selectedAnswer'],
      isCorrect: (json['isCorrect'] ?? false) as bool,
      explanation: json['explanation'] as String?,
      hasImage: (json['hasImage'] ?? false) as bool,
      imageUrl: json['imageUrl'] as String?,
    );
  }
}

/// Resultados completos del día (/api/results/today).
class DailyResults {
  final int score;
  final int correctCount;
  final int totalQuestions;
  final int totalTime;
  final ScoreBreakdown breakdown;
  final List<ReviewQuestion> reviewQuestions;
  final double? mean;
  final double? stdDev;
  final double? zScore;

  const DailyResults({
    required this.score,
    required this.correctCount,
    required this.totalQuestions,
    required this.totalTime,
    required this.breakdown,
    required this.reviewQuestions,
    this.mean,
    this.stdDev,
    this.zScore,
  });

  factory DailyResults.fromJson(Map<String, dynamic> json) {
    final me = (json['meToday'] ?? {}) as Map<String, dynamic>;
    return DailyResults(
      score: ((me['score'] ?? 0) as num).round(),
      correctCount: ((me['correctCount'] ?? 0) as num).round(),
      totalQuestions: ((me['totalQuestions'] ?? 5) as num).round(),
      totalTime: ((me['totalTime'] ?? 0) as num).round(),
      breakdown:
          ScoreBreakdown.fromJson(me['breakdown'] as Map<String, dynamic>?),
      reviewQuestions: ((json['reviewQuestions'] ?? []) as List)
          .map((e) => ReviewQuestion.fromJson(e as Map<String, dynamic>))
          .toList(),
      mean: (json['mean'] as num?)?.toDouble(),
      stdDev: ((json['stdDev'] ?? json['std_dev']) as num?)?.toDouble(),
      zScore: (json['zScore'] as num?)?.toDouble(),
    );
  }
}

class RankingEntry {
  final int position;
  final String displayName;
  final int avatarId;
  final int score;
  final int correctCount;
  final int totalTime;
  final bool isBot;
  final String? userId;

  const RankingEntry({
    required this.position,
    required this.displayName,
    required this.avatarId,
    required this.score,
    required this.correctCount,
    required this.totalTime,
    required this.isBot,
    this.userId,
  });

  factory RankingEntry.fromJson(Map<String, dynamic> json) {
    return RankingEntry(
      position: ((json['position'] ?? 0) as num).round(),
      displayName: (json['displayName'] ?? 'Anónimo') as String,
      avatarId: ((json['avatarId'] ?? 1) as num).round(),
      score: ((json['score'] ?? 0) as num).round(),
      correctCount: ((json['correctCount'] ?? 0) as num).round(),
      totalTime: ((json['totalTime'] ?? 0) as num).round(),
      isBot: (json['isBot'] ?? false) as bool,
      userId: json['userId']?.toString(),
    );
  }
}

class UserProfile {
  final String id;
  final String? email;
  final String? displayName;
  final String? username;
  final int avatarId;
  final bool onboardingCompleted;
  final int? medicalYear;
  final String? mirSpecialty;
  final String? university;
  final String? mainGoal;
  final DateTime? createdAt;

  const UserProfile({
    required this.id,
    this.email,
    this.displayName,
    this.username,
    this.avatarId = 1,
    this.onboardingCompleted = false,
    this.medicalYear,
    this.mirSpecialty,
    this.university,
    this.mainGoal,
    this.createdAt,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'].toString(),
      email: json['email'] as String?,
      displayName: json['display_name'] as String?,
      username: json['username'] as String?,
      avatarId: ((json['avatar_id'] ?? 1) as num?)?.round() ?? 1,
      onboardingCompleted: _asBool(json['onboarding_completed']),
      medicalYear: (json['medical_year'] as num?)?.round(),
      mirSpecialty:
          (json['mir_specialty'] as Map<String, dynamic>?)?['name'] as String?,
      university:
          (json['university'] as Map<String, dynamic>?)?['name'] as String?,
      mainGoal: json['main_goal'] as String?,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
    );
  }

  String get shortName {
    final name = displayName ?? username ?? email ?? 'Doctor/a';
    return name.split(' ').first;
  }

  String get fullName => displayName ?? username ?? 'Doctor/a';

  /// Lee un booleano venga como bool, número (1/0) o string ("true"/"1").
  /// Así el onboarding se detecta bien aunque el backend cambie el tipo.
  static bool _asBool(dynamic v) {
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) {
      final s = v.trim().toLowerCase();
      return s == 'true' || s == '1' || s == 't' || s == 'yes';
    }
    return false;
  }
}

/// Mazo del Studio (GET /api/studio/decks).
class Deck {
  final String id;
  final String name;
  final bool systemGenerated;
  final String? autoType; // p. ej. failed_global
  final double accuracy; // 0..1
  final int totalReviews;
  final String visualState; // perfect | clean | destroyed | failed

  const Deck({
    required this.id,
    required this.name,
    required this.systemGenerated,
    this.autoType,
    required this.accuracy,
    required this.totalReviews,
    required this.visualState,
  });

  factory Deck.fromJson(Map<String, dynamic> json) {
    return Deck(
      id: json['id'].toString(),
      name: (json['name'] ?? json['title'] ?? 'Mazo') as String,
      systemGenerated: (json['system_generated'] ?? false) as bool,
      autoType: json['auto_type'] as String?,
      accuracy: ((json['accuracy'] ?? 0) as num).toDouble(),
      totalReviews: ((json['total_reviews'] ?? 0) as num).round(),
      visualState: (json['visual_state'] ?? 'clean') as String,
    );
  }
}

/// Resumen de stats del usuario (GET /api/stats/summary).
class StatsSummary {
  final double? avgPercentage;
  final int totalQuestions;
  final double? trend;
  final String trendType; // full | partial | insufficient
  final bool insufficientData;
  final int dailys30; // nº de dailys que componen la media (basis.dailys30)

  const StatsSummary({
    this.avgPercentage,
    required this.totalQuestions,
    this.trend,
    required this.trendType,
    required this.insufficientData,
    this.dailys30 = 0,
  });

  factory StatsSummary.fromJson(Map<String, dynamic> json) {
    final basis = json['basis'] as Map<String, dynamic>?;
    return StatsSummary(
      avgPercentage: (json['avgPercentage'] as num?)?.toDouble(),
      totalQuestions: ((json['totalQuestions'] ?? 0) as num).round(),
      trend: (json['trend'] as num?)?.toDouble(),
      trendType: (json['trendType'] ?? 'insufficient') as String,
      insufficientData: json['state'] == 'insufficient_data',
      dailys30: ((basis?['dailys30'] ?? 0) as num).round(),
    );
  }
}

/// Distribución de puntuaciones del día (GET /api/stats/score-distribution).
/// Réplica móvil de la campana de la web: todas las puntuaciones de hoy
/// (usuarios + bots) con tu posición marcada.
class ScoreDistribution {
  final List<int> scores;
  final double? mean;
  final double? median;
  final double? percentile;
  final int totalUsers;
  final int sameScoreCount;
  final int? userScore;

  const ScoreDistribution({
    required this.scores,
    this.mean,
    this.median,
    this.percentile,
    required this.totalUsers,
    required this.sameScoreCount,
    this.userScore,
  });

  bool get hasData => scores.isNotEmpty;

  factory ScoreDistribution.fromJson(Map<String, dynamic> json) {
    return ScoreDistribution(
      scores: ((json['scores'] ?? []) as List)
          .map((e) => (e as num).round())
          .toList(),
      mean: (json['mean'] as num?)?.toDouble(),
      median: (json['median'] as num?)?.toDouble(),
      percentile: (json['percentile'] as num?)?.toDouble(),
      totalUsers: ((json['totalUsers'] ?? 0) as num).round(),
      sameScoreCount: ((json['sameScoreCount'] ?? 0) as num).round(),
      userScore: (json['userScore'] as num?)?.round(),
    );
  }
}

/// Un día del heatmap de actividad. level: 0 nada, 1 login, 2 daily hecho.
class HeatDay {
  final String date;
  final int level;
  const HeatDay({required this.date, required this.level});

  factory HeatDay.fromJson(Map<String, dynamic> json) => HeatDay(
        date: (json['date'] ?? '').toString(),
        level: ((json['level'] ?? 0) as num).round(),
      );
}

/// Heatmap de actividad de los últimos 30 días (GET /api/stats/activity-heatmap).
class ActivityHeatmap {
  final List<HeatDay> days;
  final int currentStreak;
  final int longestStreak;
  final int totalActiveDays;
  final int totalDailyDays;

  const ActivityHeatmap({
    required this.days,
    required this.currentStreak,
    required this.longestStreak,
    required this.totalActiveDays,
    required this.totalDailyDays,
  });

  factory ActivityHeatmap.fromJson(Map<String, dynamic> json) {
    final stats = (json['stats'] ?? {}) as Map<String, dynamic>;
    return ActivityHeatmap(
      days: ((json['days'] ?? []) as List)
          .map((e) => HeatDay.fromJson(e as Map<String, dynamic>))
          .toList(),
      currentStreak: ((stats['currentStreak'] ?? 0) as num).round(),
      longestStreak: ((stats['longestStreak'] ?? 0) as num).round(),
      totalActiveDays: ((stats['totalActiveDays'] ?? 0) as num).round(),
      totalDailyDays: ((stats['totalDailyDays'] ?? 0) as num).round(),
    );
  }
}

/// Carta de un mazo: una pregunta con sus opciones. Sirve tanto para listar
/// los items del mazo (GET .../items) como para estudiar (GET .../next).
class DeckCard {
  final String itemId; // deck_items.id (deckItemId)
  final String questionId;
  final String statement;
  final List<String> options;
  final dynamic correctAnswer; // 1-based / letra / texto. Usa [correctIndex].
  final String? explanation;
  final bool hasImage;
  final String? imageUrl;
  final String? subject;

  const DeckCard({
    required this.itemId,
    required this.questionId,
    required this.statement,
    required this.options,
    required this.correctAnswer,
    this.explanation,
    this.hasImage = false,
    this.imageUrl,
    this.subject,
  });

  int get correctIndex => resolveOptionIndex(correctAnswer, options);

  factory DeckCard.fromJson(Map<String, dynamic> json) {
    final q = (json['questions'] ?? const {}) as Map<String, dynamic>;
    final rawOpts =
        ((q['question_options'] ?? const []) as List).cast<dynamic>();
    final maps = rawOpts
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList()
      ..sort((a, b) => ((a['option_index'] ?? 0) as num)
          .compareTo((b['option_index'] ?? 0) as num));
    final options = maps.map((o) => (o['option_text'] ?? '').toString()).toList();

    return DeckCard(
      itemId: (json['id'] ?? '').toString(),
      questionId: (json['question_id'] ?? q['id'] ?? '').toString(),
      statement: (q['statement'] ?? '') as String,
      options: options,
      correctAnswer: q['correct_answer'],
      explanation: q['explanation'] as String?,
      hasImage: (q['has_image'] ?? false) as bool,
      imageUrl: q['image_url'] as String?,
      subject: q['subject'] as String?,
    );
  }
}

/// Conteo de items del mazo por estado (GET .../summary).
class DeckSummary {
  final int newCount;
  final int failed;
  final int learning;
  final int mastered;

  const DeckSummary({
    required this.newCount,
    required this.failed,
    required this.learning,
    required this.mastered,
  });

  int get total => newCount + failed + learning + mastered;

  factory DeckSummary.fromJson(Map<String, dynamic> json) => DeckSummary(
        newCount: ((json['new'] ?? 0) as num).round(),
        failed: ((json['failed'] ?? 0) as num).round(),
        learning: ((json['learning'] ?? 0) as num).round(),
        mastered: ((json['mastered'] ?? 0) as num).round(),
      );
}

// ==========================
// SIMULACRO (/api/simulacro/*)
// ==========================

class SimSubject {
  final int id;
  final String name;
  const SimSubject({required this.id, required this.name});
  factory SimSubject.fromJson(Map<String, dynamic> j) =>
      SimSubject(id: (j['id'] as num).toInt(), name: (j['name'] ?? '') as String);
}

class SimTopic {
  final int id;
  final String name;
  final int subjectId;
  const SimTopic(
      {required this.id, required this.name, required this.subjectId});
  factory SimTopic.fromJson(Map<String, dynamic> j) => SimTopic(
        id: (j['id'] as num).toInt(),
        name: (j['name'] ?? '') as String,
        subjectId: (j['subject_id'] as num).toInt(),
      );
}

/// Pregunta del simulacro tal y como la entrega el backend: SIN la respuesta
/// correcta ni la explicación (solo se revelan tras /check).
class SimQuestion {
  final int id;
  final String statement;
  final String? subject;
  final String? topic;
  final List<String> options;
  final bool hasImage;
  final String? imageUrl;

  const SimQuestion({
    required this.id,
    required this.statement,
    this.subject,
    this.topic,
    required this.options,
    this.hasImage = false,
    this.imageUrl,
  });

  factory SimQuestion.fromJson(Map<String, dynamic> j) => SimQuestion(
        id: (j['id'] as num).toInt(),
        statement: (j['statement'] ?? '') as String,
        subject: j['subject'] as String?,
        topic: j['topic'] as String?,
        options: ((j['options'] ?? const []) as List)
            .map((e) => '$e')
            .toList(),
        hasImage: (j['has_image'] ?? false) as bool,
        imageUrl: j['image_url'] as String?,
      );
}

/// Corrección de una pregunta del simulacro (POST /check).
class SimResult {
  final int questionId;
  final int correctIndex; // 0-based
  final String? explanation;
  final bool isCorrect;

  /// Resultado ternario del backend: 'correct' | 'wrong' | 'blank'.
  final String? result;

  const SimResult({
    required this.questionId,
    required this.correctIndex,
    this.explanation,
    required this.isCorrect,
    this.result,
  });

  bool get isBlank => result == 'blank';

  factory SimResult.fromJson(Map<String, dynamic> j) => SimResult(
        questionId: (j['questionId'] as num).toInt(),
        correctIndex: ((j['correctIndex'] ?? -1) as num).toInt(),
        explanation: j['explanation'] as String?,
        isCorrect: (j['isCorrect'] ?? false) as bool,
        result: j['result'] as String?,
      );
}

/// Universidad para el onboarding (GET /api/profile/universities).
class University {
  final int id;
  final String name;
  final String country;

  const University({required this.id, required this.name, required this.country});

  factory University.fromJson(Map<String, dynamic> j) => University(
        id: (j['id'] as num).toInt(),
        name: (j['name'] ?? '') as String,
        country: (j['country'] ?? '') as String,
      );
}

/// Especialidad MIR para el onboarding (GET /api/profile/mir-specialties).
class MirSpecialty {
  final int id;
  final String name;

  const MirSpecialty({required this.id, required this.name});

  factory MirSpecialty.fromJson(Map<String, dynamic> j) => MirSpecialty(
        id: (j['id'] as num).toInt(),
        name: (j['name'] ?? '') as String,
      );
}

/// Mazo en la papelera (GET .../decks/trash).
class DeckTrashEntry {
  final String id;
  final String name;
  final DateTime? deletedAt;
  final DateTime? purgeAt;

  const DeckTrashEntry({
    required this.id,
    required this.name,
    this.deletedAt,
    this.purgeAt,
  });

  factory DeckTrashEntry.fromJson(Map<String, dynamic> json) => DeckTrashEntry(
        id: (json['id'] ?? '').toString(),
        name: (json['name'] ?? 'Mazo') as String,
        deletedAt: DateTime.tryParse(json['deleted_at']?.toString() ?? ''),
        purgeAt: DateTime.tryParse(json['purge_at']?.toString() ?? ''),
      );
}
