import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../main_navigation.dart' show NavItem;

/// Ancho del raíl compacto (solo icono + etiqueta pequeña).
const double kNavRailWidth = 88;

/// Ancho del raíl extendido (icono + etiqueta al lado).
const double kNavRailExtendedWidth = 212;

/// Raíl de navegación lateral para tablet en horizontal. Es el equivalente
/// vertical de la barra inferior animada: mismos items, misma "pastilla"
/// deslizante (aquí en el eje Y), mismo `onTap`.
///
/// No tiene estado propio: el padre lo reconstruye dentro de un
/// `AnimatedBuilder` con la posición de la pastilla ya calculada, igual que
/// hace con la barra inferior.
class NavRail extends StatelessWidget {
  const NavRail({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.pillPos,
    required this.wave,
    required this.extended,
    required this.entry,
    required this.onTap,
  });

  final List<NavItem> items;
  final int selectedIndex;

  /// Posición de la pastilla en índices (p. ej. 1.7), con rebote. La calcula
  /// el padre reutilizando la misma lógica que la barra inferior.
  final double pillPos;

  /// Envolvente "ola" 0..1 mientras la pastilla viaja.
  final double wave;

  /// `true` = icono + etiqueta al lado; `false` = icono + etiqueta debajo.
  final bool extended;

  /// Progreso de la animación de entrada (0..1), compartida con la barra.
  final double entry;

  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final n = items.length;
    final width = extended ? kNavRailExtendedWidth : kNavRailWidth;

    final t = entry.clamp(0.0, 1.0);
    return FractionalTranslation(
      // Entrada suave: un 12 % desde la izquierda + fundido. Nunca se esconde
      // del todo (a diferencia de la barra inferior).
      translation: Offset(-0.12 * (1 - t), 0),
      child: Opacity(
        opacity: t,
        child: Container(
          width: width,
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(
              right: BorderSide(color: AppColors.hairline, width: 2),
            ),
          ),
          child: SafeArea(
            right: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              child: Stack(
                children: [
                  // Pastilla deslizante: alto = 1/n del raíl, viaja en Y.
                  Align(
                    alignment: Alignment(0, n == 1 ? 0 : (2 * pillPos / (n - 1) - 1)),
                    child: FractionallySizedBox(
                      heightFactor: 1 / n,
                      widthFactor: 1,
                      child: Transform.scale(
                        scale: 1 + 0.06 * wave,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: AppColors.primary
                                  .withValues(alpha: 0.12 + 0.06 * wave),
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Column(
                    children: List.generate(n, (i) {
                      final sel = (1 - (pillPos - i).abs()).clamp(0.0, 1.0);
                      return Expanded(
                        child: _RailPip(
                          item: items[i],
                          selectedness: sel,
                          wave: wave * sel,
                          extended: extended,
                          onTap: () => onTap(i),
                        ),
                      );
                    }),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RailPip extends StatelessWidget {
  const _RailPip({
    required this.item,
    required this.selectedness,
    required this.wave,
    required this.extended,
    required this.onTap,
  });

  final NavItem item;
  final double selectedness;
  final double wave;
  final bool extended;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = Color.lerp(
      AppColors.navInactive,
      AppColors.primary,
      selectedness,
    )!;

    final icon = Transform.scale(
      scale: 1.0 + (0.12 * selectedness) + (0.22 * wave),
      child: Icon(
        selectedness > 0.5 ? item.activeIcon : item.icon,
        color: color,
        size: 24,
      ),
    );

    final label = Text(
      item.label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: extended ? 13 : 10.5,
        fontWeight: selectedness > 0.5 ? FontWeight.w700 : FontWeight.w400,
        color: color,
      ),
    );

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: extended
          ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  icon,
                  const SizedBox(width: 14),
                  Flexible(child: label),
                ],
              ),
            )
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                icon,
                const SizedBox(height: 4),
                label,
              ],
            ),
    );
  }
}
