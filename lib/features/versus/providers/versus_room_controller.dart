import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../models/versus_models.dart';
import '../services/versus_api.dart';
import '../services/versus_channel.dart';

/// Estado en vivo de UNA sala de Versus.
///
/// No decide nada del juego: refleja lo que dice el servidor y corrige el
/// reloj. Las dos únicas iniciativas que toma son pedir que la partida avance
/// cuando vence una fase (el servidor decide si de verdad toca) y
/// resincronizarse cuando se recupera la conexión o la app vuelve del segundo
/// plano.
///
/// Equivale al hook `useVersusRoom` de la web, con dos añadidos que en móvil no
/// son opcionales: el ciclo de vida de la app (Android congela los temporizadores
/// al irse a segundo plano) y guardar aquí la respuesta elegida, para que un
/// rebuild de la pantalla no la pierda.
class VersusRoomController extends ChangeNotifier with WidgetsBindingObserver {
  final VersusApi api;
  final String pin;

  VersusRoomController({required this.api, required this.pin});

  VersusRoom? _room;
  VersusRoom? get room => _room;
  String? get status => _room?.status;

  List<VersusPlayer> _players = const [];
  List<VersusPlayer> get players => _players;

  String? _playerId;
  String? get playerId => _playerId;

  bool _isHost = false;
  bool get isHost => _isHost;

  VersusPhase? _phase;
  VersusPhase? get phase => _phase;

  /// La última pregunta recibida. `picks` y `reveal` no reenvían el enunciado
  /// ni las opciones (serían los mismos bytes en cada fase), así que hay que
  /// conservarla.
  VersusQuestionPhase? _question;
  VersusQuestionPhase? get question => _question;

  /// Cuántos han respondido ya la pregunta en curso, sin decir qué.
  int? _answeredCount;
  int? _aliveCount;
  int? get answeredCount => _answeredCount;
  int? get aliveCount => _aliveCount;

  /// Diferencia entre el reloj del servidor y el del móvil, en ms.
  int _clockOffset = 0;
  int get clockOffset => _clockOffset;

  bool _connected = false;
  bool get connected => _connected;

  bool _closed = false;
  bool get closed => _closed;

  /// La partida ha terminado con normalidad (hay podio que enseñar). Es
  /// distinto de [closed], que es la sala cerrada sin final.
  bool get finished => _phase is VersusEndedPhase;

  bool _loading = true;
  bool get loading => _loading;

  String? _error;
  String? get error => _error;

  // Respuesta de ESTE jugador en la ronda en curso. `answered` va aparte de
  // `selected` porque se puede haber respondido en blanco.
  int? _selected;
  bool _answered = false;
  int? _answeredIdx;
  bool _sending = false;

  int? get selected => _selected;
  bool get answered => _answered;
  bool get sending => _sending;

  VersusChannel? _channel;
  Timer? _nudgeTimer;
  String? _nudgedFor;
  Timer? _heartbeat;
  bool _disposed = false;

  /// Cada cuánto se late. El servidor da 25 s de gracia, así que esta cadencia
  /// tolera perder dos latidos seguidos sin que a uno le den por ausente.
  static const Duration _heartbeatEvery = Duration(seconds: 8);

  /// Reloj del SERVIDOR, que es contra el que se miden todos los plazos.
  int get serverNow => DateTime.now().millisecondsSinceEpoch + _clockOffset;

  // ==========================
  // Ciclo de vida
  // ==========================

  Future<void> start() async {
    WidgetsBinding.instance.addObserver(this);
    _channel = VersusChannel(
      pin: pin,
      onEvent: _onEvent,
      onConnectionChange: _onConnectionChange,
    )..connect();
    _startHeartbeat();
    await refresh();
  }

  void _startHeartbeat() {
    _beat();
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(_heartbeatEvery, (_) => _beat());
  }

  /// Que falle no rompe nada: el peor caso es que el servidor deje de contar a
  /// este jugador y la ronda no le espere. También devuelve 404 mientras el
  /// backend con `/ping` no esté desplegado, y eso no debe ensuciar la pantalla.
  /// Se sigue latiendo EN EL PODIO: la votación de la revancha se cierra cuando
  /// han votado todos los que siguen delante de la pantalla, así que dejar de
  /// latir ahí es justo lo que haría que a uno no le esperasen para votar.
  void _beat() {
    if (_disposed || _closed) return;
    unawaited(api.ping(pin).catchError((_) {}));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed || _closed) return;

    if (state == AppLifecycleState.resumed) {
      // Android estrangula los temporizadores en segundo plano: al volver puede
      // haber pasado media partida. La única salida es preguntar el estado.
      _beat();
      unawaited(refresh());
      return;
    }

    // Irse a segundo plano equivale a esconder la pestaña en la web: se avisa
    // para que el resto no espere los 25 s de gracia. No es abandonar la
    // partida — al volver, el latido de arriba devuelve a este jugador a la
    // ronda sin que nadie tenga que rehabilitarle.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      if (!finished) unawaited(api.ping(pin, bye: true).catchError((_) {}));
    }
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _nudgeTimer?.cancel();
    _heartbeat?.cancel();
    for (final timer in _noticeTimers) {
      timer.cancel();
    }
    _noticeTimers.clear();
    unawaited(_channel?.dispose());
    _channel = null;
    super.dispose();
  }

  void _onConnectionChange(bool connected) {
    if (_disposed) return;
    _connected = connected;
    notifyListeners();

    // Al (re)suscribirse hay que volver a pedir el estado: mientras el socket
    // estuvo caído pudieron pasar rondas enteras y esos eventos se perdieron.
    if (connected && !_closed) unawaited(refresh());
  }

  // ==========================
  // Estado
  // ==========================

  /// Por qué no se pudo entrar en la sala al abrirla por PIN. Null = se entró
  /// (o ya se estaba dentro).
  String? _joinError;
  String? get joinError => _joinError;

  /// Entrar es una acción aparte de leer, y hasta ahora solo la hacía la
  /// pantalla de entrada con su formulario. Quien abre una sala por PIN sin
  /// pasar por ahí —el salto a la revancha, sobre todo— se quedaba mirando el
  /// lobby sin estar dentro: no salía en la lista y la partida empezaba sin él.
  /// Se intenta UNA vez; si la sala ya arrancó o está llena, se cuenta y no se
  /// reintenta.
  bool _joinTried = false;

  Future<void> refresh() async {
    if (_disposed || _closed) return;
    try {
      var state = await api.fetchState(pin);
      if (_disposed || _closed) return;

      if (state.playerId == null &&
          !_joinTried &&
          state.room.status == VersusStatus.lobby) {
        _joinTried = true;
        try {
          state = await api.joinRoom(pin);
          _joinError = null;
        } on VersusException catch (e) {
          // Se sigue con lo que devolvió el GET: mirar la sala sin poder entrar
          // es mejor que una pantalla de error, y el motivo se enseña arriba.
          _joinError = e.message;
        }
        if (_disposed || _closed) return;
      }

      _room = state.room;
      // El playerId se fija ANTES de la plantilla: `_applyPlayers` lo usa para
      // no avisar a uno de su propia desconexión.
      _playerId = state.playerId;
      _applyPlayers(state.players);
      _isHost = state.isHost;
      _error = null;

      final phase = state.phase;
      if (phase != null) {
        _applyPhase(phase);
      }

      // Lo que ya respondió en la ronda en curso. Sin esto, quien vuelve a
      // mitad de pregunta vería las opciones como si no hubiera contestado,
      // volvería a pulsar y el servidor le rechazaría el duplicado.
      final idx = state.room.currentIndex;
      if (state.answered && idx >= 0 && _answeredIdx != idx) {
        _answeredIdx = idx;
        _answered = true;
        _selected = state.mySelection;
      }
    } on VersusException catch (e) {
      if (_disposed) return;
      // 404 = la sala ya no existe (la cerró el anfitrión o caducó). Con el
      // podio ya recibido no es un cierre: los resultados se quedan donde
      // están en vez de sustituirse por "la sala se ha cerrado".
      if (e.notFound) {
        if (!finished) _closed = true;
      } else {
        _error = e.message;
      }
    } catch (_) {
      if (_disposed) return;
      _error = 'No se pudo cargar la sala.';
    } finally {
      if (!_disposed) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  void _onEvent(String event, Map<String, dynamic> payload) {
    if (_disposed || _closed) return;

    if (event == 'room_closed') {
      _closed = true;
      _connected = false;
      _nudgeTimer?.cancel();
      notifyListeners();
      return;
    }

    if (event == 'players') {
      final list = payload['players'];
      if (list is List) {
        _applyPlayers(list
            .map((e) =>
                VersusPlayer.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList());
      }
      final status = payload['status'];
      if (status is String) _room = _room?.copyWith(status: status);
      notifyListeners();
      return;
    }

    // Si el anfitrión desaparece del lobby, el servidor traspasa el rol. Llega
    // el id de JUGADOR del nuevo anfitrión, no su user_id: es lo único con lo
    // que este cliente puede reconocerse a sí mismo.
    if (event == 'host_changed') {
      final hostPlayerId = payload['hostPlayerId'] as String?;
      final wasHost = _isHost;
      _isHost = _playerId != null && _playerId == hostPlayerId;

      if (_isHost && !wasHost) {
        _pushNotice(
          id: 'host-$hostPlayerId',
          text: 'Ahora eres el anfitrión: te toca empezar la partida.',
          kind: VersusNoticeKind.host,
        );
      } else if (!_isHost) {
        final who = (payload['hostNickname'] as String?) ?? 'Otro jugador';
        _pushNotice(
          id: 'host-$hostPlayerId',
          text: '$who es ahora el anfitrión.',
          kind: VersusNoticeKind.host,
        );
      }

      notifyListeners();
      return;
    }

    if (event == 'progress') {
      _answeredCount = (payload['answered'] as num?)?.toInt();
      _aliveCount = (payload['total'] as num?)?.toInt();
      notifyListeners();
      return;
    }

    // Alguien ha pedido pasar de pantalla. Solo cambia el recuento: quien
    // decide si de verdad se avanza es game_tick al comprobar la mayoría.
    if (event == 'continue') {
      final phase = _phase;
      final idx = (payload['idx'] as num?)?.toInt();
      if (phase is VersusRevealPhase && idx == phase.idx) {
        _phase = phase.copyWithContinue(
          votes: (payload['votes'] as num?)?.toInt(),
          total: (payload['total'] as num?)?.toInt(),
        );
        notifyListeners();
      }
      return;
    }

    if (event == 'rematch') {
      _mergeVotes(payload['votes']);
      _rematchUntil = (payload['rematchUntil'] as num?)?.toInt() ?? _rematchUntil;
      final serverNow = (payload['serverNow'] as num?)?.toInt();
      if (serverNow != null) {
        _clockOffset = serverNow - DateTime.now().millisecondsSinceEpoch;
      }
      notifyListeners();
      return;
    }

    // La sala de revancha ya existe: la pantalla salta sola a ella. Los que
    // votaron entran ya dentro, con su apodo y su avatar, sin pasarse el código.
    if (event == 'rematch_ready') {
      final next = payload['pin'] as String?;
      if (next != null && next.isNotEmpty) {
        _rematchPin = next;
        notifyListeners();
      }
      return;
    }

    final phase = VersusPhase.fromJson(event, payload);
    if (phase == null) return;

    // Arranque de la partida. El modo y las vidas se fijan en /start y NO viajan
    // en los eventos de fase, así que hay que ir a buscarlos: sin esto la sala
    // que tiene el cliente se queda en 'classic' toda la partida.
    final justStarted = _room?.status == VersusStatus.lobby;

    _applyPhase(phase);

    // El estado de la sala viaja en el propio evento, así que la pantalla no
    // depende de que llegue antes el refresco por HTTP.
    final status = payload['status'];
    if (status is String) _room = _room?.copyWith(status: status);

    notifyListeners();

    if (justStarted) unawaited(refresh());
  }

  void _applyPhase(VersusPhase phase) {
    _clockOffset = phase.serverNow - DateTime.now().millisecondsSinceEpoch;
    _phase = phase;

    if (phase is VersusEndedPhase) {
      _mergeVotes(phase.votes);
      _rematchUntil ??= phase.rematchUntil;
      _rematchPin ??= phase.rematchPin;
    }


    if (phase is VersusQuestionPhase) {
      _question = phase;
      // Solo al CAMBIAR de pregunta se limpia la selección: si se limpiara con
      // cada evento, un refresco a mitad de ronda borraría lo ya pulsado.
      if (_answeredIdx != phase.idx) {
        _selected = null;
        _answered = false;
        _sending = false;
      }
      _answeredCount = null;
      _aliveCount = null;
    }

    // 'picks' y 'reveal' traen también el enunciado y las opciones. Solo hacen
    // falta cuando no se tiene la pregunta de esta ronda, que es justo el caso
    // de quien se reconecta a mitad de ella: antes se quedaba con la tarjeta
    // vacía y la corrección señalando a ninguna parte.
    final content = switch (phase) {
      VersusPicksPhase p => p.content,
      VersusRevealPhase p => p.content,
      _ => null,
    };
    if (content != null && _question?.idx != phase.idx) {
      _question = content.asQuestion(idx: phase.idx, serverNow: phase.serverNow);
    }

    _scheduleNudge(phase);
  }

  // ==========================
  // Avance de fase
  // ==========================

  /// Cuando vence el plazo de la fase, este cliente pide avanzar UNA vez. El
  /// servidor decide si de verdad toca, así que si varios lo piden a la vez
  /// solo uno provoca el cambio. El jitter evita que lleguen todos en el mismo
  /// milisegundo.
  void _scheduleNudge(VersusPhase phase) {
    final endsAt = phase.endsAt;
    if (endsAt == null) return;

    final key = '${phase.runtimeType}:${phase.idx}';
    if (_nudgedFor == key) return;

    _nudgeTimer?.cancel();
    final delay = endsAt - serverNow + math.Random().nextInt(400);
    _nudgeTimer = Timer(
      Duration(milliseconds: math.max(delay, 0)),
      () {
        if (_disposed || _closed) return;
        _nudgedFor = key;
        // Que falle no rompe nada: el barrido del servidor es el respaldo.
        unawaited(api.advance(pin).catchError((_) {}));
      },
    );
  }

  // ==========================
  // Acciones del jugador
  // ==========================

  /// Bloqueo al pulsar, estilo Kahoot: sin cambios de última milésima, y así el
  /// tiempo de respuesta significa algo.
  Future<void> answer(int optionIndex) async {
    final phase = _phase;
    if (phase is! VersusQuestionPhase) return;
    if (_answered || _sending || _closed) return;
    // Durante la cuenta atrás la pregunta aún no es visible y el servidor
    // rechazaría la respuesta.
    if (serverNow < phase.startsAt) return;

    _selected = optionIndex;
    _answered = true;
    _answeredIdx = phase.idx;
    _sending = true;
    notifyListeners();

    try {
      await api.submitAnswer(pin, phase.idx, optionIndex);
    } catch (_) {
      // Si el servidor la rechaza (fuera de tiempo, ronda ya cerrada) se
      // devuelve el control en vez de dejar la pantalla bloqueada en falso.
      if (_disposed) return;
      _selected = null;
      _answered = false;
      _answeredIdx = null;
    } finally {
      if (!_disposed) {
        _sending = false;
        notifyListeners();
      }
    }
  }

  Future<int> startGame({
    required List<int> subjectIds,
    required List<int> topicIds,
    required int count,
    String mode = VersusMode.classic,
    int lives = 1,
  }) {
    return api.startGame(
      pin,
      subjectIds: subjectIds,
      topicIds: topicIds,
      count: count,
      mode: mode,
      lives: lives,
    );
  }

  // ==========================
  // Continuar (saltar el revelado)
  // ==========================

  /// Rondas en las que ESTE jugador ya ha pedido continuar. El servidor solo
  /// devuelve el recuento, no quién ha votado, así que hay que recordarlo aquí
  /// para no ofrecer un botón que ya no hace nada.
  final Set<int> _continueVoted = {};
  bool _votingContinue = false;

  bool get votingContinue => _votingContinue;

  bool votedContinue(int idx) => _continueVoted.contains(idx);

  /// Los eliminados miran: pueden esperar, pero no meter prisa a quien juega
  /// (el servidor les responde 409).
  bool get canVoteContinue => !amEliminated;

  Future<void> voteContinue() async {
    final phase = _phase;
    if (phase is! VersusRevealPhase) return;
    if (_votingContinue || _disposed || votedContinue(phase.idx)) return;
    if (!canVoteContinue) return;

    _votingContinue = true;
    _continueVoted.add(phase.idx);
    notifyListeners();

    try {
      final result = await api.voteContinue(pin);
      if (_disposed) return;
      final current = _phase;
      if (current is VersusRevealPhase && current.idx == phase.idx) {
        _phase = current.copyWithContinue(
          votes: result.votes,
          total: result.total,
        );
      }
    } catch (_) {
      // Si el servidor lo rechaza (ronda ya cerrada, eliminado) se devuelve el
      // botón en vez de dejarlo marcado en falso.
      if (!_disposed) _continueVoted.remove(phase.idx);
    } finally {
      if (!_disposed) {
        _votingContinue = false;
        notifyListeners();
      }
    }
  }

  // ==========================
  // Revancha
  // ==========================

  List<String> _rematchVotes = const [];
  int? _rematchUntil;
  String? _rematchPin;
  bool _votingRematch = false;

  List<String> get rematchVotes => _rematchVotes;

  /// Instante (reloj del servidor) en que se cierra la votación.
  int? get rematchUntil => _rematchUntil;

  /// PIN de la sala de revancha en cuanto existe. La pantalla salta sola.
  String? get rematchPin => _rematchPin;

  bool get votedRematch =>
      _playerId != null && _rematchVotes.contains(_playerId);
  bool get votingRematch => _votingRematch;

  /// Los votos solo crecen, así que se unen en vez de sustituirse: un refresco
  /// que llegue tarde no debe hacer bajar el contador que ya se veía.
  void _mergeVotes(dynamic incoming) {
    if (incoming is! List) return;
    final merged = {..._rematchVotes, ...incoming.map((e) => e.toString())};
    _rematchVotes = merged.toList();
  }

  Future<void> voteRematch() async {
    if (_votingRematch || votedRematch || _disposed) return;
    _votingRematch = true;
    notifyListeners();
    try {
      final result = await api.voteRematch(pin);
      if (_disposed) return;
      _mergeVotes(result.votes);
      // Puede que fuera el último que faltaba y la sala ya exista.
      if (result.pin != null && result.pin!.isNotEmpty) {
        _rematchPin = result.pin;
      }
    } catch (_) {
      // Que falle un voto no rompe el podio; se puede volver a pulsar.
    } finally {
      if (!_disposed) {
        _votingRematch = false;
        notifyListeners();
      }
    }
  }

  /// Salir de la sala. Si se va el anfitrión, el backend la cierra entera.
  Future<void> leave() async {
    try {
      await api.leave(pin);
    } catch (_) {
      // Salir es best-effort: la sala caduca sola y el tick deja de esperarle.
    }
  }

  // ==========================
  // Golpes de Guardia
  // ==========================

  VersusStrike? _strike;
  VersusStrike? get strike => _strike;

  /// El momento ya se ha reproducido. Lo llama la pantalla al terminar la
  /// animación, para que no se repita al siguiente rebuild.
  void consumeStrike() {
    if (_strike == null) return;
    _strike = null;
    notifyListeners();
  }

  /// Traduce lo que ha cambiado en la plantilla a "qué me ha pasado a mí" y a
  /// avisos para el resto.
  ///
  /// Se mira la PLANTILLA (las vidas que de verdad tiene cada uno) y no el
  /// `wounded` del revelado, porque ese campo miente cuando fallan todos: el
  /// backend descuenta la vida igualmente pero lo devuelve vacío, así que el
  /// HUD se agitaba y no salía ningún aviso. Comparar vidas es además inmune a
  /// que el revelado llegue dos veces, porque la segunda ya no hay diferencia
  /// que detectar.
  void _detectCasualties(
    Map<String, int?> livesBefore,
    Map<String, bool> downBefore,
    List<VersusPlayer> next,
  ) {
    final myId = _playerId;

    for (final player in next) {
      final before = livesBefore[player.id];
      final now = player.lives;
      final lostLife = before != null && now != null && now < before;
      final justFell = downBefore[player.id] == false && player.eliminated;

      if (!lostLife && !justFell) continue;

      if (player.id == myId) {
        _strike = VersusStrike(
          kind: justFell ? VersusStrikeKind.knockout : VersusStrikeKind.hit,
          idx: _room?.currentIndex ?? 0,
          livesLeft: now ?? 0,
        );
        continue;
      }

      // Lo que le pasa al resto: es lo que hace que se note que hay alguien
      // más al otro lado y no un cuestionario en solitario.
      _pushNotice(
        id: '${justFell ? 'down' : 'wound'}-${player.id}-${_room?.currentIndex}',
        text: justFell
            ? '${player.nickname} ha caído'
            : '${player.nickname} pierde una vida',
        kind: justFell ? VersusNoticeKind.down : VersusNoticeKind.wounded,
        avatarId: player.avatarId,
      );

      // Que caiga un rival solo se celebra si a uno no le ha pasado nada.
      if (justFell && _strike == null) {
        _strike = VersusStrike(
          kind: VersusStrikeKind.rivalDown,
          idx: _room?.currentIndex ?? 0,
          nickname: player.nickname,
        );
      }
    }
  }

  // ==========================
  // Avisos de presencia
  // ==========================

  final List<VersusNotice> _notices = [];
  List<VersusNotice> get notices => List.unmodifiable(_notices);

  final List<Timer> _noticeTimers = [];

  /// Cómo estaba cada jugador la última vez. `null` = todavía no hay foto.
  Map<String, VersusNoticeKind>? _presence;

  static const Duration _noticeVisible = Duration(seconds: 4);
  static const Duration _noticeFade = Duration(milliseconds: 200);

  /// Como mucho tres a la vez: en un móvil, más taparían las opciones.
  static const int _maxNotices = 3;

  static VersusNoticeKind _presenceOf(VersusPlayer p) {
    if (p.left) return VersusNoticeKind.left;
    return p.connected ? VersusNoticeKind.back : VersusNoticeKind.away;
  }

  /// Guarda la plantilla nueva y avisa de quién ha cambiado de estado.
  ///
  /// El diff se hace aquí y no en el widget: en la web hubo que derivarlo
  /// durante el render por las reglas de React, pero con un ChangeNotifier el
  /// sitio natural es este, que es quien recibe el evento.
  void _applyPlayers(List<VersusPlayer> next) {
    final states = {for (final p in next) p.id: _presenceOf(p)};
    final before = _presence;
    final livesBefore = {for (final p in _players) p.id: p.lives};
    final downBefore = {for (final p in _players) p.id: p.eliminated};

    _players = next;
    _presence = states;

    // La primera plantilla solo se memoriza: al entrar en una sala donde ya hay
    // alguien caído no debe saltar un aviso de algo que no acaba de pasar.
    if (before == null) return;

    _detectCasualties(livesBefore, downBefore, next);

    for (final player in next) {
      // A uno no se le avisa de su propia desconexión.
      if (player.id == _playerId) continue;

      final was = before[player.id];
      final now = states[player.id];
      if (was == null || now == null || was == now) continue;

      _pushNotice(
        id: '${player.id}-${now.name}',
        text: switch (now) {
          VersusNoticeKind.back => '${player.nickname} ha vuelto',
          VersusNoticeKind.away => '${player.nickname} se ha desconectado',
          VersusNoticeKind.left => '${player.nickname} ha salido de la sala',
          // _presenceOf solo devuelve los tres de arriba; el resto de clases de
          // aviso no salen de comparar plantillas.
          _ => player.nickname,
        },
        kind: now,
        avatarId: player.avatarId,
      );
    }
  }

  /// Un temporizador por aviso, puesto una sola vez. Reprogramarlos todos con
  /// cada aviso nuevo haría que los que ya llevaban rato en pantalla volvieran
  /// a empezar la cuenta y se quedaran pegados.
  void _pushNotice({
    required String id,
    required String text,
    required VersusNoticeKind kind,
    int? avatarId,
  }) {
    // La clave lleva un contador para que dos avisos iguales seguidos (caerse,
    // volver, caerse) no colisionen ni se reutilice el temporizador del viejo.
    final key = '$id-${_noticeSeq++}';
    _notices.add(VersusNotice(
      id: key,
      text: text,
      kind: kind,
      avatarId: avatarId,
    ));
    if (_notices.length > _maxNotices) _notices.removeAt(0);

    _noticeTimers.add(Timer(_noticeVisible, () {
      if (_disposed) return;
      final at = _notices.indexWhere((n) => n.id == key);
      if (at != -1) {
        _notices[at] = _notices[at].copyWith(leaving: true);
        notifyListeners();
      }
      _noticeTimers.add(Timer(_noticeFade, () {
        if (_disposed) return;
        _notices.removeWhere((n) => n.id == key);
        notifyListeners();
      }));
    }));
  }

  int _noticeSeq = 0;

  // ==========================
  // Derivados para la pantalla
  // ==========================

  /// Guardia: el modo que elimina. Cambia lo que se pinta (vidas, caídas) y
  /// quién puede responder.
  ///
  /// Se mira TAMBIÉN si algún jugador tiene vidas, y no solo `room.mode`: el
  /// modo se fija en `/start`, pero los eventos de fase solo traen `status`, así
  /// que la sala que tiene el cliente sigue diciendo `classic` hasta el
  /// siguiente refresco. Fiarse solo del modo dejaba las vidas sin pintar media
  /// partida — que es justo el "a veces se ven y a veces no".
  bool get isSurvival =>
      _room?.mode == VersusMode.survival ||
      _players.any((p) => p.lives != null);

  VersusPlayer? get me {
    final id = _playerId;
    return id == null ? null : playerById(id);
  }

  /// Caído en Guardia: el servidor le rechazaría la respuesta, así que la
  /// pantalla tampoco debe dejarle pulsar.
  bool get amEliminated => me?.eliminated ?? false;

  VersusPlayer? playerById(String id) {
    for (final p in _players) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Marcador ordenado de mayor a menor, con el jugador ya resuelto.
  List<({VersusScore score, VersusPlayer? player})> ranking(
    List<VersusScore> scores,
  ) {
    final rows = scores
        .map((s) => (score: s, player: playerById(s.playerId)))
        .toList();
    rows.sort((a, b) => b.score.score.compareTo(a.score.score));
    return rows;
  }
}
