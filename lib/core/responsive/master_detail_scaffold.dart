import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'breakpoints.dart';

/// Layout de dos paneles para tablet grande (`context.usesTwoPane`): una
/// lista maestra a la izquierda, ancho fijo, y el detalle ocupando el resto.
///
/// No decide POR SÍ SOLO cuándo usarse — cada pantalla comprueba
/// `context.usesTwoPane` y elige entre esto y su navegación habitual por
/// `Navigator.push`. Ver `decks_screen.dart` para el patrón completo.
class MasterDetailScaffold extends StatelessWidget {
  const MasterDetailScaffold({
    super.key,
    required this.master,
    required this.detail,
    this.masterWidth = kMasterPaneWidth,
  });

  final Widget master;
  final Widget detail;
  final double masterWidth;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: masterWidth, child: master),
        const VerticalDivider(width: 1, thickness: 1, color: AppColors.hairline),
        Expanded(
          child: ClipRect(child: detail),
        ),
      ],
    );
  }
}

/// Panel derecho mientras no hay nada seleccionado en el maestro.
class MasterDetailEmpty extends StatelessWidget {
  const MasterDetailEmpty({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.background,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 52, color: AppColors.textLight),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 8),
                Text(
                  subtitle!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13.5,
                    color: AppColors.textLight,
                    height: 1.4,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
