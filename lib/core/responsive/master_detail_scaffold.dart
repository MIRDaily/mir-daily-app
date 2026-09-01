import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'breakpoints.dart';

/// Layout de dos paneles para tablet grande (`context.usesTwoPane`): una
/// lista maestra a la izquierda —colapsable— y el detalle ocupando el resto.
///
/// No decide POR SÍ SOLO cuándo usarse — cada pantalla comprueba
/// `context.usesTwoPane` y elige entre esto y su navegación habitual por
/// `Navigator.push`. Ver `decks_screen.dart` para el patrón completo.
class MasterDetailScaffold extends StatelessWidget {
  const MasterDetailScaffold({
    super.key,
    required this.master,
    required this.detail,
    required this.masterCollapsed,
    required this.onToggleMaster,
    this.masterTitle,
    this.masterActions = const [],
    this.masterWidth = kMasterPaneWidth,
  });

  final Widget master;
  final Widget detail;

  /// La lista de la izquierda está plegada: el detalle va a pantalla completa
  /// y aparece un tirador para volver a sacarla.
  final bool masterCollapsed;
  final VoidCallback onToggleMaster;

  /// Título de la columna maestra (p. ej. "Mazos"). Opcional.
  final String? masterTitle;

  /// Acciones a la derecha del título de la columna maestra (p. ej. "nuevo").
  final List<Widget> masterActions;

  final double masterWidth;

  @override
  Widget build(BuildContext context) {
    if (masterCollapsed) {
      return Stack(
        children: [
          Positioned.fill(child: detail),
          Positioned(
            top: MediaQuery.paddingOf(context).top + 8,
            left: 8,
            child: _ListHandle(onTap: onToggleMaster),
          ),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: masterWidth,
          child: Column(
            children: [
              _MasterHeader(
                title: masterTitle,
                actions: masterActions,
                onCollapse: onToggleMaster,
              ),
              Expanded(child: master),
            ],
          ),
        ),
        const VerticalDivider(width: 1, thickness: 1, color: AppColors.hairline),
        Expanded(child: detail),
      ],
    );
  }
}

class _MasterHeader extends StatelessWidget {
  const _MasterHeader({
    required this.title,
    required this.actions,
    required this.onCollapse,
  });

  final String? title;
  final List<Widget> actions;
  final VoidCallback onCollapse;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.paddingOf(context).top + 6,
        left: 14,
        right: 6,
        bottom: 6,
      ),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(
          bottom: BorderSide(color: AppColors.hairline, width: 1),
        ),
      ),
      child: Row(
        children: [
          if (title != null)
            Expanded(
              child: Text(
                title!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  color: AppColors.textPrimary,
                ),
              ),
            )
          else
            const Spacer(),
          ...actions,
          IconButton(
            tooltip: 'Ocultar la lista',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.chevron_left_rounded),
            color: AppColors.textSecondary,
            onPressed: onCollapse,
          ),
        ],
      ),
    );
  }
}

/// Tirador que reaparece cuando la lista está plegada.
class _ListHandle extends StatelessWidget {
  const _ListHandle({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      elevation: 2,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.menu_rounded, size: 18, color: AppColors.textSecondary),
              SizedBox(width: 6),
              Text(
                'Lista',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
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
