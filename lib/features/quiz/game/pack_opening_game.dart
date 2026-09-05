import 'dart:math';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import 'pack_game_base.dart';

/// Apertura clásica: **rasgar el sobre por la costura**.
///
/// Se desliza el dedo por la banda de puntos que recorre la tijera, el
/// envoltorio se va abriendo y, al llegar al final, la parte de arriba sale
/// volando y aparecen las cartas. El premio (reparto, revelado y barajado) lo
/// pone [PackGameBase]; aquí solo vive el gesto.
class PackOpeningGame extends PackGameBase with HorizontalDragDetector {
  PackOpeningGame({
    required super.specialties,
    required super.onComplete,
    super.haptics,
  });

  /// El dedo está rasgando: la vibración sigue al desgarro.
  @override
  bool get gripped => _isTearing;

  // Componentes del envoltorio
  late GlowEffectComponent _glowEffect;
  late SparklesComponent _sparkles;
  late CutLineIndicatorComponent _cutLineIndicator;
  late PackBottomComponent _packBottom;
  late PackTopComponent _packTop;

  // Estado del rasgado
  double _tearProgress = 0.0;
  bool _isTearing = false;
  double _lastDragX = 0.0;
  bool _canInteract = true;

  /// Corte: posición Y donde se corta (desde arriba del pack).
  static const double _cutLineY = 55.0;

  @override
  double get packMouthY => _cutLineY;

  @override
  double get openProgress => _tearProgress;

  /// Cuánto se ha rasgado el sobre, 0..1.
  double get tearProgress => _tearProgress;

  /// Alias histórico de [opened].
  bool get tearComplete => opened;

  // ---- Zona donde se admite el gesto de rasgar ----
  //
  // El sobre se corta por la costura: la banda de puntos por la que pasa la
  // tijera de [CutLineIndicatorComponent], a [_cutLineY] del borde superior
  // del sobre. La banda sigue a esa costura y no baja al cuerpo del sobre:
  // rasgar por el medio no significa nada, y una zona grande se come el
  // deslizamiento horizontal del PageView sin motivo.

  /// Lo que la banda se sale del sobre por cada lado. Un dedo de más para que
  /// el gesto empiece cómodo, sin invadir el resto de la pantalla.
  static const double _tearZoneSideMargin = 40.0;

  /// Alto de la banda, centrada en la costura.
  static const double _tearZoneHeight = 110.0;

  /// La banda de rasgado, en coordenadas DEL JUEGO (no de la pantalla).
  ///
  /// Se calcula al vuelo, no se guarda: así no puede quedarse con la posición
  /// de antes de girar la pantalla. Sale una vez por gesto, no por fotograma.
  Rect get _tearZone => Rect.fromLTWH(
    packPosition.x - _tearZoneSideMargin,
    packPosition.y + _cutLineY - _tearZoneHeight / 2,
    packSize.x + 2 * _tearZoneSideMargin,
    _tearZoneHeight,
  );

  /// Solo para tests: dónde admite el juego el gesto de rasgar.
  @visibleForTesting
  Rect get debugTearZone => _tearZone;

  /// Solo para tests: la costura, en coordenadas del juego.
  @visibleForTesting
  double get debugSeamY => packPosition.y + _cutLineY;

  @override
  Future<void> loadPackVisuals() async {
    // 1. Efecto Glow (inicialmente oculto)
    _glowEffect = GlowEffectComponent(
      packPosition: packPosition,
      packSize: packSize,
      cutLineY: _cutLineY,
    )..priority = 1;
    add(_glowEffect);

    // 2. Parte inferior del pack
    _packBottom = PackBottomComponent(cutLineY: _cutLineY)..priority = 2;
    add(_packBottom);

    // 3. Chispas (encima del pack bottom, debajo del top)
    _sparkles = SparklesComponent(
      packPosition: packPosition,
      packSize: packSize,
      cutLineY: _cutLineY,
    )..priority = 3;
    add(_sparkles);

    // 4. Parte superior del pack (la que se corta)
    _packTop = PackTopComponent(cutLineY: _cutLineY)..priority = 4;
    add(_packTop);

    // 5. Línea de corte parpadeante (encima de todo)
    _cutLineIndicator = CutLineIndicatorComponent(
      packPosition: packPosition,
      packSize: packSize,
      cutLineY: _cutLineY,
    )..priority = 5;
    add(_cutLineIndicator);
  }

  @override
  void placePackVisuals() {
    _packBottom
      ..position = packPosition
      ..size = packSize;

    _packTop
      ..position = packPosition
      ..size = packSize;

    _glowEffect.updatePosition(baseY);
    _cutLineIndicator.updatePosition(baseY);
  }

  @override
  void floatPackVisuals(double y, double phase) {
    _packBottom.position.y = y;
    _packTop.position.y = y;
    _glowEffect.updatePosition(y);
    _cutLineIndicator.updatePosition(y);

    _packBottom.shadowIntensity = 0.25 + sin(phase) * 0.05;
  }

  @override
  void dismissPackVisuals() {
    // El _packTop ya se ha ido volando en _completeTear; queda el de abajo.
    _packBottom.fadeOut(0.8);
  }

  /// Dónde ha tocado el dedo, EN COORDENADAS DEL JUEGO.
  ///
  /// `eventPosition.global` es la pantalla entera (el `globalPosition` de
  /// Flutter), no el GameWidget; `eventPosition.widget` es lo que hay que
  /// comparar con [_tearZone], que vive en el sistema del juego.
  ///
  /// En móvil daba igual: el GameWidget arranca en (0,0) y ocupa la pantalla,
  /// así que los dos sistemas coinciden. En TABLET no: QuizScreen centra el
  /// juego en una columna de 460 (`ConstrainedBox`), y en horizontal el raíl
  /// de navegación lo empuja todavía más a la derecha. El toque llegaba
  /// corrido esos ~170-250 px, caía fuera de la zona de rasgado y el sobre no
  /// se abría en ninguna de las dos orientaciones.
  Vector2 _gamePos(PositionInfo info) => info.eventPosition.widget;

  @override
  void onHorizontalDragStart(DragStartInfo info) {
    if (opened || !_canInteract) return;

    final touchPos = _gamePos(info);

    if (_tearZone.contains(Offset(touchPos.x, touchPos.y))) {
      _isTearing = true;
      _lastDragX = touchPos.x;
      _packTop.startTearing();
      haptics.grab();
      _cutLineIndicator.hide(); // Ocultar la línea guía
    }
  }

  @override
  void onHorizontalDragUpdate(DragUpdateInfo info) {
    if (!_isTearing || opened) return;

    final currentX = _gamePos(info).x;
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

    if (!opened && _tearProgress < 1.0 && _tearProgress > 0.1) {
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
    _isTearing = false;
    _canInteract = false;

    haptics.pop();

    // Activar chispas
    _sparkles.explode();

    // Glow al máximo y luego desvanecer
    _glowEffect.flashAndFade();

    _packTop.flyAway(() {
      _packTop.removeFromParent();

      Future.delayed(const Duration(milliseconds: 200), startPayoff);
    });
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

    packAnimate(
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

// ==================== PACK BOTTOM / TOP COMPONENTS ====================

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

    packAnimate(
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

    _bounce = packAnimate(
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

    packAnimate(
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
