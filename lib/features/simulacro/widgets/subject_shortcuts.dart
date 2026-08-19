import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/sticker/sticker.dart';

/// Atajos para elegir asignaturas de golpe.
///
/// Antes eran pastillas con texto, exactamente igual que las asignaturas de
/// debajo: parecían dos asignaturas más y se perdían entre veinte. Ahora son
/// **botones cuadrados con un icono animado** —otra forma, otro peso— y lo que
/// hace cada uno se cuenta en un cartel que aparece al pulsarlo y se va solo.
enum SubjectShortcut { todas, aleatorias, mir, quitar }

extension SubjectShortcutInfo on SubjectShortcut {
  /// Lo que se cuenta en el cartel al elegirlo.
  String get hint => switch (this) {
        SubjectShortcut.todas => 'Todas las asignaturas, a partes iguales.',
        SubjectShortcut.aleatorias =>
          'Unas pocas asignaturas al azar, para salir del bloqueo de elegir.',
        SubjectShortcut.mir =>
          'Todas, pero repartidas como caen en el MIR de verdad: '
              'más de Digestivo, menos de Oftalmología.',
        SubjectShortcut.quitar => 'Sin ninguna asignatura elegida.',
      };

  String get label => switch (this) {
        SubjectShortcut.todas => 'Todas',
        SubjectShortcut.aleatorias => 'Aleatorias',
        SubjectShortcut.mir => 'MIR',
        SubjectShortcut.quitar => 'Quitar',
      };
}

/// Fila de atajos + el cartel que explica el último pulsado.
class SubjectShortcutBar extends StatefulWidget {
  /// Cuál está en vigor, o null si la selección se ha tocado a mano.
  ///
  /// Es uno solo: los tres atajos son formas distintas de rehacer la
  /// selección entera, así que no pueden estar dos a la vez.
  final SubjectShortcut? active;
  final bool canClear;
  final void Function(SubjectShortcut) onPick;

  const SubjectShortcutBar({
    super.key,
    required this.active,
    required this.canClear,
    required this.onPick,
  });

  @override
  State<SubjectShortcutBar> createState() => _SubjectShortcutBarState();
}

class _SubjectShortcutBarState extends State<SubjectShortcutBar> {
  SubjectShortcut? _hint;

  /// El temporizador que retira el cartel. Se guarda para poder cancelarlo:
  /// un `Future.delayed` suelto sigue vivo aunque el widget ya no esté, y en
  /// un test eso aparece como "A Timer is still pending".
  Timer? _hideHint;

  @override
  void dispose() {
    _hideHint?.cancel();
    super.dispose();
  }

  void _pick(SubjectShortcut s) {
    HapticFeedback.selectionClick();
    widget.onPick(s);
    setState(() => _hint = s);
    // El cartel se va solo: es una ayuda, no un estado que haya que cerrar.
    _hideHint?.cancel();
    _hideHint = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _hint = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _ShortcutButton(
              kind: SubjectShortcut.todas,
              active: widget.active == SubjectShortcut.todas,
              onTap: () => _pick(SubjectShortcut.todas),
            ),
            const SizedBox(width: 10),
            _ShortcutButton(
              kind: SubjectShortcut.aleatorias,
              active: widget.active == SubjectShortcut.aleatorias,
              onTap: () => _pick(SubjectShortcut.aleatorias),
            ),
            const SizedBox(width: 10),
            _ShortcutButton(
              kind: SubjectShortcut.mir,
              active: widget.active == SubjectShortcut.mir,
              onTap: () => _pick(SubjectShortcut.mir),
            ),
            if (widget.canClear) ...[
              const SizedBox(width: 10),
              _ShortcutButton(
                kind: SubjectShortcut.quitar,
                onTap: () => _pick(SubjectShortcut.quitar),
              ),
            ],
          ],
        ),
        // El hueco no se reserva: sin cartel, las asignaturas suben.
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: kEaseOut,
          alignment: Alignment.topLeft,
          child: _hint == null
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: _HintCard(
                    key: ValueKey(_hint),
                    shortcut: _hint!,
                  ),
                ),
        ),
      ],
    );
  }
}

/// Botón cuadrado con icono animado. La forma ya lo separa de las pastillas.
class _ShortcutButton extends StatefulWidget {
  final SubjectShortcut kind;
  final bool active;
  final VoidCallback onTap;

  const _ShortcutButton({
    required this.kind,
    required this.onTap,
    this.active = false,
  });

  @override
  State<_ShortcutButton> createState() => _ShortcutButtonState();
}

class _ShortcutButtonState extends State<_ShortcutButton>
    with SingleTickerProviderStateMixin {

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: switch (widget.kind) {
      SubjectShortcut.todas => const Duration(milliseconds: 2800),
      SubjectShortcut.aleatorias => const Duration(milliseconds: 2200),
      SubjectShortcut.mir => const Duration(milliseconds: 3400),
      SubjectShortcut.quitar => const Duration(milliseconds: 2600),
    },
  )..repeat();

  bool _down = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final on = widget.active;
    final fg = on ? AppColors.primaryDark : kMuted;

    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTap: () {
        setState(() => _down = false);
        widget.onTap();
      },
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 90),
            transform: Matrix4.translationValues(
                _down ? 3 : 0, _down ? 3 : 0, 0),
            height: 48,
            width: 48,
            decoration: BoxDecoration(
              color: on ? tinted(AppColors.primary, 0.24) : Colors.white,
              // Cuadrado de esquinas suaves, no pastilla: la forma es lo que
              // dice de un vistazo que esto no es una asignatura.
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: on ? kInk : kHairline, width: 2),
              boxShadow: _down ? const [] : inkShadow(3),
            ),
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, _) => CustomPaint(
                  painter: _ShortcutIconPainter(
                    kind: widget.kind,
                    t: _c.value,
                    color: fg,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            widget.kind.label,
            style: TextStyle(
              color: fg,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// Los cuatro iconos, dibujados y animados a mano.
class _ShortcutIconPainter extends CustomPainter {
  final SubjectShortcut kind;
  final double t;
  final Color color;

  const _ShortcutIconPainter({
    required this.kind,
    required this.t,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    switch (kind) {
      case SubjectShortcut.todas:
        _todas(canvas, s);
      case SubjectShortcut.aleatorias:
        _aleatorias(canvas, s);
      case SubjectShortcut.mir:
        _mir(canvas, s);
      case SubjectShortcut.quitar:
        _quitar(canvas, s);
    }
    canvas.restore();
  }

  Paint get _stroke => Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..color = color;

  /// Tres renglones a los que les va cayendo el visto, uno detrás de otro.
  void _todas(Canvas canvas, double s) {
    final line = _stroke..strokeWidth = s * 0.055;
    for (var i = 0; i < 3; i++) {
      final y = (i - 1) * s * 0.20;
      canvas.drawLine(
        Offset(-s * 0.26, y),
        Offset(s * 0.04, y),
        line..color = color.withOpacity(0.45),
      );

      // Cada visto entra un tercio de ciclo después que el anterior.
      final local = ((t - i * 0.22) % 1.0).clamp(0.0, 1.0);
      final grow = local < 0.18 ? local / 0.18 : (local < 0.80 ? 1.0 : 0.0);
      if (grow <= 0) continue;

      final tick = Path()
        ..moveTo(s * 0.13, y)
        ..lineTo(s * 0.19, y + s * 0.06)
        ..lineTo(s * 0.30, y - s * 0.08);
      canvas.drawPath(
        _trim(tick, grow),
        _stroke
          ..strokeWidth = s * 0.075
          ..color = color,
      );
    }
  }

  /// Un dado que da un saltito y cambia de cara.
  void _aleatorias(Canvas canvas, double s) {
    // Tres fases por ciclo: reposo, salto y caída con cara nueva.
    final hop = math.sin(t * math.pi * 2).clamp(-1.0, 1.0);
    final lift = -hop.abs() * s * 0.09;
    final spin = hop * 0.22;

    canvas.save();
    canvas.translate(0, lift);
    canvas.rotate(spin);

    final r = s * 0.21;
    final body = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: r * 2, height: r * 2),
      Radius.circular(s * 0.06),
    );
    canvas.drawRRect(body, _stroke..strokeWidth = s * 0.065);

    // La cara cambia en cada mitad del ciclo: 3 puntos y 5 puntos.
    final pip = Paint()..color = color;
    final rr = r * 0.52;
    if (t < 0.5) {
      for (final p in [const Offset(-1, -1), Offset.zero, const Offset(1, 1)]) {
        canvas.drawCircle(Offset(p.dx * rr, p.dy * rr), s * 0.035, pip);
      }
    } else {
      for (final p in [
        const Offset(-1, -1),
        const Offset(1, -1),
        Offset.zero,
        const Offset(-1, 1),
        const Offset(1, 1),
      ]) {
        canvas.drawCircle(Offset(p.dx * rr, p.dy * rr), s * 0.032, pip);
      }
    }
    canvas.restore();
  }

  /// Una balanza que se inclina: los platillos pesan distinto, que es
  /// exactamente lo que hace el reparto MIR.
  void _mir(Canvas canvas, double s) {
    final tilt = math.sin(t * math.pi * 2) * 0.20;
    final stroke = _stroke..strokeWidth = s * 0.06;

    // Mástil y base.
    canvas.drawLine(Offset(0, -s * 0.26), Offset(0, s * 0.24), stroke);
    canvas.drawLine(
        Offset(-s * 0.14, s * 0.24), Offset(s * 0.14, s * 0.24), stroke);

    canvas.save();
    canvas.translate(0, -s * 0.24);
    canvas.rotate(tilt);
    canvas.drawLine(Offset(-s * 0.26, 0), Offset(s * 0.26, 0), stroke);

    // Los platillos, colgando siempre rectos aunque el brazo se incline.
    for (final side in [-1.0, 1.0]) {
      final x = side * s * 0.26;
      canvas.save();
      canvas.translate(x, 0);
      canvas.rotate(-tilt);
      canvas.drawLine(Offset.zero, Offset(0, s * 0.10), stroke);
      // El de la izquierda es mayor: pesa más, como Digestivo.
      final w = side < 0 ? s * 0.13 : s * 0.09;
      canvas.drawArc(
        Rect.fromCenter(
            center: Offset(0, s * 0.10), width: w * 2, height: w * 1.5),
        0,
        math.pi,
        false,
        stroke,
      );
      canvas.restore();
    }
    canvas.restore();
  }

  /// Un aspa que se sacude de vez en cuando.
  void _quitar(Canvas canvas, double s) {
    // Solo se menea en el último tramo del ciclo; el resto está quieta.
    final shake = t > 0.82 ? math.sin((t - 0.82) / 0.18 * math.pi * 3) * 0.14 : 0.0;
    canvas.save();
    canvas.rotate(shake);
    final stroke = _stroke..strokeWidth = s * 0.075;
    final d = s * 0.16;
    canvas.drawLine(Offset(-d, -d), Offset(d, d), stroke);
    canvas.drawLine(Offset(d, -d), Offset(-d, d), stroke);
    canvas.restore();
  }

  /// Recorta un trazo al [amount] inicial de su longitud, para dibujarlo
  /// "escribiéndose" en vez de aparecer entero.
  Path _trim(Path path, double amount) {
    if (amount >= 1) return path;
    final out = Path();
    for (final metric in path.computeMetrics()) {
      out.addPath(
        metric.extractPath(0, metric.length * amount.clamp(0.0, 1.0)),
        Offset.zero,
      );
    }
    return out;
  }

  @override
  bool shouldRepaint(_ShortcutIconPainter old) =>
      old.t != t || old.color != color || old.kind != kind;
}

/// El cartel que explica el atajo recién pulsado.
class _HintCard extends StatelessWidget {
  final SubjectShortcut shortcut;

  const _HintCard({super.key, required this.shortcut});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 240),
      curve: kEaseOut,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, 8 * (1 - v)), child: child),
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: tinted(AppColors.primary, 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kHairline, width: 2),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.lightbulb_outline_rounded,
                size: 15, color: AppColors.primaryDark),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                shortcut.hint,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  height: 1.35,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
