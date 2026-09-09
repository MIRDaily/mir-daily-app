/* ════════════════════════════════════════════════════════════════════════
   El salto de nivel, contado en directo.

   NO ENSEÑA EL RESULTADO: ENSEÑA EL RECORRIDO. Arranca en el XP que había
   antes del último evento, cuenta hacia arriba, la barra se llena, y al
   completarse el nivel la insignia salta y la barra vuelve a empezar. Si el
   tramo cruza dos peldaños, se ven los dos encadenados. Enseñar "Nivel 12" ya
   hecho desperdiciaría el único momento en que el usuario está mirando y
   contento.

   CÓMO ESTÁ HECHO, que aquí importa: se anima UN SOLO valor —el XP— y de él se
   derivan la anchura de la barra y el contador. Los `AnimatedBuilder` van
   acotados a esos dos trozos, así que el recorrido no reconstruye nada más: el
   estado solo se toca al CAMBIAR DE NIVEL, que pasa una o dos veces en toda la
   secuencia.
═══════════════════════════════════════════════════════════════════════════ */
import 'package:flutter/material.dart';

import '../../../core/theme/levels.dart';
import '../../../shared/sticker/sticker.dart';
import 'chispas_de_nivel.dart';
import 'marco_nivel.dart';
import 'tarjeta_nivel.dart' show miles;

/// Cuánto dura el recorrido. Acotado para que ni se pase ni se quede corto.
Duration duracionDeSubida(int ganado) {
  final s = (0.9 + ganado / 260).clamp(1.1, 2.6);
  return Duration(milliseconds: (s * 1000).round());
}

class SubidaDeNivel extends StatefulWidget {
  final int xpAntes;
  final int xpDespues;

  /// Se avisa en cada peldaño cruzado. Es lo que destapa el titular fuera.
  final ValueChanged<int>? onNivelNuevo;

  const SubidaDeNivel({
    super.key,
    required this.xpAntes,
    required this.xpDespues,
    this.onNivelNuevo,
  });

  @override
  State<SubidaDeNivel> createState() => _SubidaDeNivelState();
}

class _SubidaDeNivelState extends State<SubidaDeNivel>
    with TickerProviderStateMixin {
  /// El recorrido del XP. Un solo valor animado.
  late final AnimationController _viaje;

  /// El golpe de la insignia en cada peldaño. Va aparte para poder relanzarlo
  /// sin tocar el viaje.
  late final AnimationController _golpe;

  final GlobalKey _barraKey = GlobalKey();

  late int _nivel;

  /// Sube al cruzar. Cada incremento dispara una salva de chispas.
  int _saltando = 0;

  bool _sinAnimacion = false;
  bool _arrancado = false;

  int get _ganado {
    final n = widget.xpDespues - widget.xpAntes;
    return n < 0 ? 0 : n;
  }

  @override
  void initState() {
    super.initState();
    _nivel = nivelParaXp(widget.xpAntes);
    _viaje = AnimationController(
      vsync: this,
      duration: duracionDeSubida(_ganado),
    )..addListener(_vigilarPeldano);
    _golpe = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 750),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_arrancado) return;
    _arrancado = true;

    _sinAnimacion = MediaQuery.disableAnimationsOf(context);
    if (_sinAnimacion) {
      // Con las animaciones desactivadas se enseña el resultado y ya: sin
      // partículas, sin recorrido y sin esconder el titular.
      _nivel = nivelParaXp(widget.xpDespues);
      _viaje.value = 1;
      widget.onNivelNuevo?.call(_nivel);
      return;
    }

    // El arranque va con un respiro: la tarjeta tiene que haber entrado antes
    // de que la barra empiece a correr.
    Future<void>.delayed(const Duration(milliseconds: 350), () {
      if (mounted) _viaje.forward();
    });
  }

  @override
  void dispose() {
    _viaje.dispose();
    _golpe.dispose();
    super.dispose();
  }

  /// El XP en este instante del recorrido. Arranca con brío y frena al final,
  /// que es como se lee "esto va subiendo" y no "esto se desliza".
  double get _xp {
    const curva = Cubic(0.16, 0.85, 0.3, 1);
    final t = curva.transform(_viaje.value.clamp(0.0, 1.0));
    return widget.xpAntes + (widget.xpDespues - widget.xpAntes) * t;
  }

  void _vigilarPeldano() {
    final n = nivelParaXp(_xp);
    if (n == _nivel) return;
    // Único punto donde se toca el estado: una o dos veces en toda la
    // secuencia.
    setState(() {
      _nivel = n;
      _saltando += 1;
    });
    _golpe.forward(from: 0);
    widget.onNivelNuevo?.call(n);
  }

  /// Avance dentro del nivel que se está pintando, de 0 a 1.
  double get _fraccion {
    final v = _xp;
    final n = nivelParaXp(v);
    final base = xpParaNivel(n);
    return ((v - base) / costeNivel(n)).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final rango = rankForLevel(_nivel);

    return Stack(
      // Las chispas tienen que poder volar por encima de la insignia y por los
      // lados. Lo que sobre lo recorta la tarjeta, que es justo el encuadre
      // que queremos.
      clipBehavior: Clip.none,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Insignia(
              nivel: _nivel,
              color: rango.color,
              golpe: _golpe,
              saltando: _saltando,
            ),
            const SizedBox(height: 14),
            if (_ganado > 0) _ChipGanado(xp: _ganado, sinAnimacion: _sinAnimacion),
            _Pista(
              barraKey: _barraKey,
              viaje: _viaje,
              golpe: _golpe,
              saltando: _saltando,
              color: rango.color,
              fraccion: () => _fraccion,
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    rango.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: kInk,
                    ),
                  ),
                ),
                // El contador, acotado a su propio AnimatedBuilder.
                AnimatedBuilder(
                  animation: _viaje,
                  builder: (context, _) => Text(
                    '${miles(_xp.round())} XP',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: kInk,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),

        // Las chispas van por encima de todo lo demás y se salen del ancho a
        // propósito.
        if (!_sinAnimacion)
          Positioned(
            left: -90,
            right: -90,
            top: -110,
            bottom: -30,
            child: ChispasDeNivel(
              salva: _saltando,
              barraKey: _barraKey,
              colores: [
                rango.color,
                const Color(0xFFDEBB7E),
                const Color(0xFFEDB53F),
                const Color(0xFFC4856A),
              ],
            ),
          ),
      ],
    );
  }
}

/// La insignia. Da un golpe en cada peldaño cruzado, con una onda que sale
/// disparada calcando el filo del marco.
class _Insignia extends StatelessWidget {
  final int nivel;
  final Color color;
  final AnimationController golpe;
  final int saltando;

  const _Insignia({
    required this.nivel,
    required this.color,
    required this.golpe,
    required this.saltando,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 96,
      width: 96,
      child: AnimatedBuilder(
        animation: golpe,
        builder: (context, hijo) {
          final t = golpe.value;
          final vivo = saltando > 0 && t > 0 && t < 1;

          // El golpe: crece de más, se pasa de rosca y vuelve.
          final g = Curves.easeOut.transform(t.clamp(0.0, 1.0));
          final escala = saltando == 0
              ? 1.0
              : 1 + 0.34 * _pico(g) - 0.06 * _rebote(g);
          final giro = saltando == 0 ? 0.0 : -0.10 * _pico(g) + 0.07 * _rebote(g);

          return Stack(
            alignment: Alignment.center,
            children: [
              if (vivo)
                Positioned.fill(
                  child: FractionallySizedBox(
                    widthFactor: 0.9091,
                    heightFactor: 0.9091,
                    child: Transform.scale(
                      scale: 1 + 1.1 * g,
                      child: Opacity(
                        opacity: (0.95 * (1 - g)).clamp(0.0, 1.0),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: const Color(0xFFDEBB7E),
                              width: 3,
                            ),
                            // Radio del 10 % del lado, como el filo del marco.
                            borderRadius: BorderRadius.circular(96 * 0.09091),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              Transform.rotate(
                angle: giro,
                child: Transform.scale(scale: escala, child: hijo),
              ),
            ],
          );
        },
        child: MarcoNivel(nivel: nivel, tamano: 96, color: color),
      ),
    );
  }

  /// Sube rápido y baja: la parte "golpe" del muelle.
  static double _pico(double t) => t < 0.34 ? t / 0.34 : (1 - t) / 0.66;

  /// El rebote de vuelta, más pequeño y más tarde.
  static double _rebote(double t) =>
      t < 0.4 ? 0 : ((t - 0.4) / 0.3).clamp(0.0, 1.0) * (1 - t) / 0.6;
}

/// El XP ganado, que es el protagonista del momento.
class _ChipGanado extends StatelessWidget {
  final int xp;
  final bool sinAnimacion;

  const _ChipGanado({required this.xp, required this.sinAnimacion});

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: kInk,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: kInk, width: 2),
      ),
      child: Text(
        '+${miles(xp)} XP',
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w900,
          color: Colors.white,
        ),
      ),
    );

    if (sinAnimacion) return chip;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 520),
      curve: Curves.elasticOut,
      builder: (context, v, hijo) => Opacity(
        opacity: v.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, -14 * (1 - v)),
          child: Transform.scale(scale: 0.7 + 0.3 * v, child: hijo),
        ),
      ),
      child: chip,
    );
  }
}

/// La barra: la pista, el relleno y el destello que la barre en cada peldaño.
class _Pista extends StatelessWidget {
  final GlobalKey barraKey;
  final AnimationController viaje;
  final AnimationController golpe;
  final int saltando;
  final Color color;
  final double Function() fraccion;

  const _Pista({
    required this.barraKey,
    required this.viaje,
    required this.golpe,
    required this.saltando,
    required this.color,
    required this.fraccion,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      key: barraKey,
      height: 16,
      decoration: BoxDecoration(
        color: const Color(0xFFF3EFED),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: kInk, width: 2),
      ),
      // El recorte va DENTRO y no en el `clipBehavior` del Container: el
      // Container recorta contra el radio EXTERIOR, y como el borde mete al
      // hijo 2 px hacia dentro, el extremo del relleno quedaba fuera de la
      // curva y se veía como una esquina cuadrada asomando por la izquierda.
      // Aquí el recorte es el del hueco interior, que es contra lo que de
      // verdad tiene que encajar.
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: Stack(
        children: [
          // El relleno, acotado a su propio AnimatedBuilder: es lo único que
          // cambia en cada fotograma del recorrido.
          AnimatedBuilder(
            animation: viaje,
            builder: (context, _) => Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: fraccion(),
                heightFactor: 1,
                child: DecoratedBox(
                  // Redondeado por los CUATRO lados: con la barra casi vacía
                  // el trocito de relleno tiene que leerse como una pastilla
                  // dentro de la pista, no como un tope cuadrado.
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ),
          ),

          // Destello blanco que barre la barra en cada peldaño: es lo que hace
          // que el cruce se lea como un golpe y no como un reinicio.
          if (saltando > 0)
            AnimatedBuilder(
              animation: golpe,
              builder: (context, _) {
                final t = (golpe.value / 0.73).clamp(0.0, 1.0);
                if (t <= 0 || t >= 1) return const SizedBox.shrink();
                final g = Curves.easeOut.transform(t);
                return Align(
                  alignment: Alignment(-1.4 + 2.8 * g, 0),
                  child: FractionallySizedBox(
                    widthFactor: 0.28,
                    heightFactor: 1,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.white.withValues(alpha: 0),
                            Colors.white.withValues(alpha: 0.95 * (1 - g)),
                            Colors.white.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
        ),
      ),
    );
  }
}
