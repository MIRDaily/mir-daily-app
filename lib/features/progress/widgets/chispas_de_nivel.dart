/* ════════════════════════════════════════════════════════════════════════
   Las chispas del salto de nivel.

   Partículas estilo fuego artificial que salen del extremo donde la barra
   acaba de llenarse y CHOCAN con ella. Es un CustomPainter alimentado por un
   Ticker: ni una dependencia nueva.

   QUÉ LAS HACE SENTIRSE FÍSICAS. No es el número de partículas, son cuatro
   detalles: (1) la gravedad las curva, así que suben frenando y bajan
   acelerando; (2) el rozamiento del aire mata la velocidad inicial rápido, que
   es lo que distingue una chispa de un cohete; (3) las que caen sobre la barra
   REBOTAN en ella, pierden velocidad y acaban posándose encima; y (4) se
   pintan como trazos entre las posiciones anteriores y la actual, así que la
   estela sale de la velocidad real y no de un desenfoque falso.

   CUATRO TRAMPAS, tres heredadas de la web y una propia de Flutter:

   · El cono NO puede ser un círculo completo. Con círculo entero más de la
     mitad de las chispas salen por fuera del extremo y caen al vacío sin tocar
     nada: queda bonito y no cuenta con la barra, que es justo el encargo.
     Apuntando arriba y HACIA DENTRO, la gravedad las devuelve y llueven SOBRE
     la barra.

   · La colisión comprueba el CRUCE (dónde estaba y dónde está), no si acabó
     dentro: a 500 px/s una chispa se salta una barra de 16 px entre dos
     fotogramas y la atravesaría sin enterarse.

   · Una salva nueva se SUMA a las que ya vuelan, nunca las reinicia. En un
     salto de dos niveles, si el estado de las partículas colgara del contador
     de salvas, la segunda borraría a la primera a media parábola.

   · En Flutter no existe el borrado parcial del lienzo que en canvas da la
     estela: el CustomPainter repinta desde cero cada fotograma. Se reproduce
     guardando las últimas posiciones de cada partícula y pintando una
     polilínea con alfa decreciente.

   Y el apagado: el Ticker se para cuando muere la última chispa. Nada de un
   bucle eterno consumiendo batería en una pantalla parada.
═══════════════════════════════════════════════════════════════════════════ */
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Píxeles por segundo al cuadrado. Alta a propósito: la gravedad "real"
/// (~980) dentro de una caja de 300 px se ve lunar.
const double _kGravedad = 1600;

/// Rozamiento del aire, por fotograma a 60 fps.
const double _kRozamiento = 0.9;

/// Velocidad que conserva al rebotar en la barra. Un tercio: son brasas, no
/// pelotas de goma.
const double _kRebote = 0.34;

/// Frenada tangencial al tocar la barra: es lo que las hace rodar y pararse.
const double _kRoce = 0.74;

/// Cuántas posiciones anteriores se guardan para dibujar la estela.
const int _kEstela = 5;

class _Chispa {
  double x;
  double y;
  double vx;
  double vy;
  double edad = 0;
  final double vida;
  final Color color;
  final double grosor;
  int rebotes = 0;

  /// Ya no se mueve: se ha posado sobre la barra.
  bool posada = false;

  /// Las últimas posiciones, de la más antigua a la más reciente.
  final List<Offset> rastro;

  _Chispa({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.vida,
    required this.color,
    required this.grosor,
  }) : rastro = [Offset(x, y)];
}

/// La barra contra la que chocan, en coordenadas del lienzo.
class _Barra {
  final double x0;
  final double x1;
  final double y;

  const _Barra(this.x0, this.x1, this.y);
}

class ChispasDeNivel extends StatefulWidget {
  /// Cada incremento dispara una salva nueva. En 0 no hay nada que pintar.
  final int salva;

  /// La barra con la que chocan. Se mide en vivo al disparar: si cambia de
  /// sitio o de ancho, las chispas chocan donde esté de verdad.
  final GlobalKey barraKey;

  final List<Color> colores;

  const ChispasDeNivel({
    super.key,
    required this.salva,
    required this.barraKey,
    required this.colores,
  });

  @override
  State<ChispasDeNivel> createState() => _ChispasDeNivelState();
}

class _ChispasDeNivelState extends State<ChispasDeNivel>
    with SingleTickerProviderStateMixin {
  final List<_Chispa> _chispas = [];
  final math.Random _azar = math.Random();

  Ticker? _ticker;
  Duration _anterior = Duration.zero;

  /// El reloj del pintor. Se avisa desde el Ticker y solo repinta el lienzo:
  /// nada de un `setState` por fotograma reconstruyendo el árbol entero.
  final ValueNotifier<int> _reloj = ValueNotifier(0);

  /// Intensidad del fogonazo, de 1 a 0.
  double _fogonazo = 0;

  /// Dónde estaba la barra en la última salva: es donde revienta el fogonazo.
  _Barra? _barra;

  @override
  void didUpdateWidget(covariant ChispasDeNivel old) {
    super.didUpdateWidget(old);
    if (widget.salva > old.salva && widget.salva > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _disparar());
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _reloj.dispose();
    super.dispose();
  }

  /// Mide la barra en coordenadas de ESTE lienzo. Es el equivalente del
  /// `getBoundingClientRect` de la web.
  _Barra? _medirBarra() {
    final miCaja = context.findRenderObject();
    final suCaja = widget.barraKey.currentContext?.findRenderObject();
    if (miCaja is! RenderBox || suCaja is! RenderBox) return null;
    if (!miCaja.hasSize || !suCaja.hasSize) return null;

    final esquina = suCaja.localToGlobal(Offset.zero);
    final origen = miCaja.globalToLocal(esquina);
    return _Barra(origen.dx, origen.dx + suCaja.size.width, origen.dy);
  }

  void _disparar() {
    if (!mounted) return;
    if (MediaQuery.disableAnimationsOf(context)) return;

    final barra = _medirBarra();
    if (barra == null) return;
    _barra = barra;

    _chispas.addAll(_crearSalva(barra));
    // Fogonazo en el punto del impacto. Dura un suspiro y es lo que lleva el
    // ojo ahí justo cuando salen las chispas.
    _fogonazo = 1;

    if (_ticker == null) {
      _anterior = Duration.zero;
      _ticker = createTicker(_paso)..start();
    }
  }

  List<_Chispa> _crearSalva(_Barra barra) {
    final fuera = <_Chispa>[];
    final colores = widget.colores.isEmpty
        ? const [Color(0xFFEDB53F)]
        : widget.colores;

    _Chispa nueva(double x, double y, double ang, double vel, double vida) =>
        _Chispa(
          x: x,
          y: y,
          vx: math.cos(ang) * vel,
          vy: math.sin(ang) * vel,
          vida: vida,
          color: colores[_azar.nextInt(colores.length)],
          grosor: 1.3 + _azar.nextDouble() * 2.1,
        );

    // La salva principal sale del extremo donde la barra ACABA de llenarse.
    // Ese es el punto exacto del salto y por eso es de donde tiene que
    // reventar: la barra llega al tope y estalla.
    final foco = barra.x1 - 6;

    // El cono apunta arriba y hacia dentro (ver la cabecera). Se lee además
    // como el retroceso de algo que choca contra un tope, así que la
    // desviación no es una trampa: es lo que haría de verdad.
    const centro = -math.pi / 2 - 0.35;
    const apertura = 2.6;

    for (var i = 0; i < 58; i++) {
      final ang = centro + (_azar.nextDouble() - 0.5) * apertura;
      // Cáscara con grosor: una explosión no manda todo a la misma velocidad,
      // pero tampoco reparte uniforme.
      final vel = 260 + _azar.nextDouble() * 380;
      final c = nueva(
        foco + (_azar.nextDouble() - 0.5) * 6,
        barra.y + (_azar.nextDouble() - 0.5) * 4,
        ang,
        vel,
        0.75 + _azar.nextDouble() * 0.75,
      );
      c.vx -= 60;
      fuera.add(c);
    }

    // Y una lluvia corta a lo largo de toda la barra: es lo que hace que el
    // efecto se lea como "la barra entera ha reaccionado" y no como un petardo
    // colgado de la punta. La velocidad está elegida para que suban entre 30 y
    // 70 px y VUELVAN a caer sobre la barra dentro de su vida: el rebote se
    // ve, que es el objetivo.
    final ancho = math.max(1.0, barra.x1 - barra.x0);
    for (var i = 0; i < 26; i++) {
      final x = barra.x0 + _azar.nextDouble() * ancho;
      final ang = -math.pi / 2 + (_azar.nextDouble() - 0.5) * 1.5;
      fuera.add(nueva(
        x,
        barra.y,
        ang,
        150 + _azar.nextDouble() * 210,
        0.6 + _azar.nextDouble() * 0.7,
      ));
    }

    return fuera;
  }

  void _paso(Duration ahora) {
    final barra = _barra;
    if (barra == null) return;

    // Acotado: si la app estuvo en segundo plano, dt sería enorme y las
    // chispas darían un salto teletransportado.
    final dt = _anterior == Duration.zero
        ? 1 / 60
        : math.min(
            0.034,
            (ahora - _anterior).inMicroseconds / Duration.microsecondsPerSecond,
          );
    _anterior = ahora;

    final frenada = math.pow(_kRozamiento, dt * 60).toDouble();

    _chispas.removeWhere((c) {
      c.edad += dt;
      if (c.edad >= c.vida) return true;

      final antesY = c.y;

      if (!c.posada) {
        c.vy += _kGravedad * dt;
        c.vx *= frenada;
        c.vy *= frenada;
        c.x += c.vx * dt;
        c.y += c.vy * dt;

        // El contacto con la barra: se comprueba el CRUCE (ver la cabecera).
        final cruza = antesY <= barra.y && c.y >= barra.y && c.vy > 0;
        if (cruza && c.x >= barra.x0 && c.x <= barra.x1) {
          c.y = barra.y;
          c.vy = -c.vy * _kRebote;
          c.vx *= _kRoce;
          c.rebotes += 1;
          // Ya sin fuerza: se queda encima y se apaga ahí. Esto es lo que
          // remata la sensación de que la barra es un objeto sólido.
          if (c.rebotes >= 2 && c.vy.abs() < 60) {
            c.posada = true;
            c.vy = 0;
            c.y = barra.y;
          }
        }
      } else {
        // Posada: solo rueda un poco y se apaga antes que las demás.
        c.vx *= math.pow(0.86, dt * 60).toDouble();
        c.x += c.vx * dt;
        c.edad += dt * 1.6;
      }

      c.rastro.add(Offset(c.x, c.y));
      if (c.rastro.length > _kEstela) c.rastro.removeAt(0);
      return false;
    });

    if (_fogonazo > 0.01) _fogonazo -= dt * 6;

    if (_chispas.isEmpty && _fogonazo <= 0.01) {
      _fogonazo = 0;
      _ticker?.dispose();
      _ticker = null;
    }
    _reloj.value++;
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _ChispasPainter(estado: this, repaint: _reloj),
        size: Size.infinite,
      ),
    );
  }
}

/// El pintor lee el estado vivo del motor. Es intencionado: las partículas se
/// mutan en sitio y no tiene sentido copiar 84 objetos por fotograma solo para
/// respetar la inmutabilidad de un widget que ya se repinta por `repaint`.
class _ChispasPainter extends CustomPainter {
  final _ChispasDeNivelState estado;

  const _ChispasPainter({
    required this.estado,
    required Listenable repaint,
  }) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    final chispas = estado._chispas;
    final b = estado._barra;
    final fogonazo = estado._fogonazo;

    if (b != null && fogonazo > 0.01) {
      final centro = Offset(b.x1 - 6, b.y);
      final r = 26 + (1 - fogonazo) * 26;
      canvas.drawCircle(
        centro,
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [
              Colors.white.withValues(alpha: 0.85 * fogonazo),
              const Color(0xFFEDB53F).withValues(alpha: 0.45 * fogonazo),
              const Color(0xFFEDB53F).withValues(alpha: 0),
            ],
            stops: const [0, 0.45, 1],
          ).createShader(Rect.fromCircle(center: centro, radius: r)),
      );
    }

    final pincel = Paint()
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    for (final c in chispas) {
      final q = (1 - c.edad / c.vida).clamp(0.0, 1.0);
      final alfa = (q * 1.5).clamp(0.0, 1.0);
      final grosor = c.grosor * (0.45 + q * 0.55);

      // La estela: los tramos más viejos, más transparentes y más finos.
      final n = c.rastro.length;
      for (var i = 1; i < n; i++) {
        final peso = i / (n - 1);
        pincel
          ..color = c.color.withValues(alpha: alfa * peso)
          ..strokeWidth = grosor * (0.35 + 0.65 * peso);
        canvas.drawLine(c.rastro[i - 1], c.rastro[i], pincel);
      }
    }
  }

  // El repintado lo manda el reloj del motor, no el ciclo de construcción.
  @override
  bool shouldRepaint(covariant _ChispasPainter old) => false;
}
