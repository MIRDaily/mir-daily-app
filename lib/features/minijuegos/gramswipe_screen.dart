// GramSwipe: clasificar antibióticos deslizando la tarjeta. Puerto de la web:
// src/components/minijuegos/gramswipe/GramSwipeGame.tsx (la lógica está en core/models/gramswipe.dart).
//
// Tres pantallas, como en la web: inicio (reglas y modo), partida y resultado.
//  - La tarjeta se arrastra con el dedo: se inclina, se tiñe del color de la respuesta y, pasado el
//    umbral, sale volando. Si no llega, vuelve a su sitio. Un toque la voltea (familia y mecanismo).
//  - Debajo, cuatro botones con las mismas respuestas: son la leyenda, sirven sin arrastrar y se
//    encienden mientras se arrastra hacia ellos.
//  - Modo estudio: tras cada tarjeta, si era o no, con la respuesta. Modo rápido: sin pausas.
//  - Salir a mitad de partida pide confirmación (en la web, el botón de volver del juego).

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/models/gramswipe.dart';
import '../../core/models/gramswipe_datos.dart';
import '../../core/responsive/breakpoints.dart';
import '../../core/services/haptics_service.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/sticker/sticker.dart';

enum _Pantalla { inicio, juego, resultado }

enum ModoGramSwipe { estudio, rapido }

const Color _gramPos = Color(0xFF8BA888);
const Color _gramNeg = Color(0xFFD4978C);
const Color _amplio = Color(0xFFA278CF);
const Color _noSe = Color(0xFFA8A4A0);

Color colorDireccion(DireccionSwipe d) => switch (d) {
      DireccionSwipe.derecha => _gramPos,
      DireccionSwipe.izquierda => _gramNeg,
      DireccionSwipe.arriba => _amplio,
      DireccionSwipe.abajo => _noSe,
    };

Color colorCobertura(Cobertura c) => switch (c) {
      Cobertura.gramPositivo => _gramPos,
      Cobertura.gramNegativo => _gramNeg,
      Cobertura.amplio => _amplio,
    };

String etiquetaDireccion(DireccionSwipe d) => switch (d) {
      DireccionSwipe.abajo => 'No sé',
      _ => etiquetaCobertura[coberturaDe(d)]!,
    };

IconData iconoDireccion(DireccionSwipe d) => switch (d) {
      DireccionSwipe.derecha => Icons.arrow_forward_rounded,
      DireccionSwipe.izquierda => Icons.arrow_back_rounded,
      DireccionSwipe.arriba => Icons.arrow_upward_rounded,
      DireccionSwipe.abajo => Icons.arrow_downward_rounded,
    };

class GramSwipeScreen extends StatefulWidget {
  /// Para los tests: el mazo y el azar con que se baraja.
  final List<Antibiotico>? mazo;
  final math.Random? azar;

  const GramSwipeScreen({super.key, this.mazo, this.azar});

  @override
  State<GramSwipeScreen> createState() => _GramSwipeScreenState();
}

class _GramSwipeScreenState extends State<GramSwipeScreen> with TickerProviderStateMixin {
  _Pantalla _pantalla = _Pantalla.inicio;
  ModoGramSwipe _modo = ModoGramSwipe.estudio;
  PartidaGramSwipe? _p;
  RespuestaGramSwipe? _feedback;

  // La tarjeta de arriba: dónde está, si está volteada y su animación de vuelo / vuelta.
  Offset _offset = Offset.zero;
  bool _volteada = false;
  DireccionSwipe? _saliendo;
  late final AnimationController _vuelo = AnimationController(vsync: this);
  Animation<Offset>? _trayecto;
  late final AnimationController _giro =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 480));
  bool _pasoUmbral = false;

  List<Antibiotico> get _mazo => widget.mazo ?? antibioticosGramSwipe;

  @override
  void initState() {
    super.initState();
    _vuelo.addListener(() {
      if (_trayecto != null) setState(() => _offset = _trayecto!.value);
    });
  }

  @override
  void dispose() {
    _vuelo.dispose();
    _giro.dispose();
    super.dispose();
  }

  void _empezar([PartidaGramSwipe? partida]) {
    setState(() {
      _p = partida ?? PartidaGramSwipe.barajada(_mazo, widget.azar);
      _feedback = null;
      _offset = Offset.zero;
      _saliendo = null;
      _volteada = false;
      _giro.value = 0;
      _pantalla = _Pantalla.juego;
    });
  }

  bool get _bloqueada => _saliendo != null || _feedback != null || _p?.actual == null;

  void _voltear() {
    if (_bloqueada) return;
    HapticsService.light();
    setState(() => _volteada = !_volteada);
    _volteada ? _giro.forward() : _giro.reverse();
  }

  void _arrastrar(DragUpdateDetails d) {
    if (_bloqueada) return;
    setState(() => _offset += d.delta);
    final pasa = intensidadArrastre(_offset.dx, _offset.dy) >= 1;
    if (pasa && !_pasoUmbral) HapticsService.light();
    _pasoUmbral = pasa;
  }

  void _soltar(DragEndDetails d) {
    if (_bloqueada) return;
    _pasoUmbral = false;
    final dir = direccionAlSoltar(_offset.dx, _offset.dy);
    if (dir != null) {
      _lanzar(dir);
    } else {
      _animarA(Offset.zero, const Duration(milliseconds: 450), const Cubic(0.22, 1, 0.36, 1));
    }
  }

  void _animarA(Offset destino, Duration duracion, Curve curva, [VoidCallback? alAcabar]) {
    _trayecto = Tween(begin: _offset, end: destino).animate(CurvedAnimation(parent: _vuelo, curve: curva));
    _vuelo
      ..duration = duracion
      ..forward(from: 0).whenComplete(() {
        _trayecto = null;
        if (mounted) alAcabar?.call();
      });
  }

  /// Saca la tarjeta volando hacia [dir] (por arrastre o con un botón) y luego la clasifica.
  void _lanzar(DireccionSwipe dir) {
    if (_bloqueada) return;
    final size = MediaQuery.sizeOf(context);
    final destino = switch (dir) {
      DireccionSwipe.derecha => Offset(size.width * 1.4, _offset.dy),
      DireccionSwipe.izquierda => Offset(-size.width * 1.4, _offset.dy),
      DireccionSwipe.arriba => Offset(_offset.dx, -size.height * 1.2),
      DireccionSwipe.abajo => Offset(_offset.dx, size.height * 1.2),
    };
    setState(() => _saliendo = dir);
    _animarA(destino, const Duration(milliseconds: 420), const Cubic(0.4, 0, 0.8, 0.65), () => _clasificar(dir));
  }

  void _clasificar(DireccionSwipe dir) {
    final r = _p!.deslizar(dir);
    if (r != null) r.acierto ? HapticsService.light() : HapticsService.medium();
    setState(() {
      _offset = Offset.zero;
      _saliendo = null;
      _volteada = false;
      _giro.value = 0;
      if (r != null && _modo == ModoGramSwipe.estudio) {
        _feedback = r;
      } else if (_p!.terminada) {
        _pantalla = _Pantalla.resultado;
      }
    });
  }

  void _continuar() {
    setState(() {
      _feedback = null;
      if (_p!.terminada) _pantalla = _Pantalla.resultado;
    });
  }

  Future<bool> _confirmarSalida() async {
    if (_pantalla != _Pantalla.juego) return true;
    final salir = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Abandonar la sesión?'),
        content: const Text('Perderás lo que llevas de esta partida.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Seguir jugando')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Abandonar')),
        ],
      ),
    );
    if (salir == true && mounted) setState(() => _pantalla = _Pantalla.inicio);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final cuerpo = switch (_pantalla) {
      _Pantalla.inicio => _Inicio(
          modo: _modo,
          total: _mazo.length,
          onModo: (m) => setState(() => _modo = m),
          onEmpezar: _empezar,
        ),
      _Pantalla.juego => _juego(),
      _Pantalla.resultado => _Resultado(
          partida: _p!,
          onRepetirErrores: () => _empezar(_p!.repetirErrores(widget.azar)),
          onNueva: _empezar,
          onInicio: () => setState(() => _pantalla = _Pantalla.inicio),
        ),
    };
    return PopScope(
      canPop: _pantalla != _Pantalla.juego,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmarSalida();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(title: const Text('GramSwipe')),
        body: SafeArea(top: false, child: cuerpo),
      ),
    );
  }

  Widget _juego() {
    final p = _p!;
    final arriba = p.cola.take(3).toList();
    final dirArrastre = _saliendo ??
        (_offset == Offset.zero ? null : direccionDeArrastre(_offset.dx, _offset.dy));
    final intensidad = _saliendo != null ? 1.0 : intensidadArrastre(_offset.dx, _offset.dy);
    return Stack(
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: EdgeInsets.fromLTRB(context.bodyGutter, 8, context.bodyGutter, 12),
              child: Column(
                children: [
                  _Marcador(hechas: p.respondidas.length, total: p.total, aciertos: p.aciertos),
                  const SizedBox(height: 14),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, cons) {
                        final ancho = cons.maxWidth;
                        final alto = math.min(cons.maxHeight - 26, ancho * 1.35);
                        return Stack(
                          alignment: Alignment.topCenter,
                          clipBehavior: Clip.none,
                          children: [
                            for (var i = arriba.length - 1; i >= 0; i--)
                              _capa(arriba[i], i, ancho, alto, dirArrastre, intensidad),
                          ],
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  _Botones(
                    activa: dirArrastre,
                    intensidad: intensidad,
                    habilitados: !_bloqueada,
                    onPulsar: _lanzar,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_feedback != null) _Feedback(respuesta: _feedback!, onContinuar: _continuar),
      ],
    );
  }

  Widget _capa(Antibiotico a, int profundidad, double ancho, double alto, DireccionSwipe? dir, double intensidad) {
    final tarjeta = SizedBox(
      key: ValueKey(a.id),
      width: ancho,
      height: alto,
      child: _Tarjeta(
        antibiotico: a,
        giro: profundidad == 0 ? _giro : null,
        tinte: profundidad == 0 ? dir : null,
        intensidad: profundidad == 0 ? intensidad : 0,
      ),
    );
    if (profundidad > 0) {
      // Las de debajo asoman, más pequeñas.
      final escala = 1 - 0.04 * profundidad;
      return AnimatedContainer(
        key: ValueKey('capa-${a.id}'),
        duration: const Duration(milliseconds: 450),
        curve: kEaseOut,
        transform: Matrix4.identity()
          ..translateByDouble(ancho * (1 - escala) / 2, 11.0 * profundidad + alto * (1 - escala), 0, 1)
          ..scaleByDouble(escala, escala, 1, 1),
        child: IgnorePointer(child: tarjeta),
      );
    }
    final rot = (_offset.dx / math.max(1, MediaQuery.sizeOf(context).width)) * 18 * math.pi / 180;
    return Semantics(
      label: '${a.nombre}. Toca para voltear; desliza para clasificar.',
      button: true,
      child: GestureDetector(
        key: ValueKey('arriba-${a.id}'),
        onTap: _voltear,
        onPanUpdate: _arrastrar,
        onPanEnd: _soltar,
        child: Transform.translate(
          offset: _offset,
          child: Transform.rotate(angle: rot, child: tarjeta),
        ),
      ),
    );
  }
}

/* ════════════════════════════════════════════════════════════════════════
   Inicio
═══════════════════════════════════════════════════════════════════════════ */

class _Inicio extends StatelessWidget {
  final ModoGramSwipe modo;
  final int total;
  final ValueChanged<ModoGramSwipe> onModo;
  final VoidCallback onEmpezar;

  const _Inicio({required this.modo, required this.total, required this.onModo, required this.onEmpezar});

  @override
  Widget build(BuildContext context) {
    Widget regla(DireccionSwipe d) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: kHairline, width: 1.5),
          ),
          child: Row(
            children: [
              Icon(iconoDireccion(d), color: colorDireccion(d), size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  d == DireccionSwipe.abajo ? 'No sé · vuelve al mazo' : etiquetaDireccion(d),
                  style: TextStyle(
                    color: d == DireccionSwipe.abajo ? kMuted : kInk,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        );

    Widget opcionModo(ModoGramSwipe m, IconData icono, String titulo, String sub) {
      final activo = m == modo;
      return Expanded(
        child: Semantics(
          selected: activo,
          button: true,
          child: GestureDetector(
            onTap: () => onModo(m),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
              decoration: BoxDecoration(
                color: activo ? tinted(kAccent, 0.16) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: activo ? kInk : kHairline, width: activo ? 2 : 1.5),
                boxShadow: activo ? inkShadow(3) : null,
              ),
              child: Column(
                children: [
                  Icon(icono, color: activo ? kInk : kMuted),
                  const SizedBox(height: 4),
                  Text(titulo, style: const TextStyle(color: kInk, fontSize: 13.5, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(sub, textAlign: TextAlign.center, style: const TextStyle(color: kMuted, fontSize: 11.5)),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return ListView(
      padding: EdgeInsets.fromLTRB(context.bodyGutter, 12, context.bodyGutter, 32),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Clasifica antibióticos',
                  style: TextStyle(color: kInk, fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -0.5),
                ),
                const SizedBox(height: 4),
                Text(
                  '$total antibióticos. Desliza cada tarjeta hacia su espectro de cobertura.',
                  style: const TextStyle(color: kMuted, fontSize: 14, height: 1.4),
                ),
                const SizedBox(height: 18),
                Row(children: [
                  Expanded(child: regla(DireccionSwipe.derecha)),
                  const SizedBox(width: 10),
                  Expanded(child: regla(DireccionSwipe.izquierda)),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: regla(DireccionSwipe.arriba)),
                  const SizedBox(width: 10),
                  Expanded(child: regla(DireccionSwipe.abajo)),
                ]),
                const SizedBox(height: 12),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.touch_app_rounded, size: 16, color: kMuted),
                    SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Toca la tarjeta para ver familia y mecanismo',
                        style: TextStyle(color: kMuted, fontSize: 12.5),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                const SectionLabel('Modo de juego'),
                const SizedBox(height: 10),
                Row(children: [
                  opcionModo(ModoGramSwipe.estudio, Icons.school_rounded, 'Estudio', 'Corrección tras cada tarjeta'),
                  const SizedBox(width: 10),
                  opcionModo(ModoGramSwipe.rapido, Icons.bolt_rounded, 'Repaso rápido', 'Sin interrupciones'),
                ]),
                const SizedBox(height: 24),
                StickerButton(label: 'Empezar', icon: Icons.play_arrow_rounded, expand: true, onPressed: onEmpezar),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/* ════════════════════════════════════════════════════════════════════════
   Partida
═══════════════════════════════════════════════════════════════════════════ */

class _Marcador extends StatelessWidget {
  final int hechas;
  final int total;
  final int aciertos;

  const _Marcador({required this.hechas, required this.total, required this.aciertos});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(end: total == 0 ? 0 : hechas / total),
                  duration: const Duration(milliseconds: 400),
                  curve: kEaseOut,
                  builder: (_, v, __) => LinearProgressIndicator(
                    value: v,
                    minHeight: 7,
                    backgroundColor: const Color(0xFFF2EFED),
                    color: kAccent,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text('$hechas / $total', style: const TextStyle(color: kMuted, fontSize: 11.5, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Semantics(
          label: '$aciertos aciertos',
          child: Container(
            padding: const EdgeInsets.fromLTRB(8, 5, 11, 5),
            decoration: BoxDecoration(
              color: tinted(_gramPos, 0.18),
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: kInk, width: 1.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle_rounded, size: 16, color: Color(0xFF55745A)),
                const SizedBox(width: 4),
                ExcludeSemantics(
                  child: Text('$aciertos', style: const TextStyle(color: kInk, fontWeight: FontWeight.w900)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Tarjeta extends StatelessWidget {
  final Antibiotico antibiotico;
  final Animation<double>? giro;
  final DireccionSwipe? tinte;
  final double intensidad;

  const _Tarjeta({required this.antibiotico, required this.giro, required this.tinte, required this.intensidad});

  @override
  Widget build(BuildContext context) {
    final g = giro;
    if (g == null) return _cara(context, delante: true);
    return AnimatedBuilder(
      animation: g,
      builder: (context, _) {
        final t = Curves.easeInOutCubic.transform(g.value);
        final delante = t < 0.5;
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0012)
            ..rotateY(math.pi * t + (delante ? 0 : math.pi)),
          child: _cara(context, delante: delante),
        );
      },
    );
  }

  Widget _cara(BuildContext context, {required bool delante}) {
    final a = antibiotico;
    final contenido = delante
        ? Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 5,
                  child: Center(
                    child: Image.asset(
                      a.foto,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Icon(Icons.medication_rounded, size: 64, color: kHairline),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'PRINCIPIO ACTIVO',
                  style: TextStyle(color: _noSe, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.8),
                ),
                Text(a.principioActivo, style: const TextStyle(color: kMuted, fontSize: 14)),
                const SizedBox(height: 2),
                Text(
                  a.nombre,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: kInk, fontSize: 25, fontWeight: FontWeight.w900, height: 1.1),
                ),
                const SizedBox(height: 10),
                const Row(
                  children: [
                    Icon(Icons.touch_app_rounded, size: 15, color: _noSe),
                    SizedBox(width: 5),
                    Flexible(
                      child: Text('Toca para ver familia y mecanismo', style: TextStyle(color: _noSe, fontSize: 11.5)),
                    ),
                  ],
                ),
              ],
            ),
          )
        : Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF2C2522), Color(0xFF1A1614)],
              ),
            ),
            padding: const EdgeInsets.all(22),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'FAMILIA',
                    style: TextStyle(color: Color(0x73FFFFFF), fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.8),
                  ),
                  const SizedBox(height: 2),
                  Text(a.familia, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800, height: 1.2)),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Divider(color: Color(0x1AFFFFFF), height: 1),
                  ),
                  const Text(
                    'MECANISMO DE ACCIÓN',
                    style: TextStyle(color: Color(0x73FFFFFF), fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.8),
                  ),
                  const SizedBox(height: 4),
                  Text(a.mecanismo, style: const TextStyle(color: Color(0xE6FFFFFF), fontSize: 14, height: 1.5)),
                  const SizedBox(height: 16),
                  const Row(
                    children: [
                      Icon(Icons.swipe_rounded, size: 15, color: Color(0x59FFFFFF)),
                      SizedBox(width: 5),
                      Flexible(
                        child: Text('Desliza para clasificar', style: TextStyle(color: Color(0x59FFFFFF), fontSize: 11.5)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );

    final d = tinte;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: kInk, width: 2),
        boxShadow: inkShadow(5),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          contenido,
          if (d != null && intensidad > 0)
            IgnorePointer(
              child: Container(
                color: colorDireccion(d).withValues(alpha: 0.62 * intensidad),
                alignment: Alignment.center,
                child: Opacity(
                  opacity: intensidad,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(iconoDireccion(d), color: Colors.white, size: 30 + 22 * intensidad),
                      const SizedBox(height: 6),
                      Text(
                        etiquetaDireccion(d).toUpperCase(),
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 2),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Las cuatro respuestas: leyenda, botones y testigo del arrastre.
class _Botones extends StatelessWidget {
  final DireccionSwipe? activa;
  final double intensidad;
  final bool habilitados;
  final ValueChanged<DireccionSwipe> onPulsar;

  const _Botones({required this.activa, required this.intensidad, required this.habilitados, required this.onPulsar});

  @override
  Widget build(BuildContext context) {
    const orden = [DireccionSwipe.izquierda, DireccionSwipe.arriba, DireccionSwipe.abajo, DireccionSwipe.derecha];
    return Row(
      children: [
        for (final d in orden) ...[
          if (d != orden.first) const SizedBox(width: 8),
          Expanded(child: _boton(d)),
        ],
      ],
    );
  }

  Widget _boton(DireccionSwipe d) {
    final color = colorDireccion(d);
    final encendido = activa == d ? intensidad : 0.0;
    return Semantics(
      button: true,
      enabled: habilitados,
      label: etiquetaDireccion(d),
      child: GestureDetector(
        onTap: habilitados ? () => onPulsar(d) : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          height: 58,
          transform: Matrix4.diagonal3Values(1 + 0.08 * encendido, 1 + 0.08 * encendido, 1),
          transformAlignment: Alignment.center,
          decoration: BoxDecoration(
            color: Color.lerp(Colors.white, tinted(color, 0.35), encendido),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: d == DireccionSwipe.abajo ? kHairline : kInk, width: 1.5),
            boxShadow: d == DireccionSwipe.abajo ? null : inkShadow(2),
          ),
          child: ExcludeSemantics(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(iconoDireccion(d), size: 18, color: color),
                const SizedBox(height: 2),
                FittedBox(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      d == DireccionSwipe.arriba ? 'Amplio' : etiquetaDireccion(d),
                      style: TextStyle(
                        color: d == DireccionSwipe.abajo ? kMuted : kInk,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Feedback extends StatelessWidget {
  final RespuestaGramSwipe respuesta;
  final VoidCallback onContinuar;

  const _Feedback({required this.respuesta, required this.onContinuar});

  @override
  Widget build(BuildContext context) {
    final ok = respuesta.acierto;
    final t = respuesta.tarjeta;
    final detalle = ok
        ? '${t.nombre} es ${etiquetaCobertura[t.cobertura]}. ¡Muy bien!'
        : 'Marcaste «${etiquetaCobertura[respuesta.marcada]}», pero ${t.nombre} es ${etiquetaCobertura[t.cobertura]}.';
    final color = ok ? const Color(0xFF55745A) : const Color(0xFFC97B6E);
    return Positioned.fill(
      child: ColoredBox(
        color: const Color(0x8C171312),
        child: SafeArea(
          child: Align(
            alignment: context.usesTwoPane ? Alignment.center : Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 280),
                  curve: kEaseOut,
                  builder: (_, v, child) => Opacity(
                    opacity: v,
                    child: Transform.translate(offset: Offset(0, 24 * (1 - v)), child: child),
                  ),
                  child: StickerCard(
                    radius: 24,
                    padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(ok ? Icons.check_circle_rounded : Icons.cancel_rounded, color: color, size: 44),
                        const SizedBox(height: 6),
                        Text(
                          ok ? '¡Correcto!' : 'Incorrecto',
                          style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 6),
                        Text(detalle, textAlign: TextAlign.center, style: const TextStyle(color: kMuted, fontSize: 14, height: 1.45)),
                        const SizedBox(height: 18),
                        StickerButton(
                          label: 'Continuar',
                          icon: Icons.arrow_forward_rounded,
                          expand: true,
                          onPressed: onContinuar,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/* ════════════════════════════════════════════════════════════════════════
   Resultado
═══════════════════════════════════════════════════════════════════════════ */

class _Resultado extends StatelessWidget {
  final PartidaGramSwipe partida;
  final VoidCallback onRepetirErrores;
  final VoidCallback onNueva;
  final VoidCallback onInicio;

  const _Resultado({
    required this.partida,
    required this.onRepetirErrores,
    required this.onNueva,
    required this.onInicio,
  });

  @override
  Widget build(BuildContext context) {
    final p = partida;
    final precision = p.precision;
    final colorArco = precision >= 70
        ? _gramPos
        : precision >= 40
            ? _gramNeg
            : const Color(0xFFC97B6E);
    final falladas = p.falladas;

    Widget cifra(int n, String texto, Color color) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: kHairline, width: 1.5),
            ),
            child: Column(
              children: [
                Text('$n', style: TextStyle(color: color, fontSize: 28, fontWeight: FontWeight.w900)),
                Text(texto, style: const TextStyle(color: _noSe, fontSize: 11.5, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        );

    return ListView(
      padding: EdgeInsets.fromLTRB(context.bodyGutter, 16, context.bodyGutter, 32),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  precision == 100
                      ? Icons.emoji_events_rounded
                      : precision >= 70
                          ? Icons.thumb_up_rounded
                          : Icons.school_rounded,
                  size: 46,
                  color: kAccent,
                ),
                const SizedBox(height: 6),
                Text(
                  tituloResultadoGramSwipe(precision),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: kInk, fontSize: 26, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 2),
                Text(
                  '${p.aciertos} de ${p.respondidas.length} correctas · $precision% de precisión',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: kMuted, fontSize: 14),
                ),
                const SizedBox(height: 18),
                Row(children: [
                  cifra(p.aciertos, 'Correctas', _gramPos),
                  const SizedBox(width: 10),
                  cifra(p.fallos, 'Errores', const Color(0xFFC97B6E)),
                  const SizedBox(width: 10),
                  cifra(p.saltadas.length, 'Saltadas', kMuted),
                ]),
                const SizedBox(height: 20),
                Center(
                  child: SizedBox(
                    width: 120,
                    height: 120,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: precision / 100),
                      duration: const Duration(milliseconds: 1000),
                      curve: kEaseOut,
                      builder: (_, v, __) => Stack(
                        fit: StackFit.expand,
                        children: [
                          CircularProgressIndicator(
                            value: v,
                            strokeWidth: 10,
                            strokeCap: StrokeCap.round,
                            backgroundColor: const Color(0xFFF2EFED),
                            color: colorArco,
                          ),
                          Center(
                            child: Text(
                              '${(v * 100).round()}%',
                              style: const TextStyle(color: kInk, fontSize: 24, fontWeight: FontWeight.w900),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (falladas.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  const SectionLabel('Tarjetas falladas'),
                  const SizedBox(height: 10),
                  for (final a in falladas)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: kHairline, width: 1.5),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(a.nombre, style: const TextStyle(color: kInk, fontSize: 14, fontWeight: FontWeight.w700)),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                              decoration: BoxDecoration(
                                color: tinted(colorCobertura(a.cobertura), 0.2),
                                borderRadius: BorderRadius.circular(99),
                              ),
                              child: Text(
                                etiquetaCobertura[a.cobertura]!,
                                style: const TextStyle(color: kInk, fontSize: 11.5, fontWeight: FontWeight.w800),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
                const SizedBox(height: 18),
                if (falladas.isNotEmpty) ...[
                  StickerButton(label: 'Repetir errores', icon: Icons.replay_rounded, expand: true, onPressed: onRepetirErrores),
                  const SizedBox(height: 10),
                ],
                GhostButton(label: 'Nueva sesión', icon: Icons.refresh_rounded, expand: true, onPressed: onNueva),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: onInicio,
                  icon: const Icon(Icons.home_rounded),
                  label: const Text('Inicio'),
                  style: TextButton.styleFrom(foregroundColor: kMuted),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
