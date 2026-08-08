import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Paleta del Panel (idéntica a la de la web MIRDaily).
class PanelColors {
  static const Color correct = Color(0xFF8BA888);
  static const Color wrong = Color(0xFFC4655A);
  static const Color blank = Color(0xFF7D8A96);
  static const Color accent = Color(0xFFE8A598);
  static const Color gold = Color(0xFFD7B977);
  static const Color ink = Color(0xFF141514);
  static const Color soft = Color(0xFFFAF7F4);
  static const Color border = Color(0xFFEAE0D5);
  static const Color track = Color(0xFFF0EAE6);
  static const Color muted = Color(0xFF7D8A96);
}

// ===========================================================================
// ESCALA DE CALOR POR % DE ACIERTO (portada de charts.tsx)
//   < 65: gradiente continuo rojo -> azul grisáceo -> verde.
//   >= 65: morado galáctico pleno (color fijo).
// ===========================================================================
const double kGalacticMin = 65;
const List<int> _galacticPurple = [126, 72, 184];

const List<(double, List<int>)> _heatStops = [
  (0, [150, 44, 38]),
  (22, [196, 101, 90]),
  (38, [125, 138, 150]),
  (52, [139, 168, 136]),
  (64, [70, 120, 70]),
];

double _lerp(double a, double b, double t) => a + (b - a) * t;

List<int> _heatRgb(double acc) {
  final a = acc.clamp(0, 100).toDouble();
  if (a >= kGalacticMin) return _galacticPurple;
  for (var i = 0; i < _heatStops.length - 1; i++) {
    final (x0, c0) = _heatStops[i];
    final (x1, c1) = _heatStops[i + 1];
    if (a <= x1) {
      final t = (a - x0) / ((x1 - x0) == 0 ? 1 : (x1 - x0));
      return [
        _lerp(c0[0].toDouble(), c1[0].toDouble(), t).round(),
        _lerp(c0[1].toDouble(), c1[1].toDouble(), t).round(),
        _lerp(c0[2].toDouble(), c1[2].toDouble(), t).round(),
      ];
    }
  }
  return _heatStops.last.$2;
}

/// Color de calor para un % de acierto (null = gris "sin datos").
Color heatColor(double? accuracy) {
  if (accuracy == null) return const Color(0xFFCFC5BB);
  final rgb = _heatRgb(accuracy);
  return Color.fromARGB(255, rgb[0], rgb[1], rgb[2]);
}

/// Variante oscurecida para gradientes de las tarjetas.
Color heatColorDark(double? accuracy, [double amount = 0.82]) {
  if (accuracy == null) return const Color(0xFFB2A89E);
  final rgb = _heatRgb(accuracy);
  return Color.fromARGB(
    255,
    (rgb[0] * amount).round(),
    (rgb[1] * amount).round(),
    (rgb[2] * amount).round(),
  );
}

// ===========================================================================
// BARRA APILADA HORIZONTAL (aciertos / fallos / blancos), animada
// ===========================================================================
class StackedBar extends StatelessWidget {
  final int correct;
  final int wrong;
  final int blank;
  final double height;

  const StackedBar({
    super.key,
    required this.correct,
    required this.wrong,
    required this.blank,
    this.height = 10,
  });

  @override
  Widget build(BuildContext context) {
    final total = (correct + wrong + blank).toDouble();
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            Widget seg(int n, Color c) => Container(
                  width: total == 0 ? 0 : (n / total) * w,
                  color: c,
                );
            return TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (context, t, child) => Stack(
                children: [
                  Container(color: PanelColors.track),
                  ClipRect(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      widthFactor: t,
                      child: Row(
                        children: [
                          seg(correct, PanelColors.correct),
                          seg(wrong, PanelColors.wrong),
                          seg(blank, PanelColors.blank),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// ===========================================================================
// ANILLO DE PRECISIÓN (gauge circular animado)
// ===========================================================================
class AccuracyRing extends StatelessWidget {
  final double? accuracy;
  final double size;
  final double stroke;

  const AccuracyRing({
    super.key,
    required this.accuracy,
    this.size = 108,
    this.stroke = 10,
  });

  @override
  Widget build(BuildContext context) {
    final color = heatColor(accuracy);
    final pct = (accuracy ?? 0).clamp(0, 100).toDouble();
    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: pct),
        duration: const Duration(milliseconds: 1100),
        curve: Curves.easeOutCubic,
        builder: (context, value, child) => CustomPaint(
          painter: _RingPainter(value: value, color: color, stroke: stroke),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  accuracy == null ? '--' : '${value.round()}%',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: PanelColors.ink,
                  ),
                ),
                const Text(
                  'ACIERTOS',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                    color: PanelColors.muted,
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

class _RingPainter extends CustomPainter {
  final double value; // 0..100
  final Color color;
  final double stroke;

  _RingPainter({required this.value, required this.color, required this.stroke});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.width - stroke) / 2;
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = PanelColors.track;
    canvas.drawCircle(center, radius, track);

    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;
    final sweep = (value / 100) * 2 * math.pi;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      sweep,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.color != color;
}

// ===========================================================================
// GRÁFICA DE PROGRESO GLOBAL (score + tiempo medio, doble eje), animada
// ===========================================================================
class ProgressLineChart extends StatefulWidget {
  final List<ProgressPoint> points;
  final double? avgScore;
  final double height;

  const ProgressLineChart({
    super.key,
    required this.points,
    this.avgScore,
    this.height = 220,
  });

  @override
  State<ProgressLineChart> createState() => _ProgressLineChartState();
}

class ProgressPoint {
  final String date;
  final double score;
  final double avgTime;
  final double? correct;
  const ProgressPoint({
    required this.date,
    required this.score,
    required this.avgTime,
    this.correct,
  });
}

class _ProgressLineChartState extends State<ProgressLineChart> {
  int? _hover;

  @override
  Widget build(BuildContext context) {
    if (widget.points.isEmpty) {
      return _emptyBox(widget.height, 'No hay actividad diaria disponible.');
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        return GestureDetector(
          onTapDown: (d) => _updateHover(d.localPosition.dx, w),
          onHorizontalDragUpdate: (d) => _updateHover(d.localPosition.dx, w),
          onHorizontalDragEnd: (_) => setState(() => _hover = null),
          onTapUp: (_) => setState(() => _hover = null),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 1100),
            curve: Curves.easeOut,
            builder: (context, t, child) => CustomPaint(
              size: Size(w, widget.height),
              painter: _ProgressPainter(
                points: widget.points,
                avgScore: widget.avgScore,
                progress: t,
                hover: _hover,
              ),
            ),
          ),
        );
      },
    );
  }

  void _updateHover(double dx, double w) {
    const padLeft = 34.0;
    const padRight = 46.0;
    final n = widget.points.length;
    final chartW = w - padLeft - padRight;
    final rel = ((dx - padLeft) / (chartW <= 0 ? 1 : chartW)).clamp(0.0, 1.0);
    final idx = (rel * (n - 1)).round().clamp(0, n - 1);
    if (idx != _hover) setState(() => _hover = idx);
  }
}

class _ProgressPainter extends CustomPainter {
  final List<ProgressPoint> points;
  final double? avgScore;
  final double progress;
  final int? hover;

  static const double padTop = 14;
  static const double padBottom = 24;
  static const double padLeft = 34;
  static const double padRight = 46;

  _ProgressPainter({
    required this.points,
    required this.avgScore,
    required this.progress,
    required this.hover,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final chartW = size.width - padLeft - padRight;
    final chartH = size.height - padTop - padBottom;
    final n = points.length;

    final scores = points.map((p) => p.score).toList();
    final minScore = scores.reduce(math.min);
    final maxScore = scores.reduce(math.max);
    final scoreRange = math.max(1, maxScore - minScore);
    final scoreMin = minScore;
    final scoreMax = maxScore + scoreRange * 0.1;

    final maxTime = points.map((p) => p.avgTime).fold<double>(0, math.max);
    final timeMax = math.max(10, (maxTime * 1.2).ceilToDouble());

    double xAt(int i) => padLeft + (n == 1 ? 0.5 : i / (n - 1)) * chartW;
    double yScore(double v) =>
        padTop + ((scoreMax - v) / (scoreMax - scoreMin)) * chartH;
    double yTime(double v) => padTop + ((timeMax - v) / timeMax) * chartH;

    // Rejilla + etiquetas de ejes.
    final gridPaint = Paint()
      ..color = PanelColors.border
      ..strokeWidth = 1;
    for (var tick = 0; tick <= 4; tick++) {
      final y = padTop + (tick / 4) * chartH;
      _dashedLine(canvas, Offset(padLeft, y), Offset(size.width - padRight, y),
          gridPaint);
      final leftVal = scoreMax - (tick / 4) * (scoreMax - scoreMin);
      final rightVal = timeMax - (tick / 4) * timeMax;
      _text(canvas, '${leftVal.round()}', Offset(padLeft - 6, y),
          PanelColors.correct, align: TextAlign.right);
      _text(canvas, '${rightVal.round()}s',
          Offset(size.width - padRight + 6, y), PanelColors.accent,
          align: TextAlign.left);
    }

    // Línea de media de score (discontinua).
    if (avgScore != null && avgScore! >= scoreMin && avgScore! <= scoreMax) {
      final y = yScore(avgScore!);
      final p = Paint()
        ..color = PanelColors.correct.withOpacity(0.6)
        ..strokeWidth = 1.5;
      _dashedLine(canvas, Offset(padLeft, y), Offset(size.width - padRight, y),
          p, dash: 4, gap: 4);
    }

    final scorePts = [
      for (var i = 0; i < n; i++) Offset(xAt(i), yScore(points[i].score))
    ];
    final timePts = [
      for (var i = 0; i < n; i++) Offset(xAt(i), yTime(points[i].avgTime))
    ];

    _drawAnimatedLine(canvas, scorePts, PanelColors.correct, 4.5, progress);
    _drawAnimatedLine(canvas, timePts, PanelColors.accent, 4, progress,
        dashed: true);

    // Cursor + puntos resaltados.
    if (hover != null && hover! >= 0 && hover! < n) {
      final hx = xAt(hover!);
      final cursor = Paint()
        ..color = const Color(0xFFCFC7C0)
        ..strokeWidth = 1;
      _dashedLine(canvas, Offset(hx, padTop),
          Offset(hx, size.height - padBottom), cursor);
      canvas.drawCircle(scorePts[hover!], 4,
          Paint()..color = PanelColors.correct);
      canvas.drawCircle(timePts[hover!], 4, Paint()..color = PanelColors.accent);
    }
  }

  void _drawAnimatedLine(Canvas canvas, List<Offset> pts, Color color,
      double width, double t,
      {bool dashed = false}) {
    if (pts.isEmpty) return;
    final path = _smoothPath(pts);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;

    if (pts.length == 1) {
      canvas.drawCircle(pts.first, width / 2, Paint()..color = color);
      return;
    }
    // Efecto de "dibujado": recorta el path según el progreso.
    for (final metric in path.computeMetrics()) {
      final extract = metric.extractPath(0, metric.length * t);
      if (dashed) {
        _drawDashedPath(canvas, extract, paint, dash: 6, gap: 5);
      } else {
        canvas.drawPath(extract, paint);
      }
    }
  }

  Path _smoothPath(List<Offset> pts) {
    final path = Path();
    if (pts.isEmpty) return path;
    path.moveTo(pts.first.dx, pts.first.dy);
    if (pts.length == 1) return path;
    const tension = 0.5;
    for (var i = 0; i < pts.length - 1; i++) {
      final p0 = i > 0 ? pts[i - 1] : pts[i];
      final p1 = pts[i];
      final p2 = pts[i + 1];
      final p3 = i + 2 < pts.length ? pts[i + 2] : p2;
      final cp1 = Offset(
        p1.dx + (p2.dx - p0.dx) / 6 * tension,
        p1.dy + (p2.dy - p0.dy) / 6 * tension,
      );
      final cp2 = Offset(
        p2.dx - (p3.dx - p1.dx) / 6 * tension,
        p2.dy - (p3.dy - p1.dy) / 6 * tension,
      );
      path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, p2.dx, p2.dy);
    }
    return path;
  }

  @override
  bool shouldRepaint(_ProgressPainter old) =>
      old.progress != progress || old.hover != hover || old.points != points;
}

// ===========================================================================
// GRÁFICA DE EVOLUCIÓN (precisión 0-100 de una asignatura) con área
// ===========================================================================
class TrendLineChart extends StatelessWidget {
  final List<double?> values; // % de acierto por día (null = sin datos)
  final Color color;
  final double height;

  const TrendLineChart({
    super.key,
    required this.values,
    required this.color,
    this.height = 190,
  });

  @override
  Widget build(BuildContext context) {
    final valid = values.whereType<double>().toList();
    if (valid.isEmpty) {
      return _emptyBox(height, 'Sin datos suficientes para la evolución.');
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 1100),
      curve: Curves.easeInOut,
      builder: (context, t, child) => CustomPaint(
        size: Size(double.infinity, height),
        painter: _TrendPainter(values: valid, color: color, progress: t),
      ),
    );
  }
}

class _TrendPainter extends CustomPainter {
  final List<double> values;
  final Color color;
  final double progress;

  _TrendPainter(
      {required this.values, required this.color, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    const padX = 10.0;
    const padY = 18.0;
    final n = values.length;
    double xAt(int i) => padX + (n == 1 ? 0.5 : i / (n - 1)) * (size.width - padX * 2);
    double yAt(double v) => padY + (1 - v / 100) * (size.height - padY * 2);

    // Rejilla.
    final grid = Paint()
      ..color = PanelColors.border
      ..strokeWidth = 1;
    for (final g in [25, 50, 75]) {
      final y = yAt(g.toDouble());
      _dashedLine(canvas, Offset(padX, y), Offset(size.width - padX, y), grid);
    }

    final pts = [for (var i = 0; i < n; i++) Offset(xAt(i), yAt(values[i]))];
    final line = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length; i++) {
      line.lineTo(pts[i].dx, pts[i].dy);
    }

    // Área bajo la curva.
    final area = Path.from(line)
      ..lineTo(pts.last.dx, size.height - padY)
      ..lineTo(pts.first.dx, size.height - padY)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, padY),
          Offset(0, size.height - padY),
          [color.withOpacity(0.22 * progress), color.withOpacity(0)],
        ),
    );

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    if (pts.length == 1) {
      canvas.drawCircle(pts.first, 4, Paint()..color = color);
    } else {
      for (final metric in line.computeMetrics()) {
        canvas.drawPath(
            metric.extractPath(0, metric.length * progress), paint);
      }
    }

    if (progress > 0.95) {
      canvas.drawCircle(pts.last, 5, Paint()..color = color);
      canvas.drawCircle(pts.last, 5,
          Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 2);
    }
  }

  @override
  bool shouldRepaint(_TrendPainter old) =>
      old.progress != progress || old.values != values || old.color != color;
}

// ===========================================================================
// Helpers de dibujo compartidos
// ===========================================================================
Widget _emptyBox(double height, String msg) => Container(
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: PanelColors.soft.withOpacity(0.6),
        border: Border.all(color: PanelColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16),
      child: Text(
        msg,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 13, color: PanelColors.muted),
      ),
    );

void _dashedLine(Canvas canvas, Offset a, Offset b, Paint paint,
    {double dash = 4, double gap = 5}) {
  final total = (b - a).distance;
  final dir = (b - a) / total;
  double d = 0;
  while (d < total) {
    final start = a + dir * d;
    final end = a + dir * math.min(d + dash, total);
    canvas.drawLine(start, end, paint);
    d += dash + gap;
  }
}

void _drawDashedPath(Canvas canvas, Path path, Paint paint,
    {double dash = 6, double gap = 5}) {
  for (final metric in path.computeMetrics()) {
    double d = 0;
    while (d < metric.length) {
      final seg = metric.extractPath(d, math.min(d + dash, metric.length));
      canvas.drawPath(seg, paint);
      d += dash + gap;
    }
  }
}

void _text(Canvas canvas, String text, Offset anchor, Color color,
    {TextAlign align = TextAlign.left}) {
  final tp = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        color: color,
      ),
    ),
    textDirection: TextDirection.ltr,
    textAlign: align,
  )..layout();
  double dx = anchor.dx;
  if (align == TextAlign.right) dx = anchor.dx - tp.width;
  tp.paint(canvas, Offset(dx, anchor.dy - tp.height / 2));
}
