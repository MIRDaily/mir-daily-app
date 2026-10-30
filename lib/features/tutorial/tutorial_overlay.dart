// La capa del tutorial. Puerto de la web: src/components/tutorial/TutorialOverlay.tsx y
// useAnchorRect.ts.
//
// Se monta por encima de TODA la app, junto a la celebración de logros (ver main.dart), y solo pinta
// algo con un tutorial en curso. Sin él no intercepta el dedo.
//
// - El foco es UN velo con un hueco redondeado sobre el ancla (y un anillo coral), no cuatro trozos.
// - Toda la capa avanza al tocarla: obligar a acertar un botón pequeño cuando la persona todavía no
//   sabe dónde está nada es lo contrario de un tutorial. Mientras escribe, el toque acelera.
// - «Saltar», siempre visible y siempre en el mismo sitio, con los puntos del avance.
// - El ancla se sigue midiendo un rato tras cada paso (las tarjetas entran con su animación y el
//   scroll hasta ella tarda): con una sola medida el foco se quedaba donde estaba a medio entrar.
// - No hay maqueta animada de los modos (PreviewModo.tsx): la web solo la pinta con hueco de sobra a
//   un lado del foco, y en el móvil nunca lo hay.

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

import '../../core/models/tutoriales.dart';
import '../../core/services/haptics_service.dart';
import '../../shared/sticker/sticker.dart';
import 'mascota_bocadillo.dart';
import 'tutoriales_controller.dart';

const double _kMargenFoco = 10;
const Color _kVelo = Color(0x8C2C3E50); // tinta al 55 %

class TutorialOverlay extends StatelessWidget {
  const TutorialOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<Tutoriales?>();
    final paso = ctrl?.pasoActual;
    if (ctrl == null || paso == null) return const IgnorePointer(child: SizedBox.shrink());
    return _CapaTutorial(ctrl: ctrl, paso: paso);
  }
}

class _CapaTutorial extends StatefulWidget {
  final Tutoriales ctrl;
  final PasoTutorial paso;

  const _CapaTutorial({required this.ctrl, required this.paso});

  @override
  State<_CapaTutorial> createState() => _CapaTutorialState();
}

class _CapaTutorialState extends State<_CapaTutorial> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  /// Cuánto se sigue midiendo el ancla tras cada paso: scroll (~0,4 s) + entrada de una tarjeta.
  static const _asentar = Duration(milliseconds: 1500);

  late final Ticker _medidor = createTicker(_alMedir);
  final ValueNotifier<int> _acelerar = ValueNotifier(0);
  Rect? _foco;
  String _pasoActual = '';
  bool _textoCompleto = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _empezarPaso();
  }

  @override
  void didUpdateWidget(_CapaTutorial oldWidget) {
    super.didUpdateWidget(oldWidget);
    _empezarPaso();
  }

  String get _clavePaso => '${widget.ctrl.enCurso}#${widget.ctrl.indice}';

  void _empezarPaso() {
    final clave = _clavePaso;
    if (clave == _pasoActual) return;
    final primero = _pasoActual.isEmpty || !_pasoActual.startsWith('${widget.ctrl.enCurso}#');
    _pasoActual = clave;
    _textoCompleto = false;
    if (!primero) HapticsService.light();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || clave != _pasoActual) return;
      _llevarALaVista();
      _medirUnRato();
    });
  }

  @override
  void didChangeMetrics() {
    // Al girar el aparato (o abrir el teclado) el ancla se mueve: se vuelve a seguir.
    if (mounted) _medirUnRato();
  }

  void _medirUnRato() {
    _remedir();
    if (_medidor.isActive) _medidor.stop();
    _medidor.start();
  }

  void _alMedir(Duration transcurrido) {
    _remedir();
    if (transcurrido >= _asentar) _medidor.stop();
  }

  Iterable<RenderBox> _cajasAncla() sync* {
    final ancla = widget.paso.anclaEfectiva;
    if (ancla == null) return;
    for (final k in widget.ctrl.anclas(ancla)) {
      final ro = k.currentContext?.findRenderObject();
      if (ro is RenderBox && ro.attached && ro.hasSize) yield ro;
    }
  }

  /// El rectángulo del ancla en las coordenadas de esta capa, recortado a la pantalla. null si no hay
  /// ancla, no está montada o está fuera (p. ej. en una pestaña vecina del PageView).
  Rect? _medir() {
    final yo = context.findRenderObject();
    if (yo is! RenderBox || !yo.hasSize) return null;
    final rects = <Rect>[];
    for (final caja in _cajasAncla()) {
      try {
        rects.add(MatrixUtils.transformRect(caja.getTransformTo(yo), Offset.zero & caja.size));
      } catch (_) {
        // Una caja de otro árbol (no debería pasar): se ignora.
      }
    }
    final u = unirRectangulos(rects);
    final pantalla = Offset.zero & yo.size;
    if (u == null || !u.overlaps(pantalla)) return null;
    return u.intersect(pantalla);
  }

  void _remedir() {
    if (!mounted) return;
    final r = _medir();
    final previo = _foco;
    final igual = r == null
        ? previo == null
        : previo != null &&
            (r.left - previo.left).abs() < 0.5 &&
            (r.top - previo.top).abs() < 0.5 &&
            (r.width - previo.width).abs() < 0.5 &&
            (r.height - previo.height).abs() < 0.5;
    if (!igual) setState(() => _foco = r);
  }

  /// Centra el ancla en su lista, si está dentro de una.
  void _llevarALaVista() {
    final cajas = _cajasAncla().toList();
    if (cajas.isEmpty) return;
    final ancla = widget.paso.anclaEfectiva!;
    final ctx = widget.ctrl.anclas(ancla).first.currentContext;
    if (ctx == null || !ctx.mounted) return;
    final reducido = MediaQuery.disableAnimationsOf(context);
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.5,
      duration: reducido ? Duration.zero : const Duration(milliseconds: 420),
      curve: kEaseOut,
    );
  }

  void _tocar() {
    if (!_textoCompleto) {
      _acelerar.value++;
      return;
    }
    widget.ctrl.avanzar();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _medidor.dispose();
    _acelerar.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final reducido = mq.disableAnimations;
    final enFila = bocadilloEnFila(mq.size.width);
    final foco = _foco;
    final altoBarra = 72 + mq.padding.bottom;
    final mirandoIzquierda = mascotaMiraIzquierda(foco, mq.size.width);
    final paso = widget.paso;
    final ctrl = widget.ctrl;

    final bocadillo = MascotaBocadillo(
      key: ValueKey(_pasoActual),
      texto: paso.texto,
      pose: paso.pose,
      enFila: enFila,
      mirandoIzquierda: mirandoIzquierda,
      acelerar: _acelerar,
      onTextoCompleto: () {
        if (mounted) setState(() => _textoCompleto = true);
      },
    );

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // El velo, con el hueco del foco (que se desliza de un ancla a la siguiente).
          Positioned.fill(
            // Sin foco el hueco es `Rect.zero` (TweenAnimationBuilder no admite un final nulo).
            child: TweenAnimationBuilder<Rect>(
              tween: _TweenFoco(end: foco?.inflate(_kMargenFoco) ?? Rect.zero),
              duration: reducido ? Duration.zero : const Duration(milliseconds: 320),
              curve: kEaseOut,
              builder: (_, r, __) => CustomPaint(painter: _VeloPainter(r)),
            ),
          ),
          // Toda la capa avanza al tocarla.
          Positioned.fill(
            child: Semantics(
              button: true,
              label: _textoCompleto ? 'Siguiente' : 'Escribir más rápido',
              child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: _tocar),
            ),
          ),
          // El bocadillo, colocado con su tamaño real.
          Positioned.fill(
            child: IgnorePointer(
              child: Padding(
                padding: EdgeInsets.only(top: mq.padding.top),
                child: CustomSingleChildLayout(
                  delegate: _ColocaBocadillo(
                    foco: foco?.translate(0, -mq.padding.top),
                    altoBarra: altoBarra,
                    anchoMax: enFila
                        ? tamanoMascota(enFila: true) + 12 + kAnchoGlobo
                        : (mq.size.width - 32).clamp(0, kAnchoGlobo + 0.0),
                  ),
                  child: AnimatedSwitcher(
                    duration: reducido ? Duration.zero : const Duration(milliseconds: 250),
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: SlideTransition(
                        position: Tween(begin: const Offset(0, 0.04), end: Offset.zero).animate(anim),
                        child: child,
                      ),
                    ),
                    layoutBuilder: (actual, previos) => Stack(
                      alignment: Alignment.topLeft,
                      children: [...previos, if (actual != null) actual],
                    ),
                    child: bocadillo,
                  ),
                ),
              ),
            ),
          ),
          // Los puntos y «Saltar».
          Positioned(
            left: 0,
            right: 0,
            bottom: 24 + mq.padding.bottom,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < ctrl.total; i++)
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i == ctrl.indice ? Colors.white : Colors.white.withValues(alpha: 0.4),
                    ),
                  ),
                const SizedBox(width: 13),
                Material(
                  color: Colors.white.withValues(alpha: 0.15),
                  shape: const StadiumBorder(),
                  child: InkWell(
                    customBorder: const StadiumBorder(),
                    onTap: ctrl.saltar,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                      child: Text(
                        'Saltar',
                        style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Del velo entero a un hueco (o al revés) no se anima desde un punto: se salta.
class _TweenFoco extends Tween<Rect> {
  _TweenFoco({super.end});

  @override
  Rect lerp(double t) {
    final b = begin, e = end!;
    if (b == null || b.isEmpty || e.isEmpty) return e;
    return Rect.lerp(b, e, t)!;
  }
}

class _VeloPainter extends CustomPainter {
  final Rect? hueco;
  _VeloPainter(this.hueco);

  @override
  void paint(Canvas canvas, Size size) {
    final todo = Offset.zero & size;
    final velo = Paint()..color = _kVelo;
    final h = hueco;
    if (h == null || h.isEmpty) {
      canvas.drawRect(todo, velo);
      return;
    }
    final rr = RRect.fromRectAndRadius(h, const Radius.circular(16));
    canvas.drawPath(
      Path.combine(PathOperation.difference, Path()..addRect(todo), Path()..addRRect(rr)),
      velo,
    );
    canvas.drawRRect(
      rr,
      Paint()
        ..color = kAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_VeloPainter old) => old.hueco != hueco;
}

class _ColocaBocadillo extends SingleChildLayoutDelegate {
  final Rect? foco;
  final double altoBarra;
  final double anchoMax;

  _ColocaBocadillo({required this.foco, required this.altoBarra, required this.anchoMax});

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(maxWidth: anchoMax, maxHeight: constraints.maxHeight);

  @override
  Offset getPositionForChild(Size size, Size childSize) => colocarBocadillo(
        pantalla: size,
        bocadillo: childSize,
        foco: foco?.inflate(_kMargenFoco),
        altoBarra: altoBarra,
      );

  @override
  bool shouldRelayout(_ColocaBocadillo old) =>
      old.foco != foco || old.altoBarra != altoBarra || old.anchoMax != anchoMax;
}
