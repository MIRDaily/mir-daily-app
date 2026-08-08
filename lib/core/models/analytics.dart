/// Modelos de la analítica de rendimiento (Panel), portados 1:1 de la web.
///
/// Endpoints backend (Railway):
///  - GET /api/stats/timeseries
///  - GET /api/analytics/effort?window=
///  - GET /api/analytics/heatmap/subjects?window=&mode=
///  - GET /api/analytics/heatmap/topics?subjectId=&window=&mode=
///  - GET /api/analytics/trend?subjectId=&window=
///  - GET /api/analytics/weak-points
library;

/// Ventana móvil de análisis: 7 días, 30 días o global.
enum AnalyticsWindow { week, month, all }

extension AnalyticsWindowX on AnalyticsWindow {
  /// Valor que espera el backend en el query string.
  String get query => switch (this) {
        AnalyticsWindow.week => '7d',
        AnalyticsWindow.month => '30d',
        AnalyticsWindow.all => 'all',
      };

  String get label => switch (this) {
        AnalyticsWindow.week => 'Semana',
        AnalyticsWindow.month => 'Mes',
        AnalyticsWindow.all => 'Global',
      };
}

/// Modo de estudio. `all` agrega los tres.
enum AnalyticsMode { all, daily, simulacro, studio }

extension AnalyticsModeX on AnalyticsMode {
  /// null = todos (el backend no filtra por modo).
  String? get query => this == AnalyticsMode.all ? null : name;

  String get label => switch (this) {
        AnalyticsMode.all => 'Todos',
        AnalyticsMode.daily => 'Daily',
        AnalyticsMode.simulacro => 'Simulacros',
        AnalyticsMode.studio => 'Mazos',
      };
}

double? _toDouble(dynamic v) => (v as num?)?.toDouble();
int _toInt(dynamic v) => ((v ?? 0) as num).round();

// ===========================================================================
// SERIE TEMPORAL (Progreso global)
// ===========================================================================

class TimeSeriesPoint {
  final String date;
  final double score;
  final double avgTime;
  final double? correct;

  const TimeSeriesPoint({
    required this.date,
    required this.score,
    required this.avgTime,
    this.correct,
  });

  factory TimeSeriesPoint.fromJson(Map<String, dynamic> j) => TimeSeriesPoint(
        date: (j['date'] ?? '').toString(),
        score: _toDouble(j['score']) ?? 0,
        avgTime: _toDouble(j['avgTime']) ?? 0,
        correct: _toDouble(j['correct']),
      );
}

class TimeSeriesResponse {
  final String? status; // 'ok' | 'insufficient_data'
  final List<TimeSeriesPoint> points;
  final int totalPoints;
  final double? avgScore30;
  final double? avgTime30;

  const TimeSeriesResponse({
    this.status,
    required this.points,
    required this.totalPoints,
    this.avgScore30,
    this.avgTime30,
  });

  bool get hasPoints => totalPoints > 0 && points.isNotEmpty;

  factory TimeSeriesResponse.fromJson(Map<String, dynamic> j) =>
      TimeSeriesResponse(
        status: j['status'] as String?,
        points: ((j['points'] ?? const []) as List)
            .map((e) => TimeSeriesPoint.fromJson(e as Map<String, dynamic>))
            .toList(),
        totalPoints: _toInt(j['totalPoints']),
        avgScore30: _toDouble(j['avgScore30']),
        avgTime30: _toDouble(j['avgTime30']),
      );
}

// ===========================================================================
// HEATMAP POR ASIGNATURA / TEMA
// ===========================================================================

class SubjectHeatmapCell {
  final int subjectId;
  final String name;
  final int correct;
  final int wrong;
  final int blank;
  final int total;

  /// % de acierto sobre respondidas (los blancos no penalizan); null si todo blancos.
  final double? accuracy;

  const SubjectHeatmapCell({
    required this.subjectId,
    required this.name,
    required this.correct,
    required this.wrong,
    required this.blank,
    required this.total,
    this.accuracy,
  });

  factory SubjectHeatmapCell.fromJson(Map<String, dynamic> j) =>
      SubjectHeatmapCell(
        subjectId: _toInt(j['subjectId']),
        name: (j['name'] ?? '') as String,
        correct: _toInt(j['correct']),
        wrong: _toInt(j['wrong']),
        blank: _toInt(j['blank']),
        total: _toInt(j['total']),
        accuracy: _toDouble(j['accuracy']),
      );
}

class SubjectHeatmapResponse {
  final List<SubjectHeatmapCell> subjects;
  const SubjectHeatmapResponse({required this.subjects});

  factory SubjectHeatmapResponse.fromJson(Map<String, dynamic> j) =>
      SubjectHeatmapResponse(
        subjects: ((j['subjects'] ?? const []) as List)
            .map((e) => SubjectHeatmapCell.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class TopicHeatmapCell {
  final int topicId;
  final String name;
  final int correct;
  final int wrong;
  final int blank;
  final int total;
  final double? accuracy;

  const TopicHeatmapCell({
    required this.topicId,
    required this.name,
    required this.correct,
    required this.wrong,
    required this.blank,
    required this.total,
    this.accuracy,
  });

  factory TopicHeatmapCell.fromJson(Map<String, dynamic> j) => TopicHeatmapCell(
        topicId: _toInt(j['topicId']),
        name: (j['name'] ?? '') as String,
        correct: _toInt(j['correct']),
        wrong: _toInt(j['wrong']),
        blank: _toInt(j['blank']),
        total: _toInt(j['total']),
        accuracy: _toDouble(j['accuracy']),
      );
}

class TopicHeatmapResponse {
  final int subjectId;
  final List<TopicHeatmapCell> topics;
  const TopicHeatmapResponse({required this.subjectId, required this.topics});

  factory TopicHeatmapResponse.fromJson(Map<String, dynamic> j) =>
      TopicHeatmapResponse(
        subjectId: _toInt(j['subjectId']),
        topics: ((j['topics'] ?? const []) as List)
            .map((e) => TopicHeatmapCell.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

// ===========================================================================
// EVOLUCIÓN (trend) DE UNA ASIGNATURA
// ===========================================================================

class TrendPoint {
  final String day;
  final int correct;
  final int wrong;
  final int blank;
  final int total;
  final double? accuracy;

  const TrendPoint({
    required this.day,
    required this.correct,
    required this.wrong,
    required this.blank,
    required this.total,
    this.accuracy,
  });

  factory TrendPoint.fromJson(Map<String, dynamic> j) => TrendPoint(
        day: (j['day'] ?? '').toString(),
        correct: _toInt(j['correct']),
        wrong: _toInt(j['wrong']),
        blank: _toInt(j['blank']),
        total: _toInt(j['total']),
        accuracy: _toDouble(j['accuracy']),
      );
}

class SubjectTrendResponse {
  final int subjectId;
  final List<TrendPoint> points;
  const SubjectTrendResponse({required this.subjectId, required this.points});

  factory SubjectTrendResponse.fromJson(Map<String, dynamic> j) =>
      SubjectTrendResponse(
        subjectId: _toInt(j['subjectId']),
        points: ((j['points'] ?? const []) as List)
            .map((e) => TrendPoint.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

// ===========================================================================
// PUNTOS DÉBILES
// ===========================================================================

class WeakTopic {
  final int topicId;
  final String name;
  final int subjectId;
  final String subjectName;
  final int correct;
  final int wrong;
  final int blank;
  final int total;
  final double? accuracy;

  /// % de fallos + blancos sobre el total: "lo que no sabes".
  final double? failRate;

  const WeakTopic({
    required this.topicId,
    required this.name,
    required this.subjectId,
    required this.subjectName,
    required this.correct,
    required this.wrong,
    required this.blank,
    required this.total,
    this.accuracy,
    this.failRate,
  });

  factory WeakTopic.fromJson(Map<String, dynamic> j) => WeakTopic(
        topicId: _toInt(j['topicId']),
        name: (j['name'] ?? '') as String,
        subjectId: _toInt(j['subjectId']),
        subjectName: (j['subjectName'] ?? '') as String,
        correct: _toInt(j['correct']),
        wrong: _toInt(j['wrong']),
        blank: _toInt(j['blank']),
        total: _toInt(j['total']),
        accuracy: _toDouble(j['accuracy']),
        failRate: _toDouble(j['failRate']),
      );
}

class WeakPointsResponse {
  final List<WeakTopic> week;
  final List<WeakTopic> month;
  final List<WeakTopic> global;

  const WeakPointsResponse({
    required this.week,
    required this.month,
    required this.global,
  });

  List<WeakTopic> forWindow(AnalyticsWindow w) => switch (w) {
        AnalyticsWindow.week => week,
        AnalyticsWindow.month => month,
        AnalyticsWindow.all => global,
      };

  static List<WeakTopic> _topics(dynamic node) {
    final map = node as Map<String, dynamic>?;
    return ((map?['topics'] ?? const []) as List)
        .map((e) => WeakTopic.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  factory WeakPointsResponse.fromJson(Map<String, dynamic> j) =>
      WeakPointsResponse(
        week: _topics(j['week']),
        month: _topics(j['month']),
        global: _topics(j['global']),
      );
}

// ===========================================================================
// ESFUERZO
// ===========================================================================

class EffortTotals {
  final int questions;
  final int correct;
  final int wrong;
  final int blank;
  final int timeSpentSeconds;

  const EffortTotals({
    required this.questions,
    required this.correct,
    required this.wrong,
    required this.blank,
    required this.timeSpentSeconds,
  });

  factory EffortTotals.fromJson(Map<String, dynamic>? j) => EffortTotals(
        questions: _toInt(j?['questions']),
        correct: _toInt(j?['correct']),
        wrong: _toInt(j?['wrong']),
        blank: _toInt(j?['blank']),
        timeSpentSeconds: _toInt(j?['timeSpentSeconds']),
      );
}

class EffortByMode {
  final String mode;
  final int questions;
  final int correct;
  final int wrong;
  final int blank;

  const EffortByMode({
    required this.mode,
    required this.questions,
    required this.correct,
    required this.wrong,
    required this.blank,
  });

  factory EffortByMode.fromJson(Map<String, dynamic> j) => EffortByMode(
        mode: (j['mode'] ?? '') as String,
        questions: _toInt(j['questions']),
        correct: _toInt(j['correct']),
        wrong: _toInt(j['wrong']),
        blank: _toInt(j['blank']),
      );
}

class EffortResponse {
  final EffortTotals totals;
  final List<EffortByMode> byMode;

  const EffortResponse({required this.totals, required this.byMode});

  factory EffortResponse.fromJson(Map<String, dynamic> j) => EffortResponse(
        totals: EffortTotals.fromJson(j['totals'] as Map<String, dynamic>?),
        byMode: ((j['byMode'] ?? const []) as List)
            .map((e) => EffortByMode.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
