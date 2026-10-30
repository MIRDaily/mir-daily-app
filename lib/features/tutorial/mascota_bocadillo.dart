// La mascota y su bocadillo, escribiéndose letra a letra. Puerto de la web:
// src/components/tutorial/MascotBubble.tsx.
//
// - Mientras escribe, cada toque ACELERA (y se puede tocar varias veces); solo con la frase entera
//   el toque pasa al paso siguiente. Que no salte a la frase completa de golpe es lo que separa «voy
//   con prisa» de «no quiero leerlo».
// - El texto completo, invisible, reserva el tamaño final: el bocadillo no crece letra a letra.
// - Con «reducir movimiento» (MediaQuery.disableAnimations) no hay máquina de escribir: sale entero.
// - En el móvil la mascota va ENCIMA del bocadillo (al lado no caben); en tablet, al lado, con el
//   bocadillo a la altura de la cabeza.
// - Sin sonido: la web hace «blips» con WebAudio; aquí acompaña la háptica de la capa al avanzar
//   (ver el resultado de la tanda 8 en el plan).

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/models/tutoriales.dart';
import '../../shared/sticker/sticker.dart';

const Color _kBordeBocadillo = Color(0x4DE8A598); // #E8A598 al 30 %
const Color _kTextoBocadillo = Color(0xFF2D3748);

/// Ancho máximo del globo de texto (el `max-w-sm` de la web).
const double kAnchoGlobo = 384;

double tamanoMascota({required bool enFila}) => enFila ? 150 : 120;

class MascotaBocadillo extends StatefulWidget {
  final String texto;
  final PoseMascota pose;
  final bool mirandoIzquierda;
  final bool enFila;

  /// Cada vez que cambia, el tecleo se acelera.
  final ValueListenable<int>? acelerar;

  /// Se llama una vez, cuando ya está escrito del todo.
  final VoidCallback? onTextoCompleto;

  const MascotaBocadillo({
    super.key,
    required this.texto,
    required this.pose,
    this.mirandoIzquierda = false,
    this.enFila = false,
    this.acelerar,
    this.onTextoCompleto,
  });

  @override
  State<MascotaBocadillo> createState() => _MascotaBocadilloState();
}

class _MascotaBocadilloState extends State<MascotaBocadillo> with SingleTickerProviderStateMixin {
  int _visibles = 0;
  int _retardo = msPorCaracter;
  Timer? _timer;
  bool _avisado = false;
  bool _arrancado = false;
  late final AnimationController _bote =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  bool get _completo => _visibles >= widget.texto.length;

  @override
  void initState() {
    super.initState();
    widget.acelerar?.addListener(_acelerar);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_arrancado) return;
    _arrancado = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _visibles = widget.texto.length;
      WidgetsBinding.instance.addPostFrameCallback((_) => _avisar());
    } else {
      _timer = Timer(Duration(milliseconds: _retardo), _escribir);
    }
  }

  @override
  void didUpdateWidget(MascotaBocadillo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.acelerar != widget.acelerar) {
      oldWidget.acelerar?.removeListener(_acelerar);
      widget.acelerar?.addListener(_acelerar);
    }
  }

  void _escribir() {
    if (!mounted) return;
    setState(() => _visibles++);
    if (_completo) {
      _avisar();
      return;
    }
    _timer = Timer(Duration(milliseconds: _retardo), _escribir);
  }

  void _acelerar() => _retardo = retardoAcelerado(_retardo);

  void _avisar() {
    if (_avisado || !mounted) return;
    _avisado = true;
    if (!MediaQuery.disableAnimationsOf(context)) _bote.repeat(reverse: true);
    setState(() {});
    widget.onTextoCompleto?.call();
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.acelerar?.removeListener(_acelerar);
    _bote.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mascota = _Mascota(
      pose: widget.pose,
      tamano: tamanoMascota(enFila: widget.enFila),
      volteada: widget.mirandoIzquierda,
    );
    final globo = _Globo(
      texto: widget.texto,
      visibles: _visibles.clamp(0, widget.texto.length),
      completo: _completo && _avisado,
      bote: _bote,
      enFila: widget.enFila,
      mirandoIzquierda: widget.mirandoIzquierda,
    );

    return Semantics(
      liveRegion: true,
      label: widget.texto,
      child: ExcludeSemantics(
        child: widget.enFila
            ? Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                textDirection: widget.mirandoIzquierda ? TextDirection.rtl : TextDirection.ltr,
                children: [
                  mascota,
                  const SizedBox(width: 12),
                  Flexible(child: globo),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: widget.mirandoIzquierda ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  mascota,
                  const SizedBox(height: 8),
                  globo,
                ],
              ),
      ),
    );
  }
}

class _Mascota extends StatelessWidget {
  final PoseMascota pose;
  final double tamano;
  final bool volteada;

  const _Mascota({required this.pose, required this.tamano, required this.volteada});

  @override
  Widget build(BuildContext context) {
    final imagen = Image.asset(
      pose.asset,
      width: tamano,
      height: tamano,
      fit: BoxFit.contain,
      // Si faltara el PNG queda el bocadillo solo, que se lee igual.
      errorBuilder: (_, __, ___) => SizedBox(width: tamano, height: tamano),
    );
    final mascota = volteada
        ? Transform.flip(flipX: true, child: imagen)
        : imagen;
    if (MediaQuery.disableAnimationsOf(context)) return mascota;
    // La entrada con rebote de la web (muelle de framer): sube 8 px y aparece.
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 420),
      curve: const Cubic(0.34, 1.56, 0.64, 1),
      builder: (_, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.translate(offset: Offset(0, 8 * (1 - t)), child: child),
      ),
      child: mascota,
    );
  }
}

class _Globo extends StatelessWidget {
  final String texto;
  final int visibles;
  final bool completo;
  final Animation<double> bote;
  final bool enFila;
  final bool mirandoIzquierda;

  const _Globo({
    required this.texto,
    required this.visibles,
    required this.completo,
    required this.bote,
    required this.enFila,
    required this.mirandoIzquierda,
  });

  static const _estilo = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w500,
    height: 1.6,
    color: _kTextoBocadillo,
  );

  @override
  Widget build(BuildContext context) {
    // El pico apunta a la cabeza: en columna sale por arriba, alineado con el centro de la mascota;
    // en fila, por el lado, a la altura de la cabeza (≈ un tercio del alto del PNG).
    final mascota = tamanoMascota(enFila: enFila);
    final pico = enFila
        ? Positioned(
            top: mascota * 0.31 - _Pico.largo / 2,
            left: mirandoIzquierda ? null : 1 - _Pico.alto,
            right: mirandoIzquierda ? 1 - _Pico.alto : null,
            child: _Pico(lado: mirandoIzquierda ? AxisDirection.right : AxisDirection.left),
          )
        : Positioned(
            top: 1 - _Pico.alto,
            left: mirandoIzquierda ? null : mascota / 2 - _Pico.largo / 2,
            right: mirandoIzquierda ? mascota / 2 - _Pico.largo / 2 : null,
            child: const _Pico(lado: AxisDirection.up),
          );

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: kAnchoGlobo),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: _kBordeBocadillo),
              boxShadow: const [
                BoxShadow(color: Color(0x387D8A96), blurRadius: 40, offset: Offset(0, 18)),
              ],
            ),
            // Dos capas: el texto completo invisible reserva el tamaño final y el escrito va encima.
            child: Stack(
              children: [
                Opacity(opacity: 0, child: Text(texto, style: _estilo)),
                Text(texto.substring(0, visibles), style: _estilo),
              ],
            ),
          ),
          pico,
          // La señal de «ya puedes seguir»: sin ella no se sabe cuándo el toque pasa de página.
          if (completo)
            Positioned(
              right: -8,
              bottom: -8,
              child: AnimatedBuilder(
                animation: bote,
                builder: (_, child) => Transform.translate(offset: Offset(0, 2 * bote.value), child: child),
                child: Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0x66E8A598)),
                    boxShadow: const [BoxShadow(color: Color(0x1A000000), blurRadius: 3, offset: Offset(0, 1))],
                  ),
                  child: const Icon(Icons.play_arrow_rounded, size: 14, color: kAccent),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// El pico del bocadillo: un triángulo blanco con el borde solo en sus dos lados de fuera. Su base
/// entra 1 px en el globo, así tapa el trozo de borde por donde sale (como el cuadrado girado de la web).
class _Pico extends StatelessWidget {
  final AxisDirection lado;
  const _Pico({required this.lado});

  static const double largo = 14;
  static const double alto = 8;

  @override
  Widget build(BuildContext context) {
    final vertical = lado == AxisDirection.up || lado == AxisDirection.down;
    return CustomPaint(
      size: vertical ? const Size(largo, alto) : const Size(alto, largo),
      painter: _PicoPainter(lado),
    );
  }
}

class _PicoPainter extends CustomPainter {
  final AxisDirection lado;
  _PicoPainter(this.lado);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final (Offset a, Offset punta, Offset b) = switch (lado) {
      AxisDirection.up => (Offset(0, h), Offset(w / 2, 0), Offset(w, h)),
      AxisDirection.down => (Offset.zero, Offset(w / 2, h), Offset(w, 0)),
      AxisDirection.left => (Offset(w, 0), Offset(0, h / 2), Offset(w, h)),
      AxisDirection.right => (Offset.zero, Offset(w, h / 2), Offset(0, h)),
    };
    final relleno = Path()
      ..moveTo(a.dx, a.dy)
      ..lineTo(punta.dx, punta.dy)
      ..lineTo(b.dx, b.dy)
      ..close();
    canvas.drawPath(relleno, Paint()..color = Colors.white);
    final borde = Path()
      ..moveTo(a.dx, a.dy)
      ..lineTo(punta.dx, punta.dy)
      ..lineTo(b.dx, b.dy);
    canvas.drawPath(
      borde,
      Paint()
        ..color = _kBordeBocadillo
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_PicoPainter old) => old.lado != lado;
}
