import 'dart:math';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/analytics.dart';
import '../data/mir_weights.dart';
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
/// Centinela de "campo ausente": permite distinguir entre no mandar una clave
/// y mandarla a null, que en el editor de perfil significan cosas distintas
/// (dejar el dato como está vs. borrarlo).
const Object _absent = Object();

class ApiService {
  final AuthService _authService;

  /// Sesión activa (la fija AuthProvider al iniciar sesión o restaurarla).
  AuthSession? session;

  /// El cliente HTTP. Se puede inyectar para poder probar la capa de red sin
  /// salir a internet — que es como se encontró que `PATCH` se enviaba como
  /// `GET`.
  final http.Client _client;

  ApiService(this._authService, {http.Client? client})
      : _client = client ?? http.Client();

  /// Arma la petición con su verbo y su cuerpo. Un solo camino para todos los
  /// métodos: si hay que añadir uno nuevo, no hay que acordarse de tocar una
  /// cadena de `if`.
  static http.Request _buildRequest(
    String method,
    Uri uri,
    Map<String, String> headers,
    String? body,
  ) {
    final req = http.Request(method, uri)..headers.addAll(headers);
    if (body != null) req.body = body;
    return req;
  }

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

    // Un verbo desconocido NO puede caer en GET por descarte: así es como las
    // tres llamadas PATCH (guardar el perfil, renombrar un grupo de flashcards
    // y editar una tarjeta) acababan saliendo como GET y sin cuerpo, y el
    // guardado no hacía nada.
    const conCuerpo = {'POST', 'PATCH', 'PUT'};
    if (method != 'GET' && method != 'DELETE' && !conCuerpo.contains(method)) {
      throw ArgumentError.value(method, 'method', 'Verbo HTTP no soportado');
    }

    final payload = conCuerpo.contains(method) ? jsonEncode(body ?? {}) : null;
    final res = await _client
        .send(_buildRequest(method, uri, headers, payload))
        .timeout(const Duration(seconds: 25))
        .then(http.Response.fromStream);

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

  /// Tope de la bio. Lo fija el backend (`BIO_MAX_LENGTH` en
  /// `src/routes/profile.js`) y la web usa el mismo, así que una bio escrita
  /// en un sitio vale en el otro. Estaba puesto a 280 y el servidor rechazaba
  /// todo lo que pasara de aquí.
  static const int maxBioLength = 160;

  /// Días que hay que esperar entre dos cambios de username.
  static const int usernameCooldownDays = 30;

  /// Edición parcial de los datos del alta y de la bio.
  ///
  /// Es un endpoint aparte de `/onboarding` a propósito: aquel reescribe el
  /// perfil entero y vuelve a sellar `username_last_changed`, así que
  /// reutilizarlo para tocar el objetivo reiniciaría el bloqueo del username
  /// sin que el usuario lo haya pedido.
  ///
  /// Solo se mandan las claves presentes, y [universityId] y
  /// [customUniversity] son excluyentes.
  Future<void> updateAcademicProfile({
    Object? mainGoal = _absent,
    Object? medicalYear = _absent,
    Object? mirSpecialtyId = _absent,
    Object? universityId = _absent,
    Object? customUniversity = _absent,
    Object? profilePublic = _absent,
    Object? bio = _absent,
  }) async {
    final body = <String, dynamic>{
      if (!identical(mainGoal, _absent)) 'mainGoal': mainGoal,
      if (!identical(medicalYear, _absent)) 'medicalYear': medicalYear,
      if (!identical(mirSpecialtyId, _absent)) 'mirSpecialtyId': mirSpecialtyId,
      if (!identical(universityId, _absent)) 'universityId': universityId,
      if (!identical(customUniversity, _absent))
        'customUniversity': customUniversity,
      if (!identical(profilePublic, _absent)) 'profilePublic': profilePublic,
      if (!identical(bio, _absent)) 'bio': bio,
    };
    if (body.isEmpty) return;
    await _request('PATCH', '/api/profile/academic', body: body);
  }

  /// Cambia el username. El backend lo bloquea 30 días desde el último
  /// cambio y devuelve 403 si aún no toca, o 409 si ya está cogido.
  Future<void> updateUsername(String username) async {
    await _request(
      'POST',
      '/api/profile/username',
      body: {'username': username.toLowerCase().trim()},
    );
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

  /// Genera las preguntas con el reparto ponderado por peso en el MIR.
  ///
  /// El endpoint solo admite un total y una lista de asignaturas, no cuotas
  /// por asignatura, así que la composición se hace aquí: una petición por
  /// asignatura con su cuota, en paralelo, y luego se baraja la unión — si no,
  /// las preguntas saldrían agrupadas por asignatura.
  ///
  /// Es la misma estrategia que usa la web en `fetchSimulacroQuestions`.
  Future<List<SimQuestion>> getSimulacroQuestionsWeighted(
    List<MirAllocation> allocations,
  ) async {
    final wanted = allocations.where((a) => a.count > 0).toList();
    if (wanted.isEmpty) return [];

    final batches = await Future.wait([
      for (final a in wanted)
        getSimulacroQuestions(
          subjectIds: [a.subjectId],
          topicIds: const [],
          count: a.count,
          // Que falle una asignatura no debe tumbar el simulacro entero.
        ).catchError((_) => <SimQuestion>[]),
    ]);

    final all = [for (final batch in batches) ...batch];
    all.shuffle(Random());
    return all;
  }

  /// Cierra la sesión de simulacro para que entre en el historial.
  ///
  /// El backend cuenta las respuestas realmente persistidas (no lo que diga
  /// el cliente) y solo guarda la fila si son >=50, así que es idempotente y
  /// "best-effort": si falla, el usuario ve sus resultados igual.
  Future<void> finishSimulacro(String sessionId, String mode) async {
    await _request(
      'POST',
      '/api/simulacro/finish',
      body: {'sessionId': sessionId, 'mode': mode},
    );
  }

  /// Historial de simulacros guardados (los completados con >=50 preguntas).
  Future<List<SimSession>> getSimulacroHistory({
    int limit = 20,
    int offset = 0,
  }) async {
    final json = await _request(
      'GET',
      '/api/simulacro/history?limit=$limit&offset=$offset',
    );
    return ((json['sessions'] ?? []) as List)
        .map((e) => SimSession.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Agregado por día para el mapa de calor del historial.
  Future<List<SimCalendarDay>> getSimulacroCalendar({
    required DateTime from,
    required DateTime to,
  }) async {
    String fmt(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
    final json = await _request(
      'GET',
      '/api/simulacro/calendar?from=${fmt(from)}&to=${fmt(to)}',
    );
    return ((json['days'] ?? []) as List)
        .map((e) => SimCalendarDay.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Repaso de un simulacro pasado, en la forma que espera la rejilla de
  /// resultados (preguntas + lo que se respondió + la corrección).
  Future<SimHistoryDetail> getSimulacroHistoryDetail(String sessionId) async {
    final json = await _request('GET', '/api/simulacro/history/$sessionId');
    final questions = ((json['questions'] ?? []) as List)
        .map((e) => SimQuestion.fromJson(e as Map<String, dynamic>))
        .toList();
    final answers = ((json['answers'] ?? []) as List)
        .map((e) => e is num ? e.toInt() : null)
        .cast<int?>()
        .toList();
    final results = ((json['results'] ?? []) as List)
        .map((e) => e == null
            ? null
            : SimResult.fromJson(e as Map<String, dynamic>))
        .cast<SimResult?>()
        .toList();
    return SimHistoryDetail(
      questions: questions,
      answers: answers,
      results: results,
    );
  }

  // ==========================
  // FLASHCARDS PERSONALIZADAS
  // ==========================

  /// Tope del backend, para avisar antes de que rechace la tarjeta.
  static const int maxFlashcardsPerDeck = 500;
  static const int maxFlashcardChars = 5000;

  Future<List<FlashDeck>> getFlashDecks() async {
    final json = await _request('GET', '/api/studio/flashcard-decks');
    return ((json['decks'] ?? []) as List)
        .map((e) => FlashDeck.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> createFlashDeck(String name, {String? description}) async {
    await _request('POST', '/api/studio/flashcard-decks', body: {
      'name': name.trim(),
      if (description != null && description.trim().isNotEmpty)
        'description': description.trim(),
    });
  }

  Future<void> updateFlashDeck(
    String deckId, {
    String? name,
    String? description,
  }) async {
    await _request('PATCH', '/api/studio/flashcard-decks/$deckId', body: {
      if (name != null) 'name': name.trim(),
      if (description != null) 'description': description.trim(),
    });
  }

  Future<List<Flashcard>> getFlashcards(String deckId) async {
    final json =
        await _request('GET', '/api/studio/flashcard-decks/$deckId/cards');
    return ((json['cards'] ?? []) as List)
        .map((e) => Flashcard.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> createFlashcard({
    required String deckId,
    required String front,
    required String back,
    String? topic,
  }) async {
    await _request(
      'POST',
      '/api/studio/flashcard-decks/$deckId/cards',
      body: {
        'front': front.trim(),
        'back': back.trim(),
        if (topic != null && topic.trim().isNotEmpty) 'topic': topic.trim(),
      },
    );
  }

  Future<void> updateFlashcard({
    required String flashcardId,
    required String front,
    required String back,
  }) async {
    await _request('PATCH', '/api/studio/flashcards/$flashcardId', body: {
      'front': front.trim(),
      'back': back.trim(),
    });
  }

  Future<void> deleteFlashcard({
    required String deckId,
    required int itemId,
  }) async {
    await _request(
      'DELETE',
      '/api/studio/flashcard-decks/$deckId/cards/$itemId',
    );
  }

  /// Siguiente tarjeta de la cola. El estudio arranca con
  /// [startDeckSession] y se cierra con [endDeckSession], que son los mismos
  /// del motor SRS de los mazos.
  Future<FlashNext> getNextFlashcard(String deckId, String sessionId) async {
    final json = await _request(
      'GET',
      '/api/studio/flashcard-decks/$deckId/next?sessionId=$sessionId',
    );
    if (json['item'] != null) {
      final item = json['item'] as Map<String, dynamic>;
      final card = (item['flashcard'] ?? const {}) as Map<String, dynamic>;
      return FlashNext(
        FlashNextKind.card,
        Flashcard(
          itemId: (item['id'] as num?)?.toInt() ?? 0,
          flashcardId: '${card['id']}',
          front: (card['front'] ?? '') as String,
          back: (card['back'] ?? '') as String,
        ),
      );
    }
    if (json['expired'] == true) return const FlashNext(FlashNextKind.expired);
    if (json['limitReached'] == true) {
      return const FlashNext(FlashNextKind.limit);
    }
    return const FlashNext(FlashNextKind.done);
  }

  /// Registra el repaso de una tarjeta. A diferencia de los mazos de
  /// preguntas, aquí la corrección la decide el usuario ("¿me la sabía?"),
  /// así que se manda `isCorrect` en vez de la opción elegida.
  Future<void> logFlashcard({
    required String deckId,
    required int deckItemId,
    required bool isCorrect,
    required String sessionId,
  }) async {
    await _request(
      'POST',
      '/api/studio/decks/$deckId/log',
      body: {
        'deckItemId': deckItemId,
        'isCorrect': isCorrect,
        'sessionId': sessionId,
      },
    );
  }
}
