import 'package:flutter/material.dart';

import '../../../core/models/guia_esfuerzo.dart';
import '../../../core/models/guias.dart';
import '../../../shared/sticker/sticker.dart';
import 'guia_estilos.dart';

/* ════════════════════════════════════════════════════════════════════════
   Gráficos de la guía de estudio. Puerto de GuideTrendChart, GuideTrendShift,
   GuidePriorityMap, GuideHeatmap y GuideEffortMatrix de la web. Donde la web
   usa el cursor (hover), aquí se toca: el detalle sale en una línea debajo.
═══════════════════════════════════════════════════════════════════════════ */

/// Preguntas por año: barras, la media anterior en línea discontinua y el último MIR en coral.
class GraficoAnios extends StatefulWidget {
  final List<({int year, int count})> perYear;
  final double average;
  final int highlightYear;
  const GraficoAnios({super.key, required this.perYear, required this.average, required this.highlightYear});

  @override
  State<GraficoAnios> createState() => _GraficoAniosState();
}

class _GraficoAniosState extends State<GraficoAnios> {
  int? _tocado;

  @override
  Widget build(BuildContext context) {
    final p = widget.perYear;
    if (p.isEmpty) return const SizedBox.shrink();
    final max = p.map((e) => e.count).reduce((a, b) => a > b ? a : b) + 2;
    const alto = 170.0;
    final t = _tocado;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // + 26: el número de encima de la barra más alta (con texto grande, 18 no bastaba).
      SizedBox(
        height: alto + 26,
        child: Stack(children: [
          // La media anterior.
          Positioned(
            left: 0,
            right: 0,
            bottom: widget.average / max * alto,
            child: Container(height: 1.5, color: kCoralTexto.withValues(alpha: 0.5)),
          ),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (var i = 0; i < p.length; i++)
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _tocado = _tocado == i ? null : i),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                      Text('${p[i].count}',
                          style: TextStyle(
                            color: p[i].year == widget.highlightYear ? kCoralTexto : kInk.withValues(alpha: t == i ? 1 : 0.7),
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                          )),
                      const SizedBox(height: 2),
                      Container(
                        height: p[i].count / max * alto,
                        decoration: BoxDecoration(
                          color: p[i].year == widget.highlightYear
                              ? kCoral
                              : kInk.withValues(alpha: t == i ? 0.35 : 0.15),
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
          ]),
        ]),
      ),
      const SizedBox(height: 4),
      Row(children: [
        for (final e in p)
          Expanded(
            child: Text(anioCorto(e.year),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: e.year == widget.highlightYear ? kCoralTexto : kMuted,
                  fontSize: 10,
                  fontWeight: e.year == widget.highlightYear ? FontWeight.w900 : FontWeight.w500,
                )),
          ),
      ]),
      const SizedBox(height: 8),
      if (t != null)
        Text(
          'MIR ${p[t].year}: ${p[t].count} preguntas · ${p[t].count - widget.average >= 0 ? '+' : ''}${formatAvg(p[t].count - widget.average)} vs media',
          style: const TextStyle(color: kInk, fontSize: 12.5, fontWeight: FontWeight.w700),
        ),
      Wrap(spacing: 14, runSpacing: 4, children: [
        _leyenda(Container(width: 14, height: 2, color: kCoralTexto.withValues(alpha: 0.5)), 'media anterior: ${formatAvg(widget.average)}'),
        _leyenda(Container(width: 10, height: 10, decoration: BoxDecoration(color: kCoral, borderRadius: BorderRadius.circular(3))), 'último MIR'),
      ]),
    ]);
  }
}

Widget _leyenda(Widget marca, String texto) => Row(mainAxisSize: MainAxisSize.min, children: [
      marca,
      const SizedBox(width: 5),
      Text(texto, style: const TextStyle(color: kMuted, fontSize: 11.5)),
    ]);

/// «Qué sube y qué baja»: la media anual anterior (punto gris) frente a la de los últimos MIR (punto coral o
/// azul), unidas por una línea del color de la tendencia.
class GraficoTendencias extends StatelessWidget {
  final List<GuideTopicWithStats> filas;
  final String earlierLabel;
  final String recentLabel;
  final ValueChanged<String> onTema;
  const GraficoTendencias({super.key, required this.filas, required this.earlierLabel, required this.recentLabel, required this.onTema});

  @override
  Widget build(BuildContext context) {
    if (filas.isEmpty) return const Text('Sin cambios que destacar.', style: TextStyle(color: kMuted));
    final maxV = filas.expand((t) => [t.stats.recentAvg, t.stats.earlierAvg]).fold(1.0, (a, b) => a > b ? a : b).ceilToDouble();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final t in filas)
        InkWell(
          onTap: () => onTema(t.id),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              SizedBox(
                width: 104,
                child: Text(t.shortName, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: kInk, fontSize: 12, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: LayoutBuilder(builder: (context, c) {
                  double px(double v) => (v / maxV * (c.maxWidth - 12)).clamp(0, c.maxWidth - 12);
                  final s = t.stats;
                  final lo = s.earlierAvg < s.recentAvg ? s.earlierAvg : s.recentAvg;
                  final hi = s.earlierAvg < s.recentAvg ? s.recentAvg : s.earlierAvg;
                  final color = switch (s.trend) {
                    GuideTrend.sube => kCoral,
                    GuideTrend.baja => kAzulBaja,
                    GuideTrend.estable => const Color(0xFFD5CFCB),
                  };
                  return SizedBox(
                    height: 18,
                    child: Stack(children: [
                      Positioned(left: 0, right: 0, top: 8, child: Container(height: 2, color: const Color(0xFFF0EAE6))),
                      Positioned(
                        left: px(lo) + 6,
                        width: (px(hi) - px(lo)).clamp(0, double.infinity),
                        top: 6,
                        child: Container(height: 6, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(99))),
                      ),
                      Positioned(left: px(s.earlierAvg), top: 3, child: _punto(const Color(0xFFBFC7CE))),
                      Positioned(left: px(s.recentAvg), top: 3, child: _punto(s.trend == GuideTrend.baja ? kAzulTexto : kCoralTexto)),
                    ]),
                  );
                }),
              ),
              const SizedBox(width: 8),
              PildoraGuia(formatAvg(t.stats.recentAvg),
                  icono: trendEstilo[t.stats.trend]!.icono, color: trendEstilo[t.stats.trend]!.texto, fondo: trendEstilo[t.stats.trend]!.fondo),
            ]),
          ),
        ),
      const SizedBox(height: 6),
      Wrap(spacing: 14, runSpacing: 4, children: [
        _leyenda(_punto(const Color(0xFFBFC7CE)), earlierLabel),
        _leyenda(_punto(kCoralTexto), recentLabel),
        const Text('preg./año', style: TextStyle(color: kMuted, fontSize: 11.5)),
      ]),
    ]);
  }

  static Widget _punto(Color c) => Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
      );
}

/// «Mapa de prioridades»: los temas ordenados (por previsión de entrada), con su total, el % de la
/// asignatura, los últimos 5 MIR, la tendencia y la previsión para el próximo examen.
class MapaPrioridades extends StatefulWidget {
  final List<GuideTopicWithStats> temas;
  final List<int> recentYears;
  final String targetExam;
  final String periodLabel;
  final ValueChanged<String> onTema;
  const MapaPrioridades({
    super.key,
    required this.temas,
    required this.recentYears,
    required this.targetExam,
    required this.periodLabel,
    required this.onTema,
  });

  @override
  State<MapaPrioridades> createState() => _MapaPrioridadesState();
}

class _MapaPrioridadesState extends State<MapaPrioridades> {
  GuideSortKey _orden = GuideSortKey.prevision;

  @override
  Widget build(BuildContext context) {
    final temas = sortGuideTopics(widget.temas, _orden);
    final max = temas.map((t) => t.stats.totalCount).fold(1, (a, b) => a > b ? a : b);
    final total = temas.fold(0, (a, t) => a + t.stats.totalCount);
    final rango = widget.recentYears.isEmpty ? '' : '${anioCorto(widget.recentYears.first)}–${anioCorto(widget.recentYears.last)}';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SelectorOrdenGuia(valor: _orden, onChanged: (k) => setState(() => _orden = k)),
      const SizedBox(height: 10),
      for (var i = 0; i < temas.length; i++) _fila(i, temas[i], max, total, rango),
      const SizedBox(height: 8),
      Text(
        '${widget.periodLabel}: preguntas de todo el periodo · ${widget.targetExam}: previsión orientativa de preguntas '
        '(pesa un 70 % lo de los últimos $recentWindow MIR). Recuadro = último MIR; punto = incluye reserva.',
        style: const TextStyle(color: kMuted, fontSize: 11.5, height: 1.4),
      ),
    ]);
  }

  Widget _fila(int i, GuideTopicWithStats t, int max, int total, String rango) {
    final tier = tierEstilo[t.topic.tier]!;
    final trend = trendEstilo[t.stats.trend]!;
    final recientes = t.perYear.length >= recentWindow ? t.perYear.sublist(t.perYear.length - recentWindow) : t.perYear;
    final share = total == 0 ? 0 : (t.stats.totalCount / total * 100).round();
    return InkWell(
      onTap: () => widget.onTema(t.id),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: kHairline, width: 1.5)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            SizedBox(width: 22, child: Text('${i + 1}', style: const TextStyle(color: kMuted, fontSize: 13, fontWeight: FontWeight.w900))),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t.shortName, style: const TextStyle(color: kInk, fontSize: 14, fontWeight: FontWeight.w900)),
                const SizedBox(height: 3),
                // La tendencia va aquí y no en la fila de los últimos MIR: a 360 px allí no cabía.
                Wrap(spacing: 4, runSpacing: 4, children: [
                  PildoraGuia(tier.label.toUpperCase(), color: tier.texto, fondo: tier.fondo),
                  PildoraGuia(trend.label, icono: trend.icono, color: trend.texto, fondo: trend.fondo),
                ]),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(formatForecast(t.stats.forecast), style: const TextStyle(color: kCoralTexto, fontSize: 18, fontWeight: FontWeight.w900)),
              Text(widget.targetExam, style: const TextStyle(color: kMuted, fontSize: 10)),
            ]),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            const SizedBox(width: 22),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: Container(
                  height: 7,
                  color: const Color(0xFFF2EFED),
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: (t.stats.totalCount / max).clamp(0.02, 1.0),
                    child: Container(color: tier.color),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text.rich(TextSpan(children: [
              TextSpan(text: '${t.stats.totalCount}', style: const TextStyle(fontWeight: FontWeight.w900, color: kInk)),
              TextSpan(text: ' · $share%', style: const TextStyle(color: kMuted)),
            ]), style: const TextStyle(fontSize: 12)),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            const SizedBox(width: 22),
            Text(rango, style: const TextStyle(color: kMuted, fontSize: 10)),
            const SizedBox(width: 6),
            for (var c = 0; c < recientes.length; c++)
              Padding(
                padding: const EdgeInsets.only(right: 3),
                child: _celda(recientes[c], ultima: c == recientes.length - 1, reserva: c == recientes.length - 1 && t.topic.lastExamReserve > 0),
              ),
          ]),
        ]),
      ),
    );
  }

  Widget _celda(int n, {bool ultima = false, bool reserva = false}) {
    final c = colorCalor(n);
    return Stack(clipBehavior: Clip.none, children: [
      Container(
        width: 22,
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c.fondo,
          borderRadius: BorderRadius.circular(6),
          border: ultima ? Border.all(color: kInk.withValues(alpha: 0.7), width: 2) : null,
        ),
        child: Text('$n', style: TextStyle(color: c.texto, fontSize: 10.5, fontWeight: FontWeight.w800)),
      ),
      if (reserva)
        Positioned(
          right: -2,
          top: -2,
          child: Container(width: 7, height: 7, decoration: const BoxDecoration(color: kOro, shape: BoxShape.circle)),
        ),
    ]);
  }
}

/// «Evolución tema a tema»: una fila por tema y una celda por MIR, con la banda de los últimos 5. Tocar una
/// celda, un tema o un año da el detalle debajo.
class MapaCalorGuia extends StatefulWidget {
  final List<GuideTopicWithStats> temas;
  final List<int> years;
  const MapaCalorGuia({super.key, required this.temas, required this.years});

  @override
  State<MapaCalorGuia> createState() => _MapaCalorGuiaState();
}

class _MapaCalorGuiaState extends State<MapaCalorGuia> {
  GuideSortKey _orden = GuideSortKey.prevision;
  int? _fila;
  int? _col;

  @override
  Widget build(BuildContext context) {
    final temas = sortGuideTopics(widget.temas, _orden);
    final years = widget.years;
    final inicioReciente = years.length - recentWindow;
    const celda = 28.0, nombre = 110.0, totalAncho = 40.0;
    final hayFoco = _fila != null || _col != null;
    bool apagada(int f, int c) {
      if (!hayFoco) return false;
      if (_fila != null && _col != null) return f != _fila && c != _col;
      if (_fila != null) return f != _fila;
      return c != _col;
    }

    String detalle() {
      final f = _fila, c = _col;
      if (f != null && c != null) {
        final n = temas[f].perYear[c];
        return '${temas[f].shortName} en el MIR ${years[c]}: $n ${n == 1 ? 'pregunta' : 'preguntas'}';
      }
      if (f != null) {
        final t = temas[f];
        return '${t.shortName}: ${t.stats.totalCount} preguntas en ${years.length} MIR · cayó en ${t.perYear.where((v) => v > 0).length} de ${years.length}';
      }
      if (c != null) {
        final suma = temas.fold(0, (a, t) => a + (c < t.perYear.length ? t.perYear[c] : 0));
        return 'MIR ${years[c]}: $suma preguntas de la asignatura';
      }
      return 'Toca una celda, un tema o un año para ver el detalle.';
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SelectorOrdenGuia(valor: _orden, onChanged: (k) => setState(() => _orden = k)),
      const SizedBox(height: 10),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const SizedBox(width: nombre),
            for (var c = 0; c < years.length; c++)
              GestureDetector(
                onTap: () => setState(() {
                  _fila = null;
                  _col = _col == c ? null : c;
                }),
                child: Container(
                  width: celda,
                  margin: const EdgeInsets.all(1.5),
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: _col == c ? kInk : Colors.transparent, borderRadius: BorderRadius.circular(4)),
                  child: Text(anioCorto(years[c]),
                      style: TextStyle(
                        color: _col == c ? Colors.white : (c >= inicioReciente ? kInk : kMuted),
                        fontSize: 10.5,
                        fontWeight: c >= inicioReciente || _col == c ? FontWeight.w900 : FontWeight.w500,
                      )),
                ),
              ),
            const SizedBox(width: totalAncho, child: Text('Total', textAlign: TextAlign.right, style: TextStyle(color: kMuted, fontSize: 10.5))),
          ]),
          for (var f = 0; f < temas.length; f++)
            Row(children: [
              GestureDetector(
                onTap: () => setState(() {
                  _col = null;
                  _fila = _fila == f ? null : f;
                }),
                child: SizedBox(
                  width: nombre,
                  child: Text(temas[f].shortName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _fila == f ? kCoralTexto : (hayFoco && _fila != null ? kInk.withValues(alpha: 0.4) : kInk),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      )),
                ),
              ),
              for (var c = 0; c < temas[f].perYear.length; c++)
                GestureDetector(
                  onTap: () => setState(() {
                    final mismo = _fila == f && _col == c;
                    _fila = mismo ? null : f;
                    _col = mismo ? null : c;
                  }),
                  child: Opacity(
                    opacity: apagada(f, c) ? 0.3 : 1,
                    child: Container(
                      width: celda,
                      height: 26,
                      margin: const EdgeInsets.all(1.5),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: colorCalor(temas[f].perYear[c]).fondo,
                        borderRadius: BorderRadius.circular(6),
                        border: _fila == f && _col == c
                            ? Border.all(color: kInk, width: 2)
                            : (c >= inicioReciente ? Border.all(color: kCoral.withValues(alpha: 0.35)) : null),
                      ),
                      child: Text('${temas[f].perYear[c]}',
                          style: TextStyle(color: colorCalor(temas[f].perYear[c]).texto, fontSize: 10.5, fontWeight: FontWeight.w800)),
                    ),
                  ),
                ),
              SizedBox(
                width: totalAncho,
                child: Text('${temas[f].stats.totalCount}',
                    textAlign: TextAlign.right,
                    style: TextStyle(color: _fila == f ? kCoralTexto : kInk, fontSize: 11.5, fontWeight: FontWeight.w900)),
              ),
            ]),
        ]),
      ),
      const SizedBox(height: 8),
      Semantics(liveRegion: true, child: Text(detalle(), style: const TextStyle(color: kInk, fontSize: 12.5, fontWeight: FontWeight.w600))),
      const SizedBox(height: 6),
      Wrap(spacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
        for (var n = 0; n <= 4; n++)
          Container(width: 14, height: 14, decoration: BoxDecoration(color: colorCalor(n).fondo, borderRadius: BorderRadius.circular(4))),
        const SizedBox(width: 4),
        const Text('0 → 4+ preguntas · recuadro coral: últimos $recentWindow MIR', style: TextStyle(color: kMuted, fontSize: 11.5)),
      ]),
    ]);
  }
}

/// «Esfuerzo frente a recompensa»: el diseño de [disenoEsfuerzo] pintado en un lienzo de 640×400 que se
/// escala al ancho (mínimo 480, con scroll en pantallas estrechas, como la web). Tocar un punto lo resalta.
class MatrizEsfuerzo extends StatefulWidget {
  final List<GuideTopicWithStats> temas;
  final String periodLabel;
  final ValueChanged<String> onTema;
  const MatrizEsfuerzo({super.key, required this.temas, required this.periodLabel, required this.onTema});

  @override
  State<MatrizEsfuerzo> createState() => _MatrizEsfuerzoState();
}

class _MatrizEsfuerzoState extends State<MatrizEsfuerzo> {
  late DisenoEsfuerzo _d = disenoEsfuerzo(widget.temas);
  String? _activo;

  @override
  void didUpdateWidget(MatrizEsfuerzo old) {
    super.didUpdateWidget(old);
    if (old.temas != widget.temas) _d = disenoEsfuerzo(widget.temas);
  }

  @override
  Widget build(BuildContext context) {
    final activo = _d.puntos.where((p) => p.tema.id == _activo).firstOrNull;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      LayoutBuilder(builder: (context, c) {
        final ancho = c.maxWidth < 480 ? 480.0 : c.maxWidth;
        final escala = ancho / esfuerzoAncho;
        final lienzo = SizedBox(
          width: ancho,
          height: esfuerzoAlto * escala,
          child: GestureDetector(
            onTapUp: (e) {
              final x = e.localPosition.dx / escala, y = e.localPosition.dy / escala;
              PuntoEsfuerzo? cerca;
              var dist = 18.0 * 18.0;
              for (final p in _d.puntos) {
                final d2 = (p.cx - x) * (p.cx - x) + (p.cy - y) * (p.cy - y);
                if (d2 < dist) {
                  dist = d2;
                  cerca = p;
                }
              }
              setState(() => _activo = cerca?.tema.id == _activo ? null : cerca?.tema.id);
            },
            child: CustomPaint(
              painter: _PintorEsfuerzo(_d, escala: escala, activo: _activo, periodLabel: widget.periodLabel),
              size: Size(ancho, esfuerzoAlto * escala),
            ),
          ),
        );
        return Semantics(
          label: 'Esfuerzo (páginas) frente a recompensa (preguntas MIR) de cada tema',
          child: c.maxWidth < 480 ? SingleChildScrollView(scrollDirection: Axis.horizontal, child: lienzo) : lienzo,
        );
      }),
      const SizedBox(height: 8),
      if (activo != null)
        Row(children: [
          Expanded(
            child: Text('${activo.tema.topic.name}: ${activo.tema.stats.totalCount} preguntas, ~${activo.tema.topic.pages} páginas',
                style: const TextStyle(color: kInk, fontSize: 12.5, fontWeight: FontWeight.w700)),
          ),
          TextButton(onPressed: () => widget.onTema(activo.tema.id), child: const Text('Ver tema')),
        ])
      else
        const Text('Cada punto es un tema. Cuanto más arriba y a la izquierda, más preguntas da por cada página que estudias. Toca uno para ver cuál es.',
            style: TextStyle(color: kMuted, fontSize: 12, height: 1.4)),
      const SizedBox(height: 6),
      Wrap(spacing: 12, runSpacing: 4, children: [
        for (final t in GuideTier.values)
          _leyenda(Container(width: 10, height: 10, decoration: BoxDecoration(color: tierEstilo[t]!.color, shape: BoxShape.circle)), tierEstilo[t]!.label),
      ]),
    ]);
  }
}

class _PintorEsfuerzo extends CustomPainter {
  final DisenoEsfuerzo d;
  final double escala;
  final String? activo;
  final String periodLabel;
  _PintorEsfuerzo(this.d, {required this.escala, required this.activo, required this.periodLabel});

  void _texto(Canvas c, String t, double x, double y, {double size = 12, Color color = kMuted, FontWeight peso = FontWeight.w400, AnclaTexto ancla = AnclaTexto.inicio, bool halo = false, double opacidad = 1}) {
    final estilo = TextStyle(fontSize: size, color: color.withValues(alpha: opacidad), fontWeight: peso, fontFamily: 'Lexend');
    TextPainter tp(TextStyle s) => TextPainter(text: TextSpan(text: t, style: s), textDirection: TextDirection.ltr)..layout();
    final p = tp(estilo);
    final dx = switch (ancla) {
      AnclaTexto.inicio => x,
      AnclaTexto.fin => x - p.width,
      AnclaTexto.medio => x - p.width / 2,
    };
    // `y` es la línea base, como en SVG.
    final top = y - size * 0.8;
    if (halo) {
      tp(estilo.copyWith(
        foreground: Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..strokeJoin = StrokeJoin.round
          ..color = Colors.white,
      )).paint(c, Offset(dx, top));
    }
    p.paint(c, Offset(dx, top));
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(escala);
    const pad = esfuerzoPad;
    final abajo = esfuerzoAlto - pad.bottom;
    final derecha = esfuerzoAncho - pad.right;
    canvas.drawRRect(RRect.fromLTRBR(pad.left, pad.top, d.splitX, d.splitY, const Radius.circular(10)), Paint()..color = kSalvia.withValues(alpha: 0.08));
    canvas.drawRRect(RRect.fromLTRBR(d.splitX, pad.top, derecha, d.splitY, const Radius.circular(10)), Paint()..color = kCoral.withValues(alpha: 0.07));
    _texto(canvas, 'Máxima rentabilidad', pad.left + 10, pad.top + 18, color: kSalviaTexto, peso: FontWeight.w800);
    _texto(canvas, 'poco temario, muchas preguntas', pad.left + 10, pad.top + 33, size: 10.5);
    _texto(canvas, 'Pilares', derecha - 10, pad.top + 18, color: kCoralTexto, peso: FontWeight.w800, ancla: AnclaTexto.fin);
    _texto(canvas, 'mucho temario, pero cae siempre', derecha - 10, pad.top + 33, size: 10.5, ancla: AnclaTexto.fin);
    _texto(canvas, 'Poco rentable', derecha - 10, d.pocoRentableY, peso: FontWeight.w800, ancla: AnclaTexto.fin);
    _texto(canvas, 'Pasada rápida', d.splitX - 10, d.pasadaRapidaY, peso: FontWeight.w800, ancla: AnclaTexto.fin);
    final eje = Paint()
      ..color = kInk.withValues(alpha: 0.25)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(pad.left, abajo), Offset(derecha, abajo), eje);
    canvas.drawLine(Offset(pad.left, pad.top), Offset(pad.left, abajo), eje);
    for (final (v, x) in d.marcasX) {
      _texto(canvas, numeroEje(v), x, abajo + 16, size: 10.5, ancla: AnclaTexto.medio);
    }
    for (final (v, y) in d.marcasY) {
      _texto(canvas, numeroEje(v), pad.left - 8, y + 4, size: 10.5, ancla: AnclaTexto.fin);
    }
    _texto(canvas, 'Esfuerzo → páginas de temario', (pad.left + derecha) / 2, esfuerzoAlto - 8, size: 11.5, color: kInk, peso: FontWeight.w600, ancla: AnclaTexto.medio);
    canvas.save();
    final medioY = (pad.top + abajo) / 2;
    canvas.translate(14, medioY);
    canvas.rotate(-1.5707963267948966);
    _texto(canvas, 'Recompensa → preguntas $periodLabel', 0, 0, size: 11.5, color: kInk, peso: FontWeight.w600, ancla: AnclaTexto.medio);
    canvas.restore();

    for (final p in d.puntos) {
      final centro = Offset(p.cx, p.cy);
      canvas.drawCircle(centro, p.r, Paint()..color = tierEstilo[p.tema.topic.tier]!.color);
      canvas.drawCircle(
        centro,
        p.r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = p.tema.id == activo ? 3 : 2
          ..color = p.tema.id == activo ? kInk : Colors.white,
      );
    }
    for (final p in d.puntos) {
      if (!p.mayor || p.tema.id == activo) continue;
      _texto(canvas, p.tema.shortName, p.cx + p.etiqueta.dx, p.cy + p.etiqueta.dy,
          color: kInk, peso: FontWeight.w700, ancla: p.etiqueta.ancla, opacidad: activo != null ? 0.2 : 0.55);
    }
    final a = d.puntos.where((p) => p.tema.id == activo).firstOrNull;
    if (a != null) {
      _texto(canvas, a.tema.shortName, a.cx + a.etiqueta.dx, a.cy + a.etiqueta.dy, color: kInk, peso: FontWeight.w900, ancla: a.etiqueta.ancla, halo: true);
    }
    if (d.textoMenores != null) _texto(canvas, d.textoMenores!, d.menoresX, d.menoresY, size: 11);
    canvas.restore();
  }

  static String numeroEje(double v) => v == v.roundToDouble() ? '${v.round()}' : formatAvg(v);

  @override
  bool shouldRepaint(_PintorEsfuerzo old) => old.d != d || old.activo != activo || old.escala != escala;
}
