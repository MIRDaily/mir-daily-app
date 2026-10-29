import 'package:flutter/material.dart';

import '../../../core/models/guias.dart';
import '../../../core/models/reportes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/report/report_button.dart';
import '../../../shared/sticker/sticker.dart';
import '../../../shared/widgets/zoomable_image.dart';
import 'guia_estilos.dart';

/// Resultado de corregirse una pregunta de la guía. Solo vive en memoria: no se guarda ni cuenta para
/// las estadísticas. Puerto de GuideQuiz.tsx.
enum ResultadoQuiz { acierto, fallo, sinMarcar }

class QuizGuia extends ChangeNotifier {
  final Map<int, ResultadoQuiz> resultados = {};

  /// Cambia con «Empezar de nuevo»: cada tarjeta lo escucha para limpiarse.
  int vuelta = 0;

  void apuntar(int pregunta, ResultadoQuiz? r) {
    final antes = resultados[pregunta];
    if (r == null) {
      resultados.remove(pregunta);
    } else {
      resultados[pregunta] = r;
    }
    if (antes != r) notifyListeners();
  }

  void reiniciar() {
    resultados.clear();
    vuelta++;
    notifyListeners();
  }
}

/// «3 de 11 corregidas · 2 aciertos · 1 fallo · Empezar de nuevo».
class MarcadorQuiz extends StatelessWidget {
  final QuizGuia quiz;
  final int total;
  const MarcadorQuiz({super.key, required this.quiz, required this.total});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: quiz,
        builder: (context, _) {
          final v = quiz.resultados.values;
          final corregidas = v.length;
          final aciertos = v.where((r) => r == ResultadoQuiz.acierto).length;
          final fallos = v.where((r) => r == ResultadoQuiz.fallo).length;
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: kInk, width: 2), boxShadow: inkShadow(3)),
            child: corregidas == 0
                ? const Row(children: [
                    Icon(Icons.fact_check_rounded, color: kCoralTexto),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text('Marca tu respuesta y pulsa «Corregir». Nada de esto se guarda ni cuenta para tus estadísticas.',
                          style: TextStyle(color: kMuted, fontSize: 12.5, height: 1.4)),
                    ),
                  ])
                : Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    const Icon(Icons.fact_check_rounded, color: kCoralTexto),
                    Text('$corregidas de $total corregidas', style: const TextStyle(color: kInk, fontWeight: FontWeight.w900, fontSize: 13)),
                    PildoraGuia('$aciertos ${aciertos == 1 ? 'acierto' : 'aciertos'}', color: kSalviaTexto, fondo: tinted(kSalvia, 0.18)),
                    PildoraGuia('$fallos ${fallos == 1 ? 'fallo' : 'fallos'}', color: AppColors.error, fondo: tinted(AppColors.error, 0.12)),
                    if (corregidas - aciertos - fallos > 0)
                      PildoraGuia('${corregidas - aciertos - fallos} sin marcar', color: kGrisTexto, fondo: const Color(0xFFF2EFED)),
                    TextButton.icon(
                      onPressed: quiz.reiniciar,
                      icon: const Icon(Icons.restart_alt_rounded, size: 18),
                      label: const Text('Empezar de nuevo'),
                      style: TextButton.styleFrom(foregroundColor: kCoralTexto, visualDensity: VisualDensity.compact),
                    ),
                  ]),
          );
        },
      );
}

/// Una pregunta del último MIR comentado: se marca una opción y se corrige (o «Ver respuesta»), con la
/// explicación y «Repasar el tema». La elección no se guarda. Se puede reportar como trozo de la guía.
class PreguntaGuia extends StatefulWidget {
  final GuideQuestion pregunta;
  final StudyGuide guia;
  final QuizGuia quiz;
  final ValueChanged<String>? onTema;
  const PreguntaGuia({super.key, required this.pregunta, required this.guia, required this.quiz, this.onTema});

  @override
  State<PreguntaGuia> createState() => _PreguntaGuiaState();
}

class _PreguntaGuiaState extends State<PreguntaGuia> {
  int? _elegida;
  bool _corregida = false;
  // No `late`: se inicializaría al leerlo por primera vez, ya con la vuelta nueva, y nunca vería el cambio.
  int _vuelta = 0;

  @override
  void initState() {
    super.initState();
    _vuelta = widget.quiz.vuelta;
    widget.quiz.addListener(_alReiniciar);
  }

  @override
  void dispose() {
    widget.quiz.removeListener(_alReiniciar);
    super.dispose();
  }

  void _alReiniciar() {
    if (widget.quiz.vuelta == _vuelta || !mounted) return;
    setState(() {
      _vuelta = widget.quiz.vuelta;
      _elegida = null;
      _corregida = false;
    });
  }

  void _corregir() {
    setState(() => _corregida = true);
    final q = widget.pregunta;
    widget.quiz.apuntar(q.number, _elegida == null ? ResultadoQuiz.sinMarcar : (_elegida == q.correct ? ResultadoQuiz.acierto : ResultadoQuiz.fallo));
  }

  void _reintentar() {
    setState(() {
      _elegida = null;
      _corregida = false;
    });
    widget.quiz.apuntar(widget.pregunta.number, null);
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.pregunta;
    final g = widget.guia;
    final acierto = _elegida == q.correct;
    final tipo = tipoPreguntaEstilo[q.kind]!;
    final borde = _corregida && _elegida != null ? (acierto ? kSalvia : AppColors.error) : kHairline;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: borde, width: 2)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text('${g.lastExam} · P${q.number}', style: const TextStyle(color: kInk, fontSize: 12.5, fontWeight: FontWeight.w900)),
              PildoraGuia(tipo.label, color: tipo.texto, fondo: tipo.fondo),
              Text(q.tag, style: const TextStyle(color: kMuted, fontSize: 11.5, fontWeight: FontWeight.w700)),
            ]),
          ),
          // La guía vive en la app: la foto la manda el cliente, como en la web.
          ReportButton(
            questionId: null,
            guideRef: refGuia(g.subjectId, q.number),
            snapshot: {
              'guide_title': g.title,
              'number': q.number,
              'stem': q.stem,
              'options': q.options,
              'correct': q.correct,
              'explanation': q.explanation,
              'imageUrl': q.imageUrl,
            },
            contexto: ContextoReporte(
              origin: OrigenReporte.guide,
              answered: _corregida,
              userAnswer: _corregida ? _elegida : null,
              isCorrect: _corregida && _elegida != null ? acierto : null,
            ),
            optionCount: q.options.length,
            subtitle: '${g.lastExam} · P${q.number}',
          ),
        ]),
        const SizedBox(height: 8),
        Text(q.stem, style: const TextStyle(color: kInk, fontSize: 14.5, height: 1.5, fontWeight: FontWeight.w500)),
        if (q.imageUrl != null) ...[
          const SizedBox(height: 10),
          ZoomableImage(url: q.imageUrl!, borderRadius: BorderRadius.circular(14)),
        ],
        const SizedBox(height: 10),
        for (var i = 0; i < q.options.length; i++) _opcion(i + 1, q.options[i]),
        const SizedBox(height: 6),
        if (!_corregida)
          Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            _elegida != null
                ? StickerButton(label: 'Corregir', icon: Icons.fact_check_rounded, compact: true, onPressed: _corregir)
                : GhostButton(label: 'Ver respuesta', icon: Icons.visibility_rounded, compact: true, onPressed: _corregir),
            if (_elegida == null) const Text('o marca una opción para corregirte', style: TextStyle(color: kMuted, fontSize: 12)),
          ])
        else ...[
          Row(children: [
            Expanded(
              child: _elegida == null
                  ? Text('Sin marcar · la correcta es la ${q.correct}', style: const TextStyle(color: kMuted, fontWeight: FontWeight.w800, fontSize: 13))
                  : acierto
                      ? const Row(children: [
                          Icon(Icons.celebration_rounded, color: kSalviaTexto, size: 18),
                          SizedBox(width: 4),
                          Text('¡Correcta!', style: TextStyle(color: kSalviaTexto, fontWeight: FontWeight.w900, fontSize: 13.5)),
                        ])
                      : Text('Marcaste la $_elegida · la correcta es la ${q.correct}',
                          style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.w800, fontSize: 13)),
            ),
            TextButton.icon(
              onPressed: _reintentar,
              icon: const Icon(Icons.replay_rounded, size: 17),
              label: const Text('Reintentar'),
              style: TextButton.styleFrom(foregroundColor: kMuted, visualDensity: VisualDensity.compact),
            ),
          ]),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFFAF7F4), borderRadius: BorderRadius.circular(14)),
            child: Text(q.explanation, style: const TextStyle(color: kInk, fontSize: 13, height: 1.5)),
          ),
          if (q.topicId != null && widget.onTema != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => widget.onTema!(q.topicId!),
                child: const Text('Repasar el tema →', style: TextStyle(color: kCoralTexto, fontWeight: FontWeight.w900)),
              ),
            ),
        ],
      ]),
    );
  }

  Widget _opcion(int numero, String texto) {
    final q = widget.pregunta;
    final correcta = numero == q.correct;
    final elegida = numero == _elegida;
    var fondo = const Color(0xFFF9F8F7);
    var tinta = kInk;
    var insignia = Colors.white;
    var tintaInsignia = kMuted;
    IconData? marca;
    var opacidad = 1.0;
    if (!_corregida && elegida) {
      fondo = kInk;
      tinta = Colors.white;
      tintaInsignia = kInk;
    }
    if (_corregida) {
      if (correcta) {
        fondo = tinted(kSalvia, 0.15);
        tinta = const Color(0xFF3F5E3C);
        insignia = kSalvia;
        tintaInsignia = Colors.white;
        marca = Icons.check_circle_rounded;
      } else if (elegida) {
        fondo = tinted(AppColors.error, 0.12);
        tinta = const Color(0xFFA4463A);
        insignia = const Color(0xFFD9786B);
        tintaInsignia = Colors.white;
        marca = Icons.cancel_rounded;
      } else {
        opacidad = 0.5;
      }
    }
    return Opacity(
      opacity: opacidad,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Semantics(
          button: !_corregida,
          selected: elegida,
          child: Material(
            color: fondo,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: _corregida ? null : () => setState(() => _elegida = elegida ? null : numero),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                child: Row(children: [
                  Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: insignia, shape: BoxShape.circle, border: Border.all(color: kHairline)),
                    child: Text('$numero', style: TextStyle(color: tintaInsignia, fontSize: 11.5, fontWeight: FontWeight.w900)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(texto, style: TextStyle(color: tinta, fontSize: 13.5, height: 1.35, fontWeight: correcta && _corregida ? FontWeight.w700 : FontWeight.w500))),
                  if (_corregida && elegida)
                    const Padding(
                      padding: EdgeInsets.only(left: 6),
                      child: Text('Tu respuesta', style: TextStyle(color: kMuted, fontSize: 10.5, fontWeight: FontWeight.w800)),
                    ),
                  if (marca != null) ...[const SizedBox(width: 6), Icon(marca, size: 18, color: insignia)],
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
