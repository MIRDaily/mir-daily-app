/* ════════════════════════════════════════════════════════════════════════
   El progreso dentro del perfil, debajo del carné.

   Es la misma decisión que en la web: el perfil es la pantalla de "cómo voy" y
   el progreso es exactamente eso.

   OJO CON LO QUE NO VA AQUÍ: el nivel no puede acabar al lado de un porcentaje
   de acierto en la misma tarjeta. El nivel mide constancia —cuántos días has
   aparecido— y la precisión dice si vas a aprobar. Juntarlos haría creer al
   usuario que un nivel alto significa que va a aprobar.
═══════════════════════════════════════════════════════════════════════════ */
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/progress_provider.dart';
import '../../../shared/sticker/sticker.dart';
import '../../progress/widgets/seccion_desafios.dart';
import '../../progress/widgets/tarjeta_nivel.dart';

class ProgressSection extends StatelessWidget {
  const ProgressSection({super.key});

  @override
  Widget build(BuildContext context) {
    final progreso = context.watch<ProgressProvider>();
    final snapshot = progreso.data;

    // Sin datos y sin estar cargando (típico: un error de red) no se ocupa
    // media pantalla con un hueco. El resto del perfil sigue sirviendo.
    if (snapshot == null && !progreso.loading) {
      if (progreso.error == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionLabel('Tu progreso'),
            StickerCard(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  const Icon(Icons.cloud_off_rounded, size: 18, color: kMuted),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      progreso.error!,
                      style: const TextStyle(fontSize: 13, color: kMuted),
                    ),
                  ),
                  GhostButton(
                    label: 'Reintentar',
                    onPressed: progreso.refresh,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionLabel('Tu progreso'),
          TarjetaNivel(
            progress: snapshot?.progress,
            loading: progreso.loading,
          ),
          const SizedBox(height: 22),
          SeccionDesafios(snapshot: snapshot, loading: progreso.loading),
        ],
      ),
    );
  }
}
