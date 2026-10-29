// Piezas visuales de las flashcards compartidas por la lista, el grupo y el estudio: tonos de los
// cuatro cubos, insignia de nivel, contadores de la lista tipo Anki, barra de dominio y la identidad
// (color e icono) de un grupo. Puerto de la web: STATUS_TONE (studio/deckUi.tsx), LEVEL_INFO
// (lib/studioFlashcards.ts), NivelBadge, Count, DUE_TONE y MasteryBar (flashcards/SubjectList.tsx).

import 'package:flutter/material.dart';

import '../../../core/models/flashcards.dart';
import '../../../core/models/models.dart';
import '../../../shared/sticker/sticker.dart';
import '../../resumenes/resumenes_grupo.dart';

/// Tono de un cubo (o de una columna de la lista).
class FlashTone {
  final Color fg, bg, border;

  const FlashTone(this.fg, this.bg, this.border);
}

const Map<FlashStatus, FlashTone> kFlashStatusTone = {
  FlashStatus.nueva: FlashTone(Color(0xFF5D7A93), Color(0xFFEAF0F5), Color(0xFFCBD9E3)),
  FlashStatus.failed: FlashTone(Color(0xFFC4655A), Color(0xFFFFF1EE), Color(0xFFF1C6BD)),
  FlashStatus.learning: FlashTone(Color(0xFFB4831F), Color(0xFFFBF3E1), Color(0xFFEBD6A3)),
  FlashStatus.mastered: FlashTone(Color(0xFF5C7A59), Color(0xFFEAF2E8), Color(0xFFCFE0CC)),
};

/// La columna «Repasos» de la lista (vencidas ya vistas, sin las falladas).
const FlashTone kDueTone = FlashTone(Color(0xFF5C7A59), Color(0xFFEAF2E8), Color(0xFFCFE0CC));

const Map<FlashStatus, String> kFlashStatusLabel = {
  FlashStatus.nueva: 'Nuevas',
  FlashStatus.failed: 'Falladas',
  FlashStatus.learning: 'En aprendizaje',
  FlashStatus.mastered: 'Dominadas',
};

/// Color de un nivel de dificultad (y su fondo suave).
const Map<int, ({Color color, Color soft})> kLevelColor = {
  1: (color: Color(0xFF5E8C5A), soft: Color(0xFFE7F0E5)),
  2: (color: Color(0xFF3F7EA6), soft: Color(0xFFE3EEF5)),
  3: (color: Color(0xFFB07A1E), soft: Color(0xFFFBF0DA)),
  4: (color: Color(0xFFB04A5E), soft: Color(0xFFFAE3E8)),
};

/// Los cuatro botones de respuesta: grado, nombre, icono y colores.
const List<({int grade, String label, IconData icon, Color fg, Color bg})> kGradeButtons = [
  (grade: 1, label: 'Otra vez', icon: Icons.replay_rounded, fg: Color(0xFFC4655A), bg: Color(0xFFFFF1EE)),
  (grade: 2, label: 'Difícil', icon: Icons.trending_down_rounded, fg: Color(0xFFB4831F), bg: Color(0xFFFBF3E1)),
  (grade: 3, label: 'Bien', icon: Icons.check_rounded, fg: Color(0xFF5C7A59), bg: Color(0xFFEAF2E8)),
  (grade: 4, label: 'Fácil', icon: Icons.bolt_rounded, fg: Color(0xFF4E7C9B), bg: Color(0xFFE7F0F6)),
];

/// Insignia del nivel de una tarjeta: cuatro puntos y el nombre.
class NivelBadge extends StatelessWidget {
  final int nivel;
  final bool grande;

  const NivelBadge(this.nivel, {super.key, this.grande = false});

  @override
  Widget build(BuildContext context) {
    final c = kLevelColor[nivel] ?? kLevelColor[1]!;
    return Semantics(
      label: 'Nivel $nivel: ${nombreNivel(nivel).toLowerCase()}',
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: grande ? 10 : 8, vertical: grande ? 4 : 2),
        decoration: BoxDecoration(
          color: c.soft,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: c.color, width: 1.5),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (var k = 1; k <= 4; k++)
            Container(
              margin: const EdgeInsets.only(right: 2),
              width: 6,
              height: 6,
              decoration: BoxDecoration(shape: BoxShape.circle, color: k <= nivel ? c.color : c.color.withOpacity(0.2)),
            ),
          const SizedBox(width: 4),
          Text(
            nombreNivel(nivel),
            style: TextStyle(color: c.color, fontSize: grande ? 12 : 11, fontWeight: FontWeight.w800),
          ),
        ]),
      ),
    );
  }
}

/// Un contador de la lista tipo Anki. A cero se pinta apagado.
class CountPill extends StatelessWidget {
  final int value;
  final FlashTone tone;

  const CountPill(this.value, this.tone, {super.key});

  @override
  Widget build(BuildContext context) {
    final on = value > 0;
    return Container(
      width: 40,
      padding: const EdgeInsets.symmetric(vertical: 4),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: on ? tone.bg : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: on ? tone.border : Colors.transparent),
      ),
      child: Text(
        '$value',
        style: TextStyle(
          color: on ? tone.fg : const Color(0xFFC9CFD5),
          fontSize: 13,
          fontWeight: FontWeight.w900,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// Las tres columnas de una fila: nuevas, falladas y lo que toca repasar (disjuntas).
class WorkCounts extends StatelessWidget {
  final int nuevas, falladas, repasos;

  const WorkCounts({super.key, required this.nuevas, required this.falladas, required this.repasos});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$nuevas nuevas, $falladas falladas, $repasos por repasar',
      excludeSemantics: true,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        CountPill(nuevas, kFlashStatusTone[FlashStatus.nueva]!),
        const SizedBox(width: 3),
        CountPill(falladas, kFlashStatusTone[FlashStatus.failed]!),
        const SizedBox(width: 3),
        CountPill(repasos, kDueTone),
      ]),
    );
  }
}

/// Rótulo de las tres columnas, alineado con [WorkCounts].
class WorkCountsHeader extends StatelessWidget {
  final double trailing;

  const WorkCountsHeader({super.key, this.trailing = 0});

  @override
  Widget build(BuildContext context) {
    Widget col(String t, Color c) => SizedBox(
          width: 43,
          child: Text(t, textAlign: TextAlign.center, style: TextStyle(color: c, fontSize: 8.5, fontWeight: FontWeight.w900, letterSpacing: 0.6)),
        );
    return Padding(
      padding: EdgeInsets.only(right: trailing),
      child: Row(children: [
        const Spacer(),
        col('NUEVAS', kFlashStatusTone[FlashStatus.nueva]!.fg),
        col('FALLADAS', kFlashStatusTone[FlashStatus.failed]!.fg),
        col('REPASOS', kDueTone.fg),
      ]),
    );
  }
}

/// Dominio: barra fina con el porcentaje de dominadas.
class MasteryBar extends StatelessWidget {
  final int percent;
  final int total;

  const MasteryBar({super.key, required this.percent, required this.total});

  @override
  Widget build(BuildContext context) {
    final color = percent >= 70
        ? kFlashStatusTone[FlashStatus.mastered]!.fg
        : percent >= 35
            ? kFlashStatusTone[FlashStatus.learning]!.fg
            : const Color(0xFFB0B8BF);
    return Row(children: [
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: total > 0 ? percent / 100 : 0,
            minHeight: 5,
            backgroundColor: const Color(0xFFEFEAE7),
            color: color,
          ),
        ),
      ),
      const SizedBox(width: 8),
      Text(
        total > 0 ? '$percent%' : '—',
        style: const TextStyle(color: kMuted, fontSize: 11, fontWeight: FontWeight.w800),
      ),
    ]);
  }
}

/// Color de la paleta para un grupo: el elegido a mano o el de su asignatura.
SubjectColor colorDeGrupo(FlashDeck d) => resolveColorResumen(visualAsignatura(d.name, d.color, d.icon).color);

/// Icono de un grupo: el elegido a mano o el de su asignatura (claves de la web).
IconData iconoDeGrupo(FlashDeck d) => iconoAsignatura(visualAsignatura(d.name, d.color, d.icon).icon);

IconData iconoAsignatura(String key) => switch (key) {
      'analytics' => Icons.analytics_rounded,
      'dermatology' => Icons.face_retouching_natural_rounded,
      'monitor_weight' => Icons.monitor_weight_rounded,
      'child_care' => Icons.child_care_rounded,
      'rheumatology' => Icons.accessibility_new_rounded,
      'pregnant_woman' => Icons.pregnant_woman_rounded,
      'visibility' => Icons.visibility_rounded,
      'hearing' => Icons.hearing_rounded,
      'water_drop' => Icons.water_drop_rounded,
      _ => iconoGrupoResumen(key),
    };

/// Los cuatro cubos de un grupo o tema, en losetas (la cabecera de una asignatura en la web).
class SummaryTiles extends StatelessWidget {
  final FlashSummary summary;
  final int total;

  const SummaryTiles({super.key, required this.summary, required this.total});

  static const _iconos = {
    FlashStatus.nueva: Icons.fiber_new_rounded,
    FlashStatus.failed: Icons.close_rounded,
    FlashStatus.learning: Icons.trending_up_rounded,
    FlashStatus.mastered: Icons.verified_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final dominio = total > 0 ? (summary.mastered * 100 / total).round() : 0;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        const Text('DOMINIO', style: TextStyle(color: kMuted, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.4)),
        const SizedBox(width: 10),
        Expanded(child: MasteryBar(percent: dominio, total: total)),
      ]),
      const SizedBox(height: 10),
      LayoutBuilder(builder: (context, c) {
        final cols = c.maxWidth >= 520 ? 4 : 2;
        final w = (c.maxWidth - 8 * (cols - 1)) / cols;
        return Wrap(spacing: 8, runSpacing: 8, children: [
          for (final s in FlashStatus.values)
            SizedBox(
              width: w,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: kFlashStatusTone[s]!.bg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: kFlashStatusTone[s]!.border),
                ),
                child: Row(children: [
                  Icon(_iconos[s], size: 18, color: kFlashStatusTone[s]!.fg),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${summary.of(s)}', style: TextStyle(color: kFlashStatusTone[s]!.fg, fontSize: 16, fontWeight: FontWeight.w900)),
                      Text(
                        kFlashStatusLabel[s]!.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: kMuted, fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.5),
                      ),
                    ]),
                  ),
                ]),
              ),
            ),
        ]);
      }),
    ]);
  }
}
