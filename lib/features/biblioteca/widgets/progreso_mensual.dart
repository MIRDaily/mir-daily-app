import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/progreso_semana.dart';
import '../../../core/services/api_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/sticker/sticker.dart';

/// «Progreso Mensual» de la portada de Studio (GET /api/analytics/monthly-progress): preguntas repasadas
/// en los últimos 30 días, su variación frente a los 30 anteriores y el total del año. Como la tarjeta de
/// /studio en la web. Es un extra: si falla o aún no hay datos, no ocupa sitio.
class ProgresoMensualCard extends StatefulWidget {
  const ProgresoMensualCard({super.key});

  @override
  State<ProgresoMensualCard> createState() => _ProgresoMensualCardState();
}

class _ProgresoMensualCardState extends State<ProgresoMensualCard> {
  ProgresoMensual? _p;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final p = await context.read<ApiService>().getMonthlyProgress();
      if (mounted) setState(() => _p = p);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    if (p == null || (p.mes == 0 && p.anio == 0)) return const SizedBox.shrink();
    final t = textoProgresoMensual(p);
    final colorInsignia = t.signo > 0 ? AppColors.successDark : (t.signo < 0 ? AppColors.error : kMuted);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Semantics(
        label: 'Progreso mensual: ${t.valor} preguntas en 30 días${t.insignia != null ? ', ${t.insignia}' : ''}. ${t.detalle}',
        excludeSemantics: true,
        child: StickerCard(
          depth: 3,
          radius: 18,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: tinted(AppColors.success, 0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: kInk, width: 2),
              ),
              child: const Icon(Icons.trending_up_rounded, color: AppColors.successDark),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('PROGRESO MENSUAL',
                    style: TextStyle(color: kMuted, fontSize: 10.5, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
                const SizedBox(height: 2),
                Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 2, children: [
                  Text(t.valor, style: const TextStyle(color: kInk, fontSize: 22, fontWeight: FontWeight.w900, height: 1.1)),
                  if (t.insignia != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: tinted(colorInsignia, 0.14),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(t.insignia!,
                          style: TextStyle(color: colorInsignia, fontSize: 11.5, fontWeight: FontWeight.w900)),
                    ),
                ]),
                const SizedBox(height: 2),
                Text(t.detalle, style: const TextStyle(color: kMuted, fontSize: 12)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
