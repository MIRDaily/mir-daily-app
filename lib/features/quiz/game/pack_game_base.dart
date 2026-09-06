import 'dart:math';
import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame/effects.dart';
import 'package:flutter/material.dart';

import '../../../core/data/subject_visuals.dart';
import '../../../core/services/haptics_service.dart';
import '../../../core/theme/app_theme.dart';
import 'pack_haptics.dart';

typedef OnPackOpenComplete = void Function(List<String> specialties);

/// Anima durante [duration] segundos: llama a [onUpdate] con el avance (0..1)
/// en cada tick y, al acabar, a [onDone] UNA sola vez.
///
/// Lo importante es que el temporizador se retira al terminar. Todas las
/// animaciones de este archivo usaban un TimerComponent con repeat que no se
/// quitaba nunca: seguían gastando un tick cada 16 ms para siempre y, las que
/// llevaban callback, lo volvían a disparar en cada uno. Eso dejaba el sobre
/// inabrible: el callback del rebote pone el desgarro a cero, y no paraba de
/// hacerlo mientras el usuario intentaba volver a rasgar.
/// Devuelve el temporizador para poder cortar la animación antes de tiempo.
TimerComponent packAnimate(
  Component owner, {
  required double duration,
  required void Function(double t) onUpdate,
  VoidCallback? onDone,
}) {
  double elapsed = 0;
  late final TimerComponent timer;
  timer = TimerComponent(
    period: 0.016,
    repeat: true,
    onTick: () {
      elapsed += 0.016;
      onUpdate((elapsed / duration).clamp(0.0, 1.0));
      if (elapsed >= duration) {
        timer.removeFromParent();
        onDone?.call();
      }
    },
  );
  owner.add(timer);
  return timer;
}

/// Lo que comparten TODAS las animaciones de apertura del sobre.
///
/// Abrir el sobre son dos actos muy distintos. El PRIMERO es el gesto: cómo se
/// rompe el envoltorio, y es lo único que cambia de una animación a otra. El
/// SEGUNDO es el premio: las cinco cartas salen disparadas, se colocan en
/// abanico, se dan la vuelta, se recogen, se barajan y se van. Ese segundo
/// acto es la identidad del daily y tiene que ser idéntico en todas, porque es
/// lo que el usuario reconoce como "el sobre de MIRDaily".
///
/// Por eso el premio vive aquí y el gesto en las subclases:
///
///  - [PackOpeningGame] — rasgar por la costura (la de siempre).
///  - [PackBurstGame] — apretar hasta que revienta.
///  - [PackTwistGame] — retorcerlo como un caramelo.
///
/// Una animación nueva es una subclase que pinta su envoltorio y llama a
/// [startPayoff] cuando se abre; no tiene que saber nada de cartas.
abstract class PackGameBase extends FlameGame {
  final List<String> specialties;
  final OnPackOpenComplete onComplete;

  /// `true` mientras hay que enseñar la leyenda de siglas (`CD · Cardiología …`)
  /// al pie del sobre: se enciende tras revelar las cartas y se apaga al
  /// recogerlas. Lo pinta [QuizScreen] con un `ValueListenableBuilder`; se hace
  /// así y no con un overlay de Flame para que los tests puedan montar el juego
  /// suelto sin registrar builders.
  final ValueNotifier<bool> legendVisible = ValueNotifier(false);

  /// [haptics] se puede sustituir en tests por un doble que apunte lo que
  /// sale: la vibración no se ve ni se oye, así que es la única forma de
  /// comprobar que sube, se mantiene y se desvanece.
  PackGameBase({
    required this.specialties,
    required this.onComplete,
    PackHaptics? haptics,
  }) : haptics = haptics ?? PackHaptics();

  // Componentes compartidos: el mazo que asoma por la abertura y las cartas.
  late CardsBehindPackComponent cardsBehind;
  late List<CardComponent> cards;

  // Estado
  bool _opened = false;
  bool _isRevealing = false;
  bool _isVisible = true;

  /// `true` en cuanto el envoltorio se ha abierto y empieza el reparto. A
  /// partir de ahí el sobre deja de flotar y no admite más gestos.
  bool get opened => _opened;

  /// Avance de la apertura, 0..1. Lo pinta la barra de progreso de la pantalla
  /// del daily; cada animación lo llena a su manera (rasgando, apretando…).
  double get openProgress;

  // ---- Posiciones ----
  //
  // Son la MISMA instancia durante toda la vida del juego, y se rellenan en
  // [_layout]. No es un detalle: los componentes decorativos se quedan con
  // estos dos Vector2 en su constructor, así que al recolocar el sobre hay que
  // MUTARLOS (setValues), no cambiarlos por otros nuevos, o seguirían pintando
  // donde estaba el sobre antes.
  final Vector2 packPosition = Vector2.zero();
  final Vector2 packSize = Vector2.zero();

  /// El sobre siempre mide lo mismo: es una ilustración, no una caja que se
  /// estire con la pantalla.
  static final Vector2 packDesignSize = Vector2(240, 320);

  /// Lo que el sobre se sube respecto al centro exacto, para dejar sitio a la
  /// barra de navegación de abajo. Es el mismo desplazamiento que usa
  /// `MainNavigation._getPackZone` para saber dónde bloquear el deslizamiento
  /// entre pestañas: si uno cambia, el otro también.
  static const double packLift = 30.0;

  // Animación flotante
  double _floatPhase = 0.0;
  double baseY = 0.0;

  /// Altura, DENTRO del sobre, por la que salen las cartas. La marca cada
  /// animación: la de rasgar abre por la costura de arriba, la de reventar se
  /// parte por el medio.
  double get packMouthY;

  // ---- Reparto de las cartas al abrirse el sobre ----

  /// Proporción de la carta, la de toda la vida (85x115).
  static const double _cardAspect = 115 / 85;

  /// Inclinación máxima de una carta, en radianes (~8°).
  static const double _cardTilt = 0.14;

  /// Cuánto sube la carta central de su fila respecto a las de los extremos.
  static const double _cardArc = 16.0;

  /// Aire que queda entre dos cartas en el caso peor.
  static const double _cardAir = 8.0;

  /// Hueco entre cartas.
  ///
  /// A lo ancho basta el aire: el reparto ya no desvía nada al azar, y lo que
  /// se come el giro ya está contado en el ancho inclinado. Antes había que
  /// reservar el doble del desfase por si dos vecinas se movían la una hacia
  /// la otra; sin azar, ese presupuesto vuelve a las cartas, que con tres por
  /// fila se habían quedado estrechas para los nombres largos.
  static const double _cardGapX = _cardAir;

  /// A lo alto hay que absorber el arco: una carta de la fila de abajo puede
  /// subir mientras la de encima no se mueve, y entonces se acercan.
  static const double _cardGapY = _cardArc + _cardAir;

  static const double _cardsMargin = 15.0;

  /// Tope: por muy ancha que sea la pantalla, tampoco hace falta que sean
  /// gigantes.
  static const double _cardMaxWidth = 108.0;

  /// Ancho con el que se diseñaron los rótulos de la carta. El texto se escala
  /// contra esto (ver CardComponent._drawSpecialtyOverlay).
  static const double cardDesignWidth = 85.0;

  /// Tamaño real: depende de la pantalla, porque lo que cabe con dos por fila
  /// e inclinación no es lo mismo en un móvil estrecho que en uno ancho.
  late double cardWidth;
  late double cardHeight;

  /// Lo que barre una carta ya inclinada. Es mayor que su ancho/alto, y es la
  /// medida buena para repartirlas: usar la plana las dejaría solapadas en
  /// cuanto se ladean.
  double get _tiltedCardWidth =>
      cardWidth * cos(_cardTilt) + cardHeight * sin(_cardTilt);
  double get _tiltedCardHeight =>
      cardWidth * sin(_cardTilt) + cardHeight * cos(_cardTilt);

  /// Cuántas cartas salen del sobre. Tiene que coincidir con las que crea
  /// [_loadCards], o el reparto contaría un número de filas equivocado.
  int get _cardCount => specialties.isNotEmpty ? specialties.length : 5;

  /// Cuántas cartas van en cada fila: **dos filas**, la de arriba con la mitad
  /// redondeada hacia arriba. Con las 5 del daily sale 3-2, que es el mismo
  /// reparto que hace el dashboard de la web (`ceil(total / 2)`).
  ///
  /// Antes eran 2-1-2 con desfase al azar, y el montón se leía como si las
  /// cartas se hubieran rociado por la pantalla.
  List<int> get _rowSizes {
    final n = _cardCount;
    if (n <= 1) return [n];
    final arriba = (n + 1) ~/ 2; // ceil(n / 2)
    return [arriba, n - arriba];
  }

  int get _cardRows => _rowSizes.length;

  /// La fila más ancha, que es la que manda al calcular cuánto puede medir una
  /// carta.
  int get _cardsWidestRow => _rowSizes.fold(1, (a, b) => a > b ? a : b);

  /// Solo para tests: el reparto que saldría en una pantalla dada, para poder
  /// comprobar que las cartas no se solapan.
  @visibleForTesting
  List<Vector2> debugCardLayout(Vector2 screen, Random random) {
    onGameResize(screen);
    _computeCardSize();
    return generateCardPositions(random: random);
  }

  /// Solo para tests: lo que barre una carta contando su inclinación.
  @visibleForTesting
  Vector2 get debugTiltedCardSize =>
      Vector2(_tiltedCardWidth, _tiltedCardHeight);

  /// Solo para tests: el sobre, en coordenadas del juego.
  @visibleForTesting
  Rect get debugPackRect =>
      Rect.fromLTWH(packPosition.x, packPosition.y, packSize.x, packSize.y);

  /// El mayor tamaño que cabe dejando sitio al hueco, al desfase y al giro.
  void _computeCardSize() {
    final availableWidth = size.x - 2 * _cardsMargin;
    final availableHeight = size.y - (_cardsMargin + 20) - (_cardsMargin + 80);

    // Se despeja el ancho de: nº * anchoInclinado + huecos + desfase <= sitio.
    final tiltW = cos(_cardTilt) + _cardAspect * sin(_cardTilt);
    final tiltH = sin(_cardTilt) + _cardAspect * cos(_cardTilt);

    final byWidth =
        (availableWidth - (_cardsWidestRow - 1) * _cardGapX) /
        (_cardsWidestRow * tiltW);
    // Arriba y abajo se reserva el arco: la carta central de la primera fila
    // sube, y no debe salirse por el borde superior.
    final byHeight =
        (availableHeight - (_cardRows - 1) * _cardGapY - 2 * _cardArc) /
        (_cardRows * tiltH);

    cardWidth = min(min(byWidth, byHeight), _cardMaxWidth);
    cardHeight = cardWidth * _cardAspect;
  }

  /// Enciende o apaga el sobre según esté a la vista.
  ///
  /// Antes esto solo bajaba una bandera y `update()` salía temprano, pero el
  /// bucle de Flame seguía corriendo y **`render()` seguía pintando el juego
  /// en cada fotograma**. Medido en la Tab S8: la app repintaba a ~127
  /// fotogramas por segundo estando en Versus o en Premium, con el sobre fuera
  /// de la pantalla. Era el único motivo por el que no descansaba nunca.
  ///
  /// No basta con el `TickerMode` de `MainNavigation`: Flame monta su bucle
  /// con un `Ticker` CRUDO (ver `game_loop.dart` del paquete), no a través de
  /// un `TickerProvider`, así que `TickerMode` no puede silenciarlo. Hay que
  /// parar el motor a mano.
  ///
  /// `pauseEngine` y `resumeEngine` son idempotentes (`GameLoop.start()` es un
  /// noop si ya corre) y seguros antes de que el juego se monte: van por
  /// `_gameRenderBox?.gameLoop?`, y al montarse el render box respeta
  /// `paused`. Al reanudar, Flame NO arrastra el tiempo que ha pasado parado,
  /// así que no hay salto —y `update()` clampea el `dt` de todas formas—.
  void setVisible(bool visible) {
    _isVisible = visible;
    if (visible) {
      resumeEngine();
    } else {
      // Callar ANTES de parar el motor: con el bucle detenido ya no habría
      // quien apagara la vibración, y el móvil se quedaría zumbando en el
      // bolsillo por haber cambiado de pestaña a media apertura.
      haptics.stop();
      _wasGripped = false;
      pauseEngine();
    }
  }

  /// El fondo que Flame pinta por debajo del juego. Sin esto es NEGRO, y como
  /// GameWidget lo pinta desde el primer frame pero no muestra el resto (ni
  /// siquiera su backgroundBuilder) hasta que onLoad() termina, la pantalla
  /// daba un pantallazo negro al entrar.
  @override
  Color backgroundColor() => AppColors.background;

  @override
  void onRemove() {
    legendVisible.dispose();
    super.onRemove();
  }

  @override
  Future<void> onLoad() async {
    // Qué sabe hacer el motor de vibración de este aparato. Se escupe una vez
    // por ejecución: es la única forma de saber si la rampa de intensidad
    // tiene algo debajo que la respete (ver HapticsService.probe).
    HapticsService.logProbeOnce();

    // El tamaño ya está calculado: onGameResize() corre ANTES que onLoad().
    await loadPackVisuals();
    await _loadCards();

    // onLoad() espera a los sprites, y en esa espera puede colarse un resize
    // que se saltó placeComponents() porque el juego aún no estaba cargado.
    placeComponents();
  }

  /// Monta el envoltorio y sus adornos. Cada animación pinta el suyo.
  ///
  /// Las prioridades por debajo de 10 son para el envoltorio; de 10 en
  /// adelante van las cartas, que tienen que quedar POR ENCIMA de todo lo
  /// demás cuando salen disparadas.
  Future<void> loadPackVisuals();

  /// Recoloca el envoltorio cuando cambia el tamaño de la pantalla.
  void placePackVisuals();

  /// Cada fotograma mientras el sobre sigue cerrado: [y] es la altura del
  /// sobre ya con el vaivén sumado, y [phase] la fase del vaivén.
  void floatPackVisuals(double y, double phase);

  /// Justo cuando arranca el reparto: el envoltorio ya se ha roto y toca
  /// quitarlo de en medio.
  void dismissPackVisuals();

  Future<void> _loadCards() async {
    cardsBehind = CardsBehindPackComponent()
      ..size = Vector2(cardWidth, cardHeight)
      ..priority = 0;
    add(cardsBehind);

    // Una carta por pregunta del sobre diario (5 con la mecánica actual).
    cards = [];
    for (int i = 0; i < _cardCount; i++) {
      final card =
          CardComponent(
              index: i,
              specialty: i < specialties.length ? specialties[i] : 'General',
            )
            ..size = Vector2(cardWidth, cardHeight)
            ..priority = 10 + i
            ..setOpacity(0)
            ..scale = Vector2.all(0.3);
      cards.add(card);
      add(card);
    }
  }

  /// Centra el sobre en el área de juego y recalcula lo que cuelga de ello.
  ///
  /// Está fuera de onLoad() a propósito, porque onLoad() corre UNA VEZ. Todo
  /// esto se calculaba allí con el tamaño que tuviera la pantalla en ese
  /// momento y no se volvía a tocar nunca: al girar la tablet el juego sí
  /// cambiaba de tamaño, pero el sobre se quedaba con las cuentas de la
  /// orientación anterior. Cargándolo en horizontal (alto ~800) y girando a
  /// vertical (alto ~1280), el sobre se quedaba a 210 puntos del borde
  /// superior en vez de a 450: pegado a la parte de arriba de la pantalla.
  void _layout() {
    _computeCardSize();

    packSize.setFrom(packDesignSize);
    packPosition.setValues(
      size.x / 2 - packSize.x / 2,
      size.y / 2 - packSize.y / 2 - packLift,
    );
    baseY = packPosition.y;
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size); // deja `this.size` ya actualizado
    _layout();

    // Al girar la pantalla con el sobre ya abierto no se recoloca nada: las
    // cartas están en pleno vuelo hacia su sitio y moverles el suelo debajo
    // solo puede quedar peor. Dura un segundo y después se entra al quiz.
    if (isLoaded && !_opened) {
      placeComponents();
    }
  }

  /// Dónde nacen las cartas: la boca del sobre.
  /// Dónde acaba el DIBUJO del envoltorio dentro de su caja, en tanto por uno.
  ///
  /// El PNG no llena su lienzo: la ilustración deja aire transparente, y el
  /// borde ondulado de abajo se acaba al 91% de la altura, no al 100%. Medido
  /// sobre los píxeles opacos de `pack_closed.png` (1024x1536).
  ///
  /// Importa porque el mazo que asoma por la abertura se coloca contra ESTO y
  /// no contra la caja: contando la caja entera, en pantallas anchas —donde
  /// las cartas llegan a su tope de 108x146— el montón asomaba por debajo del
  /// sobre cerrado, como si se saliera por el culo del envoltorio.
  static const double packArtBottom = 0.912;
  static const double packArtTop = 0.053;

  /// Aire que se le deja al mazo por debajo. Cubre lo que el propio montón se
  /// desplaza: son cinco cartas escalonadas de 1,2 en 1,2 más su sombra.
  static const double _cardsBehindMargin = 10.0;

  /// La altura, DENTRO del sobre, a la que se apoya el mazo que asoma.
  ///
  /// Sale de [packMouthY], pero sin dejar que se salga del dibujo.
  double get cardsBehindY {
    final tope = packSize.y * packArtBottom - cardHeight - _cardsBehindMargin;
    final suelo = packSize.y * packArtTop + 4;
    return (packMouthY + 8).clamp(min(suelo, tope), max(suelo, tope));
  }

  Vector2 get cardsOrigin => Vector2(
    packPosition.x + packSize.x / 2 - cardWidth / 2,
    packPosition.y + packMouthY,
  );

  @protected
  void placeComponents() {
    final cardSize = Vector2(cardWidth, cardHeight);
    final origin = cardsOrigin;

    cardsBehind
      ..position = Vector2(origin.x, packPosition.y + cardsBehindY)
      ..size = cardSize;

    // Las cartas siguen dentro del sobre hasta que se abre.
    for (final card in cards) {
      card
        ..position = origin + Vector2(0, 10)
        ..size = cardSize;
    }

    placePackVisuals();
  }

  @override
  void update(double dt) {
    // Si no es visible, no actualizar nada (evita acumulación de tiempo).
    if (!_isVisible) return;

    // Limitar dt para evitar saltos grandes.
    final clampedDt = dt.clamp(0.0, 0.033); // Máximo ~30 FPS worth de tiempo

    super.update(clampedDt);

    updateOpening(clampedDt);
    _updateHaptics(clampedDt);

    if (!_opened) {
      _floatPhase += clampedDt * 2.0;

      // El mecido se apaga y se enciende con suavidad; ver [_floatAmount].
      _floatAmount += (floatTarget - _floatAmount) *
          min(1.0, clampedDt * _floatEase);
      if ((floatTarget - _floatAmount).abs() < 0.002) {
        _floatAmount = floatTarget;
      }

      final floatOffset = sin(_floatPhase) * 5.0 * _floatAmount;

      cardsBehind.position.y = baseY + cardsBehindY + floatOffset;
      floatPackVisuals(baseY + floatOffset, _floatPhase);
    }
  }

  /// La vibración del gesto: sube con el avance, se queda quieta si te paras a
  /// medias y se desvanece si sueltas. Ver [PackHaptics].
  ///
  /// Vive aquí y no en cada animación porque la regla es la misma para las
  /// tres —lo que cambia es el gesto, no lo que se siente—, y porque así el
  /// tren de pulsos se para solo al pausarse el motor del juego: nadie se
  /// queda con el móvil zumbando en el bolsillo al cambiar de pestaña.
  final PackHaptics haptics;

  /// Si el dedo está ahora mismo sujetando el sobre para abrirlo.
  ///
  /// Es lo que separa "voy a medias y me he parado" —la vibración se mantiene
  /// en su nivel— de "he soltado", que la desvanece.
  @protected
  bool get gripped => false;

  bool _wasGripped = false;

  /// Si el sobre debería estar meciéndose ahora mismo (1) o quieto (0).
  ///
  /// Lo baja la animación que sujeta el sobre con el dedo: mientras se aprieta
  /// o se retuerce, el sobre está agarrado y no puede seguir meciéndose. Va
  /// aquí y no en cada subclase porque el mazo que asoma tiene que moverse con
  /// el envoltorio: si el sobre se para y el mazo no, el montón se desplaza
  /// solo y acaba asomando por el borde.
  @protected
  double get floatTarget => 1.0;

  /// Lo que de verdad se aplica: [floatTarget] perseguido con suavidad.
  ///
  /// Es lo que quita el tirón al empezar el gesto. Apagando el vaivén de golpe,
  /// el sobre saltaba de donde estuviera del mecido —hasta 5 puntos— a su
  /// altura de reposo en un solo fotograma. Se notaba como un tic seco justo
  /// al tocar, y en "apretar" y "retorcer" caía en el peor momento posible:
  /// el primer instante del gesto.
  ///
  /// Persecución exponencial, no una animación con duración: da igual cuándo
  /// se agarre o se suelte el sobre, y si se suelta a media frenada arranca
  /// desde donde iba, sin saltos.
  double _floatAmount = 1.0;

  /// Lo rápido que se apaga y se enciende el mecido. A 9, tarda ~0,25 s en
  /// hacer el 90% del camino: lo justo para que no se vea el corte y no tanto
  /// como para que el sobre parezca seguir suelto mientras lo sujetas.
  static const double _floatEase = 9.0;

  /// Para que las subclases apaguen con la MISMA suavidad lo suyo (el
  /// respirar del envoltorio, por ejemplo). Si una lo apagara de golpe por su
  /// cuenta, volvería el tirón por otro lado.
  @protected
  double get floatAmount => _floatAmount;

  @visibleForTesting
  double get debugFloatAmount => _floatAmount;

  /// Lleva la vibración al compás del gesto.
  ///
  /// Mientras el dedo sujeta, la fuerza ES el avance: si te paras a medias, el
  /// avance no cambia y la vibración se queda clavada en ese nivel. Al soltar
  /// sin abrir se desvanece —y se desvanece de forma explícita, no siguiendo
  /// al avance, porque el avance vuelve a cero rebotando (el sobre se desinfla
  /// con un rebote elástico, el retorcido se destuerce pasándose de largo) y
  /// eso en la mano se sentiría como un tartamudeo, no como un final.
  void _updateHaptics(double dt) {
    if (!opened) {
      if (gripped) {
        haptics.driveTo(openProgress);
        _wasGripped = true;
      } else if (_wasGripped) {
        _wasGripped = false;
        haptics.fadeOut();
      }
    }
    haptics.update(dt);
  }

  /// Un tick del gesto de apertura, con el `dt` ya acotado.
  ///
  /// Va aquí y no en un `update()` propio para que las subclases no tengan que
  /// repetir el acotado del `dt` ni el corte por visibilidad, que es justo lo
  /// que mantiene el sobre en reposo cuando está en otra pestaña.
  @protected
  void updateOpening(double dt) {}

  /// El envoltorio se ha roto: empieza el premio.
  ///
  /// De aquí en adelante todas las animaciones hacen exactamente lo mismo.
  @protected
  void startPayoff() {
    if (_opened) return;
    _opened = true;

    cardsBehind.fadeOut();
    dismissPackVisuals();

    _dealCards();
  }

  void _dealCards() {
    final random = Random();

    final targetPositions = generateCardPositions(random: random);

    // La inclinación va en abanico, no al azar: dentro de cada fila la carta
    // se ladea según lo lejos que esté del centro, como en la web. El tope es
    // el mismo que se usó para repartirlas, así que siguen sin tocarse.
    final targetAngles = _generateCardAngles();

    final originPos = cardsOrigin;

    for (int i = 0; i < cards.length; i++) {
      final card = cards[i];
      final targetPos = targetPositions[i];
      final targetAngle = targetAngles[i];
      final delay = i * 70;

      Future.delayed(Duration(milliseconds: delay), () {
        card.shootOut(
          from: originPos.clone(),
          to: targetPos,
          targetAngle: targetAngle,
        );
      });
    }

    final totalDealTime = (cards.length * 70) + 600;
    Future.delayed(Duration(milliseconds: totalDealTime), () {
      _startRevealSequence();
    });
  }

  /// Reparte las cartas por la pantalla como si las hubieran tirado a mano.
  ///
  /// Por debajo hay una rejilla, pero cada carta se ladea y describe un arco,
  /// así que no se lee como una tabla. El truco para que no se solapen nunca
  /// es que cada una ocupa el hueco de su caja YA inclinada, y el arco que
  /// puede moverse está reservado de antemano en [_computeCardSize]: el
  /// desorden cabe siempre, no depende de la suerte.
  @protected
  List<Vector2> generateCardPositions({required Random random}) {
    final positions = <Vector2>[];

    final count = _cardCount;
    if (count == 0) return positions;

    final topMargin = _cardsMargin + 20;
    final bottomMargin = _cardsMargin + 80; // hueco de la barra inferior
    final availableHeight = size.y - topMargin - bottomMargin;

    final slotW = _tiltedCardWidth;
    final slotH = _tiltedCardHeight;

    final rowSizes = _rowSizes;

    final totalHeight =
        rowSizes.length * slotH + (rowSizes.length - 1) * _cardGapY;
    final startY = topMargin + (availableHeight - totalHeight) / 2;

    for (var row = 0; row < rowSizes.length; row++) {
      final n = rowSizes[row];
      final rowWidth = n * slotW + (n - 1) * _cardGapX;
      final rowStartX = size.x / 2 - rowWidth / 2;
      final rowY = startY + row * (slotH + _cardGapY);

      // El desvío no es al azar sino un ARCO: dentro de cada fila, la carta
      // del medio queda un poco más alta que las de los lados, igual que en el
      // dashboard de la web. Con el desfase aleatorio el reparto parecía un
      // montón de cartas rociadas; así se lee como un abanico puesto a mano.
      final mid = (n - 1) / 2;

      for (var i = 0; i < n; i++) {
        // La carta va centrada en su hueco: el hueco es su caja inclinada, que
        // es más grande que ella.
        final slotX = rowStartX + i * (slotW + _cardGapX);
        final x = slotX + (slotW - cardWidth) / 2;
        final y = rowY + (slotH - cardHeight) / 2;

        // 1 en el centro de la fila y 0 en los extremos. El alto del arco se
        // limita al desfase que [_computeCardSize] ya tenía reservado, así que
        // no puede hacer que dos cartas se toquen.
        final t = mid == 0 ? 0.0 : 1 - pow((i - mid) / mid, 2).toDouble();
        positions.add(Vector2(x, y - t * _cardArc));
      }
    }

    return positions;
  }

  /// Inclinación de cada carta, en el mismo orden que [generateCardPositions].
  List<double> _generateCardAngles() {
    final angles = <double>[];
    for (final n in _rowSizes) {
      final mid = (n - 1) / 2;
      for (var i = 0; i < n; i++) {
        // Las de la izquierda hacia un lado y las de la derecha hacia el otro.
        angles.add(mid == 0 ? 0 : ((i - mid) / mid) * _cardTilt);
      }
    }
    return angles;
  }

  void _startRevealSequence() {
    if (_isRevealing) return;
    _isRevealing = true;

    const revealStagger = 220;

    for (int i = 0; i < cards.length; i++) {
      final delayMs = i * revealStagger;

      Future.delayed(Duration(milliseconds: delayMs), () {
        if (i < cards.length) {
          cards[i].flipReveal();
        }
      });
    }

    // Con 5 cartas el volteo termina sobre el segundo; a partir de ahí se
    // sostienen quietas lo justo para leer de un vistazo qué asignaturas han
    // tocado, no para estudiarlas. Antes eran 6 s fijos y se hacía eterno.
    final lastRevealTime = (cards.length - 1) * revealStagger;
    const waitAfterFirst = 2600;
    final waitAfterLast = lastRevealTime + 1200;
    final totalWait = max(waitAfterFirst, waitAfterLast);

    // La leyenda entra justo después del último volteo y acompaña a las cartas
    // mientras están quietas.
    Future.delayed(Duration(milliseconds: lastRevealTime + 350), () {
      if (isMounted && _opened) legendVisible.value = true;
    });

    Future.delayed(Duration(milliseconds: totalWait), () {
      _gatherAndShuffle();
    });
  }

  void _gatherAndShuffle() async {
    legendVisible.value = false;

    final centerX = size.x / 2 - cardWidth / 2;
    final centerY = size.y / 2 - cardHeight / 2;
    final centerPos = Vector2(centerX, centerY);

    for (int i = 0; i < cards.length; i++) {
      final card = cards[i];
      final delay = i * 50;

      Future.delayed(Duration(milliseconds: delay), () {
        card.stopFloating();

        final stackIndex = (cards.length - 1 - i);
        final stackOffset = Vector2(stackIndex * 0.8, stackIndex * 0.8);

        card.add(
          MoveEffect.to(
            centerPos + stackOffset,
            EffectController(duration: 0.4, curve: Curves.easeOutBack),
          ),
        );

        card.add(
          RotateEffect.to(
            0,
            EffectController(duration: 0.35, curve: Curves.easeOutCubic),
          ),
        );

        card.add(
          ScaleEffect.to(Vector2.all(0.8), EffectController(duration: 0.4)),
        );
      });
    }

    await Future.delayed(Duration(milliseconds: (cards.length * 50) + 500));

    await _performShuffleAnimation(centerPos);

    await Future.delayed(const Duration(milliseconds: 150));
    _exitAnimation();
  }

  Future<void> _performShuffleAnimation(Vector2 centerPos) async {
    for (int i = 3; i < cards.length; i++) {
      cards[i].fadeToOpacity(0, duration: 0.2);
    }

    await Future.delayed(const Duration(milliseconds: 180));

    final shuffleCards = cards.take(3).toList();

    // Dos pasadas bastan para leerse como "baraja"; cuatro alargaban el trámite
    // entre el sobre y el quiz sin aportar nada.
    for (int shuffle = 0; shuffle < 2; shuffle++) {
      await Future.delayed(const Duration(milliseconds: 130));

      for (int i = 0; i < shuffleCards.length; i++) {
        final card = shuffleCards[i];
        final offsetX = (i - 1) * 55.0;
        final offsetY = (shuffle % 2 == 0 ? -1.0 : 1.0) * (i == 1 ? 0.0 : 18.0);

        card.add(
          MoveEffect.to(
            centerPos + Vector2(offsetX, offsetY),
            EffectController(duration: 0.12, curve: Curves.easeOutCubic),
          ),
        );

        card.add(
          RotateEffect.to((i - 1) * 0.08, EffectController(duration: 0.12)),
        );
      }
    }

    await Future.delayed(const Duration(milliseconds: 150));

    for (int i = 0; i < shuffleCards.length; i++) {
      final card = shuffleCards[i];
      card.add(
        MoveEffect.to(
          centerPos + Vector2((2 - i) * 1.0, (2 - i) * 1.0),
          EffectController(duration: 0.2, curve: Curves.easeOutBack),
        ),
      );
      card.add(RotateEffect.to(0, EffectController(duration: 0.2)));
    }

    await Future.delayed(const Duration(milliseconds: 200));
  }

  void _exitAnimation() {
    final exitY = size.y + 150;

    for (int i = 0; i < cards.length; i++) {
      final card = cards[i];
      final delay = i * 30;

      Future.delayed(Duration(milliseconds: delay), () {
        card.add(
          MoveEffect.by(
            Vector2(0, exitY),
            EffectController(duration: 0.6, curve: Curves.easeInCubic),
          ),
        );

        card.add(
          RotateEffect.by(
            (i.isEven ? 1 : -1) * 0.3,
            EffectController(duration: 0.6),
          ),
        );

        card.fadeToOpacity(0, duration: 0.5);
      });
    }

    final totalExitTime = (cards.length * 30) + 700;
    Future.delayed(Duration(milliseconds: totalExitTime), () {
      onComplete(specialties);
    });
  }
}

// ==================== CARDS BEHIND PACK COMPONENT ====================

class CardsBehindPackComponent extends PositionComponent with HasGameRef {
  late Sprite _cardBackSprite;
  double _opacity = 1.0;

  @override
  Future<void> onLoad() async {
    _cardBackSprite = await gameRef.loadSprite('card_back.png');
  }

  @override
  void render(Canvas canvas) {
    if (_opacity <= 0) return;
    
    final paint = Paint()..color = Colors.white.withOpacity(_opacity);
    
    // Dibujar varias cartas apiladas
    for (int i = 4; i >= 0; i--) {
      canvas.save();
      canvas.translate(i * 1.2, i * 1.2);
      
      if (i == 0) {
        final shadowPaint = Paint()
          ..color = Colors.black.withOpacity(0.2 * _opacity)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(2, 3, size.x, size.y),
            const Radius.circular(8),
          ),
          shadowPaint,
        );
      }
      
      _cardBackSprite.render(canvas, size: size, overridePaint: paint);
      canvas.restore();
    }
  }

  void fadeOut() {
    packAnimate(this, duration: 0.5, onUpdate: (t) => _opacity = 1 - t);
  }
}

// ==================== GLOW EFFECT COMPONENT ====================

// ==================== CARD COMPONENT ====================

class CardComponent extends PositionComponent with HasGameRef {
  final int index;
  final String specialty;
  
  late Sprite _backSprite;
  late Sprite _frontSprite;
  
  bool _isFlipped = false;
  double _opacity = 0.0;
  double _flipProgress = 0.0;
  bool _showSpecialty = false;
  
  double _floatPhase = 0.0;
  double _floatAmplitude = 0.0;
  bool _isFloating = false;

  /// La sigla (CD, DG, NR…) y el icono de la asignatura. Se resuelve una vez:
  /// el nombre del backend viene con muchas variantes y casarlo no es gratis.
  late final SubjectVisual _visual = subjectVisual(specialty);

  /// Marrón tinta del marco de la carta, el mismo que llevaba el nombre.
  static const Color _cardInk = Color(0xFF4E342E);

  CardComponent({
    required this.index,
    required this.specialty,
  }) {
    _floatPhase = index * 0.7;
  }

  @override
  Future<void> onLoad() async {
    _backSprite = await gameRef.loadSprite('card_back.png');
    _frontSprite = await gameRef.loadSprite('card_front.png');
  }

  @override
  void update(double dt) {
    // Limitar dt para evitar saltos grandes
    final clampedDt = dt.clamp(0.0, 0.05);
    super.update(clampedDt);
    
    if (_isFloating) {
      _floatPhase += clampedDt * 2.5;
    }
  }

  @override
  void render(Canvas canvas) {
    if (_opacity <= 0) return;
    
    canvas.save();
    
    final floatOffset = _isFloating ? sin(_floatPhase) * _floatAmplitude : 0.0;
    canvas.translate(0, floatOffset);
    
    // Sombra dinámica
    final shadowDistance = 6.0 + (_isFloating ? sin(_floatPhase) * 2.5 : 0);
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.3 * _opacity)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 10 + shadowDistance);
    
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(4, shadowDistance + 3, size.x, size.y),
        const Radius.circular(10),
      ),
      shadowPaint,
    );
    
    // Flip animation
    if (_flipProgress > 0 && _flipProgress < 1) {
      final scaleX = cos(_flipProgress * pi);
      canvas.translate(size.x / 2, 0);
      canvas.scale(scaleX.abs().clamp(0.05, 1.0), 1);
      canvas.translate(-size.x / 2, 0);
    }
    
    final paint = Paint()..color = Colors.white.withOpacity(_opacity);
    final showFront = _flipProgress >= 0.5;
    
    if (showFront && _isFlipped) {
      _frontSprite.render(canvas, size: size, overridePaint: paint);
      
      if (_showSpecialty) {
        _drawSpecialtyOverlay(canvas);
      }
    } else {
      _backSprite.render(canvas, size: size, overridePaint: paint);
    }
    
    canvas.restore();
  }

  /// Dónde cae la costura dentro del sprite de la carta, en fracción de su
  /// tamaño. Medido sobre card_front.png: el PNG lleva bastante aire alrededor
  /// y el marco cosido va por dentro, así que la zona utilizable es mucho menor
  /// que la carta (un 55% del ancho). Escribir contra el borde del componente
  /// dejaba el texto pisando la costura.
  static const double _seamLeft = 0.225;
  static const double _seamRight = 0.774;
  static const double _seamTop = 0.101;
  static const double _seamBottom = 0.887;

  /// Aire entre la costura y el contenido, para que no se toquen.
  static const double _seamInset = 0.035;

  void _drawSpecialtyOverlay(Canvas canvas) {
    // Recuadro de trabajo: por dentro de la costura, con su respiro.
    final left = size.x * (_seamLeft + _seamInset);
    final right = size.x * (_seamRight - _seamInset);
    final top = size.y * (_seamTop + _seamInset);
    final bottom = size.y * (_seamBottom - _seamInset);
    final centerX = (left + right) / 2;

    // Cuánto ha crecido la carta respecto al diseño original.
    final scale = size.x / PackGameBase.cardDesignWidth;

    // Icono de línea (Lucide) en el glifo de su fuente, tintado como el marco.
    final iconPainter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(_visual.icon.codePoint),
        style: TextStyle(
          fontSize: 30 * scale,
          fontFamily: _visual.icon.fontFamily,
          package: _visual.icon.fontPackage,
          color: _cardInk,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    iconPainter.layout();

    // La sigla (CD, DG…) en grande y a UNA línea: los nombres completos se
    // salían de la costura o quedaban a dos renglones apretados.
    final siglaPainter = TextPainter(
      text: TextSpan(
        text: _visual.sigla,
        style: TextStyle(
          fontSize: 17 * sqrt(scale),
          color: _cardInk,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );
    siglaPainter.layout();

    // La sigla se ancla al fondo del recuadro y el icono se centra en el hueco
    // que queda por encima.
    final siglaTop = bottom - siglaPainter.height;
    siglaPainter.paint(
      canvas,
      Offset(centerX - siglaPainter.width / 2, siglaTop),
    );
    iconPainter.paint(
      canvas,
      Offset(
        centerX - iconPainter.width / 2,
        (top + siglaTop) / 2 - iconPainter.height / 2,
      ),
    );
  }

  void setOpacity(double value) => _opacity = value;
  
  void stopFloating() {
    _isFloating = false;
    _floatAmplitude = 0;
  }

  void shootOut({
    required Vector2 from,
    required Vector2 to,
    required double targetAngle,
  }) {
    position = from;
    _opacity = 1.0;
    scale = Vector2.all(0.3);
    
    add(MoveEffect.to(
      to,
      EffectController(
        duration: 0.65,
        curve: Curves.easeOutBack,
      ),
      onComplete: () {
        _isFloating = true;
        _floatAmplitude = 3.5;
      },
    ));
    
    add(ScaleEffect.to(
      Vector2.all(1.0),
      EffectController(
        duration: 0.55,
        curve: Curves.elasticOut,
      ),
    ));
    
    add(RotateEffect.to(
      targetAngle,
      EffectController(
        duration: 0.5,
        curve: Curves.easeOutCubic,
      ),
    ));
  }

  void flipReveal() {
    if (_isFlipped) return;
    _isFlipped = true;
    
    add(ScaleEffect.to(
      Vector2.all(1.1),
      EffectController(
        duration: 0.1,
        curve: Curves.easeOut,
      ),
    )..onComplete = () {
      add(ScaleEffect.to(
        Vector2.all(1.0),
        EffectController(
          duration: 0.15,
          curve: Curves.easeInOut,
        ),
      ));
    });
    
    packAnimate(
      this,
      duration: 0.4,
      onUpdate: (t) {
        _flipProgress = Curves.easeInOut.transform(t);
        // A media vuelta la carta ya enseña su cara: es cuando se cambia.
        if (t >= 0.5) _showSpecialty = true;
      },
      onDone: () => _flipProgress = 1.0,
    );
  }

  void fadeToOpacity(double target, {required double duration}) {
    final startOpacity = _opacity;

    packAnimate(
      this,
      duration: duration,
      onUpdate: (t) => _opacity = startOpacity + (target - startOpacity) * t,
    );
  }
}

/// La estrella de cuatro puntas que lleva impresa el propio envoltorio:
/// puntas largas y cintura muy estrecha, que es lo que le da el aire de
/// destello dibujado a mano.
///
/// La comparten las chispas de todas las animaciones. Es el detalle que hace
/// que los destellos se lean como parte del sobre y no como confeti genérico.
Path packStar(double r) {
  final path = Path();
  final cintura = r * 0.28;
  path.moveTo(0, -r);
  path.quadraticBezierTo(cintura, -cintura, r, 0);
  path.quadraticBezierTo(cintura, cintura, 0, r);
  path.quadraticBezierTo(-cintura, cintura, -r, 0);
  path.quadraticBezierTo(-cintura, -cintura, 0, -r);
  path.close();
  return path;
}
