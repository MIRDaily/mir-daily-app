import 'dart:math';

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/sticker/sticker.dart';
import 'pack_game_base.dart';

/// Apertura alternativa: **apretar el sobre hasta que revienta**.
///
/// El gesto es lo contrario del de rasgar. Allí el dedo VIAJA por la costura;
/// aquí se queda quieto y lo que pasa es que el sobre se hincha: se ensancha,
/// tiembla cada vez más fuerte, las chispas se van juntando hacia él y, al
/// llegar arriba, PUM — el envoltorio se parte en dos por un desgarro
/// irregular, las dos mitades salen despedidas girando y cae confeti.
///
/// Está construido con los principios de la animación de dibujos: anticipación
/// (el sobre se comprime antes de crecer), estirar y encoger (se ensancha más
/// de lo que crece a lo alto, como una bolsa que se llena de aire), y un golpe
/// seco con estrella de impacto. Si se suelta antes de tiempo, se desinfla con
/// un rebote elástico, que es lo que hace que apetezca volver a intentarlo.
///
/// Toda la paleta sale de la marca: coral, coral intenso, dorado, crema y el
/// trazo de tinta de `lib/shared/sticker/`. Las estrellas de cuatro puntas son
/// las mismas que lleva impresas el propio envoltorio.
///
/// Se usa `MultiTouchTapDetector` y no el `TapDetector` de toda la vida por
/// dos motivos: el segundo ni siquiera está exportado en Flame 1.34, y este
/// avisa del dedo abajo EN EL ACTO, mientras que el reconocedor de toque
/// simple espera ~100 ms a ver si gana la puja de gestos. Para una barra que
/// se llena mientras se aprieta, esos 100 ms se notan como un retardo.
class PackBurstGame extends PackGameBase with MultiTouchTapDetector {
  PackBurstGame({
    required super.specialties,
    required super.onComplete,
    super.haptics,
  });

  late _SqueezePackComponent _pack;
  late _PressGlowComponent _glow;
  late _GatherSparksComponent _sparks;
  late _PressHintComponent _hint;
  late _ImpactStarComponent _impact;
  late _ConfettiComponent _confetti;

  /// Lo que cuesta reventarlo manteniendo el dedo, en segundos.
  ///
  /// Poco más de un segundo: lo justo para que dé tiempo a que la tensión
  /// suba y se lea, sin que llegue a parecer un trámite. Por debajo de ~0,8 no
  /// se aprecia el hinchado; por encima de ~1,5 cansa.
  static const double _chargeSeconds = 1.15;

  /// Lo que tarda en desinflarse al soltar antes de tiempo.
  static const double _releaseSeconds = 0.45;

  /// El sobre se parte por la mitad, así que las cartas salen de ahí.
  @override
  double get packMouthY => packSize.y / 2;

  double _charge = 0.0;
  bool _pressing = false;
  bool _burst = false;

  /// De dónde viene el desinflado cuando se suelta a medias, para que la
  /// vuelta salga del punto exacto en el que estaba y no dé un salto.
  double _releaseFrom = 0.0;
  double _releaseT = 1.0;

  /// Al soltar a medias, el rebote SE PASA DE LARGO: el sobre se queda un
  /// instante más estrecho que en reposo antes de asentarse, que es la
  /// continuación del movimiento de toda la vida en dibujos animados. Eso
  /// significa que [_charge] baja de cero a propósito, y hay un tope para que
  /// no se vaya al infinito.
  static const double _undershoot = -0.4;

  /// Hacia fuera, la apertura nunca es negativa: la barra de progreso de la
  /// pantalla del daily pinta esto y no tiene por qué saber del rebote.
  @override
  double get openProgress => _charge.clamp(0.0, 1.0);

  /// El dedo está apretando: la vibración sigue a la carga.
  @override
  bool get gripped => _pressing;

  /// La zona que responde al dedo: el propio sobre con un dedo de margen.
  ///
  /// No vale toda la pantalla. El sobre vive dentro de un PageView que cambia
  /// de pestaña al deslizar, y quedarse con cualquier toque le robaría el
  /// gesto a la navegación.
  Rect get _pressZone => Rect.fromLTWH(
    packPosition.x - 28,
    packPosition.y - 28,
    packSize.x + 56,
    packSize.y + 56,
  );

  /// Solo para tests: dónde admite el juego el gesto de apretar.
  @visibleForTesting
  Rect get debugPressZone => _pressZone;

  @override
  Future<void> loadPackVisuals() async {
    _glow = _PressGlowComponent(packPosition: packPosition, packSize: packSize)
      ..priority = 1;
    add(_glow);

    _sparks = _GatherSparksComponent(
      packPosition: packPosition,
      packSize: packSize,
    )..priority = 2;
    add(_sparks);

    _pack = _SqueezePackComponent()..priority = 3;
    add(_pack);

    _hint = _PressHintComponent(packPosition: packPosition, packSize: packSize)
      ..priority = 5;
    add(_hint);

    _impact = _ImpactStarComponent(
      packPosition: packPosition,
      packSize: packSize,
    )..priority = 6;
    add(_impact);

    _confetti = _ConfettiComponent(
      packPosition: packPosition,
      packSize: packSize,
    )..priority = 8;
    add(_confetti);
  }

  @override
  void placePackVisuals() {
    _pack
      ..position = packPosition
      ..size = packSize;
    _glow.updatePosition(baseY);
    _hint.updatePosition(baseY);
  }

  /// Mientras se aprieta, el sobre deja de mecerse: está sujeto por el dedo.
  /// Que siguiera flotando delataría que el vaivén y el apretón son dos
  /// animaciones distintas pegadas. La base se encarga de que ese apagado sea
  /// suave y no un corte seco.
  @override
  double get floatTarget => _pressing || _charge > 0.02 ? 0.0 : 1.0;

  @override
  void floatPackVisuals(double y, double phase) {
    _pack.position.y = y;
    _glow.updatePosition(y);
    _hint.updatePosition(y);
    // El respirar se apaga con el mismo desvanecido que el mecido: si se
    // cortara de golpe, el tirón volvería por aquí.
    _pack.breath = sin(phase) * 0.012 * floatAmount;
  }

  @override
  void dismissPackVisuals() {
    _hint.hide();
    // El envoltorio no se desvanece: se ha partido en dos y las mitades salen
    // volando solas (ver [_SqueezePackComponent.burst]).
  }

  // ---- El gesto ----

  /// El dedo que está apretando. Con varios dedos a la vez manda el primero
  /// que cayó dentro del sobre: si no, apoyar la otra mano en la pantalla
  /// soltaría el apretón a medias.
  int? _pointer;

  @override
  void onTapDown(int pointerId, TapDownInfo info) {
    if (opened || _burst || _pointer != null) return;

    final p = info.eventPosition.widget; // NO .global: ver PackOpeningGame
    if (!_pressZone.contains(Offset(p.x, p.y))) return;

    _pointer = pointerId;
    _pressing = true;
    _hint.hide();
    haptics.grab();
  }

  @override
  void onTapUp(int pointerId, TapUpInfo info) => _release(pointerId);

  @override
  void onTapCancel(int pointerId) => _release(pointerId);

  void _release(int pointerId) {
    if (pointerId != _pointer) return;
    _pointer = null;

    if (!_pressing || _burst) return;
    _pressing = false;

    if (_charge <= 0.0) return;

    // Se desinfla con rebote elástico desde donde estuviera.
    _releaseFrom = _charge;
    _releaseT = 0.0;
    _hint.show();
  }

  @override
  void updateOpening(double dt) {
    if (_burst) return;

    if (_pressing) {
      _charge = (_charge + dt / _chargeSeconds).clamp(0.0, 1.0);
      if (_charge >= 1.0) {
        _pop();
        return;
      }
    } else if (_releaseT < 1.0) {
      _releaseT = (_releaseT + dt / _releaseSeconds).clamp(0.0, 1.0);
      // elasticOut PASA DE 1 en sus rebotes, así que esto se queda en negativo
      // a ratos. Es lo que da el rebote, pero hay que acotarlo: sin el tope,
      // `Curves.transform` recibe un valor fuera de [0,1] y salta la aserción.
      _charge = (_releaseFrom * (1 - Curves.elasticOut.transform(_releaseT)))
          .clamp(_undershoot, 1.0);
      if (_releaseT >= 1.0) _charge = 0.0;
    }

    _pack.charge = _charge;
    _glow.intensity = _charge;
    _sparks.charge = _charge;
  }

  void _pop() {
    _burst = true;
    _pressing = false;
    _charge = 1.0;

    haptics.pop();

    _impact.flash();
    _confetti.burst();
    _sparks.scatter();
    _glow.flashAndFade();
    _pack.burst();

    // Las mitades tienen que haber despejado el centro antes de que salga la
    // primera carta, o se cruzarían por delante del reparto.
    Future.delayed(const Duration(milliseconds: 260), startPayoff);
  }
}

// ==================== EL ENVOLTORIO QUE SE APRIETA ====================

/// El sobre: se hincha mientras se aprieta y se parte en dos al reventar.
class _SqueezePackComponent extends PositionComponent with HasGameRef {
  late Sprite _sprite;

  double charge = 0.0;

  /// Respiración del reposo, sumada a la escala. La pone el juego a partir de
  /// la fase del vaivén para que el sobre parezca vivo antes de tocarlo.
  double breath = 0.0;

  double _t = 0.0;
  bool _burst = false;
  double _burstT = 0.0;

  /// El desgarro por el que se parte: una línea quebrada vertical.
  ///
  /// Se calcula UNA vez y se guarda. Sortearla en cada fotograma haría que el
  /// borde roto hirviera, que es el error clásico al romper algo por código.
  late final List<Offset> _rip = _buildRip();

  static List<Offset> _buildRip() {
    final random = Random(7);
    const steps = 14;
    return List.generate(steps + 1, (i) {
      final t = i / steps;
      // Los extremos se quedan en el centro para que las dos mitades encajen.
      final amp = sin(t * pi);
      final jitter = (random.nextDouble() * 2 - 1) * 15 * amp;
      return Offset(jitter, t);
    });
  }

  @override
  Future<void> onLoad() async {
    _sprite = await gameRef.loadSprite('pack_closed.png');
  }

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
    if (_burst) _burstT = (_burstT + dt / 0.9).clamp(0.0, 1.0);
  }

  void burst() {
    _burst = true;
    _burstT = 0.0;
  }

  @override
  void render(Canvas canvas) {
    if (_burst) {
      _renderHalves(canvas);
      return;
    }
    _renderWhole(canvas);
  }

  /// El sobre entero, comprimiéndose y temblando según [charge].
  void _renderWhole(Canvas canvas) {
    // Estirar y encoger: se ENSANCHA bastante más de lo que crece a lo alto,
    // que es lo que hace leer "a punto de estallar" en vez de "acercándose".
    //
    // Con la carga en negativo —el rebote de soltar, que se pasa de largo— la
    // curva no vale: `transform` solo admite [0,1]. Ahí se usa el valor tal
    // cual, que es justo lo que se busca: el sobre se queda un instante MÁS
    // ESTRECHO que en reposo antes de asentarse.
    final e = charge >= 0
        ? Curves.easeInOutCubic.transform(charge.clamp(0.0, 1.0))
        : charge;
    final wobble = sin(_t * 34) * 0.030 * charge;
    final sx = 1 + 0.26 * e + wobble + breath;
    final sy = 1 + 0.07 * e - wobble + breath;

    // El temblor crece con el cuadrado: casi nada al principio y muy nervioso
    // al final. Lineal se notaba como un zumbido constante desde el inicio.
    final shakeX = sin(_t * 47) * 7.5 * charge * charge;
    final shakeY = cos(_t * 39) * 3.5 * charge * charge;
    final tilt = sin(_t * 29) * 0.035 * charge;

    final cx = size.x / 2;
    final cy = size.y / 2;

    canvas.save();

    // Sombra: se aplasta y se separa según crece el sobre, como si se
    // levantara del papel.
    final shadow = Paint()
      ..color = Colors.black.withValues(alpha: 0.20 + 0.10 * charge)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 14 + 8 * charge);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, size.y - 6 + 10 * charge),
        width: size.x * (0.72 + 0.18 * charge),
        height: 26,
      ),
      shadow,
    );

    canvas.translate(cx + shakeX, cy + shakeY);
    canvas.rotate(tilt);
    canvas.scale(sx, sy);
    canvas.translate(-cx, -cy);

    final caja = Rect.fromLTWH(0, 0, size.x, size.y);

    if (charge <= 0.05) {
      _sprite.render(canvas, size: size);
      canvas.restore();
      return;
    }

    // La tensión se lee además como un brillo que recorre el envoltorio: es el
    // reflejo del plástico estirándose.
    //
    // Va en una CAPA con `srcATop`, no suelto encima. El envoltorio es un PNG
    // con esquinas transparentes, y un brillo pintado sobre la caja entera se
    // salía de la ilustración: quedaba un rectángulo blanco de bordes duros
    // flotando detrás del sobre. Con `srcATop` sobre una capa que ya tiene el
    // envoltorio dibujado, el brillo solo toca sus píxeles opacos, o sea, su
    // silueta exacta —bordes ondulados incluidos—.
    canvas.saveLayer(caja, Paint());
    _sprite.render(canvas, size: size);

    // El reflejo barre en diagonal según se aprieta, de arriba abajo. El
    // recorrido se queda dentro de [0,1] con hueco a los lados para que los
    // tres topes del degradado sigan siendo crecientes tras recortarlos.
    final sweep = 0.15 + 0.7 * charge;
    canvas.drawRect(
      caja,
      Paint()
        ..blendMode = BlendMode.srcATop
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0.42 * charge),
            Colors.white.withValues(alpha: 0),
          ],
          stops: [
            (sweep - 0.22).clamp(0.0, 1.0),
            sweep.clamp(0.0, 1.0),
            (sweep + 0.22).clamp(0.0, 1.0),
          ],
        ).createShader(caja),
    );
    canvas.restore(); // cierra la capa del brillo

    canvas.restore();
  }

  /// Las dos mitades tras el reventón, girando y cayendo.
  void _renderHalves(Canvas canvas) {
    final t = _burstT;
    if (t >= 1.0) return;

    final out = Curves.easeOutCubic.transform(t);
    final fade = (1 - t * t).clamp(0.0, 1.0);

    for (final left in [true, false]) {
      final dir = left ? -1.0 : 1.0;

      canvas.save();

      // Salen de lado, suben un poco y caen: parábola de tebeo.
      final dx = dir * (18 + 300 * out);
      final dy = -70 * out + 460 * t * t;
      canvas.translate(size.x / 2 + dx, size.y / 2 + dy);
      canvas.rotate(dir * 1.7 * out);
      final s = 1 - 0.18 * t;
      canvas.scale(s, s);
      canvas.translate(-size.x / 2, -size.y / 2);

      canvas.save();
      canvas.clipPath(_halfPath(left));
      _sprite.render(
        canvas,
        size: size,
        overridePaint: Paint()..color = Colors.white.withValues(alpha: fade),
      );
      canvas.restore();

      // El borde roto, con el trazo de tinta de la marca. Sin esto las mitades
      // parecen recortadas con regla y se pierde el efecto de desgarro.
      canvas.drawPath(
        _ripPath(),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.5
          ..strokeJoin = StrokeJoin.round
          ..color = kInk.withValues(alpha: 0.9 * fade),
      );

      canvas.restore();
    }
  }

  /// La mitad izquierda o derecha del envoltorio, cortada por el desgarro.
  Path _halfPath(bool left) {
    final path = Path();
    final edge = left ? -4.0 : size.x + 4.0;

    path.moveTo(edge, -4);
    for (final p in _rip) {
      path.lineTo(size.x / 2 + p.dx, p.dy * size.y);
    }
    path.lineTo(edge, size.y + 4);
    path.close();
    return path;
  }

  Path _ripPath() {
    final path = Path();
    for (var i = 0; i < _rip.length; i++) {
      final p = _rip[i];
      final x = size.x / 2 + p.dx;
      final y = p.dy * size.y;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    return path;
  }
}

// ==================== RESPLANDOR DE PRESIÓN ====================

/// El resplandor que crece bajo el sobre según se aprieta, y que estalla en un
/// fogonazo al reventar.
class _PressGlowComponent extends PositionComponent {
  final Vector2 packPosition;
  final Vector2 packSize;

  double intensity = 0.0;
  double _flash = 0.0;
  double _y = 0.0;

  _PressGlowComponent({required this.packPosition, required this.packSize});

  void updatePosition(double newY) => _y = newY;

  void flashAndFade() {
    _flash = 1.0;
    packAnimate(this, duration: 0.7, onUpdate: (t) => _flash = 1 - t);
  }

  @override
  void render(Canvas canvas) {
    final v = max(intensity, _flash);
    if (v <= 0.01) return;

    final center = Offset(packPosition.x + packSize.x / 2, _y + packSize.y / 2);

    // Tres capas de dentro a fuera: el coral de marca por fuera y el dorado
    // en el corazón, que es el orden en el que la marca usa esos dos colores.
    for (var layer = 2; layer >= 0; layer--) {
      final radius = (packSize.x * 0.55) + layer * 46 + v * 40;
      final paint = Paint()
        ..color = Color.lerp(
          AppColors.gold,
          AppColors.primary,
          layer / 2,
        )!.withValues(alpha: 0.20 * v * (1 - layer * 0.22))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 28.0 + layer * 16);
      canvas.drawCircle(center, radius, paint);
    }
  }
}

// ==================== CHISPAS QUE SE CONCENTRAN ====================

/// Chispas que se van juntando HACIA el sobre mientras se aprieta.
///
/// Es lo contrario de la explosión de la apertura clásica, y a propósito: que
/// todo se meta hacia dentro es lo que hace sentir que se está acumulando algo
/// que va a soltarse. Al reventar, salen despedidas.
class _GatherSparksComponent extends PositionComponent {
  final Vector2 packPosition;
  final Vector2 packSize;

  double charge = 0.0;

  final List<_Spark> _sparks = [];

  /// Sembrado: la variedad la dan las decenas de chispas, no el reloj. Con
  /// semilla fija la animación se puede fotografiar en un test y comparar.
  final Random _random = Random(11);
  double _spawnAcc = 0.0;
  bool _scattering = false;

  _GatherSparksComponent({required this.packPosition, required this.packSize});

  Offset get _center =>
      Offset(packPosition.x + packSize.x / 2, packPosition.y + packSize.y / 2);

  void scatter() {
    _scattering = true;
    for (final s in _sparks) {
      final a = _random.nextDouble() * 2 * pi;
      final speed = 180 + _random.nextDouble() * 260;
      s.vx = cos(a) * speed;
      s.vy = sin(a) * speed - 90;
    }
  }

  @override
  void update(double dt) {
    super.update(dt);

    if (!_scattering && charge > 0.02) {
      // Cuanto más apretado, más chispas por segundo. El caudal es alto a
      // propósito: lo que se busca es una CORRIENTE que se traga el sobre, no
      // unas cuantas motas sueltas. Con el ritmo de antes se contaban las
      // chispas una a una y no llegaba a leerse como un remolino.
      _spawnAcc += dt * (55 + 320 * charge);
      while (_spawnAcc >= 1) {
        _spawnAcc -= 1;
        // Tope de seguridad: a pleno apretón salen ~375 al segundo y viven
        // poco más de uno. Sin freno, un fotograma lento las acumularía.
        if (_sparks.length < _maxSparks) _spawn();
      }
    }

    for (final s in _sparks) {
      if (_scattering) {
        s.x += s.vx * dt;
        s.y += s.vy * dt;
        s.vy += 520 * dt;
        s.life -= dt * 1.4;
      } else {
        // Espiral hacia el centro: el ángulo avanza mientras el radio cae.
        // Y cuanto más cerca del centro, más rápido gira —como el agua al
        // irse por el desagüe—, que es lo que convierte el arrastre en
        // remolino.
        s.angle += dt * s.swirl * (1 + 90 / (s.radius + 40));
        s.radius -= dt * s.speed;
        s.life -= dt * 0.9;
        if (s.radius <= 6) s.life = 0;
      }
      s.spin += dt * s.spinSpeed;
    }

    _sparks.removeWhere((s) => s.life <= 0);
  }

  /// Cuántas chispas puede haber vivas a la vez.
  static const int _maxSparks = 460;

  /// La paleta del remolino: los dorados y corales de la marca, más el crema
  /// del fondo para que algunas destellen casi blancas al cruzar el sobre.
  static const List<Color> _palette = [
    AppColors.gold,
    AppColors.goldSoft,
    AppColors.primary,
    AppColors.warning,
    AppColors.envelopeAccent,
    Colors.white,
  ];

  void _spawn() {
    // Tres capas de profundidad: las de fuera son grandes, lentas y opacas; las
    // de dentro, pequeñas y rápidas. Es lo que le da cuerpo al remolino —con
    // todas del mismo tamaño se ve una nube plana—.
    final capa = _random.nextInt(3);
    final lejos = capa / 2; // 0 = cerca, 1 = lejos

    _sparks.add(
      _Spark(
        angle: _random.nextDouble() * 2 * pi,
        radius: 70 + lejos * 90 + _random.nextDouble() * 130,
        speed: 130 + _random.nextDouble() * 190,
        size: 1.8 + (1 - lejos) * 1.4 + _random.nextDouble() * 4.2,
        color: _palette[_random.nextInt(_palette.length)],
        life: 1.0,
        // Cada una gira a su ritmo y en su sentido: con el giro compartido
        // parpadeaban todas a la vez, como un estroboscopio.
        spinSpeed: (_random.nextBool() ? 1 : -1) * (3 + _random.nextDouble() * 7),
        // La velocidad angular también varía; si no, el remolino se ve como un
        // disco rígido dando vueltas.
        swirl: 1.7 + _random.nextDouble() * 2.4,
      ),
    );
  }

  @override
  void render(Canvas canvas) {
    if (_sparks.isEmpty) return;

    final c = _center;

    for (final s in _sparks) {
      final pos = _scattering
          ? Offset(c.dx + s.x, c.dy + s.y)
          : Offset(
              c.dx + cos(s.angle) * s.radius,
              c.dy + sin(s.angle) * s.radius,
            );

      final alpha = s.life.clamp(0.0, 1.0);
      final paint = Paint()..color = s.color.withValues(alpha: alpha);

      // Estela: un arco corto por detrás, sobre la propia órbita. Es lo que
      // convierte un montón de puntos girando en una CORRIENTE; sin ella el
      // remolino se lee como confeti flotando.
      if (!_scattering && s.radius > 14) {
        final atras = s.angle - 0.16;
        canvas.drawLine(
          Offset(c.dx + cos(atras) * (s.radius + 7),
              c.dy + sin(atras) * (s.radius + 7)),
          pos,
          Paint()
            ..color = s.color.withValues(alpha: alpha * 0.35)
            ..strokeWidth = s.size * 0.5
            ..strokeCap = StrokeCap.round,
        );
      }

      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate(s.spin);
      // La misma estrella de cuatro puntas que lleva impresa el envoltorio.
      canvas.drawPath(packStar(s.size), paint);
      canvas.restore();
    }
  }
}

class _Spark {
  double angle;
  double radius;
  double speed;
  double size;
  Color color;
  double life;

  /// Giro sobre sí misma: cada una a su ritmo y en su sentido.
  double spinSpeed;

  /// Su velocidad angular alrededor del sobre.
  double swirl;

  double spin = 0;
  double x = 0, y = 0, vx = 0, vy = 0;

  _Spark({
    required this.angle,
    required this.radius,
    required this.speed,
    required this.size,
    required this.color,
    required this.life,
    required this.spinSpeed,
    required this.swirl,
  }) {
    x = cos(angle) * radius;
    y = sin(angle) * radius;
    spin = angle; // arranca ya orientada al azar
  }
}

// ==================== INVITACIÓN A APRETAR ====================

/// Lo que enseña el gesto: un dedo que baja sobre el sobre y un aro que se
/// cierra sobre él, en bucle.
///
/// Hace el mismo papel que la tijera de la apertura clásica —enseñar el gesto
/// sin escribirlo— y por eso está construido igual: un icono de Material
/// pintado con TextPainter, no un cartel de texto.
class _PressHintComponent extends PositionComponent {
  final Vector2 packPosition;
  final Vector2 packSize;

  double _t = 0.0;
  double _fade = 1.0;
  double _y = 0.0;

  _PressHintComponent({required this.packPosition, required this.packSize});

  void updatePosition(double newY) => _y = newY;

  void hide() {
    if (_fade == 0) return;
    packAnimate(this, duration: 0.18, onUpdate: (t) => _fade = 1 - t);
  }

  void show() {
    // Se reinicia el ciclo: si acabas de intentarlo y soltar, la pista vuelve
    // enseguida en vez de hacerte esperar hasta la siguiente ronda.
    _t = 0;
    packAnimate(this, duration: 0.3, onUpdate: (t) => _fade = t);
  }

  // ---- Cada cuánto asoma ----
  //
  // La pista NO está siempre puesta. Un dedo dando toques en bucle sin parar
  // deja de leerse como una indicación y pasa a ser ruido de fondo: se mira
  // una vez, se entiende, y a partir de ahí solo estorba a la ilustración.
  //
  // Así que asoma, hace su gesto una vez y se va; y pasa bastante más tiempo
  // callada que a la vista.

  /// Lo que dura la aparición: el dedo baja, toca y vuelve.
  static const double _aparicion = 2.0;

  /// Cada cuánto vuelve a asomar, contando desde que empezó la anterior.
  /// Con estos números se ve 2 s y descansa 5,5 s.
  static const double _periodo = 7.5;

  /// Entrada y salida por fundido, para que no aparezca de golpe.
  static const double _fundido = 0.35;

  /// Segundos desde que arrancó la ronda actual.
  @override
  void update(double dt) {
    super.update(dt);
    _t = (_t + dt) % _periodo;
  }

  @override
  void render(Canvas canvas) {
    if (_fade <= 0.01) return;
    if (_t > _aparicion) return; // descansando entre rondas

    // La envolvente de la ronda: entra y sale por fundido.
    final ronda = min(_t / _fundido, (_aparicion - _t) / _fundido)
        .clamp(0.0, 1.0);

    // Centrada en el sobre.
    //
    // Antes vivía en el tercio de abajo para no cruzar el medallón de los
    // pulmones, pero eso tenía sentido cuando estaba SIEMPRE puesta y taparlo
    // era permanente. Ahora que solo asoma un par de segundos cada siete, el
    // sitio bueno es el centro: es donde se posa el pulgar y donde se mira.
    //
    // El aro se pinta con trazo de tinta debajo justamente para poder cruzar
    // el dorado del logo sin desaparecer.
    final center = Offset(
      packPosition.x + packSize.x / 2,
      // Un pelo por debajo del centro: el dedo se dibuja POR ENCIMA del aro,
      // así que bajando el aro el conjunto queda centrado de verdad.
      _y + packSize.y * 0.56,
    );

    // Avance dentro de la ronda: 0 -> 1 bajando, 1 -> 0 subiendo, con una
    // pausa abajo.
    final q = _t / _aparicion;
    final p = q < 0.45
        ? Curves.easeOut.transform(q / 0.45)
        : q < 0.62
        ? 1.0
        : 1 - Curves.easeInOut.transform((q - 0.62) / 0.38);

    // El aro se cierra cuando el dedo toca. Va en dos pasadas —tinta debajo,
    // crema encima— porque el aro cae sobre el naranja del envoltorio pero
    // también puede pisar el círculo dorado del logo: en blanco a secas
    // desaparecía sobre el dorado. Con el trazo de tinta detrás se lee sobre
    // cualquiera de los dos, que es justo para lo que la marca usa la tinta.
    final ringR = 46.0 - 16 * p;
    final visible = (0.45 + 0.55 * p) * _fade * ronda;
    _dashedCircle(
      canvas,
      center,
      ringR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round
        ..color = kInk.withValues(alpha: 0.55 * visible),
    );
    _dashedCircle(
      canvas,
      center,
      ringR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: visible),
    );

    // El dedo, bajando.
    final painter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(Icons.touch_app_rounded.codePoint),
        style: TextStyle(
          fontFamily: Icons.touch_app_rounded.fontFamily,
          package: Icons.touch_app_rounded.fontPackage,
          fontSize: 34,
          color: Colors.white.withValues(alpha: _fade * ronda),
          shadows: [
            Shadow(
              color: Colors.black.withValues(alpha: 0.35 * _fade * ronda),
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
    canvas.translate(center.dx, center.dy - 26 + 20 * p);
    painter.paint(canvas, Offset(-painter.width / 2, -painter.height / 2));
    canvas.restore();
  }

  void _dashedCircle(Canvas canvas, Offset c, double r, Paint paint) {
    const dashes = 14;
    const sweep = 2 * pi / dashes;
    final rect = Rect.fromCircle(center: c, radius: r);
    for (var i = 0; i < dashes; i++) {
      canvas.drawArc(rect, i * sweep, sweep * 0.55, false, paint);
    }
  }
}

// ==================== ESTRELLA DE IMPACTO ====================

/// El "¡PUM!" del reventón: una estrella de pico dibujada con trazo de tinta,
/// que crece de golpe y se desvanece.
class _ImpactStarComponent extends PositionComponent {
  final Vector2 packPosition;
  final Vector2 packSize;

  double _t = 1.0;

  _ImpactStarComponent({required this.packPosition, required this.packSize});

  void flash() {
    _t = 0.0;
    packAnimate(this, duration: 0.55, onUpdate: (v) => _t = v);
  }

  @override
  void render(Canvas canvas) {
    if (_t >= 1.0) return;

    final center = Offset(
      packPosition.x + packSize.x / 2,
      packPosition.y + packSize.y / 2,
    );

    // Sale disparada y se para: easeOutBack le da el golpe seco de tebeo.
    final grow = Curves.easeOutBack.transform(min(_t / 0.45, 1.0));
    final fade = _t < 0.45 ? 1.0 : 1 - (_t - 0.45) / 0.55;
    final outer = (packSize.x * 0.52) * grow;
    final inner = outer * 0.52;

    final path = Path();
    const spikes = 12;
    for (var i = 0; i < spikes * 2; i++) {
      final r = i.isEven ? outer : inner;
      // Las puntas no son todas iguales: alternarlas un poco quita el aire de
      // estrella hecha con compás.
      final jitter = i.isEven ? (i % 4 == 0 ? 1.0 : 0.86) : 1.0;
      final a = (i * pi / spikes) - pi / 2;
      final p = Offset(
        center.dx + cos(a) * r * jitter,
        center.dy + sin(a) * r * jitter,
      );
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    path.close();

    canvas.drawPath(
      path,
      Paint()..color = AppColors.goldSoft.withValues(alpha: 0.92 * fade),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeJoin = StrokeJoin.round
        ..color = kInk.withValues(alpha: 0.85 * fade),
    );
  }
}

// ==================== CONFETI ====================

/// La lluvia de confeti del reventón: cintas y estrellas de la paleta de
/// marca, girando y cayendo.
class _ConfettiComponent extends PositionComponent {
  final Vector2 packPosition;
  final Vector2 packSize;

  final List<_Confetto> _pieces = [];
  final Random _random = Random(3); // ver la nota de _GatherSparksComponent

  _ConfettiComponent({required this.packPosition, required this.packSize});

  static const List<Color> _palette = [
    AppColors.primary,
    AppColors.primaryDark,
    AppColors.gold,
    AppColors.goldSoft,
    AppColors.envelopeAccent,
    Colors.white,
  ];

  void burst() {
    for (var i = 0; i < 54; i++) {
      final angle = -pi / 2 + (_random.nextDouble() - 0.5) * pi * 1.35;
      final speed = 220 + _random.nextDouble() * 330;
      _pieces.add(
        _Confetto(
          x: (_random.nextDouble() - 0.5) * packSize.x * 0.5,
          y: (_random.nextDouble() - 0.5) * packSize.y * 0.3,
          vx: cos(angle) * speed,
          vy: sin(angle) * speed,
          size: 5 + _random.nextDouble() * 7,
          color: _palette[_random.nextInt(_palette.length)],
          spin: (_random.nextDouble() - 0.5) * 14,
          star: _random.nextDouble() < 0.35,
          life: 1.3 + _random.nextDouble() * 0.7,
        ),
      );
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_pieces.isEmpty) return;

    for (final p in _pieces) {
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.vy += 720 * dt; // gravedad
      p.vx *= 0.985; // el aire las frena de lado
      p.angle += p.spin * dt;
      p.life -= dt;
    }
    _pieces.removeWhere((p) => p.life <= 0);
  }

  @override
  void render(Canvas canvas) {
    if (_pieces.isEmpty) return;

    final cx = packPosition.x + packSize.x / 2;
    final cy = packPosition.y + packSize.y / 2;

    for (final p in _pieces) {
      final alpha = p.life.clamp(0.0, 1.0);
      canvas.save();
      canvas.translate(cx + p.x, cy + p.y);
      canvas.rotate(p.angle);

      final paint = Paint()..color = p.color.withValues(alpha: alpha);

      if (p.star) {
        canvas.drawPath(packStar(p.size * 0.85), paint);
      } else {
        // Cinta: se "voltea" al girar, aplastándose a lo alto. Es lo que hace
        // que el confeti parezca papel y no puntos de color.
        final flip = (cos(p.angle * 1.7)).abs().clamp(0.18, 1.0);
        final rect = RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset.zero,
            width: p.size * 1.6,
            height: p.size * flip,
          ),
          const Radius.circular(1.5),
        );
        canvas.drawRRect(rect, paint);
      }

      canvas.restore();
    }
  }
}

class _Confetto {
  double x, y, vx, vy;
  double size;
  Color color;
  double spin;
  bool star;
  double life;
  double angle = 0;

  _Confetto({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.size,
    required this.color,
    required this.spin,
    required this.star,
    required this.life,
  });
}
