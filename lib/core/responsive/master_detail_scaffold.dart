import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'breakpoints.dart';

/// Layout de dos paneles para tablet grande (`context.usesTwoPane`): una
/// lista maestra a la izquierda —colapsable— y el detalle ocupando el resto.
///
/// El detalle vive SIEMPRE en el mismo `Expanded`; al plegar/desplegar solo
/// se anima el ancho de la columna maestra, así que el detalle no se
/// reconstruye y la transición es fluida.
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

  final bool masterCollapsed;
  final VoidCallback onToggleMaster;

  final String? masterTitle;
  final List<Widget> masterActions;
  final double masterWidth;

  static const _duration = Duration(milliseconds: 170);
  static const _curve = Curves.easeOutCubic;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Columna maestra: el ancho se anima entre 0 y masterWidth. El
            // contenido se mantiene a su ancho natural (OverflowBox) y solo
            // lo tapa el recorte, sin re-maquetar nada.
            ClipRect(
              child: AnimatedContainer(
                duration: _duration,
                curve: _curve,
                width: masterCollapsed ? 0 : masterWidth,
                decoration: const BoxDecoration(
                  border: Border(
                    right:
                        BorderSide(color: AppColors.hairline, width: 1),
                  ),
                ),
                child: OverflowBox(
                  alignment: Alignment.centerLeft,
                  minWidth: masterWidth,
                  maxWidth: masterWidth,
                  child: SizedBox(
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
                ),
              ),
            ),
            Expanded(child: detail),
          ],
        ),
        // Tirador para volver a sacar la lista.
        Positioned(
          top: MediaQuery.paddingOf(context).top + 8,
          left: 8,
          child: AnimatedSlide(
            duration: _duration,
            curve: _curve,
            offset: masterCollapsed ? Offset.zero : const Offset(-1.4, 0),
            child: AnimatedOpacity(
              duration: _duration,
              opacity: masterCollapsed ? 1 : 0,
              child: IgnorePointer(
                ignoring: !masterCollapsed,
                child: _ListHandle(onTap: onToggleMaster),
              ),
            ),
          ),
        ),
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
        right: 4,
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
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
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
