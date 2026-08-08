import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../models/versus_models.dart';

/// Evolución de la puntuación ronda a ronda, una línea por jugador.
///
/// Los puntos que manda el servidor son ACUMULADOS: una ronda fallada suma 0 y
/// la línea se queda plana, que es justo lo que deja ver dónde se decidió la
/// partida. La línea propia va más gruesa y por encima del resto.
class VersusScoreChart extends StatelessWidget {
  final List<VersusScoreSeries> series;
  final List<VersusPlayer> players;
  final String? meId;
  final double height;

  const VersusScoreChart({
    super.key,
    required this.series,
    required this.players,
    required this.meId,
    this.height = 170,
  });

  /// Paleta estable por posición en la lista: el color de cada uno no debe
  /// bailar entre la leyenda y el trazo.
  static const List<Color> _palette = [
    AppColors.primary,
    AppColors.secondary,
    AppColors.success,
    AppColors.warning,
    AppColors.emerald,
    AppColors.slate,
    AppColors.primaryDark,
    AppColors.gold,
  ];

  static Color colorFor(int index) => _palette[index % _palette.length];

  @override
  Widget build(BuildContext context) {
    // Con el cero de salida por delante, incluso una sola ronda dibuja un tramo.
    final usable = series.where((s) => s.points.isNotEmpty).toList();
    if (usable.length < 2) return const SizedBox.shrink();

    String nameOf(String playerId) {
      for (final p in players) {
        if (p.id == playerId) return p.nickname;
      }
      return 'Jugador';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'CÓMO SE DECIDIÓ',
          style: TextStyle(
            color: AppColors.textLight,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          height: height,
          padding: const EdgeInsets.fromLTRB(8, 12, 12, 8),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border, width: 2),
          ),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (context, t, _) => CustomPaint(
              size: Size.infinite,
              painter: _ScoreChartPainter(
                series: usable,
                meId: meId,
                progress: t,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          runSpacing: 6,
          children: [
            for (int i = 0; i < usable.length; i++)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 12,
                    height: 3,
                    decoration: BoxDecoration(
                      color: colorFor(i),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    nameOf(usable[i].playerId),
                    style: TextStyle(
                      color: usable[i].playerId == meId
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: usable[i].playerId == meId
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

class _ScoreChartPainter extends CustomPainter {
  final List<VersusScoreSeries> series;
  final String? meId;
  final double progress;

  _ScoreChartPainter({
    required this.series,
    required this.meId,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const double padLeft = 6;
    const double padRight = 6;
    const double padTop = 6;
    const double padBottom = 6;

    final w = size.width - padLeft - padRight;
    final h = size.height - padTop - padBottom;
    if (w <= 0 || h <= 0) return;

    // +1 por el origen: la línea arranca en cero, antes de la primera pregunta.
    // Sin ese punto empezaba a media tarjeta, en lo que ya se había puntuado en
    // la ronda 1, y parecía que la partida salía de la nada.
    final rounds =
        series.map((s) => s.points.length).reduce((a, b) => a > b ? a : b) + 1;
    if (rounds < 2) return;

    // El techo se calcula sobre TODAS las series para que las líneas sean
    // comparables entre sí; con un máximo por línea, el último no se vería peor
    // que el primero.
    var maxY = 1;
    for (final s in series) {
      for (final p in s.points) {
        if (p > maxY) maxY = p;
      }
    }

    double dx(int i) => padLeft + w * (i / (rounds - 1));
    double dy(int value) => padTop + h * (1 - value / maxY);

    // Rejilla mínima: solo la base, para no competir con las líneas.
    canvas.drawLine(
      Offset(padLeft, padTop + h),
      Offset(padLeft + w, padTop + h),
      Paint()
        ..color = AppColors.border
        ..strokeWidth = 1,
    );

    // La propia se pinta la última para que quede por encima del resto.
    final order = List.generate(series.length, (i) => i)
      ..sort((a, b) {
        final aMine = series[a].playerId == meId ? 1 : 0;
        final bMine = series[b].playerId == meId ? 1 : 0;
        return aMine - bMine;
      });

    for (final i in order) {
      // El cero de salida por delante, igual que en la web.
      final points = <int>[0, ...series[i].points];
      final mine = series[i].playerId == meId;
      final color = VersusScoreChart.colorFor(i);

      // Cuántos tramos se han dibujado ya, para que el trazo entre animándose.
      final visible = (1 + (points.length - 1) * progress).clamp(1, points.length);

      // Los vértices que toca dibujar en este instante de la animación. El
      // último puede ir a medias, para que la punta avance suave.
      final vertices = <Offset>[Offset(dx(0), dy(points[0]))];
      for (int p = 1; p < visible.floor(); p += 1) {
        vertices.add(Offset(dx(p), dy(points[p])));
      }
      final partial = visible - visible.floor();
      if (partial > 0 && visible.floor() < points.length) {
        final from = visible.floor() - 1;
        final to = visible.floor();
        vertices.add(Offset(
          dx(from) + (dx(to) - dx(from)) * partial,
          dy(points[from]) + (dy(points[to]) - dy(points[from])) * partial,
        ));
      }

      final path = _monotonePath(vertices);

      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = mine ? 3.4 : 2
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = mine ? color : color.withValues(alpha: 0.75),
      );

      // Punto final, solo cuando la línea ya ha llegado.
      if (progress >= 1) {
        canvas.drawCircle(
          Offset(dx(points.length - 1), dy(points.last)),
          mine ? 4 : 3,
          Paint()..color = color,
        );
      }
    }
  }

  /// Interpolación cúbica MONÓTONA (Fritsch–Carlson), la misma que usa la web.
  ///
  /// Una suavidad normal (una spline de Catmull-Rom, por ejemplo) se pasa de
  /// largo al cambiar la pendiente, y aquí eso sería mentir: la puntuación es
  /// acumulada y NUNCA baja, así que un sobrepaso dibujaría una bajada que no
  /// ocurrió. Esta preserva la monotonía — lo plano se queda plano y lo que
  /// sube solo sube, sin los picos de unir los puntos con rectas.
  static Path _monotonePath(List<Offset> p) {
    final path = Path();
    if (p.isEmpty) return path;

    path.moveTo(p[0].dx, p[0].dy);
    if (p.length == 1) return path;

    final n = p.length;
    final dx = <double>[];
    final slope = <double>[];
    for (int i = 0; i < n - 1; i += 1) {
      final h = p[i + 1].dx - p[i].dx;
      dx.add(h);
      slope.add(h == 0 ? 0 : (p[i + 1].dy - p[i].dy) / h);
    }

    // Tangente inicial en cada punto: media de las pendientes vecinas.
    final m = <double>[slope[0]];
    for (int i = 1; i < n - 1; i += 1) {
      m.add((slope[i - 1] + slope[i]) / 2);
    }
    m.add(slope[n - 2]);

    // Y aquí está lo que evita el sobrepaso: donde el tramo es plano la
    // tangente se fuerza a 0, y en el resto se recorta al círculo de radio 3.
    for (int i = 0; i < n - 1; i += 1) {
      if (slope[i] == 0) {
        m[i] = 0;
        m[i + 1] = 0;
        continue;
      }
      final a = m[i] / slope[i];
      final b = m[i + 1] / slope[i];
      final s = a * a + b * b;
      if (s > 9) {
        final t = 3 / math.sqrt(s);
        m[i] = t * a * slope[i];
        m[i + 1] = t * b * slope[i];
      }
    }

    for (int i = 0; i < n - 1; i += 1) {
      final h = dx[i] / 3;
      path.cubicTo(
        p[i].dx + h,
        p[i].dy + m[i] * h,
        p[i + 1].dx - h,
        p[i + 1].dy - m[i + 1] * h,
        p[i + 1].dx,
        p[i + 1].dy,
      );
    }
    return path;
  }

  @override
  bool shouldRepaint(_ScoreChartPainter old) =>
      old.progress != progress || old.series != series || old.meId != meId;
}
