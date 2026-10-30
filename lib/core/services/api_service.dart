import 'dart:math';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/analytics.dart';
import '../data/mir_weights.dart';
import '../models/flashcards.dart';
import '../models/mazos_extra.dart';
import '../models/progreso_semana.dart';
import '../models/simulacro_a_medida.dart';
import '../models/models.dart';
import '../models/progress.dart';
import 'auth_service.dart';
import 'cliente_con_sesion.dart';

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

  /// [_client] con la renovación en 401 (ver [ClienteConSesion]). Es el que deben usar TODOS los
  /// clientes del backend con la sesión del usuario (se lo pasa main.dart), para que un token
  /// rechazado se renueve una vez y en un único sitio.
  late final http.Client clienteConSesion = ClienteConSesion(_client, renovar: tokenTrasRechazo);

  /// Se llama cuando la sesión muere de verdad (Supabase rechaza el refresh token): AuthProvider
  /// lo usa para volver al login en vez de dejar cada pantalla fallando con 401.
  void Function(String mensaje)? alPerderSesion;

  /// La renovación en curso: varias peticiones a la vez esperan a la misma, en vez de gastar cada
  /// una el refresh token (Supabase lo rota: el segundo uso podría fallar y cerrar la sesión).
  Future<AuthSession>? _renovando;

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
    if (s.isExpired) s = await _renovar(s);
    return s.accessToken;
  }

  Future<AuthSession> _renovar(AuthSession s) {
    final enCurso = _renovando;
    if (enCurso != null) return enCurso;
    final f = _authService.refresh(s).then((nueva) {
      session = nueva;
      return nueva;
    }, onError: (Object e, StackTrace st) {
      if (e is AuthException) {
        // Supabase ha dicho que no: la sesión ya no vale (refresh ya la ha borrado del disco).
        session = null;
        alPerderSesion?.call(e.message);
      }
      return Future<AuthSession>.error(e, st);
    });
    _renovando = f;
    f.then((_) => null, onError: (_) => null).whenComplete(() {
      if (identical(_renovando, f)) _renovando = null;
    });
    return f;
  }

  /// Tras un 401 con [rechazado]: el token con el que reintentar, o null si no hay.
  /// Si otra petición ya lo renovó, da el actual sin volver a renovar.
  Future<String?> tokenTrasRechazo(String rechazado) async {
    final s = session;
    if (s == null) return null;
    if (s.accessToken != rechazado) return s.accessToken;
    try {
      return (await _renovar(s)).accessToken;
    } catch (_) {
      return null;
    }
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
    final res = await clienteConSesion
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
    Object? galleryStyle = _absent,
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
      if (!identical(galleryStyle, _absent)) 'galleryStyle': galleryStyle,
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

  /// Nombre visible (el que ven los demás, p. ej. en el ranking del daily). El backend admite 2-16 letras,
  /// números y espacios y responde 400 con el motivo si no.
  Future<void> updateDisplayName(String displayName) async {
    await _request('POST', '/api/profile/display-name', body: {'displayName': displayName.trim()});
  }

  /// Borra la cuenta y TODOS sus datos (RGPD, derecho de supresión). El
  /// backend lo hace en una transacción: o se borra todo o nada. Tras esto
  /// la sesión ya no vale y hay que cerrarla.
  Future<void> deleteAccount() async {
    await _request(
      'POST',
      '/api/profile/delete-account',
      body: {'confirm': 'ELIMINAR'},
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

  /// Los mazos MÁS en cuáles está ya guardada [questionId], de una petición.
  ///
  /// `membership` va deckId -> itemId (el id de la fila dentro del mazo, que
  /// es lo que hace falta para poder quitarla). Si un mazo no aparece, la
  /// pregunta no está en él.
  ///
  /// Antes esto eran dos pasos en serie, y el segundo recorría paginando los
  /// items de TODOS los mazos hasta dar con la pregunta: decenas de
  /// peticiones cada vez que se abría la hoja de "guardar en un mazo", más
  /// cuantos más mazos tuvieras. El backend lo resuelve con una consulta
  /// indexada y anota cada mazo con `saved_item_id`.
  Future<({List<Deck> decks, Map<String, String> membership})> getDecksWithSaved(
    String questionId,
  ) async {
    final json = await _request(
      'GET',
      '/api/studio/decks?questionId=${Uri.encodeQueryComponent(questionId)}',
    );
    final raw = ((json['decks'] ?? []) as List).cast<Map<String, dynamic>>();
    return (
      decks: raw.map(Deck.fromJson).toList(),
      membership: {
        for (final d in raw)
          if (d['saved_item_id'] != null)
            d['id'].toString(): d['saved_item_id'].toString(),
      },
    );
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
  // NIVEL, XP, RACHA Y DESAFÍOS
  // ==========================

  /// Estado completo del sistema de niveles: nivel, XP, racha y los desafíos
  /// del día y de la semana.
  ///
  /// Es solo lectura, y es la ÚNICA llamada que hace falta para pintar toda la
  /// pantalla de progreso. No existe ningún endpoint para sumar XP: lo concede
  /// el servidor por su cuenta al responder preguntas o cerrar una sesión, así
  /// que después de terminar un daily, un simulacro o un mazo basta con volver
  /// a leer esto.
  Future<ProgressSnapshot> getProgress() async {
    final json = await _request('GET', '/api/progress');
    return ProgressSnapshot.fromJson(json);
  }

  /// Serie diaria de XP de los últimos 30 días, desglosada por origen.
  Future<List<XpHistoryDay>> getXpHistory() async {
    final json = await _request('GET', '/api/progress/history');
    return ((json['days'] ?? []) as List)
        .whereType<Map>()
        .map((e) => XpHistoryDay.fromJson(Map<String, dynamic>.from(e)))
        .toList();
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

  /// Preguntas repasadas en los últimos 30 días frente a los 30 anteriores, y en el año.
  Future<ProgresoMensual> getMonthlyProgress() async =>
      ProgresoMensual.fromJson(await _request('GET', '/api/analytics/monthly-progress'));

  /// La pregunta más fallada de la semana pasada, con lo que respondiste tú. Null si no hay datos.
  Future<MasFallada?> getMostFailedWeek() async =>
      MasFallada.fromJson(await _request('GET', '/api/stats/most-failed-week'));

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

  /// Tamaño de página del listado de preguntas. El backend admite hasta 50;
  /// se pide el máximo para bajar el número de viajes en mazos grandes.
  static const int deckItemsPageSize = 50;

  /// Una página de preguntas del mazo, con búsqueda opcional por enunciado.
  ///
  /// Antes esto pedía la primera página y devolvía solo la lista: en un mazo
  /// de 50 preguntas la pantalla enseñaba 20 y decía que eran todas.
  Future<DeckItemsPage> getDeckItems(
    String deckId, {
    int page = 1,
    String query = '',
  }) async {
    final params = <String, String>{
      'page': '$page',
      'pageSize': '$deckItemsPageSize',
      if (query.trim().isNotEmpty) 'q': query.trim(),
    };
    final qs = params.entries
        .map((e) =>
            '${e.key}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');

    final json =
        await _request('GET', '/api/studio/decks/$deckId/items?$qs');
    final pagination =
        (json['pagination'] ?? const {}) as Map<String, dynamic>;

    return DeckItemsPage(
      items: ((json['items'] ?? []) as List)
          .map((e) => DeckCard.fromJson(e as Map<String, dynamic>))
          .toList(),
      total: ((pagination['total'] ?? 0) as num).round(),
      page: ((pagination['page'] ?? page) as num).round(),
      totalPages: ((pagination['totalPages'] ?? 1) as num).round(),
    );
  }

  /// Asignaturas que componen el mazo, con cuántas preguntas aporta cada una.
  Future<List<DeckSubject>> getDeckSubjects(String deckId) async {
    final json = await _request('GET', '/api/studio/decks/$deckId/subjects');
    return ((json['subjects'] ?? []) as List)
        .map((e) => DeckSubject.fromJson(e as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => b.count.compareTo(a.count));
  }

  Future<void> createDeck(String name) async {
    await _request('POST', '/api/studio/decks', body: {'name': name.trim()});
  }

  /// Tope de la bio de un mazo. Lo fija el backend
  /// (`DECK_DESCRIPTION_MAX_LENGTH` en `src/routes/studio.js`) y la web usa el
  /// mismo, así que una bio escrita en un sitio vale en el otro.
  static const int maxDeckDescriptionLength = 120;

  /// Edita la bio corta y/o el preset de portada de un mazo.
  ///
  /// Persistido en base de datos (antes el gradiente solo vivía en el
  /// navegador de la web), así que la elección viaja entre dispositivos. El
  /// mazo automático de fallos responde 403: no admite personalización.
  Future<void> updateDeck(
    String deckId, {
    Object? description = _absent,
    Object? gradient = _absent,
  }) async {
    final body = <String, dynamic>{
      if (!identical(description, _absent)) 'description': description,
      if (!identical(gradient, _absent)) 'gradient': gradient,
    };
    if (body.isEmpty) return;
    await _request('POST', '/api/studio/decks/$deckId/update', body: body);
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

  /// Añade preguntas a un mazo.
  ///
  /// Es idempotente por diseño del backend: una pregunta que ya está en el
  /// mazo se ignora, y una que estaba en la papelera se restaura. Así que no
  /// hace falta comprobar antes si ya estaba.
  ///
  /// El mazo automático de fallos responde 403: se rellena solo.
  /// Añade preguntas a un mazo. Devuelve questionId -> itemId (el id de la
  /// fila dentro del mazo), que es lo que hace falta para poder quitarlas
  /// después sin volver a leer el mazo entero.
  Future<Map<String, String>> addDeckItems(
    String deckId,
    List<String> questionIds,
  ) async {
    if (questionIds.isEmpty) return const {};
    final json = await _request(
      'POST',
      '/api/studio/decks/$deckId/items',
      body: {'questionIds': questionIds},
    );
    final items = (json['items'] ?? const {}) as Map<String, dynamic>;
    return {
      for (final e in items.entries)
        if (e.value != null) e.key: e.value.toString(),
    };
  }

  Future<void> removeDeckItem(String deckId, String itemId) async {
    await _request('DELETE', '/api/studio/decks/$deckId/items/$itemId');
  }

  /// Preguntas quitadas del mazo que aún se pueden recuperar (24 h), la más reciente primero.
  Future<List<DeckItemTrashEntry>> getDeckItemsTrash(String deckId) async {
    final json = await _request('GET', '/api/studio/decks/$deckId/items/trash');
    final l = json['trash'];
    return ordenarPapelera(l is List
        ? l.whereType<Map>().map((e) => DeckItemTrashEntry.fromJson(Map<String, dynamic>.from(e))).toList()
        : const []);
  }

  /// Devuelve al mazo una pregunta de su papelera (400 si ya caducó).
  Future<void> restoreDeckItem(String deckId, String itemId) async {
    await _request('POST', '/api/studio/decks/$deckId/items/$itemId/restore');
  }

  /// Guarda el orden a mano de los mazos propios (`decks.position`), el mismo que se arrastra en la web.
  Future<void> reorderDecks(List<String> orderedDeckIds) async {
    await _request('POST', '/api/studio/decks/reorder', body: {'orderedDeckIds': orderedDeckIds});
  }

  /// Acierto por asignatura del mazo (último intento de cada pregunta).
  Future<List<SubjectPerformance>> getDeckSubjectPerformance(String deckId) async {
    final json = await _request('GET', '/api/studio/decks/$deckId/subject-performance');
    final l = json['subjects'];
    return l is List
        ? l.whereType<Map>().map((e) => SubjectPerformance.fromJson(Map<String, dynamic>.from(e))).toList()
        : const [];
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
  /// Siguiente carta de la sesión.
  ///
  /// [subjectId], [status] y [mode] son los filtros de la sesión: el backend
  /// los aplica en cada llamada (no al crear la sesión), así que viajan aquí.
  /// [mode] 'smart' activa Smart Review; cualquier otra cosa es el orden
  /// manual de siempre.
  Future<DeckCard?> getNextDeckItem(
    String deckId,
    String sessionId, {
    int? subjectId,
    String? status,
    String mode = 'normal',
  }) async {
    final params = <String, String>{
      'sessionId': sessionId,
      if (subjectId != null) 'subject': '$subjectId',
      if (status != null && status.isNotEmpty) 'status': status,
      'mode': mode == 'smart' ? 'smart' : 'normal',
    };
    final qs = params.entries
        .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');

    final json = await _request(
      'GET',
      '/api/studio/decks/$deckId/next?$qs',
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

  /// «Simulacro a tu medida»: el servidor elige [count] preguntas (10-40, por defecto 30) de los
  /// temas en que peor vas y manda el desglose por asignatura. Sin señal suficiente, `insufficient`.
  Future<PlanAMedida> getSimulacroAMedida({int count = 30}) async =>
      PlanAMedida.fromJson(await _request('POST', '/api/simulacro/smart', body: {'count': count}));

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
    int? level,
  }) async {
    await _request(
      'POST',
      '/api/studio/flashcard-decks/$deckId/cards',
      body: {
        'front': front.trim(),
        'back': back.trim(),
        if (topic != null && topic.trim().isNotEmpty) 'topic': topic.trim(),
        if (level != null) 'level': level,
      },
    );
  }

  /// Edita una tarjeta. El nivel solo se manda si cambia ([setLevel]); con
  /// `level: null` se le quita.
  Future<void> updateFlashcard({
    required String flashcardId,
    required String front,
    required String back,
    bool setLevel = false,
    int? level,
  }) async {
    await _request('PATCH', '/api/studio/flashcards/$flashcardId', body: {
      'front': front.trim(),
      'back': back.trim(),
      if (setLevel) 'level': level,
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

  /// Abre (o reutiliza) la sesión de estudio de un grupo con sus ajustes:
  /// niveles, escalera, temas, solo falladas/pendientes/nuevas y cuántas
  /// tarjetas. Los aplica la cola del servidor; ver flashcards_sesion.dart.
  Future<String> startFlashcardSession(
    String deckId,
    int limit, {
    Map<String, dynamic> opciones = const {},
  }) async {
    final json = await _request(
      'POST',
      '/api/studio/decks/$deckId/start-session',
      body: {'limit': limit, 'ladder': true, ...opciones},
    );
    final id = json['sessionId'];
    if (id is! String || id.isEmpty) {
      throw const ApiException(500, 'Respuesta inválida al iniciar la sesión');
    }
    return id;
  }

  /// Siguiente tarjeta de la cola, con los cuatro intervalos que le tocarían
  /// según el grado (los calcula el servidor al servirla).
  Future<FlashNext> getNextFlashcard(String deckId, String sessionId) async {
    final json = await _request(
      'GET',
      '/api/studio/flashcard-decks/$deckId/next?sessionId=${Uri.encodeQueryComponent(sessionId)}',
    );
    if (json['item'] is Map) {
      final item = Map<String, dynamic>.from(json['item'] as Map);
      final card = item['flashcard'] is Map ? Map<String, dynamic>.from(item['flashcard'] as Map) : const <String, dynamic>{};
      return FlashNext(
        FlashNextKind.card,
        Flashcard(
          itemId: (item['id'] as num?)?.toInt() ?? 0,
          flashcardId: '${card['id']}',
          front: (card['front'] ?? '') as String,
          back: (card['back'] ?? '') as String,
          topic: card['topic'] as String?,
          level: Flashcard.levelDe(card['level']),
          source: FlashSource.fromJson(card['source']),
        ),
        GradePreview.mapFromJson(item['preview']),
      );
    }
    if (json['expired'] == true) return const FlashNext(FlashNextKind.expired);
    if (json['limitReached'] == true) {
      return const FlashNext(FlashNextKind.limit);
    }
    return const FlashNext(FlashNextKind.done);
  }

  /// Registra el repaso de una tarjeta con su GRADO (1 Otra vez, 2 Difícil,
  /// 3 Bien, 4 Fácil). Va a la ruta propia de flashcards, que planifica con
  /// FSRS: la genérica de mazos (`/decks/:id/log`) espera un sí/no y usa la
  /// escalera de tres intervalos fijos, así que repasar desde la app dejaba la
  /// tarjeta con otra fecha que desde la web.
  Future<void> logFlashcard({
    required String deckId,
    required int deckItemId,
    required int grade,
    required String sessionId,
    int timeSpent = 0,
  }) async {
    await _request(
      'POST',
      '/api/studio/flashcard-decks/$deckId/log',
      body: {
        'deckItemId': deckItemId,
        'grade': grade,
        'sessionId': sessionId,
        'timeSpent': timeSpent,
      },
    );
  }

  /// Deshace el último repaso de la sesión y devuelve la tarjeta con los
  /// intervalos recalculados sobre el estado restaurado. Null si no hay nada
  /// que deshacer o el repaso es anterior al sistema de deshacer (409).
  Future<({int deckItemId, Map<int, GradePreview> preview})?> undoFlashcardReview(
    String deckId,
    String sessionId,
  ) async {
    try {
      final json = await _request(
        'POST',
        '/api/studio/flashcard-decks/$deckId/undo',
        body: {'sessionId': sessionId},
      );
      final id = json['deckItemId'];
      if (id is! num) return null;
      return (deckItemId: id.toInt(), preview: GradePreview.mapFromJson(json['preview']));
    } on ApiException catch (e) {
      if (e.statusCode == 409) return null;
      rethrow;
    }
  }

  /// Escalera de dificultad del grupo (la calcula el servidor).
  Future<Escalera> getFlashcardLadder(String deckId) async {
    final json = await _request('GET', '/api/studio/flashcard-decks/$deckId/ladder');
    return sanearEscalera(json);
  }

  /// Cuántas tarjetas vencen cada día de los próximos [days] (día de Madrid),
  /// con las ya vencidas aparte.
  Future<FlashForecast> getFlashcardForecast({int days = 30}) async {
    final json = await _request('GET', '/api/studio/flashcards/forecast?days=$days');
    return FlashForecast.fromJson(json);
  }

  /// Madurez y retención de todas las flashcards del usuario.
  Future<FlashStats> getFlashcardStats() async {
    final json = await _request('GET', '/api/studio/flashcards/stats');
    return FlashStats.fromJson(json);
  }

  /// Mueve tarjetas a otro grupo. Devuelve cuántas se movieron y cuántas ya
  /// estaban allí.
  Future<({int done, int alreadyThere})> moveFlashcards(List<int> itemIds, String targetDeckId) async {
    final json = await _request('POST', '/api/studio/flashcard-cards/move', body: {
      'itemIds': itemIds,
      'targetDeckId': targetDeckId,
    });
    return (done: (json['moved'] as num?)?.toInt() ?? 0, alreadyThere: (json['alreadyThere'] as num?)?.toInt() ?? 0);
  }

  /// Duplica tarjetas en otro grupo (las que ya existan allí con el mismo
  /// anverso y reverso no se duplican).
  Future<({int done, int alreadyThere})> copyFlashcards(List<int> itemIds, String targetDeckId) async {
    final json = await _request('POST', '/api/studio/flashcard-cards/copy', body: {
      'itemIds': itemIds,
      'targetDeckId': targetDeckId,
    });
    return (done: (json['copied'] as num?)?.toInt() ?? 0, alreadyThere: (json['alreadyThere'] as num?)?.toInt() ?? 0);
  }

  /// Borra tarjetas de golpe (recuperables 24 h).
  Future<int> bulkDeleteFlashcards(List<int> itemIds) async {
    final json = await _request('POST', '/api/studio/flashcard-cards/bulk-delete', body: {'itemIds': itemIds});
    return (json['deleted'] as num?)?.toInt() ?? 0;
  }

  /// Manda un grupo a la papelera (recuperable 24 h): el borrado genérico de mazos.
  Future<void> deleteFlashDeck(String deckId) async {
    await _request('POST', '/api/studio/decks/$deckId/delete');
  }
}
