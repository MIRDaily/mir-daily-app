/* ════════════════════════════════════════════════════════════════════════
   Los desafíos del día y de la semana.

   El bloque semanal se muestra siempre, incluso vacío de progreso: es el que
   sostiene la vuelta el lunes, y esconderlo hasta que haya avance lo haría
   invisible justo cuando más falta hace.

   EL CONTADOR DE LA CABECERA EXCLUYE `all_daily`. "Día redondo" es el bono por
   completar los otros tres, no un cuarto desafío: contarlo daría "1/4" cuando
   el usuario ve tres tareas.
═══════════════════════════════════════════════════════════════════════════ */
import 'package:flutter/material.dart';

import '../../../core/models/progress.dart';
import '../../../core/responsive/breakpoints.dart';
import '../../../shared/sticker/sticker.dart';
import 'tarjeta_nivel.dart' show miles;

const Color _kHecho = Color(0xFF8BA888);
const Color _kEnCurso = Color(0xFFD18D80);

class SeccionDesafios extends StatelessWidget {
  final ProgressSnapshot? snapshot;
  final bool loading;

  const SeccionDesafios({
    super.key,
    required this.snapshot,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final s = snapshot;

    if (s == null || (s.daily.isEmpty && s.weekly.isEmpty)) {
      if (!loading) return const SizedBox.shrink();
      return const StickerCard(
        padding: EdgeInsets.all(20),
        child: Text(
          'Cargando tus desafíos…',
          style: TextStyle(fontSize: 14, color: kMuted),
        ),
      );
    }

    final hoy = <Widget>[
      if (s.daily.isNotEmpty) ...[
        SectionLabel(
          'Desafíos de hoy',
          trailing: Text(
            '${s.dailyHechos}/${s.dailyReales.length}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: kMuted,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
        for (final c in s.daily) _FilaDesafio(c: c),
      ],
    ];

    final semana = <Widget>[
      if (s.weekly.isNotEmpty) ...[
        const SectionLabel('Esta semana'),
        for (final c in s.weekly) _FilaDesafio(c: c),
      ],
    ];

    // En apaisado (y en tablet) los dos bloques van uno al lado del otro, como
    // en la web: siete tarjetas en una sola columna obligan a un scroll largo
    // justo donde hay ancho de sobra. En vertical se apilan.
    if (context.isWide && hoy.isNotEmpty && semana.isNotEmpty) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: hoy,
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: semana,
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...hoy,
        if (hoy.isNotEmpty && semana.isNotEmpty) const SizedBox(height: 20),
        ...semana,
      ],
    );
  }
}

class _FilaDesafio extends StatelessWidget {
  final Challenge c;

  const _FilaDesafio({required this.c});

  @override
  Widget build(BuildContext context) {
    final hecho = c.completed;
    final color = hecho ? _kHecho : _kEnCurso;

    return StickerCard(
      depth: 3,
      radius: 16,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      background: hecho ? tinted(_kHecho, 0.10) : Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (hecho) ...[
                          const Icon(
                            Icons.check_circle_rounded,
                            size: 17,
                            color: _kHecho,
                          ),
                          const SizedBox(width: 5),
                        ],
                        Flexible(
                          child: Text(
                            c.title,
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w900,
                              color: kInk,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      c.description,
                      style: const TextStyle(fontSize: 12.5, color: kMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: hecho ? _kHecho : const Color(0xFFF3EFED),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  '+${miles(c.xpReward)} XP',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: hecho ? Colors.white : kMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    height: 8,
                    color: const Color(0xFFF3EFED),
                    alignment: Alignment.centerLeft,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: c.fraccion),
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 600),
                      curve: kEaseOut,
                      builder: (context, v, _) => FractionallySizedBox(
                        widthFactor: v,
                        child: Container(
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${miles(c.progress)}/${miles(c.target)}',
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: kMuted,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
