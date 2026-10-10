import 'package:flutter/material.dart';

import '../../core/models/resumen.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/sticker/sticker.dart';
import 'resumenes_grupo.dart';

/// Detalle de un grupo de resúmenes activos. En esta fase (1b) es un marcador:
/// la edición de párrafos y el estudio llegan en las fases 1c y 1d.
class ResumenDetailScreen extends StatelessWidget {
  final GrupoResumen grupo;

  const ResumenDetailScreen({super.key, required this.grupo});

  @override
  Widget build(BuildContext context) {
    final color = resolveColorResumen(grupo.color);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(grupo.name, style: const TextStyle(color: kInk, fontWeight: FontWeight.w900)),
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color.bg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: kInk, width: 2),
                    boxShadow: inkShadow(3),
                  ),
                  child: Icon(iconoGrupoResumen(grupo.icon), color: Colors.white, size: 34),
                ),
                const SizedBox(height: 18),
                Text('${grupo.total} ${grupo.total == 1 ? 'párrafo' : 'párrafos'}', style: const TextStyle(color: kInk, fontWeight: FontWeight.w900, fontSize: 18)),
                const SizedBox(height: 8),
                const Text(
                  'La edición de párrafos y el estudio llegan en las próximas fases.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13.5, height: 1.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
