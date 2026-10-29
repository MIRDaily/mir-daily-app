import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/simulacro_a_medida.dart';
import '../../../core/providers/progress_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/sticker/sticker.dart';
import '../../simulacro/simulacro_a_medida_sheet.dart';

/// La tarjeta destacada de Studio: «Simulacro a tu medida». Dice en qué tema flojeas (del desafío
/// personalizado del día, la misma fuente que la web) y abre la hoja que arma la tanda. Sin un punto
/// débil detectado se pinta apagada y lo explica, como en la web, pero se puede pulsar igual (la web
/// la deja inerte): decide el servidor, y si no hay datos la hoja lo dice con su «Crear un simulacro
/// normal». Además, en el hub toda tarjeta se pulsa.
class AMedidaCard extends StatelessWidget {
  const AMedidaCard({super.key});

  @override
  Widget build(BuildContext context) {
    final punto = puntoDebilDe(context.watch<ProgressProvider?>()?.data?.daily ?? const []);
    final listo = punto != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Semantics(
        button: true,
        label: 'Simulacro a tu medida. ${descripcionAMedida(punto)}',
        excludeSemantics: true,
        child: StickerCard(
          depth: listo ? 5 : 3,
          radius: 22,
          background: listo ? const Color(0xFFFFF4EF) : Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          pressDelay: const Duration(milliseconds: 120),
          onTap: () => abrirSimulacroAMedida(context),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: listo ? AppColors.primary : const Color(0xFFF2EFED),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: kInk, width: 2),
              ),
              child: Icon(Icons.psychology_alt_rounded, color: listo ? Colors.white : kMuted),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (listo) const DocChip(label: 'RECOMENDADO', tone: DocTone.accent),
                if (listo) const SizedBox(height: 6),
                const Text('Simulacro a tu medida',
                    style: TextStyle(color: kInk, fontSize: 16.5, fontWeight: FontWeight.w900)),
                const SizedBox(height: 3),
                Text(descripcionAMedida(punto), style: const TextStyle(color: kMuted, fontSize: 13, height: 1.4)),
                if (listo) ...[
                  const SizedBox(height: 10),
                  const Row(children: [
                    Icon(Icons.play_arrow_rounded, size: 18, color: AppColors.primaryDark),
                    SizedBox(width: 4),
                    Flexible(
                      child: Text('Generar sesión personalizada',
                          style: TextStyle(color: AppColors.primaryDark, fontSize: 13, fontWeight: FontWeight.w900)),
                    ),
                  ]),
                ],
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
