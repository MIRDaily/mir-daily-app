import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/sticker/sticker.dart';

/// Deslizador del número de preguntas, con el muelle de la web.
///
/// El `Slider` de Material salta de golpe al cambiar el valor desde fuera, y
/// aquí eso pasa constantemente: los atajos (10, 25, 50…) mueven el mando de
/// una punta a otra. Con muelle, el salto se lee — y de paso se ve hacia dónde
/// ha ido. Los parámetros son los mismos que el `useSpring` de la web
/// (rigidez 210, amortiguación 18, masa 0,85).
class CountSlider extends StatefulWidget {
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  const CountSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 1,
    this.max = 210,
  });

  @override
  State<CountSlider> createState() => _CountSliderState();
}

class _CountSliderState extends State<CountSlider>
    with SingleTickerProviderStateMixin {
  static const _spring = SpringDescription(
    mass: 0.85,
    stiffness: 210,
    damping: 18,
  );

  /// Alto del carril y radio del mando; el segundo manda en el padding.
  static const _track = 8.0;
  static const _thumb = 13.0;

  late final AnimationController _ctrl = AnimationController.unbounded(
    vsync: this,
    value: _fractionOf(widget.value),
  )..addListener(() => setState(() {}));

  /// Mientras se arrastra, el mando sigue al dedo sin muelle: rebotar debajo
  /// del dedo se siente como si el control fuera impreciso.
  bool _dragging = false;

  double _fractionOf(int v) =>
      (v - widget.min) / (widget.max - widget.min);

  @override
  void didUpdateWidget(covariant CountSlider old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value && !_dragging) {
      _ctrl.animateWith(
        SpringSimulation(_spring, _ctrl.value, _fractionOf(widget.value), 0),
      );
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _setFromLocal(double dx, double width) {
    final usable = width - _thumb * 2;
    if (usable <= 0) return;
    final f = ((dx - _thumb) / usable).clamp(0.0, 1.0);
    final v = (widget.min + f * (widget.max - widget.min)).round();
    _ctrl.value = f;
    if (v != widget.value) {
      HapticFeedback.selectionClick();
      widget.onChanged(v);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (d) {
            _dragging = true;
            _setFromLocal(d.localPosition.dx, width);
          },
          onHorizontalDragUpdate: (d) =>
              _setFromLocal(d.localPosition.dx, width),
          onHorizontalDragEnd: (_) => _dragging = false,
          onTapDown: (d) => _setFromLocal(d.localPosition.dx, width),
          child: SizedBox(
            height: _thumb * 2 + 8,
            width: width,
            child: CustomPaint(
              painter: _CountSliderPainter(
                // El muelle se pasa un poco de largo a propósito; se deja
                // salir solo lo que cabe en el hueco del mando, para que el
                // rebote se vea también en los extremos sin escaparse.
                fraction: _ctrl.value.clamp(-0.04, 1.04),
                track: _track,
                thumb: _thumb,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CountSliderPainter extends CustomPainter {
  final double fraction;
  final double track;
  final double thumb;

  const _CountSliderPainter({
    required this.fraction,
    required this.track,
    required this.thumb,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height / 2;
    final left = thumb;
    final right = size.width - thumb;
    final usable = right - left;
    if (usable <= 0) return;

    final rail = Rect.fromLTRB(left, cy - track / 2, right, cy + track / 2);
    final radius = Radius.circular(track);

    // Carril apagado.
    canvas.drawRRect(
      RRect.fromRectAndRadius(rail, radius),
      Paint()..color = AppColors.surfaceVariant,
    );

    // Tramo recorrido, recortado al carril aunque el muelle se pase.
    final filledTo = left + usable * fraction.clamp(0.0, 1.0);
    if (filledTo > left) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(left, rail.top, filledTo, rail.bottom),
          radius,
        ),
        Paint()..color = AppColors.primary,
      );
    }

    // El trazo del carril va por encima de los dos rellenos.
    canvas.drawRRect(
      RRect.fromRectAndRadius(rail, radius),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = kInk,
    );

    // El mando sí puede salirse un pelo: ahí es donde se ve el rebote.
    final cx = left + usable * fraction;
    canvas.drawCircle(Offset(cx + 2, cy + 2), thumb, Paint()..color = kInk);
    canvas.drawCircle(Offset(cx, cy), thumb, Paint()..color = Colors.white);
    canvas.drawCircle(
      Offset(cx, cy),
      thumb,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = kInk,
    );
    canvas.drawCircle(
        Offset(cx, cy), thumb * 0.30, Paint()..color = AppColors.primary);
  }

  @override
  bool shouldRepaint(_CountSliderPainter old) => old.fraction != fraction;
}
