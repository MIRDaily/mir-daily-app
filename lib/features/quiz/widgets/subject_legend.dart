import 'package:flutter/material.dart';

import '../../../core/data/subject_visuals.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/sticker/sticker.dart';

/// Leyenda al pie del sobre: qué significan las siglas de las cartas reveladas
/// (`CD · Cardiología`). Solo las asignaturas del sobre de hoy, sin repetir.
///
/// Entra y sale con un fundido corto: la monta y desmonta el propio juego
/// (`PackGameBase.legendOverlay`) al revelar y al recoger las cartas.
class SubjectLegend extends StatefulWidget {
  final List<String> specialties;

  const SubjectLegend({super.key, required this.specialties});

  @override
  State<SubjectLegend> createState() => _SubjectLegendState();
}

class _SubjectLegendState extends State<SubjectLegend>
    with SingleTickerProviderStateMixin {
  late final AnimationController _in;

  @override
  void initState() {
    super.initState();
    _in = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _in.forward();
  }

  @override
  void dispose() {
    _in.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Sigla -> nombre, en el orden en que salieron y sin duplicar asignatura.
    final seen = <String>{};
    final entries = <({String sigla, String name})>[];
    for (final raw in widget.specialties) {
      final sigla = subjectVisual(raw).sigla;
      if (seen.add(sigla)) entries.add((sigla: sigla, name: raw));
    }
    if (entries.isEmpty) return const SizedBox.shrink();

    final fade = CurvedAnimation(parent: _in, curve: Curves.easeOut);

    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
          child: FadeTransition(
            opacity: fade,
            child: SlideTransition(
              position: Tween(
                begin: const Offset(0, 0.35),
                end: Offset.zero,
              ).animate(fade),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: kInk, width: 2),
                  boxShadow: inkShadow(4),
                ),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 14,
                  runSpacing: 6,
                  children: [
                    for (final e in entries)
                      RichText(
                        text: TextSpan(
                          style: const TextStyle(
                            fontSize: 12,
                            height: 1.1,
                            color: AppColors.textSecondary,
                          ),
                          children: [
                            TextSpan(
                              text: e.sigla,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                color: kInk,
                                letterSpacing: 0.3,
                              ),
                            ),
                            const TextSpan(text: '  '),
                            TextSpan(text: e.name),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
