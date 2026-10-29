import 'package:flutter/material.dart';

import '../../../core/models/guias.dart';
import '../../../shared/sticker/sticker.dart';

/* ════════════════════════════════════════════════════════════════════════
   Estilos de la guía de estudio. Los mismos colores que guideStyles.ts de
   la web: coral (imprescindible), salvia (alta), oro viejo (media) y gris
   (pasada rápida); tendencia al alza en coral y a la baja en azul.
═══════════════════════════════════════════════════════════════════════════ */

const kCoral = Color(0xFFE8A598);
const kCoralTexto = Color(0xFFB5655A);
const kSalvia = Color(0xFF8BA888);
const kSalviaTexto = Color(0xFF5E7D5B);
const kOro = Color(0xFFD9B26F);
const kOroTexto = Color(0xFF946C2C);
const kGrisBaja = Color(0xFFBFC7CE);
const kGrisTexto = Color(0xFF6B7884);
const kAzulBaja = Color(0xFF8FA9C2);
const kAzulTexto = Color(0xFF4F6D8A);

final tierEstilo = <GuideTier, ({String label, Color color, Color texto, Color fondo})>{
  GuideTier.imprescindible: (label: 'Imprescindible', color: kCoral, texto: kCoralTexto, fondo: tinted(kCoral, 0.15)),
  GuideTier.alta: (label: 'Prioridad alta', color: kSalvia, texto: kSalviaTexto, fondo: tinted(kSalvia, 0.15)),
  GuideTier.media: (label: 'Prioridad media', color: kOro, texto: kOroTexto, fondo: tinted(kOro, 0.2)),
  GuideTier.baja: (label: 'Pasada rápida', color: kGrisBaja, texto: kGrisTexto, fondo: const Color(0xFFEAE4E2)),
};

final trendEstilo = <GuideTrend, ({String label, IconData icono, Color texto, Color fondo})>{
  GuideTrend.sube: (label: 'Al alza', icono: Icons.trending_up_rounded, texto: kCoralTexto, fondo: tinted(kCoral, 0.15)),
  GuideTrend.estable: (label: 'Estable', icono: Icons.trending_flat_rounded, texto: kGrisTexto, fondo: const Color(0xFFF2EFED)),
  GuideTrend.baja: (label: 'A la baja', icono: Icons.trending_down_rounded, texto: kAzulTexto, fondo: tinted(kAzulBaja, 0.2)),
};

final tipoPreguntaEstilo = <GuideQuestionKind, ({String label, Color texto, Color fondo})>{
  GuideQuestionKind.bloque: (label: 'Bloque', texto: Colors.white, fondo: kInk),
  GuideQuestionKind.reserva: (label: 'Reserva', texto: kOroTexto, fondo: tinted(kOro, 0.2)),
  GuideQuestionKind.frontera: (label: 'Otra asignatura', texto: kGrisTexto, fondo: const Color(0xFFEAE4E2)),
};

/// Color de una celda del mapa de calor según las preguntas de ese año (0 → 4+).
({Color fondo, Color texto}) colorCalor(int n) {
  if (n <= 0) return (fondo: const Color(0xFFF4F1EF), texto: Colors.transparent);
  if (n == 1) return (fondo: tinted(kCoral, 0.25), texto: kCoralTexto);
  if (n == 2) return (fondo: tinted(kCoral, 0.55), texto: const Color(0xFF8F4A40));
  if (n == 3) return (fondo: kCoral, texto: Colors.white);
  return (fondo: const Color(0xFFC97B6D), texto: Colors.white);
}

/// Los Material Symbols que usan las guías en sus conclusiones, en su equivalente de Flutter.
IconData iconoGuia(String nombre) => switch (nombre) {
      'hub' => Icons.hub_rounded,
      'trending_up' => Icons.trending_up_rounded,
      'trending_down' => Icons.trending_down_rounded,
      'event_busy' => Icons.event_busy_rounded,
      'equalizer' => Icons.equalizer_rounded,
      'emergency' => Icons.emergency_rounded,
      'visibility' => Icons.visibility_rounded,
      'vaccines' => Icons.vaccines_rounded,
      'science' => Icons.science_rounded,
      'report' => Icons.report_rounded,
      'photo_camera' => Icons.photo_camera_rounded,
      'neurology' => Icons.psychology_rounded,
      'menu_book' => Icons.menu_book_rounded,
      'medication' => Icons.medication_rounded,
      'image' => Icons.image_rounded,
      'crisis_alert' => Icons.crisis_alert_rounded,
      'content_cut' => Icons.content_cut_rounded,
      'child_care' => Icons.child_care_rounded,
      'bolt' => Icons.bolt_rounded,
      'biotech' => Icons.biotech_rounded,
      'bedtime' => Icons.bedtime_rounded,
      'insights' => Icons.insights_rounded,
      _ => Icons.lightbulb_rounded,
    };

/// «'26»: el año corto de los ejes.
String anioCorto(int year) => "'${'$year'.length >= 4 ? '$year'.substring(2) : year}";

/// Una píldora de color (prioridad, tendencia, tipo de pregunta).
class PildoraGuia extends StatelessWidget {
  final String texto;
  final Color color;
  final Color fondo;
  final IconData? icono;
  const PildoraGuia(this.texto, {super.key, required this.color, required this.fondo, this.icono});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(99)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icono != null) ...[Icon(icono, size: 13, color: color), const SizedBox(width: 3)],
          Flexible(
            child: Text(texto,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.2)),
          ),
        ]),
      );
}

/// «Ordenar por: Previsión · Histórico · Tendencia».
class SelectorOrdenGuia extends StatelessWidget {
  final GuideSortKey valor;
  final ValueChanged<GuideSortKey> onChanged;
  const SelectorOrdenGuia({super.key, required this.valor, required this.onChanged});

  @override
  Widget build(BuildContext context) => Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 6,
        runSpacing: 6,
        children: [
          const Text('Ordenar por', style: TextStyle(color: kMuted, fontSize: 12, fontWeight: FontWeight.w700)),
          for (final k in GuideSortKey.values)
            ChoiceChip(
              label: Text(kNombreOrdenGuia[k]!),
              selected: valor == k,
              showCheckmark: false,
              visualDensity: VisualDensity.compact,
              onSelected: (_) => onChanged(k),
              selectedColor: kInk,
              backgroundColor: Colors.white,
              side: BorderSide(color: valor == k ? kInk : kHairline, width: 1.5),
              labelStyle: TextStyle(color: valor == k ? Colors.white : kInk, fontWeight: FontWeight.w800, fontSize: 12),
            ),
        ],
      );
}

/// La cabecera de cada apartado: icono, título y subtítulo.
class TituloApartado extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String subtitulo;
  final bool mayor;
  const TituloApartado({super.key, required this.icono, required this.titulo, required this.subtitulo, this.mayor = false});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: mayor ? 40 : 34,
            height: mayor ? 40 : 34,
            decoration: BoxDecoration(
              color: mayor ? kCoral : const Color(0xFFFFF4EF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kInk, width: 2),
            ),
            child: Icon(icono, size: mayor ? 22 : 18, color: mayor ? Colors.white : kCoralTexto),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(titulo, style: TextStyle(color: kInk, fontSize: mayor ? 20 : 17, fontWeight: FontWeight.w900, height: 1.2)),
              const SizedBox(height: 2),
              Text(subtitulo, style: const TextStyle(color: kMuted, fontSize: 12.5, height: 1.4)),
            ]),
          ),
        ]),
      );
}
