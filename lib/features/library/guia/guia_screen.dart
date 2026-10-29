import 'package:flutter/material.dart';

import '../../../core/models/guias.dart';
import '../../../core/models/reportes.dart';
import '../../../core/responsive/content_shell.dart';
import '../../../core/services/guias_assets.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/report/report_button.dart';
import '../../../shared/sticker/sticker.dart';
import '../../../shared/sticker/textures.dart';
import 'guia_estilos.dart';
import 'guia_graficos.dart';
import 'guia_preguntas.dart';
import 'guia_temas.dart';

const _grupos = <({GuideQuestionKind kind, String titulo, String indice, String descripcion})>[
  (
    kind: GuideQuestionKind.bloque,
    titulo: 'Bloque de la asignatura',
    indice: 'Bloque de la asignatura',
    descripcion: 'Las que evalúan esta asignatura: las de su bloque y las que salieron sueltas en otras zonas del examen.',
  ),
  (
    kind: GuideQuestionKind.reserva,
    titulo: 'Preguntas de reserva',
    indice: 'Preguntas de reserva',
    descripcion: 'Solo puntúan si se anula alguna, pero dicen qué tenía en mente el tribunal.',
  ),
  (
    kind: GuideQuestionKind.frontera,
    titulo: 'También en otras asignaturas',
    indice: 'Otras asignaturas',
    descripcion: 'Preguntas de otros bloques que se contestan con lo que estudias aquí.',
  ),
];

/// La guía de estudio de una asignatura, nativa: cabecera con cifras, qué nos dice el último MIR,
/// preguntas por año, qué sube y qué baja, mapa de prioridades, evolución tema a tema, esfuerzo y
/// recompensa, plan de estudio, tema a tema y el último MIR comentado. Puerto de
/// src/app/library/[subjectId]/guia/page.tsx; los datos van dentro de la app (assets/guides/).
class GuiaScreen extends StatefulWidget {
  /// La clave de texto de la guía («reumatologia»).
  final String clave;
  const GuiaScreen({super.key, required this.clave});

  @override
  State<GuiaScreen> createState() => _GuiaScreenState();
}

class _GuiaScreenState extends State<GuiaScreen> {
  ResumenGuia? _r;
  String? _error;
  final _quiz = QuizGuia();
  final _claves = <String, GlobalKey>{};
  final _temas = <String, GlobalKey<TarjetaTemaGuiaState>>{};

  GlobalKey _clave(String id) => _claves.putIfAbsent(id, GlobalKey.new);

  @override
  void initState() {
    super.initState();
    GuiasAssets.guia(widget.clave).then((g) {
      if (mounted) setState(() => _r = ResumenGuia.de(g));
    }).catchError((Object _) {
      if (mounted) setState(() => _error = 'No se pudo abrir la guía.');
    });
  }

  @override
  void dispose() {
    _quiz.dispose();
    super.dispose();
  }

  Future<void> _ir(String id) async {
    final c = _claves[id]?.currentContext;
    if (c == null) return;
    await Scrollable.ensureVisible(c, duration: const Duration(milliseconds: 420), curve: kEaseOut, alignment: 0.04);
  }

  void _irATema(String topicId) {
    _temas[topicId]?.currentState?.abrir();
    // Tras abrirse, la tarjeta ya mide lo que mide de verdad.
    WidgetsBinding.instance.addPostFrameCallback((_) => _ir('tema-$topicId'));
  }

  @override
  Widget build(BuildContext context) {
    final r = _r;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        title: Text(r == null ? 'Guía de estudio' : 'Guía · ${r.guia.title}',
            maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: kInk, fontWeight: FontWeight.w900)),
      ),
      body: SafeArea(
        child: r == null
            ? Center(
                child: _error != null
                    ? Text(_error!, style: const TextStyle(color: AppColors.error))
                    : const CircularProgressIndicator(color: AppColors.primary),
              )
            : BodyConstraint(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _contenido(r)),
                ),
              ),
      ),
    );
  }

  List<Widget> _contenido(ResumenGuia r) {
    final g = r.guia;
    final indice = <({String id, String texto, IconData icono})>[
      (id: 'conclusiones', texto: 'Qué nos dice el ${g.lastExam}', icono: Icons.insights_rounded),
      (id: 'tendencia', texto: 'Preguntas por año', icono: Icons.bar_chart_rounded),
      (id: 'tendencias', texto: 'Qué sube y qué baja', icono: Icons.swap_vert_rounded),
      (id: 'prioridades', texto: 'Mapa de prioridades', icono: Icons.format_list_numbered_rounded),
      (id: 'evolucion', texto: 'Evolución tema a tema', icono: Icons.grid_on_rounded),
      (id: 'rentabilidad', texto: 'Esfuerzo y recompensa', icono: Icons.scatter_plot_rounded),
      (id: 'plan', texto: 'Plan de estudio', icono: Icons.route_rounded),
      (id: 'temas', texto: 'Tema a tema', icono: Icons.menu_book_rounded),
      (id: 'ultimo-mir', texto: '${g.lastExam} comentado', icono: Icons.quiz_rounded),
    ];
    final topicsById = {for (final t in r.topics) t.id: t};

    Widget apartado(String id, Widget hijo, {bool tarjeta = true}) => Padding(
          key: _clave(id),
          padding: const EdgeInsets.only(top: 22),
          child: tarjeta
              ? StickerCard(depth: 4, radius: 22, padding: const EdgeInsets.all(16), child: hijo)
              : hijo,
        );

    return [
      // ---- Cabecera
      StickerCard(
        depth: 6,
        radius: 24,
        texture: ruledPaper(step: 26),
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Align(
            alignment: Alignment.centerLeft,
            child: DocChip(label: 'Guía de estudio · ${g.targetExam}', icon: Icons.menu_book_rounded, tone: DocTone.accent),
          ),
          const SizedBox(height: 10),
          Text(g.title, style: const TextStyle(color: kInk, fontSize: 26, fontWeight: FontWeight.w900, height: 1.1, letterSpacing: -0.4)),
          const SizedBox(height: 6),
          Text('${g.subtitle}. Basada en ${g.historyRange} e incluye todas las preguntas del ${g.lastExam}.',
              style: const TextStyle(color: kMuted, fontSize: 13.5, height: 1.45)),
          const SizedBox(height: 16),
          LayoutBuilder(builder: (context, c) {
            final ancho = c.maxWidth >= 560 ? (c.maxWidth - 30) / 4 : (c.maxWidth - 10) / 2;
            Widget tile(String valor, String etiqueta, {bool acento = false}) => Container(
                  width: ancho,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: acento ? const Color(0xFFFFF4EF) : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: acento ? kCoral : kHairline, width: 2),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(valor, style: TextStyle(color: acento ? kCoralTexto : kInk, fontSize: 22, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 2),
                    Text(etiqueta, style: const TextStyle(color: kMuted, fontSize: 11.5, height: 1.3)),
                  ]),
                );
            return Wrap(spacing: 10, runSpacing: 10, children: [
              // Con menos de 10 al año el redondeo engaña (4,5 → 5): un decimal.
              tile(r.average < 10 ? formatAvg(r.average) : '${r.average.round()}', 'preguntas por año de media (${g.historyRange})'),
              tile(
                '${r.lastExamCount}',
                g.lastExamReserveTotal > 0 ? 'en el ${g.lastExam} (${g.lastExamReserveTotal} de reserva)' : 'en el ${g.lastExam}',
                acento: true,
              ),
              tile('${r.topThreeShare}%', 'de las preguntas salen de ${r.topThree.map((t) => t.shortName).join(', ')}'),
              tile('1 de ${r.unaDeCada}', 'preguntas del MIR es de esta asignatura'),
            ]);
          }),
        ]),
      ),
      const SizedBox(height: 14),
      // ---- Índice
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final i in indice)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ActionChip(
                avatar: Icon(i.icono, size: 16, color: kCoralTexto),
                label: Text(i.texto),
                onPressed: () => _ir(i.id),
                backgroundColor: Colors.white,
                side: const BorderSide(color: kHairline, width: 1.5),
                labelStyle: const TextStyle(color: kInk, fontSize: 12, fontWeight: FontWeight.w800),
              ),
            ),
        ]),
      ),
      // ---- Conclusiones
      apartado(
        'conclusiones',
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TituloApartado(mayor: true, icono: Icons.insights_rounded, titulo: 'Qué nos dice el ${g.lastExam}', subtitulo: 'Lo que cambia (y lo que no) de cara a tu examen.'),
          for (final ins in g.insights)
            StickerCard(
              depth: 3,
              radius: 18,
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(color: const Color(0xFFFFF4EF), borderRadius: BorderRadius.circular(11)),
                  child: Icon(iconoGuia(ins.icon), color: kCoralTexto, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(ins.title, style: const TextStyle(color: kInk, fontSize: 14, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 3),
                    Text(ins.body, style: const TextStyle(color: kMuted, fontSize: 12.5, height: 1.45)),
                  ]),
                ),
              ]),
            ),
        ]),
        tarjeta: false,
      ),
      // ---- Preguntas por año
      apartado(
        'tendencia',
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TituloApartado(icono: Icons.bar_chart_rounded, titulo: 'Preguntas por año', subtitulo: '${g.title}, ${r.periodLabel}.'),
          GraficoAnios(perYear: r.perYear, average: r.average, highlightYear: r.lastYear),
          const SizedBox(height: 10),
          Text.rich(TextSpan(children: [
            TextSpan(text: '${r.fraseAnios} '),
            if (r.ultimoPorDebajo) ...[
              const TextSpan(text: 'El '),
              TextSpan(text: g.lastExam, style: const TextStyle(fontWeight: FontWeight.w900, color: kInk)),
              const TextSpan(text: ' se quedó por debajo de la media: lo normal es que el siguiente vuelva a acercarse a ella.'),
            ],
          ]), style: const TextStyle(color: kMuted, fontSize: 12.5, height: 1.45)),
        ]),
      ),
      // ---- Qué sube y qué baja
      apartado(
        'tendencias',
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TituloApartado(
            icono: Icons.swap_vert_rounded,
            titulo: 'Qué sube y qué baja',
            subtitulo: 'Preguntas por año: ${r.earlierLabel} frente a los últimos $recentWindow MIR (${r.recentLabel}).',
          ),
          GraficoTendencias(filas: r.filasTendencia(), earlierLabel: r.earlierLabel, recentLabel: r.recentLabel, onTema: _irATema),
        ]),
      ),
      // ---- Prioridades
      apartado(
        'prioridades',
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TituloApartado(
            icono: Icons.format_list_numbered_rounded,
            titulo: 'Mapa de prioridades',
            subtitulo: 'Ordenado por la previsión para el ${g.targetExam}, que pesa más lo reciente. Toca un tema para ver su resumen.',
          ),
          MapaPrioridades(
            temas: r.topicsByForecast,
            recentYears: r.years.length >= recentWindow ? r.years.sublist(r.years.length - recentWindow) : r.years,
            targetExam: g.targetExam,
            periodLabel: r.periodLabel,
            onTema: _irATema,
          ),
        ]),
      ),
      // ---- Evolución
      apartado(
        'evolucion',
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TituloApartado(icono: Icons.grid_on_rounded, titulo: 'Evolución tema a tema', subtitulo: 'Preguntas de cada tema en cada MIR, ${r.periodLabel}.'),
          MapaCalorGuia(temas: r.topics, years: r.years),
        ]),
      ),
      // ---- Esfuerzo
      apartado(
        'rentabilidad',
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const TituloApartado(icono: Icons.scatter_plot_rounded, titulo: 'Esfuerzo frente a recompensa', subtitulo: 'Dónde rinde más cada hora de estudio.'),
          MatrizEsfuerzo(temas: r.topics, periodLabel: r.periodLabel, onTema: _irATema),
        ]),
      ),
      // ---- Plan
      apartado(
        'plan',
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TituloApartado(
            icono: Icons.route_rounded,
            titulo: 'Si tienes ${r.planDays} días para esta asignatura',
            subtitulo: 'Reparto por vueltas según el peso real de cada tema.',
          ),
          for (var i = 0; i < g.plan.length; i++) _paso(i, g.plan[i], r.planDays, topicsById),
        ]),
      ),
      // ---- Tema a tema
      apartado(
        'temas',
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TituloApartado(
            mayor: true,
            icono: Icons.menu_book_rounded,
            titulo: 'Tema a tema',
            subtitulo: 'De más a menos preguntado (${r.periodLabel}). Cada tema dice dónde se concentran las preguntas y lo que hay que llevar sabido.',
          ),
          for (var i = 0; i < r.topicsByPriority.length; i++)
            KeyedSubtree(
              key: _clave('tema-${r.topicsByPriority[i].id}'),
              child: TarjetaTemaGuia(
                key: _temas.putIfAbsent(r.topicsByPriority[i].id, GlobalKey<TarjetaTemaGuiaState>.new),
                tema: r.topicsByPriority[i],
                years: r.years,
                maxYearCount: r.maxTopicYearCount,
                targetExam: g.targetExam,
                lastExamLabel: g.lastExam,
                preguntas: r.preguntasDeTema(r.topicsByPriority[i].id),
                abiertaDeEntrada: i == 0,
                onPregunta: (n) => _ir('pregunta-$n'),
              ),
            ),
        ]),
        tarjeta: false,
      ),
      // ---- Último MIR comentado
      apartado(
        'ultimo-mir',
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TituloApartado(
            mayor: true,
            icono: Icons.quiz_rounded,
            titulo: '${g.lastExam} comentado',
            subtitulo: 'Marca tu respuesta y corrígete. Respuestas contrastadas con las definitivas publicadas tras las impugnaciones.',
          ),
          MarcadorQuiz(quiz: _quiz, total: g.questions.length),
          for (final grupo in _grupos)
            if (g.questions.any((q) => q.kind == grupo.kind)) ...[
              const SizedBox(height: 18),
              Text.rich(TextSpan(children: [
                TextSpan(text: grupo.titulo),
                TextSpan(
                  text: ' (${g.questions.where((q) => q.kind == grupo.kind).length})',
                  style: const TextStyle(color: kMuted, fontWeight: FontWeight.w700),
                ),
              ]), style: const TextStyle(color: kInk, fontSize: 16, fontWeight: FontWeight.w900)),
              const SizedBox(height: 3),
              Text(grupo.descripcion, style: const TextStyle(color: kMuted, fontSize: 12.5, height: 1.4)),
              const SizedBox(height: 10),
              for (final q in g.questions.where((q) => q.kind == grupo.kind))
                KeyedSubtree(
                  key: _clave('pregunta-${q.number}'),
                  child: PreguntaGuia(pregunta: q, guia: g, quiz: _quiz, onTema: _irATema),
                ),
            ],
        ]),
        tarjeta: false,
      ),
      const SizedBox(height: 18),
      Text(g.sourcesNote, style: const TextStyle(color: kMuted, fontSize: 11.5, height: 1.45)),
      const SizedBox(height: 6),
      Row(children: [
        ReportButton(
          questionId: null,
          guideRef: refGuia(g.subjectId),
          snapshot: {'guide_title': g.title},
          contexto: const ContextoReporte(origin: OrigenReporte.guide, answered: true),
          subtitle: g.title,
        ),
        const Expanded(child: Text('¿Has visto un error en esta guía?', style: TextStyle(color: kMuted, fontSize: 12.5, fontWeight: FontWeight.w700))),
      ]),
    ];
  }

  Widget _paso(int i, GuidePlanStep paso, int total, Map<String, GuideTopicWithStats> temas) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: const Color(0xFFFAF7F4), borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: kInk, borderRadius: BorderRadius.circular(9)),
              child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(paso.title, style: const TextStyle(color: kInk, fontSize: 14, fontWeight: FontWeight.w900)),
                Text(paso.subtitle, style: const TextStyle(color: kMuted, fontSize: 12.5, height: 1.4)),
              ]),
            ),
            const SizedBox(width: 8),
            Text('${paso.days} ${paso.days == 1 ? 'día' : 'días'}', style: const TextStyle(color: kCoralTexto, fontSize: 13, fontWeight: FontWeight.w900)),
          ]),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: Container(
              height: 6,
              color: const Color(0xFFEAE4E2),
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(widthFactor: total == 0 ? 0 : paso.days / total, child: Container(color: kCoral)),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final id in paso.topicIds)
              if (temas[id] != null)
                ActionChip(
                  label: Text(temas[id]!.shortName),
                  onPressed: () => _irATema(id),
                  visualDensity: VisualDensity.compact,
                  backgroundColor: Colors.white,
                  side: const BorderSide(color: kHairline, width: 1.5),
                  labelStyle: const TextStyle(color: kInk, fontSize: 11.5, fontWeight: FontWeight.w800),
                ),
          ]),
        ]),
      );
}
