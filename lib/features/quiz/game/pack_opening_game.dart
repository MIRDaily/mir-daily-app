import 'dart:math';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flame/effects.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

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
TimerComponent _animate(
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

class PackOpeningGame extends FlameGame with HorizontalDragDetector {
  final List<String> specialties;
  final OnPackOpenComplete onComplete;
  
  // Componentes principales
  late CardsBehindPackComponent _cardsBehind;
  late GlowEffectComponent _glowEffect;
  late SparklesComponent _sparkles;
  late CutLineIndicatorComponent _cutLineIndicator;
  late PackBottomComponent _packBottom;
  late PackTopComponent _packTop;
  late List<CardComponent> _cards;
  
  // Estado
  double _tearProgress = 0.0;
  bool _isTearing = false;
  bool _tearComplete = false;
  double _lastDragX = 0.0;
  bool _isRevealing = false;
  bool _canInteract = true;
  bool _isVisible = true; // Control de visibilidad
  double _lastUpdateTime = 0.0;
  
  // Posiciones
  late Vector2 _packPosition;
  late Vector2 _packSize;
  late Rect _tearZone;
  
  // Animación flotante
  double _floatPhase = 0.0;
  double _baseY = 0.0;
  
  // Corte: posición Y donde se corta (desde arriba del pack)
  static const double _cutLineY = 55.0;
  
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

  /// Tamaño real, calculado en onLoad: depende de la pantalla, porque lo que
  /// cabe con dos por fila e inclinación no es lo mismo en un móvil estrecho
  /// que en uno ancho.
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
  /// _loadComponents, o el reparto contaría un número de filas equivocado.
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
  /// carta. Antes se daba por hecho [_cardsPerRow] y con tres por fila las
  /// cartas salían demasiado grandes.
  int get _cardsWidestRow =>
      _rowSizes.fold(1, (a, b) => a > b ? a : b);

  /// Solo para tests: el reparto que saldría en una pantalla dada, para poder
  /// comprobar que las cartas no se solapan.
  @visibleForTesting
  List<Vector2> debugCardLayout(Vector2 screen, Random random) {
    onGameResize(screen);
    _computeCardSize();
    return _generateCardPositions(random: random);
  }

  /// Solo para tests: lo que barre una carta contando su inclinación.
  @visibleForTesting
  Vector2 get debugTiltedCardSize =>
      Vector2(_tiltedCardWidth, _tiltedCardHeight);

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


  // Getters públicos para el overlay de UI
  bool get showButtons => false;
  double get tearProgress => _tearProgress;
  bool get tearComplete => _tearComplete;
  
  // Métodos para controlar visibilidad desde fuera
  void setVisible(bool visible) {
    _isVisible = visible;
    if (visible) {
      // Resetear el tiempo para evitar saltos
      _lastUpdateTime = 0.0;
    }
  }

  PackOpeningGame({
    required this.specialties,
    required this.onComplete,
  });

  /// El fondo que Flame pinta por debajo del juego. Sin esto es NEGRO, y como
  /// GameWidget lo pinta desde el primer frame pero no muestra el resto (ni
  /// siquiera su backgroundBuilder) hasta que onLoad() termina, la pantalla
  /// daba un pantallazo negro al entrar.
  @override
  Color backgroundColor() => AppColors.background;

  @override
  Future<void> onLoad() async {
    // Antes que nada: los componentes de abajo ya se montan con este tamaño.
    _computeCardSize();

    // SOBRE MÁS GRANDE
    _packSize = Vector2(240, 320);
    _packPosition = Vector2(
      size.x / 2 - _packSize.x / 2,
      size.y / 2 - _packSize.y / 2 - 30,
    );
    _baseY = _packPosition.y;
    
    // ZONA DE RASGADO MÁS AMPLIA (más margen horizontal y vertical)
    _tearZone = Rect.fromLTWH(
      _packPosition.x - 60,  // Más margen horizontal
      _packPosition.y + _cutLineY - 50,  // Más margen arriba
      _packSize.x + 120,  // Más ancho
      100,  // Más alto
    );
    
    await _loadComponents();
  }

  Future<void> _loadComponents() async {
    // 1. CAPA MÁS BAJA: Cartas detrás del pack (visible al cortar)
    _cardsBehind = CardsBehindPackComponent()
      ..position = Vector2(
        _packPosition.x + _packSize.x / 2 - cardWidth / 2,
        _packPosition.y + _cutLineY + 8,
      )
      ..size = Vector2(cardWidth, cardHeight)
      ..priority = 0;
    add(_cardsBehind);
    
    // 2. Efecto Glow (inicialmente oculto)
    _glowEffect = GlowEffectComponent(
      packPosition: _packPosition,
      packSize: _packSize,
      cutLineY: _cutLineY,
    )..priority = 1;
    add(_glowEffect);
    
    // 3. Parte inferior del pack
    _packBottom = PackBottomComponent(cutLineY: _cutLineY)
      ..position = _packPosition
      ..size = _packSize
      ..priority = 2;
    add(_packBottom);
    
    // 4. Chispas (encima del pack bottom, debajo del top)
    _sparkles = SparklesComponent(
      packPosition: _packPosition,
      packSize: _packSize,
      cutLineY: _cutLineY,
    )..priority = 3;
    add(_sparkles);
    
    // 5. Parte superior del pack (la que se corta)
    _packTop = PackTopComponent(cutLineY: _cutLineY)
      ..position = _packPosition
      ..size = _packSize
      ..priority = 4;
    add(_packTop);
    
    // 6. Línea de corte parpadeante (encima de todo)
    _cutLineIndicator = CutLineIndicatorComponent(
      packPosition: _packPosition,
      packSize: _packSize,
      cutLineY: _cutLineY,
    )..priority = 5;
    add(_cutLineIndicator);
    
    // 6. Crear cartas individuales (ocultas inicialmente)
    // Una carta por pregunta del sobre diario (5 con la mecánica actual).
    _cards = [];
    final cardCount = specialties.isNotEmpty ? specialties.length : 5;
    for (int i = 0; i < cardCount; i++) {
      final card = CardComponent(
        index: i,
        specialty: i < specialties.length ? specialties[i] : 'General',
      )
        ..position = Vector2(
          _packPosition.x + _packSize.x / 2 - cardWidth / 2,
          _packPosition.y + _cutLineY + 10,
        )
        ..size = Vector2(cardWidth, cardHeight)
        ..priority = 10 + i
        ..setOpacity(0)
        ..scale = Vector2.all(0.3);
      _cards.add(card);
      add(card);
    }
  }

  @override
  void update(double dt) {
    // Si no es visible, no actualizar nada (evita acumulación de tiempo)
    if (!_isVisible) {
      return;
    }
    
    // Limitar dt para evitar saltos grandes
    final clampedDt = dt.clamp(0.0, 0.033); // Máximo ~30 FPS worth de tiempo
    
    super.update(clampedDt);
    
    if (!_tearComplete) {
      _floatPhase += clampedDt * 2.0;
      final floatOffset = sin(_floatPhase) * 5.0;
      
      _packBottom.position.y = _baseY + floatOffset;
      _packTop.position.y = _baseY + floatOffset;
      _cardsBehind.position.y = _baseY + _cutLineY + 8 + floatOffset;
      _glowEffect.updatePosition(_baseY + floatOffset);
      _cutLineIndicator.updatePosition(_baseY + floatOffset);
      
      _packBottom.shadowIntensity = 0.25 + sin(_floatPhase) * 0.05;
    }
  }

  @override
  void onHorizontalDragStart(DragStartInfo info) {
    if (_tearComplete || !_canInteract) return;
    
    final touchPos = info.eventPosition.global;
    
    if (_tearZone.contains(Offset(touchPos.x, touchPos.y))) {
      _isTearing = true;
      _lastDragX = touchPos.x;
      _packTop.startTearing();
      _cutLineIndicator.hide(); // Ocultar la línea guía
    }
  }

  @override
  void onHorizontalDragUpdate(DragUpdateInfo info) {
    if (!_isTearing || _tearComplete) return;
    
    final currentX = info.eventPosition.global.x;
    final delta = (currentX - _lastDragX).abs();
    _lastDragX = currentX;
    
    _tearProgress = (_tearProgress + delta / 100.0).clamp(0.0, 1.0);
    _packTop.tearProgress = _tearProgress;
    
    // Mostrar glow progresivamente
    _glowEffect.intensity = _tearProgress;
    
    if (_tearProgress >= 1.0) {
      _completeTear();
    }
  }

  @override
  void onHorizontalDragEnd(DragEndInfo info) {
    _isTearing = false;
    
    if (!_tearComplete && _tearProgress < 1.0 && _tearProgress > 0.1) {
      _packTop.bounceBack(() {
        _tearProgress = 0.0;
        _glowEffect.intensity = 0.0;
        _cutLineIndicator.show(); // Mostrar la línea guía de nuevo
      });
    } else if (_tearProgress <= 0.1) {
      _tearProgress = 0.0;
      _packTop.tearProgress = 0.0;
      _glowEffect.intensity = 0.0;
      _cutLineIndicator.show(); // Mostrar la línea guía de nuevo
    }
  }

  void _completeTear() {
    _tearComplete = true;
    _isTearing = false;
    _canInteract = false;
    
    // Activar chispas
    _sparkles.explode();
    
    // Glow al máximo y luego desvanecer
    _glowEffect.flashAndFade();
    
    _packTop.flyAway(() {
      _packTop.removeFromParent();
      
      Future.delayed(const Duration(milliseconds: 200), () {
        _dealCardsWithExplosion();
      });
    });
  }

  void _dealCardsWithExplosion() {
    // Ocultar las cartas detrás del pack
    _cardsBehind.fadeOut();
    
    // Desvanecer el pack bottom
    _packBottom.fadeOut(0.8);
    
    final random = Random();

    final targetPositions = _generateCardPositions(random: random);

    // La inclinación va en abanico, no al azar: dentro de cada fila la carta
    // se ladea según lo lejos que esté del centro, como en la web. El tope es
    // el mismo que se usó para repartirlas, así que siguen sin tocarse.
    final targetAngles = _generateCardAngles();
    
    final originPos = Vector2(
      _packPosition.x + _packSize.x / 2 - cardWidth / 2,
      _packPosition.y + _cutLineY,
    );
    
    for (int i = 0; i < _cards.length; i++) {
      final card = _cards[i];
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
    
    final totalDealTime = (_cards.length * 70) + 600;
    Future.delayed(Duration(milliseconds: totalDealTime), () {
      _startRevealSequence();
    });
  }

  /// Reparte las cartas por la pantalla como si las hubieran tirado a mano.
  ///
  /// Por debajo hay una rejilla de [_cardsPerRow] por fila, pero cada carta se
  /// desvía de su sitio y se ladea, así que no se lee como una tabla. El truco
  /// para que no se solapen nunca es que cada una ocupa el hueco de su caja YA
  /// inclinada, y el desfase que puede moverse está reservado de antemano en
  /// [_computeCardSize]: el desorden cabe siempre, no depende de la suerte.
  List<Vector2> _generateCardPositions({required Random random}) {
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
      final baseY = startY + row * (slotH + _cardGapY);

      // El desvío ya no es al azar sino un ARCO: dentro de cada fila, la carta
      // del medio queda un poco más alta que las de los lados, igual que en el
      // dashboard de la web. Con el desfase aleatorio el reparto parecía un
      // montón de cartas rociadas; así se lee como un abanico puesto a mano.
      final mid = (n - 1) / 2;

      for (var i = 0; i < n; i++) {
        // La carta va centrada en su hueco: el hueco es su caja inclinada, que
        // es más grande que ella.
        final slotX = rowStartX + i * (slotW + _cardGapX);
        final x = slotX + (slotW - cardWidth) / 2;
        final y = baseY + (slotH - cardHeight) / 2;

        // 1 en el centro de la fila y 0 en los extremos. El alto del arco se
        // limita al desfase que [_computeCardSize] ya tenía reservado, así que
        // no puede hacer que dos cartas se toquen.
        final t = mid == 0 ? 0.0 : 1 - pow((i - mid) / mid, 2).toDouble();
        positions.add(Vector2(x, y - t * _cardArc));
      }
    }

    return positions;
  }

  /// Inclinación de cada carta, en el mismo orden que [_generateCardPositions].
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
    
    for (int i = 0; i < _cards.length; i++) {
      final delayMs = i * 300;
      
      Future.delayed(Duration(milliseconds: delayMs), () {
        if (i < _cards.length) {
          _cards[i].flipReveal();
        }
      });
    }
    
    final lastRevealTime = (_cards.length - 1) * 300;
    const waitAfterFirst = 6000;
    final waitAfterLast = lastRevealTime + 2000;
    final totalWait = max(waitAfterFirst, waitAfterLast);
    
    Future.delayed(Duration(milliseconds: totalWait), () {
      _gatherAndShuffle();
    });
  }

  void _gatherAndShuffle() async {
    final centerX = size.x / 2 - cardWidth / 2;
    final centerY = size.y / 2 - cardHeight / 2;
    final centerPos = Vector2(centerX, centerY);
    
    for (int i = 0; i < _cards.length; i++) {
      final card = _cards[i];
      final delay = i * 50;
      
      Future.delayed(Duration(milliseconds: delay), () {
        card.stopFloating();
        
        final stackIndex = (_cards.length - 1 - i);
        final stackOffset = Vector2(stackIndex * 0.8, stackIndex * 0.8);
        
        card.add(MoveEffect.to(
          centerPos + stackOffset,
          EffectController(
            duration: 0.4,
            curve: Curves.easeOutBack,
          ),
        ));
        
        card.add(RotateEffect.to(
          0,
          EffectController(
            duration: 0.35,
            curve: Curves.easeOutCubic,
          ),
        ));
        
        card.add(ScaleEffect.to(
          Vector2.all(0.8),
          EffectController(duration: 0.4),
        ));
      });
    }
    
    await Future.delayed(Duration(milliseconds: (_cards.length * 50) + 500));
    
    await _performShuffleAnimation(centerPos);
    
    await Future.delayed(const Duration(milliseconds: 300));
    _exitAnimation();
  }

  Future<void> _performShuffleAnimation(Vector2 centerPos) async {
    for (int i = 3; i < _cards.length; i++) {
      _cards[i].fadeToOpacity(0, duration: 0.2);
    }
    
    await Future.delayed(const Duration(milliseconds: 250));
    
    final shuffleCards = _cards.take(3).toList();
    
    for (int shuffle = 0; shuffle < 4; shuffle++) {
      await Future.delayed(const Duration(milliseconds: 150));
      
      for (int i = 0; i < shuffleCards.length; i++) {
        final card = shuffleCards[i];
        final offsetX = (i - 1) * 55.0;
        final offsetY = (shuffle % 2 == 0 ? -1.0 : 1.0) * (i == 1 ? 0.0 : 18.0);
        
        card.add(MoveEffect.to(
          centerPos + Vector2(offsetX, offsetY),
          EffectController(
            duration: 0.12,
            curve: Curves.easeOutCubic,
          ),
        ));
        
        card.add(RotateEffect.to(
          (i - 1) * 0.08,
          EffectController(duration: 0.12),
        ));
      }
    }
    
    await Future.delayed(const Duration(milliseconds: 200));
    
    for (int i = 0; i < shuffleCards.length; i++) {
      final card = shuffleCards[i];
      card.add(MoveEffect.to(
        centerPos + Vector2((2 - i) * 1.0, (2 - i) * 1.0),
        EffectController(
          duration: 0.2,
          curve: Curves.easeOutBack,
        ),
      ));
      card.add(RotateEffect.to(
        0,
        EffectController(duration: 0.2),
      ));
    }
    
    await Future.delayed(const Duration(milliseconds: 300));
  }

  void _exitAnimation() {
    final exitY = size.y + 150;
    
    for (int i = 0; i < _cards.length; i++) {
      final card = _cards[i];
      final delay = i * 30;
      
      Future.delayed(Duration(milliseconds: delay), () {
        card.add(MoveEffect.by(
          Vector2(0, exitY),
          EffectController(
            duration: 0.6,
            curve: Curves.easeInCubic,
          ),
        ));
        
        card.add(RotateEffect.by(
          (i.isEven ? 1 : -1) * 0.3,
          EffectController(duration: 0.6),
        ));
        
        card.fadeToOpacity(0, duration: 0.5);
      });
    }
    
    final totalExitTime = (_cards.length * 30) + 700;
    Future.delayed(Duration(milliseconds: totalExitTime), () {
      onComplete(specialties);
    });
  }
  
  // Métodos públicos para compatibilidad
  void revealAllCards() {}
  void skipReveal() => _gatherAndShuffle();
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
    _animate(this, duration: 0.5, onUpdate: (t) => _opacity = 1 - t);
  }
}

// ==================== GLOW EFFECT COMPONENT ====================

class GlowEffectComponent extends PositionComponent {
  final Vector2 packPosition;
  final Vector2 packSize;
  final double cutLineY;
  
  double intensity = 0.0;
  double _wavePhase = 0.0;
  double _flashIntensity = 0.0;
  bool _isFlashing = false;

  GlowEffectComponent({
    required this.packPosition,
    required this.packSize,
    required this.cutLineY,
  });

  void updatePosition(double newY) {
    position = Vector2(packPosition.x, newY);
  }

  @override
  void update(double dt) {
    super.update(dt);
    _wavePhase += dt * 8.0;
  }

  @override
  void render(Canvas canvas) {
    if (intensity <= 0 && _flashIntensity <= 0) return;
    
    final currentIntensity = max(intensity, _flashIntensity);
    
    // Centro del glow (en la línea de corte)
    final centerX = packSize.x / 2;
    final centerY = cutLineY;
    
    // Ondulación del borde (material design wave)
    final waveAmplitude = 8.0 * currentIntensity;
    
    // Gradiente radial con ondulación
    for (int layer = 3; layer >= 0; layer--) {
      final layerIntensity = currentIntensity * (0.3 + layer * 0.2);
      final baseRadius = 30.0 + layer * 25.0;
      
      // Calcular radio con ondulación
      final waveOffset = sin(_wavePhase + layer * 0.5) * waveAmplitude;
      final radius = baseRadius + waveOffset;
      
      final glowPaint = Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.amber.withOpacity(layerIntensity * 0.8),
            Colors.orange.withOpacity(layerIntensity * 0.4),
            Colors.transparent,
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(Rect.fromCircle(
          center: Offset(centerX, centerY),
          radius: radius,
        ));
      
      canvas.drawCircle(
        Offset(centerX, centerY),
        radius,
        glowPaint,
      );
    }
    
    // Línea brillante central
    if (currentIntensity > 0.3) {
      final linePaint = Paint()
        ..color = Colors.white.withOpacity(currentIntensity * 0.9)
        ..strokeWidth = 3 + sin(_wavePhase * 2) * 1
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 6 + sin(_wavePhase) * 2);
      
      final lineWidth = packSize.x * 0.7 * currentIntensity;
      canvas.drawLine(
        Offset(centerX - lineWidth / 2, centerY),
        Offset(centerX + lineWidth / 2, centerY),
        linePaint,
      );
    }
  }

  void flashAndFade() {
    _isFlashing = true;
    _flashIntensity = 1.5;

    _animate(
      this,
      duration: 0.8,
      onUpdate: (t) =>
          _flashIntensity = 1.5 * (1 - Curves.easeOutCubic.transform(t)),
      onDone: () {
        _isFlashing = false;
        intensity = 0;
      },
    );
  }
}

// ==================== SPARKLES COMPONENT ====================

class SparklesComponent extends PositionComponent {
  final Vector2 packPosition;
  final Vector2 packSize;
  final double cutLineY;
  
  final List<Sparkle> _sparkles = [];
  final Random _random = Random();
  bool _isExploding = false;

  SparklesComponent({
    required this.packPosition,
    required this.packSize,
    required this.cutLineY,
  });

  void explode() {
    _isExploding = true;
    
    // Crear muchas chispas
    for (int i = 0; i < 40; i++) {
      final angle = _random.nextDouble() * 2 * pi;
      final speed = 150 + _random.nextDouble() * 200;
      final size = 3 + _random.nextDouble() * 5;
      
      _sparkles.add(Sparkle(
        x: packSize.x / 2,
        y: cutLineY,
        vx: cos(angle) * speed,
        vy: sin(angle) * speed - 100, // Sesgo hacia arriba
        size: size,
        color: _random.nextBool() 
          ? Colors.amber 
          : (_random.nextBool() ? Colors.orange : Colors.white),
        life: 0.6 + _random.nextDouble() * 0.4,
      ));
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    
    if (!_isExploding) return;
    
    for (final sparkle in _sparkles) {
      sparkle.x += sparkle.vx * dt;
      sparkle.y += sparkle.vy * dt;
      sparkle.vy += 400 * dt; // Gravedad
      sparkle.life -= dt;
      sparkle.size *= 0.98;
    }
    
    _sparkles.removeWhere((s) => s.life <= 0 || s.size < 0.5);
    
    if (_sparkles.isEmpty) {
      _isExploding = false;
    }
  }

  @override
  void render(Canvas canvas) {
    if (!_isExploding) return;
    
    canvas.save();
    canvas.translate(packPosition.x, packPosition.y);
    
    for (final sparkle in _sparkles) {
      final opacity = (sparkle.life * 2).clamp(0.0, 1.0);
      
      final paint = Paint()
        ..color = sparkle.color.withOpacity(opacity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
      
      canvas.drawCircle(
        Offset(sparkle.x, sparkle.y),
        sparkle.size,
        paint,
      );
      
      // Estela
      final trailPaint = Paint()
        ..color = sparkle.color.withOpacity(opacity * 0.3)
        ..strokeWidth = sparkle.size * 0.5
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      
      canvas.drawLine(
        Offset(sparkle.x, sparkle.y),
        Offset(sparkle.x - sparkle.vx * 0.02, sparkle.y - sparkle.vy * 0.02),
        trailPaint,
      );
    }
    
    canvas.restore();
  }
}

class Sparkle {
  double x, y;
  double vx, vy;
  double size;
  Color color;
  double life;
  
  Sparkle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.size,
    required this.color,
    required this.life,
  });
}

// ==================== CUT LINE INDICATOR COMPONENT ====================

class CutLineIndicatorComponent extends PositionComponent {
  final Vector2 packPosition;
  final Vector2 packSize;
  final double cutLineY;
  
  double _phase = 0.0;
  bool _isVisible = true;
  double _baseY = 0.0;

  /// Avance de la tijera por la línea (0..1, en bucle). Es lo que enseña el
  /// gesto: recorre el corte de izquierda a derecha, descansa y vuelve.
  double _scissorsT = 0.0;

  /// Lo que tarda una pasada entera, descanso incluido.
  static const double _scissorsCycle = 2.6;

  /// Parte del ciclo que la tijera pasa recorriendo; el resto está fuera.
  static const double _scissorsTravel = 0.72;

  CutLineIndicatorComponent({
    required this.packPosition,
    required this.packSize,
    required this.cutLineY,
  }) {
    _baseY = packPosition.y;
  }

  void updatePosition(double newY) {
    _baseY = newY;
  }

  void hide() {
    _isVisible = false;
  }

  void show() {
    _isVisible = true;
  }

  @override
  void update(double dt) {
    super.update(dt);
    _phase += dt * 4.0;
    _scissorsT = (_scissorsT + dt / _scissorsCycle) % 1.0;
  }

  @override
  void render(Canvas canvas) {
    if (!_isVisible) return;
    
    final blinkOpacity = 0.5 + 0.5 * sin(_phase);
    
    final y = _baseY + cutLineY;
    
    // Configuración de guiones - más anchos y mejor distribuidos
    const dashWidth = 14.0;
    const dashGap = 10.0;
    const dashHeight = 4.0;
    const margin = 10.0; // Margen desde los bordes del pack
    
    // Calcular el ancho total disponible
    final totalWidth = packSize.x - (margin * 2);
    
    // Calcular cuántos guiones caben
    final dashPlusGap = dashWidth + dashGap;
    final numDashes = ((totalWidth + dashGap) / dashPlusGap).floor();
    
    // Calcular el ancho real que ocuparán los guiones
    final actualWidth = numDashes * dashWidth + (numDashes - 1) * dashGap;
    
    // Calcular el offset para centrar
    final startX = packPosition.x + (packSize.x - actualWidth) / 2;
    
    // Color de los guiones
    final dashPaint = Paint()
      ..color = Colors.white.withOpacity(blinkOpacity * 0.9)
      ..style = PaintingStyle.fill;
    
    // Sombra/glow de los guiones
    final glowPaint = Paint()
      ..color = Colors.amber.withOpacity(blinkOpacity * 0.4)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    
    // Dibujar guiones centrados
    for (int i = 0; i < numDashes; i++) {
      final x = startX + i * dashPlusGap;
      
      // Glow
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x - 2, y - dashHeight / 2 - 2, dashWidth + 4, dashHeight + 4),
          const Radius.circular(3),
        ),
        glowPaint,
      );
      
      // Guión
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y - dashHeight / 2, dashWidth, dashHeight),
          const Radius.circular(2),
        ),
        dashPaint,
      );
    }

    _renderScissors(canvas, startX, actualWidth, y);
  }

  /// La tijera que recorre el corte. Sustituye al cartel de "desliza en la
  /// costura": enseña dónde y hacia dónde va el gesto sin escribirlo.
  void _renderScissors(Canvas canvas, double startX, double width, double y) {
    if (_scissorsT > _scissorsTravel) return; // descansando fuera de plano

    final p = _scissorsT / _scissorsTravel;

    // Entra y sale con un fundido, para que no aparezca de golpe al reiniciar.
    final fade = min(p / 0.12, (1 - p) / 0.12).clamp(0.0, 1.0);

    final painter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(Icons.content_cut.codePoint),
        style: TextStyle(
          fontFamily: Icons.content_cut.fontFamily,
          package: Icons.content_cut.fontPackage,
          fontSize: 26,
          color: Colors.white.withOpacity(fade),
          shadows: [
            Shadow(
              color: Colors.black.withOpacity(0.35 * fade),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    painter.layout();

    canvas.save();
    canvas.translate(startX + p * width, y);
    // Las hojas van abriendo y cerrando mientras avanza.
    canvas.rotate(sin(_scissorsT * _scissorsCycle * 14) * 0.14);
    painter.paint(canvas, Offset(-painter.width / 2, -painter.height / 2));
    canvas.restore();
  }
}

// ==================== PACK BOTTOM COMPONENT ====================

class PackBottomComponent extends PositionComponent with HasGameRef {
  final double cutLineY;
  late Sprite _sprite;
  double shadowIntensity = 0.25;
  double _opacity = 1.0;

  PackBottomComponent({required this.cutLineY});

  @override
  Future<void> onLoad() async {
    _sprite = await gameRef.loadSprite('pack_closed.png');
  }

  @override
  void render(Canvas canvas) {
    if (_opacity <= 0) return;
    
    canvas.save();
    
    // Sombra (solo para la parte inferior, NO se ve arriba)
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(shadowIntensity * _opacity)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 15);
    
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(8, cutLineY + 12, size.x - 4, size.y - cutLineY - 8),
        const Radius.circular(12),
      ),
      shadowPaint,
    );
    
    // Clipear para mostrar solo la parte inferior
    canvas.clipRect(Rect.fromLTWH(0, cutLineY, size.x, size.y - cutLineY));
    
    final paint = Paint()..color = Colors.white.withOpacity(_opacity);
    _sprite.render(canvas, size: size, overridePaint: paint);
    
    canvas.restore();
  }

  void fadeOut(double duration) {
    final startOpacity = _opacity;

    _animate(
      this,
      duration: duration,
      onUpdate: (t) =>
          _opacity = startOpacity * (1 - Curves.easeOut.transform(t)),
    );
  }
}

// ==================== PACK TOP COMPONENT ====================

class PackTopComponent extends PositionComponent with HasGameRef {
  final double cutLineY;
  late Sprite _sprite;
  
  double _tearProgress = 0.0;
  bool _isTearing = false;
  double _shakeOffset = 0.0;
  double shadowIntensity = 0.0; // Empieza en 0 para que no se vea
  
  bool _isFlying = false;
  double _flyY = 0.0;
  double _flyRotation = 0.0;
  double _opacity = 1.0;

  PackTopComponent({required this.cutLineY});

  @override
  Future<void> onLoad() async {
    _sprite = await gameRef.loadSprite('pack_closed.png');
  }

  @override
  void render(Canvas canvas) {
    if (_opacity <= 0) return;
    
    canvas.save();
    
    if (_isFlying) {
      canvas.translate(size.x / 2, cutLineY / 2);
      canvas.rotate(_flyRotation);
      canvas.translate(-size.x / 2, -cutLineY / 2 + _flyY);
    } else {
      canvas.translate(_shakeOffset, -_tearProgress * 20);
    }
    
    // Clipear para mostrar solo la parte superior
    canvas.clipRect(Rect.fromLTWH(0, 0, size.x, cutLineY));
    
    final paint = Paint()..color = Colors.white.withOpacity(_opacity);
    _sprite.render(canvas, size: size, overridePaint: paint);
    
    // Sombra inferior del corte (solo visible cuando se está rasgando)
    if (_tearProgress > 0 && !_isFlying) {
      final shadowPaint = Paint()
        ..color = Colors.black.withOpacity(0.3 * _tearProgress)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      
      canvas.drawRect(
        Rect.fromLTWH(0, cutLineY - 5, size.x, 10),
        shadowPaint,
      );
    }
    
    canvas.restore();
  }

  set tearProgress(double value) {
    _tearProgress = value;
    if (_isTearing) {
      _shakeOffset = sin(value * 25) * 4 * value;
    }
  }

  /// El rebote en curso, si lo hay. Se guarda para poder cortarlo: si el
  /// usuario vuelve a rasgar mientras el sobre rebota, dejarlo acabar pondría
  /// el desgarro a cero encima del que acaba de empezar.
  TimerComponent? _bounce;

  void startTearing() {
    _bounce?.removeFromParent();
    _bounce = null;
    _isTearing = true;
  }

  void bounceBack(VoidCallback onComplete) {
    final startProgress = _tearProgress;

    _bounce = _animate(
      this,
      duration: 0.35,
      onUpdate: (t) {
        _tearProgress = startProgress * (1 - Curves.elasticOut.transform(t));
        _shakeOffset = 0;
      },
      onDone: () {
        _bounce = null;
        _isTearing = false;
        onComplete();
      },
    );
  }

  void flyAway(VoidCallback onComplete) {
    _isFlying = true;
    _isTearing = false;

    _animate(
      this,
      duration: 0.55,
      onUpdate: (t) {
        _flyY = -Curves.easeOutCubic.transform(t) * 350;
        _flyRotation = Curves.easeOut.transform(t) * 0.6;
        _opacity = 1 - Curves.easeIn.transform(t);
      },
      onDone: onComplete,
    );
  }
}

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
  
  static const Map<String, String> specialtyEmojis = {
    'Cardiología': '❤️',
    'Neurología': '🧠',
    'Neumología': '🫁',
    'Digestivo': '🍽️',
    'Nefrología': '💧',
    'Pediatría': '👶',
    'Infecciosas': '🦠',
    'Traumatología': '🦴',
    'Dermatología': '🧴',
    'Oftalmología': '👁️',
    'Ginecología': '🤰',
    'Psiquiatría': '🧘',
    'Cirugía': '🔪',
    'Farmacología': '💊',
    'Hematología': '🩸',
    'Endocrinología': '⚖️',
    'General': '🏥',
  };

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
    final emoji = specialtyEmojis[specialty] ?? specialtyEmojis['General']!;

    // Recuadro de trabajo: por dentro de la costura, con su respiro.
    final left = size.x * (_seamLeft + _seamInset);
    final right = size.x * (_seamRight - _seamInset);
    final top = size.y * (_seamTop + _seamInset);
    final bottom = size.y * (_seamBottom - _seamInset);
    final boxWidth = right - left;
    final centerX = (left + right) / 2;

    // Cuánto ha crecido la carta respecto al diseño original.
    final scale = size.x / PackOpeningGame.cardDesignWidth;

    final emojiPainter = TextPainter(
      text: TextSpan(text: emoji, style: TextStyle(fontSize: 30 * scale)),
      textDirection: TextDirection.ltr,
    );
    emojiPainter.layout();

    final namePainter = TextPainter(
      text: TextSpan(
        text: specialty,
        style: TextStyle(
          fontSize: 11 * sqrt(scale),
          color: Colors.brown.shade800,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: 2,
      ellipsis: '…',
    );
    namePainter.layout(maxWidth: boxWidth);

    // El nombre se ancla al fondo del recuadro y el emoji se centra en lo que
    // queda por encima.
    final nameTop = bottom - namePainter.height;
    namePainter.paint(canvas, Offset(centerX - namePainter.width / 2, nameTop));
    emojiPainter.paint(
      canvas,
      Offset(
        centerX - emojiPainter.width / 2,
        (top + nameTop) / 2 - emojiPainter.height / 2,
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
    
    _animate(
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

    _animate(
      this,
      duration: duration,
      onUpdate: (t) => _opacity = startOpacity + (target - startOpacity) * t,
    );
  }
}
