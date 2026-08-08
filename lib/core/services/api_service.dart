import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/analytics.dart';
import '../models/models.dart';
import 'auth_service.dart';

class ApiException implements Exception {
  final int statusCode;
  final String message;
  final bool alreadyCompleted;

  const ApiException(
    this.statusCode,
    this.message, {
    this.alreadyCompleted = false,
  });

  @override
  String toString() => message;
}

/// Cliente del backend MIRDaily (Railway).
/// Renueva el JWT de Supabase automáticamente cuando caduca.
class ApiService {
  final AuthService _authService;

  /// Sesión activa (la fija AuthProvider al iniciar sesión o restaurarla).
  AuthSession? session;

  ApiService(this._authService);

  /// Token válido (renovado si hacía falta). Lo usa el cliente de Versus, que
  /// vive en su propia feature pero comparte esta misma sesión: así el JWT se
  /// renueva en un único sitio.
  Future<String> validToken() => _validToken();

  Future<String> _validToken() async {
    var s = session;
    if (s == null) {
      throw const ApiException(401, 'No hay sesión activa.');
    }
    if (s.isExpired) {
      s = await _authService.refresh(s);
      session = s;
    }
    return s.accessToken;
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final token = await _validToken();
    final uri = Uri.parse('${AppConfig.apiBaseUrl}$path');
    final headers = {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };

    late http.Response res;
    if (method == 'POST') {
      res = await http
          .post(uri, headers: headers, body: jsonEncode(body ?? {}))
          .timeout(const Duration(seconds: 25));
    } else if (method == 'DELETE') {
      res = await http
          .delete(uri, headers: headers)
          .timeout(const Duration(seconds: 25));
    } else {
      res = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 25));
    }

    Map<String, dynamic> json;
    try {
      json = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      json = {};
    }

    if (res.statusCode >= 200 && res.statusCode < 300) {
      return json;
    }

    throw ApiException(
      res.statusCode,
      (json['error'] ?? 'Error del servidor (${res.statusCode})').toString(),
      alreadyCompleted: (json['alreadyCompleted'] ?? false) as bool,
    );
  }

  // ==========================
  // ENDPOINTS
  // ==========================

  /// Preguntas del sobre de hoy. Lanza ApiException(alreadyCompleted: true)
  /// si el daily ya se ha completado.
  Future<List<DailyQuestion>> getDailyQuestions() async {
    final json = await _request('GET', '/api/daily-questions');
    return ((json['questions'] ?? []) as List)
        .map((e) => DailyQuestion.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<SubmitResult> submitAnswers(List<UserAnswer> answers) async {
    final json = await _request(
      'POST',
      '/api/submit-answers',
      body: {'answers': answers.map((a) => a.toJson()).toList()},
    );
    return SubmitResult.fromJson(json);
  }

  Future<DailyResults> getResultsToday() async {
    final json = await _request('GET', '/api/results/today');
    return DailyResults.fromJson(json);
  }

  Future<List<RankingEntry>> getRanking() async {
    final json = await _request('GET', '/api/ranking');
    return ((json['ranking'] ?? []) as List)
        .map((e) => RankingEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<UserProfile> getProfile() async {
    final json = await _request('GET', '/api/profile');
    return UserProfile.fromJson(json);
  }

  Future<void> updateAvatar(int avatarId) async {
    await _request('POST', '/api/profile/avatar', body: {'avatarId': avatarId});
  }

  // ==========================
  // ONBOARDING (usuarios nuevos)
  // ==========================

  Future<List<University>> getUniversities() async {
    final json = await _request('GET', '/api/profile/universities');
    return ((json['universities'] ?? []) as List)
        .map((e) => University.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<MirSpecialty>> getMirSpecialties() async {
    final json = await _request('GET', '/api/profile/mir-specialties');
    return ((json['specialties'] ?? []) as List)
        .map((e) => MirSpecialty.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Comprueba si un username está libre. El formato ya debe validarse en
  /// cliente (el backend devuelve 400 para formatos inválidos).
  Future<bool> checkUsername(String username) async {
    final json = await _request(
      'POST',
      '/api/profile/check-username',
      body: {'username': username},
    );
    return (json['available'] ?? false) as bool;
  }

  /// Envía el onboarding y marca onboarding_completed=true en el servidor.
  /// [medicalYear] admite 0 ("Médico") hasta 6, o null. universityId y
  /// customUniversity son excluyentes.
  Future<void> submitOnboarding({
    required String displayName,
    required String username,
    int? medicalYear,
    int? mirSpecialtyId,
    String? mainGoal,
    int? universityId,
    String? customUniversity,
    required bool profilePublic,
  }) async {
    await _request('POST', '/api/profile/onboarding', body: {
      'displayName': displayName,
      'username': username,
      'medicalYear': medicalYear,
      'mirSpecialtyId': mirSpecialtyId,
      'mainGoal': mainGoal,
      'universityId': universityId,
      'customUniversity': customUniversity,
      'profilePublic': profilePublic,
    });
  }

  Future<List<Deck>> getDecks() async {
    final json = await _request('GET', '/api/studio/decks');
    return ((json['decks'] ?? []) as List)
        .map((e) => Deck.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<StatsSummary> getStatsSummary() async {
    final json = await _request('GET', '/api/stats/summary');
    return StatsSummary.fromJson(json);
  }

  Future<ScoreDistribution> getScoreDistribution() async {
    final json = await _request('GET', '/api/stats/score-distribution');
    return ScoreDistribution.fromJson(json);
  }

  Future<ActivityHeatmap> getActivityHeatmap() async {
    final json = await _request('GET', '/api/stats/activity-heatmap');
    return ActivityHeatmap.fromJson(json);
  }

  // ==========================
  // PANEL / ANALÍTICA DE RENDIMIENTO
  // (misma infraestructura que la web /panel)
  // ==========================

  /// Serie temporal del progreso global (score + tiempo medio por daily).
  Future<TimeSeriesResponse> getTimeSeries() async {
    final json = await _request('GET', '/api/stats/timeseries');
    return TimeSeriesResponse.fromJson(json);
  }

  /// Esfuerzo (volumen y reparto acierto/fallo/blanco) en una ventana.
  Future<EffortResponse> getEffort(AnalyticsWindow window) async {
    final json =
        await _request('GET', '/api/analytics/effort?window=${window.query}');
    return EffortResponse.fromJson(json);
  }

  /// Mapa de calor por asignatura para una ventana y modo dados.
  Future<SubjectHeatmapResponse> getSubjectHeatmap(
    AnalyticsWindow window,
    AnalyticsMode mode,
  ) async {
    final params = <String>['window=${window.query}'];
    final m = mode.query;
    if (m != null) params.add('mode=$m');
    final json = await _request(
      'GET',
      '/api/analytics/heatmap/subjects?${params.join('&')}',
    );
    return SubjectHeatmapResponse.fromJson(json);
  }

  /// Mapa de calor por tema (drill-down de una asignatura).
  Future<TopicHeatmapResponse> getTopicHeatmap(
    int subjectId,
    AnalyticsWindow window,
    AnalyticsMode mode,
  ) async {
    final params = <String>['subjectId=$subjectId', 'window=${window.query}'];
    final m = mode.query;
    if (m != null) params.add('mode=$m');
    final json = await _request(
      'GET',
      '/api/analytics/heatmap/topics?${params.join('&')}',
    );
    return TopicHeatmapResponse.fromJson(json);
  }

  /// Evolución diaria de la precisión de una asignatura.
  Future<SubjectTrendResponse> getSubjectTrend(
    int subjectId,
    AnalyticsWindow window,
  ) async {
    final json = await _request(
      'GET',
      '/api/analytics/trend?subjectId=$subjectId&window=${window.query}',
    );
    return SubjectTrendResponse.fromJson(json);
  }

  /// Puntos débiles: las tres ventanas (semana/mes/global) en una respuesta.
  Future<WeakPointsResponse> getWeakPoints() async {
    final json = await _request('GET', '/api/analytics/weak-points');
    return WeakPointsResponse.fromJson(json);
  }

  // ==========================
  // STUDIO / MAZOS
  // ==========================

  Future<List<DeckCard>> getDeckItems(String deckId) async {
    final json = await _request('GET', '/api/studio/decks/$deckId/items');
    return ((json['items'] ?? []) as List)
        .map((e) => DeckCard.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> createDeck(String name) async {
    await _request('POST', '/api/studio/decks', body: {'name': name.trim()});
  }

  Future<void> deleteDeck(String deckId) async {
    await _request('POST', '/api/studio/decks/$deckId/delete');
  }

  Future<void> restoreDeck(String deckId) async {
    await _request('POST', '/api/studio/decks/$deckId/restore');
  }

  Future<List<DeckTrashEntry>> getDecksTrash() async {
    final json = await _request('GET', '/api/studio/decks/trash');
    return ((json['trash'] ?? []) as List)
        .map((e) => DeckTrashEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> removeDeckItem(String deckId, String itemId) async {
    await _request('DELETE', '/api/studio/decks/$deckId/items/$itemId');
  }

  Future<DeckSummary> getDeckSummary(String deckId) async {
    final json = await _request('GET', '/api/studio/decks/$deckId/summary');
    return DeckSummary.fromJson(
        (json['summary'] ?? const {}) as Map<String, dynamic>);
  }

  /// Crea o reutiliza una sesión de estudio. Devuelve el sessionId.
  Future<String> startDeckSession(String deckId, int limit) async {
    final json = await _request(
      'POST',
      '/api/studio/decks/$deckId/start-session',
      body: {'limit': limit},
    );
    return json['sessionId'].toString();
  }

  /// Siguiente item de la sesión. Devuelve null si la sesión terminó
  /// (done / limitReached / expired); el item en otro caso.
  Future<DeckCard?> getNextDeckItem(String deckId, String sessionId) async {
    final json = await _request(
      'GET',
      '/api/studio/decks/$deckId/next?sessionId=$sessionId',
    );
    if (json['item'] == null) return null;
    return DeckCard.fromJson(json['item'] as Map<String, dynamic>);
  }

  /// Registra el estudio de un item (la corrección la calcula el servidor).
  /// [selectedOption] es 1-based, como espera el backend.
  Future<bool> logDeckItem({
    required String deckId,
    required String deckItemId,
    required int selectedOption,
    required String sessionId,
  }) async {
    final json = await _request(
      'POST',
      '/api/studio/decks/$deckId/log',
      body: {
        'deckItemId': deckItemId,
        'selectedOption': selectedOption,
        'sessionId': sessionId,
      },
    );
    return (json['isCorrect'] ?? false) as bool;
  }

  Future<void> endDeckSession(String sessionId) async {
    await _request('POST', '/api/studio/sessions/$sessionId/end');
  }

  // ==========================
  // SIMULACRO
  // ==========================

  Future<List<SimSubject>> getSimulacroSubjects() async {
    final json = await _request('GET', '/api/simulacro/subjects');
    return ((json['subjects'] ?? []) as List)
        .map((e) => SimSubject.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<SimTopic>> getSimulacroTopics(List<int> subjectIds) async {
    if (subjectIds.isEmpty) return [];
    final json = await _request(
      'GET',
      '/api/simulacro/topics?subjects=${subjectIds.join(',')}',
    );
    return ((json['topics'] ?? []) as List)
        .map((e) => SimTopic.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Genera las preguntas del simulacro (sin respuesta correcta).
  Future<List<SimQuestion>> getSimulacroQuestions({
    required List<int> subjectIds,
    required List<int> topicIds,
    required int count,
  }) async {
    final json = await _request(
      'POST',
      '/api/simulacro/questions',
      body: {
        'subjectIds': subjectIds,
        'topicIds': topicIds,
        'count': count,
      },
    );
    return ((json['questions'] ?? []) as List)
        .map((e) => SimQuestion.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Corrige en el servidor y revela la opción correcta + explicación.
  ///
  /// Si se pasa [sessionId] (uuid, el mismo en toda la sesión de simulacro), el
  /// backend registra cada respuesta en user_responses de forma idempotente, de
  /// modo que los simulacros cuenten como preguntas hechas por el usuario.
  Future<List<SimResult>> checkSimulacro(
    List<Map<String, dynamic>> answers, {
    String? sessionId,
  }) async {
    if (answers.isEmpty) return [];
    final json = await _request(
      'POST',
      '/api/simulacro/check',
      body: {
        'answers': answers,
        if (sessionId != null) 'sessionId': sessionId,
      },
    );
    return ((json['results'] ?? []) as List)
        .map((e) => SimResult.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
