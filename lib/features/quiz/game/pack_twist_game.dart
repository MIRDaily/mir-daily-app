import 'dart:math';

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/sticker/sticker.dart';
import 'pack_game_base.dart';

/// Tercera apertura: **retorcer el sobre como un caramelo**.
///
/// El dedo da vueltas alrededor del sobre. El envoltorio se va escurriendo por
/// el medio —el cuello se estrecha, los extremos se ensanchan y se ladean en
/// sentidos contrarios, y salen pliegues de tinta del pellizco— hasta que el
/// papel no da más de sí y se ROMPE por el cuello: las dos mitades salen
/// disparadas en direcciones opuestas y las cartas se derraman por el medio.
///
/// El gesto es el tercero distinto de la casa: rasgar es un dedo que VIAJA en
/// línea, apretar es un dedo QUIETO, y esto es un dedo que GIRA. Ninguno se
/// confunde con otro, ni con el deslizamiento entre pestañas.
///
/// Lo que hace que se lea como torsión y no como un simple pellizco es que el
/// envoltorio se pinta en tiras horizontales, cada una con su propio
/// estrechamiento, su desplazamiento y su giro. Es una deformación de verdad
/// del dibujo, no una escala.
class PackTwistGame extends PackGameBase with PanDetector {
  PackTwistGame({
    required super.specialties,
    required super.onComplete,
    super.haptics,
  });

  late _TwistPackComponent _pack;
  late _NeckGlowComponent _glow;
  late _NeckSparksComponent _sparks;
  late _TwistHintComponent _hint;
  late _ShredsComponent _shreds;

  /// Cuánto hay que girar para romperlo, en radianes. Casi dos vueltas: es lo
  /// que cuesta retorcer un envoltorio de verdad, y deja sitio para que la
  /// tensión suba de forma legible. Con una vuelta se rompía antes de que se
  /// notara el pellizco.
  static const double _twistTarget = 3.4 * pi;

  /// El sobre se parte por el cuello, o sea, por el medio.
  @override
  double get packMouthY => packSize.y / 2;

  /// Radianes girados hasta ahora (siempre positivo: vale en los dos
  /// sentidos, como un envoltorio de verdad).
  double _twist = 0.0;
  bool _turning = false;
  bool _broken = false;
  double _lastAngle = 0.0;

  /// Desde dónde se destuerce al soltar a medias.
  double _releaseFrom = 0.0;
  double _releaseT = 1.0;

  /// Lo que tarda en destorcerse solo. Bastante más lento que el apretón: el
  /// papel retorcido vuelve con desgana, no de golpe.
  static const double _unwindSeconds = 0.7;

  @override
  double get openProgress => (_twist / _twistTarget).clamp(0.0, 1.0);

  /// Mientras se retuerce, el sobre está sujeto: deja de mecerse. La base se
  /// encarga de que ese apagado sea suave y no un corte seco.
  @override
  double get floatTarget => _turning || _twist > 0.05 ? 0.0 : 1.0;

  /// El dedo está retorciendo: la vibración sigue al giro.
  @override
  bool get gripped => _turning;

  /// La corona donde se admite el giro: el sobre con un margen generoso, para
  /// que el dedo pueda dar la vuelta por fuera sin salirse de la zona.
  Rect get _turnZone => Rect.fromLTWH(
        packPosition.x - 70,
        packPosition.y - 50,
        packSize.x + 140,
        packSize.y + 100,
      );

  /// Solo para tests: dónde admite el juego el gesto de retorcer.
  @visibleForTesting
  Rect get debugTurnZone => _turnZone;

  Offset get _center => Offset(
        packPosition.x + packSize.x / 2,
        packPosition.y + packSize.y / 2,
      );

  @override
  Future<void> loadPackVisuals() async {
    _glow = _NeckGlowComponent(packPosition: packPosition, packSize: packSize)
      ..priority = 1;
    add(_glow);

    _pack = _TwistPackComponent()..priority = 3;
    add(_pack);

    _sparks = _NeckSparksComponent(
      packPosition: packPosition,
      packSize: packSize,
    )..priority = 4;
    add(_sparks);

    _shreds = _ShredsComponent(packPosition: packPosition, packSize: packSize)
      ..priority = 5;
    add(_shreds);

    _hint = _TwistHintComponent(packPosition: packPosition, packSize: packSize)
      ..priority = 6;
    add(_hint);
  }

  @override
  void placePackVisuals() {
    _pack
      ..position = packPosition
      ..size = packSize;
    _glow.updatePosition(baseY);
    _hint.updatePosition(baseY);
  }

  @override
  void floatPackVisuals(double y, double phase) {
    _pack.position.y = y;
    _glow.updatePosition(y);
    _hint.updatePosition(y);
    // El respirar se apaga con el mismo desvanecido que el mecido: si se
    // cortara de golpe, el tirón volvería por aquí.
    _pack.breath = sin(phase) * 0.010 * floatAmount;
  }

  @override
  void dismissPackVisuals() {
    _hint.hide();
    // El envoltorio no se desvanece: se ha partido por el cuello y las mitades
    // se van solas (ver [_TwistPackComponent.snap]).
  }

  // ---- El gesto ----

  @override
  void onPanStart(DragStartInfo info) {
    if (opened || _broken) return;

    final p = info.eventPosition.widget; // NO .global: ver PackOpeningGame
    if (!_turnZone.contains(Offset(p.x, p.y))) return;

    _turning = true;
    _lastAngle = _angleOf(p);
    _hint.hide();
    haptics.grab();
  }

  @override
  void onPanUpdate(DragUpdateInfo info) {
    if (!_turning || _broken) return;

    final p = info.eventPosition.widget;

    // Justo encima del centro, el ángulo del dedo salta como loco: un
    // temblor de dos píxeles puede dar media vuelta. Ahí se ignora.
    if ((Offset(p.x, p.y) - _center).distance < 26) return;

    final ahora = _angleOf(p);

    // Diferencia de ángulo llevada a (-pi, pi]: sin esto, cruzar el eje de
    // las 9 en punto cuenta como una vuelta entera de golpe.
    var delta = ahora - _lastAngle;
    while (delta > pi) {
      delta -= 2 * pi;
    }
    while (delta < -pi) {
      delta += 2 * pi;
    }
    _lastAngle = ahora;

    // En valor absoluto: retuerce igual en los dos sentidos.
    _twist += delta.abs();
    _apply();

    // No hay chasquido por cuarto de vuelta: la vibración continua de
    // [PackGameBase.haptics] ya cuenta la tensión, y meter además golpes
    // sueltos por el otro camino (, que es otro subsistema)
    // se pisaba con el zumbido en vez de sumar.

    if (_twist >= _twistTarget) _snap();
  }

  @override
  void onPanEnd(DragEndInfo info) => _release();

  @override
  void onPanCancel() => _release();

  void _release() {
    if (!_turning || _broken) return;
    _turning = false;
    if (_twist <= 0) return;
    _releaseFrom = _twist;
    _releaseT = 0.0;
    _hint.show();
  }

  double _angleOf(Vector2 p) => atan2(p.y - _center.dy, p.x - _center.dx);

  @override
  void updateOpening(double dt) {
    if (_broken || _turning) return;

    if (_releaseT < 1.0) {
      _releaseT = (_releaseT + dt / _unwindSeconds).clamp(0.0, 1.0);
      // Se destuerce con desgana y un último temblor: easeOutBack se pasa un
      // poco de largo, y eso es justo el coletazo del papel al soltarse.
      _twist = _releaseFrom * (1 - Curves.easeOutBack.transform(_releaseT));
      if (_twist < 0) _twist = 0;
      if (_releaseT >= 1.0) _twist = 0;
      _apply();
    }
  }

  void _apply() {
    final t = openProgress;
    _pack.twist = t;
    _glow.intensity = t;
    _sparks.twist = t;
  }

  void _snap() {
    _broken = true;
    _turning = false;
    _twist = _twistTarget;
    _apply();

    haptics.pop();

    _sparks.burstAtNeck();
    _shreds.scatter();
    _glow.flashAndFade();
    _pack.snap();

    // Las mitades tienen que despejar el centro antes de la primera carta.
    Future.delayed(const Duration(milliseconds: 240), startPayoff);
  }
}

// ==================== EL ENVOLTORIO QUE SE RETUERCE ====================

/// El sobre, pintado en tiras horizontales para poder retorcerlo de verdad.
///
/// Cada tira es un trozo del PNG (un `Sprite` con su `srcPosition`), así que
/// no hay que recortar nada ni se cuela contenido de una tira en otra. Se
/// construyen una vez, en [onLoad].
class _TwistPackComponent extends PositionComponent with HasGameRef {
  /// Cuántas tiras. Con menos se ven escalones en el cuello; con muchas más no
  /// se gana nada y son otras tantas llamadas de dibujo por fotograma.
  static const int _strips = 44;

  late final List<Sprite> _slices;

  /// 0..1. Lo pone el juego a partir de las vueltas dadas.
  double twist = 0.0;

  /// Lo que de verdad se pinta: persigue a [twist] con suavidad.
  ///
  /// Hace falta por cómo avisa Flutter de un arrastre. `PanGestureRecognizer`
  /// no dice nada hasta que el dedo ha recorrido 36 puntos, y entonces suelta
  /// el primer aviso ya con todo ese recorrido acumulado: unos 0,36 radianes
  /// de golpe. Pintado tal cual, el envoltorio se retorcía de un tirón en el
  /// primer fotograma del gesto —justo el salto que se notaba—.
  ///
  /// La persecución es rápida (unos 90 ms) para que el giro siga sintiéndose
  /// pegado al dedo; lo único que se come es el escalón de entrada.
  double _shown = 0.0;
  static const double _follow = 18.0;

  /// Respiración del reposo.
  double breath = 0.0;

  double _t = 0.0;
  bool _snapped = false;
  double _snapT = 0.0;

  @override
  Future<void> onLoad() async {
    final img = await gameRef.images.load('pack_closed.png');
    final alto = img.height / _strips;
    _slices = List.generate(
      _strips,
      (i) => Sprite(
        img,
        srcPosition: Vector2(0, i * alto),
        srcSize: Vector2(img.width.toDouble(), alto),
      ),
    );
  }

  @override
  void update(double dt) {
    super.update(dt);
    _t += dt;
    _shown += (twist - _shown) * min(1.0, dt * _follow);
    if (_snapped) _snapT = (_snapT + dt / 0.95).clamp(0.0, 1.0);
  }

  void snap() {
    _snapped = true;
    _snapT = 0.0;
  }

  @override
  void render(Canvas canvas) {
    if (_snapped) {
      _renderHalves(canvas);
      return;
    }
    _renderTwisted(canvas);
  }

  /// Cuánto se estrecha el cuello como mucho, en tanto por uno del ancho.
  static const double _maxCinch = 0.66;

  /// El envoltorio retorcido.
  ///
  /// Todo se pinta contra [_shown], no contra [twist]: es la versión suavizada
  /// del giro, y es lo que quita el escalón del arranque del gesto.
  void _renderTwisted(Canvas canvas) {
    final w = size.x;
    final h = size.y;
    final cx = w / 2;
    final twist = _shown;

    // La tensión hace vibrar el papel cuando ya está muy retorcido.
    final nervio = twist * twist;
    final shakeX = sin(_t * 41) * 3.4 * nervio;
    final shakeY = cos(_t * 33) * 1.8 * nervio;

    canvas.save();

    // Sombra: se estrecha con el sobre, porque lo que hay debajo también se
    // ha escurrido.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, h - 4),
        width: w * (0.72 - 0.16 * twist),
        height: 24,
      ),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.20)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );

    canvas.translate(shakeX, shakeY);

    // Un poco de vida en reposo.
    if (breath != 0) {
      canvas.translate(cx, h / 2);
      canvas.scale(1 + breath, 1 - breath);
      canvas.translate(-cx, -h / 2);
    }

    final stripH = h / _strips;

    // Todo el envoltorio va en una CAPA, para poder pintarle los pliegues
    // encima sin que se salgan de él. La caja se agranda porque las puntas se
    // ensanchan y se ladean, y al girar barren fuera del recuadro del
    // componente.
    final capa = Rect.fromLTWH(-w * 0.4, -20, w * 1.8, h + 40);
    canvas.saveLayer(capa, Paint());

    for (var i = 0; i < _strips; i++) {
      // u va de -1 (arriba) a 1 (abajo); 0 es el cuello.
      final u = (i + 0.5) / _strips * 2 - 1;
      final centroY = (i + 0.5) * stripH;

      // El cuello se escurre y los extremos se ensanchan: el papel que sale
      // del medio tiene que ir a alguna parte.
      final aprieto = 1 - u * u; // 1 en el cuello, 0 en las puntas
      final ancho = 1 - _maxCinch * twist * aprieto + 0.10 * twist * (1 - aprieto);

      // Desplazamiento en S: la parte de arriba se va a un lado y la de abajo
      // al otro. Es lo que se ve al escurrir un trapo, y lo que distingue una
      // TORSIÓN de un simple pellizco.
      final corrimiento = twist * 30 * u * aprieto;

      // Y cada mitad se ladea en sentido contrario.
      final giro = twist * 0.34 * u;

      canvas.save();
      canvas.translate(cx + corrimiento, centroY);
      canvas.rotate(giro);
      canvas.scale(ancho, 1);
      canvas.translate(-cx, -centroY);

      _slices[i].render(
        canvas,
        position: Vector2(0, centroY - stripH / 2),
        // La tira se pinta un pelo más alta de la cuenta: si no, entre tira y
        // tira queda una raya de fondo por el redondeo de los píxeles.
        size: Vector2(w, stripH + 1),
      );

      canvas.restore();
    }

    // Los adornos del pellizco, DENTRO de la capa: se pintan con `srcATop`,
    // así que solo tocan los píxeles que ya ha dejado el envoltorio. Sin esto
    // la sombra del cuello y los pliegues se salían por los lados y quedaba
    // una banda gris flotando sobre el fondo.
    if (twist > 0.06) {
      _renderPleats(canvas, cx, h / 2, w, twist);
    }

    canvas.restore(); // cierra la capa del envoltorio
    canvas.restore();
  }

  /// Los pliegues del cuello: trazos de tinta que salen del pellizco.
  ///
  /// Es el detalle que remata la torsión. Sin ellos el cuello se ve como una
  /// cintura lisa; con ellos se lee que el papel está arrugado ahí.
  /// [twist] llega por parámetro y no se lee del campo a propósito: aquí hay
  /// que usar el giro SUAVIZADO, el mismo con el que se han pintado las tiras.
  void _renderPleats(
    Canvas canvas,
    double cx,
    double cy,
    double w,
    double twist,
  ) {
    final fuerza = Curves.easeIn.transform(twist.clamp(0.0, 1.0));
    final cuello = w * (1 - _maxCinch * twist) / 2;

    final tinta = Paint()
      ..blendMode = BlendMode.srcATop
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.0
      ..color = kInk.withValues(alpha: 0.5 * fuerza);

    // Sombra del hueco del pliegue: oscurece por los dos lados del cuello y
    // deja el centro limpio, que es como se ve un papel escurrido.
    final sombra = Rect.fromCenter(
      center: Offset(cx, cy),
      width: cuello * 2.6,
      height: 34,
    );
    canvas.drawRect(
      sombra,
      Paint()
        ..blendMode = BlendMode.srcATop
        ..shader = LinearGradient(
          colors: [
            Colors.black.withValues(alpha: 0.30 * fuerza),
            Colors.black.withValues(alpha: 0),
            Colors.black.withValues(alpha: 0.30 * fuerza),
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(sombra),
    );

    // Cinco pliegues arriba y cinco abajo, abriéndose en abanico desde el
    // cuello, como las arrugas de un caramelo. Se quedan cerca del pellizco:
    // más largos parecerían rayas del dibujo, no arrugas.
    for (var lado = -1; lado <= 1; lado += 2) {
      for (var k = 0; k < 5; k++) {
        final f = (k + 0.5) / 5 - 0.5; // -0.4 .. 0.4
        final salida = Offset(cx + f * cuello * 1.6, cy);
        final llegada = Offset(
          cx + f * cuello * 2.8,
          cy + lado * (14 + 22 * fuerza),
        );
        canvas.drawPath(
          Path()
            ..moveTo(salida.dx, salida.dy)
            ..quadraticBezierTo(
              salida.dx + (llegada.dx - salida.dx) * 0.15,
              (salida.dy + llegada.dy) / 2,
              llegada.dx,
              llegada.dy,
            ),
          tinta,
        );
      }
    }
  }

  /// Las dos mitades tras romperse el cuello.
  void _renderHalves(Canvas canvas) {
    final t = _snapT;
    if (t >= 1.0) return;

    final salida = Curves.easeOutCubic.transform(t);
    final fade = (1 - t * t).clamp(0.0, 1.0);
    final w = size.x;
    final h = size.y;
    final stripH = h / _strips;
    final mitad = _strips ~/ 2;

    for (final arriba in [true, false]) {
      final dir = arriba ? -1.0 : 1.0;

      canvas.save();

      // Salen por donde apuntaba la torsión: una arriba y a un lado, la otra
      // abajo y al contrario. Siguen girando al irse, por inercia.
      canvas.translate(
        w / 2 + dir * 150 * salida,
        h / 2 + dir * (200 * salida) + 120 * t * t,
      );
      canvas.rotate(dir * (0.5 + 2.4 * salida));
      final s = 1 - 0.2 * t;
      canvas.scale(s, s);
      canvas.translate(-w / 2, -h / 2);

      final desde = arriba ? 0 : mitad;
      final hasta = arriba ? mitad : _strips;

      final pintura = Paint()..color = Colors.white.withValues(alpha: fade);

      for (var i = desde; i < hasta; i++) {
        final u = (i + 0.5) / _strips * 2 - 1;
        final aprieto = 1 - u * u;
        final ancho = 1 - _maxCinch * aprieto + 0.10 * (1 - aprieto);
        final centroY = (i + 0.5) * stripH;

        canvas.save();
        canvas.translate(w / 2 + 30 * u * aprieto, centroY);
        canvas.rotate(0.34 * u);
        canvas.scale(ancho, 1);
        canvas.translate(-w / 2, -centroY);
        _slices[i].render(
          canvas,
          position: Vector2(0, centroY - stripH / 2),
          size: Vector2(w, stripH + 1),
          overridePaint: pintura,
        );
        canvas.restore();
      }

      // El borde roto del cuello, con el trazo de tinta de la marca.
      final yRoto = arriba ? mitad * stripH : mitad * stripH;
      final anchoCuello = w * (1 - _maxCinch) / 2;
      final rasgado = Path();
      for (var k = 0; k <= 8; k++) {
        final f = k / 8;
        final x = w / 2 - anchoCuello + f * anchoCuello * 2;
        final y = yRoto + (k.isEven ? -3.5 : 3.5);
        k == 0 ? rasgado.moveTo(x, y) : rasgado.lineTo(x, y);
      }
      canvas.drawPath(
        rasgado,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeJoin = StrokeJoin.round
          ..color = kInk.withValues(alpha: 0.85 * fade),
      );

      canvas.restore();
    }
  }
}

// ==================== RESPLANDOR DEL CUELLO ====================

/// El resplandor que se concentra en el cuello según se retuerce.
class _NeckGlowComponent extends PositionComponent {
  final Vector2 packPosition;
  final Vector2 packSize;

  double intensity = 0.0;
  double _flash = 0.0;
  double _y = 0.0;

  _NeckGlowComponent({required this.packPosition, required this.packSize});

  void updatePosition(double newY) => _y = newY;

  void flashAndFade() {
    _flash = 1.0;
    packAnimate(this, duration: 0.7, onUpdate: (t) => _flash = 1 - t);
  }

  @override
  void render(Canvas canvas) {
    final v = max(intensity, _flash);
    if (v <= 0.01) return;

    final centro = Offset(packPosition.x + packSize.x / 2, _y + packSize.y / 2);

    // Alargado a lo ancho: el brillo sale POR el cuello, hacia los lados, no
    // en redondo. Un círculo aquí parecería el resplandor de "apretar".
    for (var capa = 2; capa >= 0; capa--) {
      canvas.drawOval(
        Rect.fromCenter(
          center: centro,
          width: packSize.x * (0.9 + capa * 0.35) + v * 60,
          height: 46.0 + capa * 26,
        ),
        Paint()
          ..color = Color.lerp(AppColors.gold, AppColors.primary, capa / 2)!
              .withValues(alpha: 0.22 * v * (1 - capa * 0.22))
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 22.0 + capa * 14),
      );
    }
  }
}

// ==================== CHISPAS DEL CUELLO ====================

/// Las chispas que se escapan POR el cuello mientras se escurre, y el chorro
/// que sale al romperse.
///
/// A diferencia del remolino de "apretar", que se mete hacia dentro, estas
/// salen disparadas a los lados: es lo que se escapa del pellizco.
class _NeckSparksComponent extends PositionComponent {
  final Vector2 packPosition;
  final Vector2 packSize;

  double twist = 0.0;

  final List<_NeckSpark> _sparks = [];
  final Random _random = Random(23);
  double _acc = 0.0;

  static const int _max = 320;

  _NeckSparksComponent({required this.packPosition, required this.packSize});

  static const List<Color> _palette = [
    AppColors.gold,
    AppColors.goldSoft,
    AppColors.primary,
    AppColors.warning,
    Colors.white,
  ];

  void burstAtNeck() {
    for (var i = 0; i < 90; i++) {
      _spawn(fuerte: true);
    }
  }

  void _spawn({bool fuerte = false}) {
    if (_sparks.length >= _max) return;
    // Salen del cuello, hacia la izquierda o la derecha, con dispersión.
    final lado = _random.nextBool() ? -1.0 : 1.0;
    final abre = (_random.nextDouble() - 0.5) * (fuerte ? 2.2 : 1.1);
    final v = (fuerte ? 240 : 90) + _random.nextDouble() * (fuerte ? 320 : 130);

    _sparks.add(
      _NeckSpark(
        x: lado * packSize.x * 0.16 * _random.nextDouble(),
        y: (_random.nextDouble() - 0.5) * 14,
        vx: lado * v * cos(abre),
        vy: v * sin(abre) * 0.8 - (fuerte ? 60 : 20),
        size: 1.8 + _random.nextDouble() * (fuerte ? 5.0 : 3.2),
        color: _palette[_random.nextInt(_palette.length)],
        spin: (_random.nextDouble() - 0.5) * 12,
        life: 0.5 + _random.nextDouble() * (fuerte ? 0.9 : 0.5),
      ),
    );
  }

  @override
  void update(double dt) {
    super.update(dt);

    if (twist > 0.08) {
      // Cuanto más retorcido, más se escapa por el cuello.
      _acc += dt * (20 + 190 * twist);
      while (_acc >= 1) {
        _acc -= 1;
        _spawn();
      }
    }

    for (final s in _sparks) {
      s.x += s.vx * dt;
      s.y += s.vy * dt;
      s.vy += 430 * dt;
      s.vx *= 0.985;
      s.angle += s.spin * dt;
      s.life -= dt;
    }
    _sparks.removeWhere((s) => s.life <= 0);
  }

  @override
  void render(Canvas canvas) {
    if (_sparks.isEmpty) return;

    final cx = packPosition.x + packSize.x / 2;
    final cy = packPosition.y + packSize.y / 2;

    for (final s in _sparks) {
      final alpha = s.life.clamp(0.0, 1.0);
      canvas.save();
      canvas.translate(cx + s.x, cy + s.y);
      canvas.rotate(s.angle);
      canvas.drawPath(
        packStar(s.size),
        Paint()..color = s.color.withValues(alpha: alpha),
      );
      canvas.restore();
    }
  }
}

class _NeckSpark {
  double x, y, vx, vy;
  double size;
  Color color;
  double spin;
  double life;
  double angle = 0;

  _NeckSpark({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.size,
    required this.color,
    required this.spin,
    required this.life,
  });
}

// ==================== TROZOS DE PAPEL ====================

/// Los trocitos de envoltorio que saltan al romperse el cuello.
///
/// Van aparte de las chispas porque son otra cosa: papel naranja con su borde
/// de tinta, no destellos. Que salten los dos a la vez es lo que hace que la
/// rotura parezca material y no solo luz.
class _ShredsComponent extends PositionComponent {
  final Vector2 packPosition;
  final Vector2 packSize;

  final List<_Shred> _pieces = [];
  final Random _random = Random(5);

  _ShredsComponent({required this.packPosition, required this.packSize});

  static const List<Color> _papel = [
    AppColors.envelopeTop,
    AppColors.envelopeBottom,
    AppColors.envelopeAccent,
    AppColors.gold,
  ];

  void scatter() {
    for (var i = 0; i < 26; i++) {
      final a = _random.nextDouble() * 2 * pi;
      final v = 130 + _random.nextDouble() * 300;
      _pieces.add(
        _Shred(
          x: (_random.nextDouble() - 0.5) * packSize.x * 0.5,
          y: (_random.nextDouble() - 0.5) * 20,
          vx: cos(a) * v,
          vy: sin(a) * v - 120,
          w: 5 + _random.nextDouble() * 11,
          h: 4 + _random.nextDouble() * 7,
          color: _papel[_random.nextInt(_papel.length)],
          spin: (_random.nextDouble() - 0.5) * 16,
          life: 1.1 + _random.nextDouble() * 0.7,
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
      p.vy += 700 * dt;
      p.vx *= 0.99;
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
      // Se voltea al girar, como un trozo de papel de verdad.
      final flip = cos(p.angle * 1.6).abs().clamp(0.2, 1.0);
      final r = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: p.w, height: p.h * flip),
        const Radius.circular(1.5),
      );
      canvas.drawRRect(r, Paint()..color = p.color.withValues(alpha: alpha));
      canvas.drawRRect(
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = kInk.withValues(alpha: 0.8 * alpha),
      );
      canvas.restore();
    }
  }
}

class _Shred {
  double x, y, vx, vy;
  double w, h;
  Color color;
  double spin;
  double life;
  double angle = 0;

  _Shred({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.w,
    required this.h,
    required this.color,
    required this.spin,
    required this.life,
  });
}

// ==================== INVITACIÓN A GIRAR ====================

/// Lo que enseña el gesto: una flecha curva que da vueltas alrededor del
/// sobre, con su punta.
///
/// Mismo papel que la tijera de "rasgar" y el dedo de "apretar": enseñar el
/// gesto sin escribirlo.
class _TwistHintComponent extends PositionComponent {
  final Vector2 packPosition;
  final Vector2 packSize;

  double _t = 0.0;
  double _fade = 1.0;
  double _y = 0.0;

  _TwistHintComponent({required this.packPosition, required this.packSize});

  void updatePosition(double newY) => _y = newY;

  void hide() {
    if (_fade == 0) return;
    packAnimate(this, duration: 0.18, onUpdate: (t) => _fade = 1 - t);
  }

  void show() {
    packAnimate(this, duration: 0.3, onUpdate: (t) => _fade = t);
  }

  /// Lo que dura una vuelta entera de la flecha.
  static const double _cycle = 2.4;

  @override
  void update(double dt) {
    super.update(dt);
    _t = (_t + dt / _cycle) % 1.0;
  }

  @override
  void render(Canvas canvas) {
    if (_fade <= 0.01) return;

    final centro = Offset(packPosition.x + packSize.x / 2, _y + packSize.y / 2);
    final rx = packSize.x * 0.60;
    final ry = packSize.y * 0.42;

    final avance = _t * 2 * pi;

    // Un arco de un tercio de vuelta que va dando la vuelta al sobre.
    final caja = Rect.fromCenter(
      center: centro,
      width: rx * 2,
      height: ry * 2,
    );

    // Trazo de tinta debajo y crema encima: se lee tanto sobre el beige del
    // fondo como sobre el naranja del envoltorio.
    for (final capa in [true, false]) {
      canvas.drawArc(
        caja,
        avance,
        pi * 0.62,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = capa ? 8 : 4.5
          ..color = (capa ? kInk.withValues(alpha: 0.35) : Colors.white)
              .withValues(alpha: (capa ? 0.35 : 0.95) * _fade),
      );
    }

    // La punta de la flecha, al final del arco.
    final fin = avance + pi * 0.62;
    final punta = Offset(
      centro.dx + cos(fin) * rx,
      centro.dy + sin(fin) * ry,
    );
    // Tangente de la elipse en ese punto: hacia donde apunta.
    final tang = atan2(ry * cos(fin), -rx * sin(fin));

    canvas.save();
    canvas.translate(punta.dx, punta.dy);
    canvas.rotate(tang);
    final cabeza = Path()
      ..moveTo(9, 0)
      ..lineTo(-5, -7)
      ..lineTo(-5, 7)
      ..close();
    canvas.drawPath(
      cabeza,
      Paint()..color = Colors.white.withValues(alpha: 0.95 * _fade),
    );
    canvas.drawPath(
      cabeza,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..color = kInk.withValues(alpha: 0.5 * _fade),
    );
    canvas.restore();
  }
}

