import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/config/app_config.dart';
import '../../../core/services/api_service.dart';
import '../models/versus_models.dart';

/// Acceso a las salas de Versus a través del BACKEND.
///
/// La app nunca lee las tablas `game_*` directamente: tienen RLS activada y sin
/// políticas, así que la anon key no ve nada. El estado en vivo llega por el
/// canal de broadcast (ver `versus_channel.dart`) y el backend es quien lo
/// emite; esto es solo el camino de ida (crear, entrar, responder) y el de
/// recuperación (`fetchState`).
class VersusApi {
  final ApiService _api;

  VersusApi(this._api);

  static const String _base = '/api/game';

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final token = await _api.validToken();
    final uri = Uri.parse('${AppConfig.apiBaseUrl}$_base$path');
    final headers = {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };

    final http.Response res = method == 'POST'
        ? await http
            .post(uri, headers: headers, body: jsonEncode(body ?? {}))
            .timeout(const Duration(seconds: 20))
        : await http.get(uri, headers: headers).timeout(
              const Duration(seconds: 20),
            );

    Map<String, dynamic> json;
    try {
      json = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      json = {};
    }

    if (res.statusCode >= 200 && res.statusCode < 300) return json;

    throw VersusException(
      res.statusCode,
      (json['error'] ?? 'Error del servidor (${res.statusCode})').toString(),
      code: json['code'] as String?,
    );
  }

  /// Crea la sala y mete dentro al anfitrión.
  Future<VersusRoomState> createRoom({
    String mode = VersusMode.classic,
    int? secondsPerQuestion,
    int? maxPlayers,
  }) async {
    final json = await _request('POST', '/rooms', body: {
      'mode': mode,
      'config': {
        if (secondsPerQuestion != null) 'secondsPerQuestion': secondsPerQuestion,
        if (maxPlayers != null) 'maxPlayers': maxPlayers,
      },
    });
    return VersusRoomState.fromJson(json);
  }

  Future<VersusRoomState> joinRoom(String pin) async {
    final json = await _request('POST', '/rooms/${_normalize(pin)}/join');
    return VersusRoomState.fromJson(json);
  }

  /// Estado completo de la sala. Es el único camino de recuperación para quien
  /// se reconecta a mitad de partida y se perdió los broadcasts.
  Future<VersusRoomState> fetchState(String pin) async {
    final json = await _request('GET', '/rooms/${_normalize(pin)}');
    return VersusRoomState.fromJson(json);
  }

  /// Cuántas preguntas hay de cada asignatura. Lo contesta el mismo codigo que
  /// luego elige las de la partida, asi que el numero que se enseña al
  /// configurarla es exactamente el que se va a jugar.
  Future<Map<int, int>> pool(List<int> subjectIds,
      {List<int> topicIds = const []}) async {
    if (subjectIds.isEmpty) return const {};

    final qs = StringBuffer('subjectIds=${subjectIds.join(',')}');
    if (topicIds.isNotEmpty) qs.write('&topicIds=${topicIds.join(',')}');

    final json = await _request('GET', '/pool?$qs');
    final bySubject = (json['bySubject'] as Map?) ?? const {};
    return bySubject.map((k, v) =>
        MapEntry(int.tryParse(k.toString()) ?? -1, (v as num?)?.toInt() ?? 0));
  }

  /// Solo el anfitrión. El arranque se anuncia por el canal, así que la
  /// pantalla cambia sola al llegar el evento.
  ///
  /// El modo y las vidas se eligen aquí y no al crear la sala, para que el
  /// anfitrión pueda cambiarlos mientras la gente va entrando.
  Future<int> startGame(
    String pin, {
    required List<int> subjectIds,
    required List<int> topicIds,
    required int count,
    String mode = VersusMode.classic,
    int lives = 1,
  }) async {
    final json = await _request('POST', '/rooms/${_normalize(pin)}/start',
        body: {
          'subjectIds': subjectIds,
          'topicIds': topicIds,
          'count': count,
          'mode': mode,
          'lives': lives,
        });
    return (json['total'] as num?)?.toInt() ?? 0;
  }

  /// Voto para repetir partida. La sala nueva la crea el SERVIDOR cuando han
  /// votado todos los que siguen delante de la pantalla, o al vencer el plazo;
  /// devuelve su PIN en cuanto existe (también a quien vota tarde, que se va
  /// derecho a ella en vez de quedarse votando algo ya decidido).
  Future<({List<String> votes, String? pin})> voteRematch(String pin) async {
    final json = await _request('POST', '/rooms/${_normalize(pin)}/rematch');
    return (
      votes: ((json['votes'] ?? const []) as List)
          .map((e) => e.toString())
          .toList(),
      pin: json['pin'] as String?,
    );
  }

  /// No devuelve si se acertó: la corrección llega por el canal en el revelado,
  /// cuando el servidor ha cerrado el plazo para todos.
  Future<bool> submitAnswer(String pin, int idx, int? selectedOption) async {
    final json = await _request('POST', '/rooms/${_normalize(pin)}/answer',
        body: {'idx': idx, 'selectedOption': selectedOption});
    return json['accepted'] == true;
  }

  /// La llama cualquier cliente al agotarse su cuenta atrás. El servidor decide
  /// si de verdad toca avanzar, así que llamarla de más es inofensivo.
  Future<void> advance(String pin) async {
    await _request('POST', '/rooms/${_normalize(pin)}/advance');
  }

  /// Pide pasar de pantalla durante el revelado. El revelado dura un minuto
  /// para que dé tiempo a leer la explicación, y se corta antes por MAYORÍA de
  /// los que siguen jugando: nadie decide solo, y los eliminados no meten prisa
  /// (el servidor les responde 409).
  Future<({int votes, int total})> voteContinue(String pin) async {
    final json = await _request('POST', '/rooms/${_normalize(pin)}/continue');
    return (
      votes: (json['votes'] as num?)?.toInt() ?? 0,
      total: (json['total'] as num?)?.toInt() ?? 0,
    );
  }

  /// Latido: le dice al servidor que este jugador sigue delante de la pantalla.
  /// Sin esto el servidor no distingue entre "está pensando la respuesta" y "se
  /// fue hace un minuto", y `game_tick()` deja de contarle a los 25 s: la ronda
  /// se come el reloj entero en vez de cerrarse en cuanto responden todos.
  ///
  /// Con [bye] envejece el latido a propósito, para que el resto no tenga que
  /// esperar los 25 s de gracia cuando la app se va a segundo plano. Es
  /// reversible: el siguiente latido devuelve al jugador a la ronda.
  Future<void> ping(String pin, {bool bye = false}) async {
    await _request('POST', '/rooms/${_normalize(pin)}/ping',
        body: bye ? {'bye': true} : null);
  }

  /// Devuelve true si la sala se ha cerrado (se fue el anfitrión).
  Future<bool> leave(String pin) async {
    final json = await _request('POST', '/rooms/${_normalize(pin)}/leave');
    return json['closed'] == true;
  }

  static String _normalize(String pin) => pin.trim().toUpperCase();
}

/// El backend responde con un `code` cuando el motivo importa para la pantalla:
/// sin username hay que mandar al perfil, no enseñar un error genérico.
class VersusException implements Exception {
  final int statusCode;
  final String message;
  final String? code;

  const VersusException(this.statusCode, this.message, {this.code});

  bool get usernameRequired => code == 'USERNAME_REQUIRED';
  bool get alreadyStarted => code == 'ALREADY_STARTED';
  bool get roomFull => code == 'ROOM_FULL';
  bool get notEnoughPlayers => code == 'NOT_ENOUGH_PLAYERS';
  bool get noQuestions => code == 'NO_QUESTIONS';

  /// La sala no existe o ya terminó.
  bool get notFound => statusCode == 404;

  @override
  String toString() => message;
}
