import 'package:flutter/material.dart';

import '../../../core/models/guias.dart';
import '../../../shared/sticker/sticker.dart';
import 'guia_estilos.dart';

/// Un tema de la guía, plegable (el primero abierto): de qué va, su evolución en el MIR, dónde se
/// concentran las preguntas, lo que hay que saber, la trampa del examen y sus preguntas del último MIR.
/// Puerto de GuideTopicCard.tsx de la web.
class TarjetaTemaGuia extends StatefulWidget {
  final GuideTopicWithStats tema;
  final List<int> years;
  final int maxYearCount;
  final String targetExam;
  final String lastExamLabel;
  final List<GuideQuestion> preguntas;
  final bool abiertaDeEntrada;
  final ValueChanged<int> onPregunta;

  const TarjetaTemaGuia({
    super.key,
    required this.tema,
    required this.years,
    required this.maxYearCount,
    required this.targetExam,
    required this.lastExamLabel,
    required this.preguntas,
    required this.onPregunta,
    this.abiertaDeEntrada = false,
  });

  @override
  State<TarjetaTemaGuia> createState() => TarjetaTemaGuiaState();
}

class TarjetaTemaGuiaState extends State<TarjetaTemaGuia> {
  late bool _abierta = widget.abiertaDeEntrada;

  /// Al saltar aquí desde otro apartado, se abre.
  void abrir() {
    if (!_abierta) setState(() => _abierta = true);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tema;
    final s = t.stats;
    final tier = tierEstilo[t.topic.tier]!;
    final trend = trendEstilo[s.trend]!;
    return StickerCard(
      depth: _abierta ? 5 : 3,
      radius: 20,
      margin: const EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.zero,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => setState(() => _abierta = !_abierta),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: tier.color, borderRadius: BorderRadius.circular(12), border: Border.all(color: kInk, width: 2)),
                child: Text(t.topic.code, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t.topic.name, style: const TextStyle(color: kInk, fontSize: 15, fontWeight: FontWeight.w900, height: 1.25)),
                  const SizedBox(height: 4),
                  Wrap(spacing: 6, runSpacing: 4, children: [
                    PildoraGuia(tier.label, color: tier.texto, fondo: tier.fondo),
                    PildoraGuia(trend.label, icono: trend.icono, color: trend.texto, fondo: trend.fondo),
                    _insigniaUltimo(),
                  ]),
                  const SizedBox(height: 6),
                  Text.rich(TextSpan(children: [
                    TextSpan(text: '${s.totalCount}', style: const TextStyle(fontWeight: FontWeight.w900, color: kInk)),
                    TextSpan(text: ' ${s.totalCount == 1 ? 'pregunta' : 'preguntas'} en ${widget.years.length} MIR · últimos $recentWindow MIR: '),
                    TextSpan(text: '${formatAvg(s.recentAvg)}/año', style: const TextStyle(fontWeight: FontWeight.w900, color: kInk)),
                  ]), style: const TextStyle(color: kMuted, fontSize: 12)),
                ]),
              ),
              AnimatedRotation(
                turns: _abierta ? 0.5 : 0,
                duration: const Duration(milliseconds: 200),
                child: const Icon(Icons.expand_more_rounded, color: kInk),
              ),
            ]),
          ),
        ),
        if (_abierta)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(t.topic.focus, style: const TextStyle(color: kInk, fontSize: 13.5, height: 1.5)),
              const SizedBox(height: 14),
              _evolucion(),
              if (t.topic.hotspots.isNotEmpty) ...[
                const SizedBox(height: 14),
                const Text('Dónde se concentran las preguntas', style: TextStyle(color: kInk, fontSize: 13, fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                for (final h in t.topic.hotspots)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Semantics(
                        label: 'Frecuencia ${h.heat} de 3',
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          for (var l = 1; l <= 3; l++)
                            Icon(Icons.local_fire_department_rounded, size: 15, color: l <= h.heat ? kCoralTexto : const Color(0xFFE6DEDA)),
                        ]),
                      ),
                      const SizedBox(width: 6),
                      Expanded(child: Text(h.name, style: const TextStyle(color: kInk, fontSize: 12.5, height: 1.35))),
                    ]),
                  ),
              ],
              if (t.topic.keys.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('Lo que tienes que saber', style: TextStyle(color: kInk, fontSize: 13, fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                for (final k in t.topic.keys)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Container(
                        width: 7,
                        height: 7,
                        margin: const EdgeInsets.only(top: 6, right: 8),
                        decoration: BoxDecoration(color: tier.color, shape: BoxShape.circle),
                      ),
                      Expanded(child: Text(k, style: const TextStyle(color: kInk, fontSize: 12.5, height: 1.45))),
                    ]),
                  ),
              ],
              if (t.topic.trap != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: tinted(kOro, 0.18), borderRadius: BorderRadius.circular(14)),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.lightbulb_rounded, size: 18, color: kOroTexto),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text.rich(TextSpan(children: [
                        const TextSpan(text: 'Ojo en el examen: ', style: TextStyle(fontWeight: FontWeight.w900)),
                        TextSpan(text: t.topic.trap),
                      ]), style: const TextStyle(color: kInk, fontSize: 12.5, height: 1.45)),
                    ),
                  ]),
                ),
              ],
              if (widget.preguntas.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text('En el ${widget.lastExamLabel}:', style: const TextStyle(color: kMuted, fontSize: 12, fontWeight: FontWeight.w700)),
                  for (final q in widget.preguntas)
                    ActionChip(
                      label: Text('P${q.number}${q.kind != GuideQuestionKind.bloque ? ' · ${tipoPreguntaEstilo[q.kind]!.label.toLowerCase()}' : ''}'),
                      onPressed: () => widget.onPregunta(q.number),
                      visualDensity: VisualDensity.compact,
                      backgroundColor: Colors.white,
                      side: const BorderSide(color: kHairline, width: 1.5),
                      labelStyle: const TextStyle(color: kInk, fontSize: 11.5, fontWeight: FontWeight.w800),
                    ),
                ]),
              ],
            ]),
          ),
      ]),
    );
  }

  Widget _insigniaUltimo() {
    final s = widget.tema.stats;
    final reserva = widget.tema.topic.lastExamReserve;
    if (s.lastExamCount == 0) {
      final sorpresa = esSorpresa(widget.tema);
      return Tooltip(
        message: sorpresa ? 'Suele caer y no cayó: candidato a volver' : '',
        child: PildoraGuia('${widget.lastExamLabel}: 0${sorpresa ? ' · ¡ojo!' : ''}',
            color: sorpresa ? kCoralTexto : kGrisTexto, fondo: sorpresa ? tinted(kCoral, 0.15) : const Color(0xFFF2EFED)),
      );
    }
    return PildoraGuia('${widget.lastExamLabel}: ${s.lastExamCount}${reserva > 0 ? ' ($reserva de reserva)' : ''}',
        color: Colors.white, fondo: kInk);
  }

  /// La evolución del tema en el MIR: una barra por año, la banda de los últimos 5 y la previsión.
  Widget _evolucion() {
    final t = widget.tema;
    final s = t.stats;
    final years = widget.years;
    final inicioReciente = years.length - recentWindow;
    final escala = widget.maxYearCount < 1 ? 1 : widget.maxYearCount;
    final trend = trendEstilo[s.trend]!;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFFFAF7F4), borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Evolución en el MIR', style: TextStyle(color: kInk, fontSize: 12.5, fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        SizedBox(
          height: 70,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (var i = 0; i < t.perYear.length; i++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1.5),
                  child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                    Text('${t.perYear[i]}',
                        style: TextStyle(color: i >= inicioReciente ? kInk : kMuted, fontSize: 9.5, fontWeight: FontWeight.w800)),
                    Container(
                      height: t.perYear[i] == 0 ? 2 : t.perYear[i] / escala * 46,
                      decoration: BoxDecoration(
                        color: i == years.length - 1 ? kCoral : (i >= inicioReciente ? kCoral.withValues(alpha: 0.55) : const Color(0xFFD5CFCB)),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                      ),
                    ),
                  ]),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 3),
        Row(children: [
          for (final y in years)
            Expanded(child: Text(anioCorto(y), textAlign: TextAlign.center, style: const TextStyle(color: kMuted, fontSize: 8.5))),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 10, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          PildoraGuia(trend.label, icono: trend.icono, color: trend.texto, fondo: trend.fondo),
          Text.rich(TextSpan(children: [
            TextSpan(text: '${s.recentCount}', style: const TextStyle(fontWeight: FontWeight.w900, color: kInk)),
            TextSpan(text: ' ${s.recentCount == 1 ? 'pregunta' : 'preguntas'} en los últimos $recentWindow · '),
            TextSpan(text: formatAvg(s.recentAvg), style: const TextStyle(fontWeight: FontWeight.w900, color: kInk)),
            TextSpan(text: '/año (antes ${formatAvg(s.earlierAvg)}/año)'),
          ]), style: const TextStyle(color: kMuted, fontSize: 12)),
          Text.rich(TextSpan(children: [
            const TextSpan(text: 'cayó en '),
            TextSpan(text: '${s.recentHits} de $recentWindow', style: const TextStyle(fontWeight: FontWeight.w900, color: kInk)),
          ]), style: const TextStyle(color: kMuted, fontSize: 12)),
          Text.rich(TextSpan(children: [
            TextSpan(text: 'Previsión ${widget.targetExam}: '),
            TextSpan(text: formatForecast(s.forecast), style: const TextStyle(fontWeight: FontWeight.w900, color: kCoralTexto)),
          ]), style: const TextStyle(color: kMuted, fontSize: 12)),
        ]),
      ]),
    );
  }
}
