/// Modelos de Versus, el modo multijugador en directo.
///
/// Son el reflejo exacto de lo que emite el backend (`src/routes/game.js`) y de
/// los tipos de la web (`src/lib/versus/types.ts`). El cliente no calcula nada
/// del juego: ni puntúa, ni decide cuándo avanza una fase, ni sabe cuál es la
/// respuesta correcta hasta que el servidor la manda en el revelado.
library;

/// Modos jugables. Los tres tienen reglas escritas en el backend
/// (`src/game/rulesets.js`) y se pueden elegir desde el panel de la sala.
class VersusMode {
  VersusMode._();

  /// Velocidad + acierto, estilo Kahoot.
  static const String classic = 'classic';

  /// Puntuación real del MIR: +3 el acierto, −1 el fallo, 0 el blanco, y sin
  /// premio a la velocidad. Es el único modo en el que el acumulado BAJA.
  static const String mirRank = 'mir_rank';

  /// Guardia: quien falla pierde una vida y sin vidas cae. Gana el último en
  /// pie, y la partida acaba al quedar uno aunque sobren preguntas.
  static const String survival = 'survival';

  /// Nombre visible del modo, en un solo sitio.
  ///
  /// Estaba repartido en ternarios binarios por la interfaz, y al añadir el
  /// tercer modo el panel de espera del invitado seguía enseñando "Clásico".
  static String labelOf(String? mode) => switch (mode) {
        classic => 'Clásico',
        mirRank => 'Número de orden',
        survival => 'Guardia',
        _ => 'Modo sin elegir',
      };
}

/// Fases de una sala. `picks` es el momento en que ya se ve qué ha elegido cada
/// jugador pero todavía no cuál era la correcta.
class VersusStatus {
  VersusStatus._();

  static const String lobby = 'lobby';
  static const String question = 'question';
  static const String picks = 'picks';
  static const String reveal = 'reveal';
  static const String ended = 'ended';
}

int _int(dynamic value, [int fallback = 0]) {
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

int? _intOrNull(dynamic value) => value is num ? value.toInt() : null;

class VersusConfig {
  final int secondsPerQuestion;
  final int maxPlayers;

  /// Guardia: vidas con las que arranca cada uno (1 = muerte súbita).
  final int lives;

  const VersusConfig({
    this.secondsPerQuestion = 30,
    this.maxPlayers = 8,
    this.lives = 1,
  });

  factory VersusConfig.fromJson(Map<String, dynamic>? j) => VersusConfig(
        secondsPerQuestion: _int(j?['secondsPerQuestion'], 30),
        maxPlayers: _int(j?['maxPlayers'], 8),
        lives: _int(j?['lives'], 1),
      );
}

/// Sin `hostUserId`: el user_id del anfitrion no viaja a los clientes. Para
/// saber si mandas esta `isHost`, que lo resuelve el servidor, y al anfitrion
/// nuevo se le reconoce por el playerId que trae `host_changed`.
class VersusRoom {
  final String id;
  final String pin;
  final String mode;
  final String status;
  final VersusConfig config;
  final int currentIndex;

  const VersusRoom({
    required this.id,
    required this.pin,
    required this.mode,
    required this.status,
    required this.config,
    required this.currentIndex,
  });

  factory VersusRoom.fromJson(Map<String, dynamic> j) => VersusRoom(
        id: (j['id'] ?? '').toString(),
        pin: (j['pin'] ?? '').toString(),
        mode: (j['mode'] ?? VersusMode.classic).toString(),
        status: (j['status'] ?? VersusStatus.lobby).toString(),
        config: VersusConfig.fromJson(j['config'] as Map<String, dynamic>?),
        currentIndex: _int(j['currentIndex']),
      );

  VersusRoom copyWith({String? status}) => VersusRoom(
        id: id,
        pin: pin,
        mode: mode,
        status: status ?? this.status,
        config: config,
        currentIndex: currentIndex,
      );
}

class VersusPlayer {
  final String id;
  final String nickname;
  final int avatarId;
  final int score;
  final bool isGuest;

  /// Se fue con la partida ya empezada: sigue en el marcador, pero en gris.
  final bool left;

  /// Sigue dando señales de vida. A diferencia de [left], se deshace solo en
  /// cuanto vuelve a latir. Por defecto true: los backends anteriores al
  /// sistema de latidos no mandan el campo, y dar a todo el mundo por
  /// desconectado pintaría la sala entera en gris.
  final bool connected;

  /// Guardia: vidas que le quedan. null fuera de Guardia.
  final int? lives;

  /// Guardia: en qué pregunta cayó. null = sigue en pie.
  final int? eliminatedAtIdx;

  const VersusPlayer({
    required this.id,
    required this.nickname,
    required this.avatarId,
    required this.score,
    required this.isGuest,
    required this.left,
    this.connected = true,
    this.lives,
    this.eliminatedAtIdx,
  });

  /// Ni se ha ido ni responde: se pinta apagado en la sala y el marcador.
  bool get away => left || !connected;

  bool get eliminated => eliminatedAtIdx != null;

  factory VersusPlayer.fromJson(Map<String, dynamic> j) => VersusPlayer(
        id: (j['id'] ?? '').toString(),
        nickname: (j['nickname'] ?? 'Jugador').toString(),
        avatarId: _int(j['avatarId'], 1),
        score: _int(j['score']),
        isGuest: j['isGuest'] == true,
        left: j['left'] == true,
        connected: j['connected'] as bool? ?? true,
        lives: _intOrNull(j['lives']),
        eliminatedAtIdx: _intOrNull(j['eliminatedAtIdx']),
      );
}

/// Puntuación ACUMULADA de un jugador ronda a ronda, para el gráfico del podio.
/// Una ronda fallada suma 0 y la línea se queda plana; no son los puntos
/// sueltos de cada pregunta.
class VersusScoreSeries {
  final String playerId;
  final List<int> points;

  const VersusScoreSeries({required this.playerId, required this.points});

  factory VersusScoreSeries.fromJson(Map<String, dynamic> j) =>
      VersusScoreSeries(
        playerId: (j['playerId'] ?? '').toString(),
        points: ((j['points'] ?? const []) as List).map((e) => _int(e)).toList(),
      );
}

class VersusScore {
  final String playerId;
  final int score;
  final int correct;
  final int answered;

  const VersusScore({
    required this.playerId,
    required this.score,
    required this.correct,
    required this.answered,
  });

  factory VersusScore.fromJson(Map<String, dynamic> j) => VersusScore(
        playerId: (j['playerId'] ?? '').toString(),
        score: _int(j['score']),
        correct: _int(j['correct']),
        answered: _int(j['answered']),
      );
}

class VersusPick {
  final String playerId;

  /// null = respondió en blanco (o se le acabó el tiempo sin elegir).
  final int? selected;

  const VersusPick({required this.playerId, required this.selected});

  factory VersusPick.fromJson(Map<String, dynamic> j) => VersusPick(
        playerId: (j['playerId'] ?? '').toString(),
        selected: _intOrNull(j['selected']),
      );
}

class VersusResult {
  final String playerId;
  final int? selected;
  final bool? isCorrect;
  final int msTaken;
  final int points;

  const VersusResult({
    required this.playerId,
    required this.selected,
    required this.isCorrect,
    required this.msTaken,
    required this.points,
  });

  factory VersusResult.fromJson(Map<String, dynamic> j) => VersusResult(
        playerId: (j['playerId'] ?? '').toString(),
        selected: _intOrNull(j['selected']),
        isCorrect: j['isCorrect'] as bool?,
        msTaken: _int(j['msTaken']),
        points: _int(j['points']),
      );
}

/// Un evento del canal, ya tipado. `serverNow` viaja en todos porque el reloj
/// del móvil puede ir adelantado o atrasado y TODOS los plazos se miden contra
/// el del servidor.
sealed class VersusPhase {
  final int serverNow;

  const VersusPhase({required this.serverNow});

  /// Índice de la pregunta a la que corresponde la fase. `ended` es la única
  /// fase sin pregunta detrás, y devuelve -1.
  int get idx;

  /// Instante (reloj del servidor) en que vence la fase. `ended` no vence.
  int? get endsAt;

  static VersusPhase? fromJson(String event, Map<String, dynamic> j) {
    switch (event) {
      case 'question':
        return VersusQuestionPhase.fromJson(j);
      case 'picks':
        return VersusPicksPhase.fromJson(j);
      case 'reveal':
        return VersusRevealPhase.fromJson(j);
      case 'ended':
        return VersusEndedPhase.fromJson(j);
      default:
        return null;
    }
  }
}

class VersusQuestionPhase extends VersusPhase {
  @override
  final int idx;
  final int total;
  final String statement;
  final String? subject;
  final String? topic;
  final bool hasImage;
  final String? imageUrl;
  final List<String> options;

  /// Fin de la cuenta atrás "3 · 2 · 1": está en el FUTURO cuando llega el
  /// evento. Es también el instante desde el que el servidor mide lo que tarda
  /// cada uno en responder.
  final int startsAt;

  @override
  final int endsAt;

  const VersusQuestionPhase({
    required super.serverNow,
    required this.idx,
    required this.total,
    required this.statement,
    required this.subject,
    required this.topic,
    required this.hasImage,
    required this.imageUrl,
    required this.options,
    required this.startsAt,
    required this.endsAt,
  });

  factory VersusQuestionPhase.fromJson(Map<String, dynamic> j) =>
      VersusQuestionPhase(
        serverNow: _int(j['serverNow']),
        idx: _int(j['idx']),
        total: _int(j['total']),
        statement: (j['statement'] ?? '').toString(),
        subject: j['subject'] as String?,
        topic: j['topic'] as String?,
        hasImage: j['hasImage'] == true,
        imageUrl: j['imageUrl'] as String?,
        options: ((j['options'] ?? const []) as List)
            .map((e) => (e ?? '').toString())
            .toList(),
        startsAt: _int(j['startsAt']),
        endsAt: _int(j['endsAt']),
      );
}

/// El enunciado y las opciones de la ronda, tal y como los ve esta sala.
///
/// Viajan en las TRES fases con pregunta detrás y no solo en 'question': quien
/// se reconecta a mitad de ronda (volver de segundo plano, recuperar el socket)
/// recibe la fase en la que esté la sala, y sin esto se encontraba la tarjeta
/// vacía y ninguna opción que mirar. Null si lo manda un backend anterior.
class VersusRoundContent {
  final int total;
  final String statement;
  final String? subject;
  final String? topic;
  final bool hasImage;
  final String? imageUrl;
  final List<String> options;

  const VersusRoundContent({
    required this.total,
    required this.statement,
    required this.subject,
    required this.topic,
    required this.hasImage,
    required this.imageUrl,
    required this.options,
  });

  static VersusRoundContent? fromJson(Map<String, dynamic> j) {
    final options = j['options'];
    if (options is! List || options.isEmpty) return null;
    return VersusRoundContent(
      total: _int(j['total']),
      statement: (j['statement'] ?? '').toString(),
      subject: j['subject'] as String?,
      topic: j['topic'] as String?,
      hasImage: j['hasImage'] == true,
      imageUrl: j['imageUrl'] as String?,
      options: options.map((e) => (e ?? '').toString()).toList(),
    );
  }

  /// La pregunta que pinta el runner. Los plazos salen SIEMPRE de la fase que
  /// hay en pantalla, así que aquí valen los de la propia fase: en 'picks' y
  /// 'reveal' ya no hay cuenta atrás de respuesta que mostrar.
  VersusQuestionPhase asQuestion({required int idx, required int serverNow}) =>
      VersusQuestionPhase(
        serverNow: serverNow,
        idx: idx,
        total: total,
        statement: statement,
        subject: subject,
        topic: topic,
        hasImage: hasImage,
        imageUrl: imageUrl,
        options: options,
        startsAt: serverNow,
        endsAt: serverNow,
      );
}

class VersusPicksPhase extends VersusPhase {
  @override
  final int idx;
  @override
  final int endsAt;
  final List<VersusPick> picks;

  /// Enunciado y opciones de la ronda, para quien se reconecta aquí.
  final VersusRoundContent? content;

  const VersusPicksPhase({
    required super.serverNow,
    required this.idx,
    required this.endsAt,
    required this.picks,
    this.content,
  });

  factory VersusPicksPhase.fromJson(Map<String, dynamic> j) => VersusPicksPhase(
        serverNow: _int(j['serverNow']),
        idx: _int(j['idx']),
        endsAt: _int(j['endsAt']),
        picks: ((j['picks'] ?? const []) as List)
            .map((e) => VersusPick.fromJson(
                Map<String, dynamic>.from(e as Map)))
            .toList(),
        content: VersusRoundContent.fromJson(j),
      );
}

class VersusRevealPhase extends VersusPhase {
  @override
  final int idx;
  @override
  final int endsAt;

  /// Posición (en el orden que ve ESTA sala) de la opción correcta.
  final int correctIndex;
  final String? explanation;
  final List<VersusResult> results;
  final List<VersusScore> scores;

  /// Guardia: quién ha caído en ESTA ronda. Viaja en el revelado y no antes,
  /// porque en 'picks' delataría quién ha fallado justo cuando la gracia es no
  /// saberlo todavía. Vacío fuera de Guardia.
  final List<String> eliminated;

  /// Guardia: quién ha perdido una vida SIN llegar a caer.
  final List<String> wounded;

  /// Enunciado y opciones de la ronda, para quien se reconecta aquí.
  final VersusRoundContent? content;

  /// A partir de cuándo cuentan los votos de "continuar". Antes de ese instante
  /// el botón se enseña deshabilitado: sirve de suelo para que dos toques
  /// rápidos no se coman la cinemática de caída de Guardia.
  final int skipFrom;

  /// QUIÉNES han pedido ya continuar. El servidor manda los ids de jugador, no
  /// un contador — leerlo como número dejaba el recuento siempre a cero.
  /// Además así se sabe si uno mismo ya votó sin fiarse de un estado local.
  final List<String> continueVoters;

  /// Cuántos siguen jugando: el denominador de la mayoría.
  final int continueTotal;

  int get continueVotes => continueVoters.length;

  /// Votos que hacen falta para que la ronda pase.
  int get continueNeeded => (continueTotal / 2).floor() + 1;

  const VersusRevealPhase({
    required super.serverNow,
    required this.idx,
    required this.endsAt,
    required this.correctIndex,
    required this.explanation,
    required this.results,
    required this.scores,
    this.eliminated = const [],
    this.wounded = const [],
    this.content,
    this.skipFrom = 0,
    this.continueVoters = const [],
    this.continueTotal = 0,
  });

  factory VersusRevealPhase.fromJson(Map<String, dynamic> j) =>
      VersusRevealPhase(
        serverNow: _int(j['serverNow']),
        idx: _int(j['idx']),
        endsAt: _int(j['endsAt']),
        correctIndex: _int(j['correctIndex'], -1),
        explanation: j['explanation'] as String?,
        results: ((j['results'] ?? const []) as List)
            .map((e) =>
                VersusResult.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        scores: ((j['scores'] ?? const []) as List)
            .map((e) =>
                VersusScore.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        eliminated: _ids(j['eliminated']),
        wounded: _ids(j['wounded']),
        content: VersusRoundContent.fromJson(j),
        skipFrom: _int(j['skipFrom']),
        continueVoters: _ids(j['continueVotes']),
        continueTotal: _int(j['continueTotal']),
      );

  VersusRevealPhase copyWithContinue({List<String>? votes, int? total}) =>
      VersusRevealPhase(
        serverNow: serverNow,
        idx: idx,
        endsAt: endsAt,
        correctIndex: correctIndex,
        explanation: explanation,
        results: results,
        scores: scores,
        eliminated: eliminated,
        wounded: wounded,
        content: content,
        skipFrom: skipFrom,
        continueVoters: votes ?? continueVoters,
        continueTotal: total ?? continueTotal,
      );
}

List<String> _ids(dynamic value) =>
    value is List ? value.map((e) => e.toString()).toList() : const [];

class VersusEndedPhase extends VersusPhase {
  final List<VersusScore> scores;

  /// Evolución acumulada por jugador, para el gráfico del podio.
  final List<VersusScoreSeries> series;

  /// Quién ha votado ya la revancha (ids de jugador).
  final List<String> votes;

  /// Instante (reloj del servidor) en que se cierra la votación. null = esta
  /// sala no admite revancha.
  final int? rematchUntil;

  /// Código de la sala de revancha, en cuanto el servidor la crea.
  final String? rematchPin;

  const VersusEndedPhase({
    required super.serverNow,
    required this.scores,
    this.series = const [],
    this.votes = const [],
    this.rematchUntil,
    this.rematchPin,
  });

  @override
  int get idx => -1;

  /// La votación de revancha sí vence, pero NO se pide avanzar por ella: la
  /// cierra el servidor. Por eso aquí no hay plazo de fase.
  @override
  int? get endsAt => null;

  factory VersusEndedPhase.fromJson(Map<String, dynamic> j) => VersusEndedPhase(
        serverNow: _int(j['serverNow']),
        scores: ((j['scores'] ?? const []) as List)
            .map((e) =>
                VersusScore.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        series: ((j['series'] ?? const []) as List)
            .map((e) =>
                VersusScoreSeries.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        votes: _ids(j['votes']),
        rematchUntil: _intOrNull(j['rematchUntil']),
        rematchPin: j['rematchPin'] as String?,
      );

  VersusEndedPhase copyWith({
    List<String>? votes,
    int? rematchUntil,
    String? rematchPin,
  }) =>
      VersusEndedPhase(
        serverNow: serverNow,
        scores: scores,
        series: series,
        votes: votes ?? this.votes,
        rematchUntil: rematchUntil ?? this.rematchUntil,
        rematchPin: rematchPin ?? this.rematchPin,
      );
}

/// Aviso efímero de lo que le pasa a la gente de la sala: quién se cae, quién
/// vuelve, quién se va y a quién le toca ser anfitrión.
enum VersusNoticeKind {
  /// Ha vuelto a dar señales de vida.
  back,

  /// Sin latido: se le cayó el wifi, se quedó sin batería o cerró la app.
  away,

  /// Se fue de la sala a propósito.
  left,

  /// El servidor le ha traspasado el rol de anfitrión.
  host,

  /// Guardia: ha perdido una vida pero sigue en pie.
  wounded,

  /// Guardia: se ha quedado sin vidas.
  down,
}

class VersusNotice {
  final String id;
  final String text;
  final int? avatarId;
  final VersusNoticeKind kind;

  /// Ya se está desvaneciendo; se quita de la lista al acabar.
  final bool leaving;

  const VersusNotice({
    required this.id,
    required this.text,
    required this.kind,
    this.avatarId,
    this.leaving = false,
  });

  VersusNotice copyWith({bool? leaving}) => VersusNotice(
        id: id,
        text: text,
        kind: kind,
        avatarId: avatarId,
        leaving: leaving ?? this.leaving,
      );
}

/// Lo que el anfitrión lleva marcado en el panel de configuración, para que el
/// resto del lobby no espere a ciegas.
///
/// Es DECORATIVO: lo emite la app del anfitrión por el canal, no el servidor.
/// La configuración que cuenta es la que viaja en `POST /start` y valida el
/// backend; esto solo evita la pantalla de "esperando" sin más información.
class VersusLobbyDraft {
  /// null mientras el anfitrión no haya elegido modo.
  final String? mode;

  final int lives;
  final int count;

  /// Nombres de las asignaturas marcadas, ya resueltos por el anfitrión: el
  /// resto no tiene por qué haber cargado el catálogo.
  final List<String> subjects;

  const VersusLobbyDraft({
    required this.mode,
    required this.lives,
    required this.count,
    required this.subjects,
  });

  Map<String, dynamic> toJson() => {
        'mode': mode,
        'lives': lives,
        'count': count,
        'subjects': subjects,
      };

  factory VersusLobbyDraft.fromJson(Map<String, dynamic> j) => VersusLobbyDraft(
        mode: j['mode'] as String?,
        lives: _int(j['lives'], 1),
        count: _int(j['count'], 10),
        subjects: ((j['subjects'] ?? const []) as List)
            .map((e) => e.toString())
            .toList(),
      );
}

/// Qué ha pasado en el revelado de una ronda de Guardia, ya resuelto desde el
/// punto de vista de ESTE jugador. Es lo que dispara el momento a pantalla
/// completa: sin él, perder una vida se leía igual que acertar.
enum VersusStrikeKind {
  /// Has perdido una vida pero sigues en pie.
  hit,

  /// Te has quedado sin vidas.
  knockout,

  /// Ha caído otro. Se celebra distinto que sobrevivir a secas.
  rivalDown,
}

class VersusStrike {
  final VersusStrikeKind kind;

  /// Ronda a la que corresponde, para no repetir el mismo golpe dos veces si el
  /// revelado llega por broadcast y por refresco.
  final int idx;

  /// Vidas que quedan tras el golpe (solo en [VersusStrikeKind.hit]).
  final int livesLeft;

  /// A quién se ha llevado la ronda, cuando el golpe es de otro.
  final String? nickname;

  const VersusStrike({
    required this.kind,
    required this.idx,
    this.livesLeft = 0,
    this.nickname,
  });
}

/// Lo que este jugador ya respondió en la ronda en curso, tal y como lo cuenta
/// el servidor al reconectar. Que exista significa que respondió, aunque
/// `selected` sea null (dejó la pregunta en blanco).
class VersusRestoredAnswer {
  final int idx;
  final int? selected;

  const VersusRestoredAnswer({required this.idx, this.selected});
}

/// Respuesta de crear / entrar / consultar una sala.
class VersusRoomState {
  final VersusRoom room;
  final List<VersusPlayer> players;
  final String? playerId;
  final bool isHost;
  final VersusPhase? phase;
  final bool answered;
  final int? mySelection;

  const VersusRoomState({
    required this.room,
    required this.players,
    required this.playerId,
    required this.isHost,
    this.phase,
    this.answered = false,
    this.mySelection,
  });

  factory VersusRoomState.fromJson(Map<String, dynamic> j) {
    final phaseJson = j['phase'] as Map<String, dynamic>?;
    // `player` solo llega al crear/entrar; en el GET de estado viene playerId.
    final player = j['player'] as Map<String, dynamic>?;

    return VersusRoomState(
      room: VersusRoom.fromJson(
          Map<String, dynamic>.from(j['room'] as Map)),
      players: ((j['players'] ?? const []) as List)
          .map((e) =>
              VersusPlayer.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      playerId: (j['playerId'] ?? player?['id'])?.toString(),
      isHost: j['isHost'] == true,
      phase: phaseJson == null
          ? null
          : VersusPhase.fromJson(
              (phaseJson['event'] ?? '').toString(), phaseJson),
      answered: j['answered'] == true,
      mySelection: _intOrNull(j['mySelection']),
    );
  }
}
