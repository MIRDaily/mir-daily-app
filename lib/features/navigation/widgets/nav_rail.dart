import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../main_navigation.dart' show NavItem;

/// Ancho del raíl compacto (solo icono + etiqueta pequeña debajo).
const double kNavRailWidth = 76;

/// Ancho del raíl extendido (icono + etiqueta al lado).
const double kNavRailExtendedWidth = 184;

/// Alto de cada destino del raíl. Fijo: los destinos van agrupados arriba,
/// no repartidos por todo el alto (eso los hacía enormes en una tablet).
const double _kItemHeight = 60;

/// Separación entre el borde superior y el primer destino.
const double _kTopGap = 10;

/// Raíl de navegación lateral para tablet en horizontal. Es el equivalente
/// vertical de la barra inferior animada: mismos items, misma "pastilla"
/// deslizante (aquí en el eje Y), mismo `onTap`.
///
/// No tiene estado propio: el padre lo reconstruye dentro de un
/// `AnimatedBuilder` con la posición de la pastilla ya calculada.
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

  /// Posición de la pastilla en índices (p. ej. 1.7), con rebote.
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
    final topPad = MediaQuery.paddingOf(context).top;

    return FractionalTranslation(
      translation: Offset(-0.14 * (1 - t), 0),
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
          child: Padding(
            padding: EdgeInsets.only(
              top: topPad + _kTopGap,
              left: 8,
              right: 8,
              bottom: 12,
            ),
            child: SizedBox(
              height: n * _kItemHeight,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Pastilla: alto fijo, se desliza entre las ranuras.
                  Positioned(
                    left: 0,
                    right: 0,
                    top: pillPos * _kItemHeight + 4,
                    height: _kItemHeight - 8,
                    child: Transform.scale(
                      scale: 1 + 0.04 * wave,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppColors.primary
                              .withValues(alpha: 0.12 + 0.06 * wave),
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                  Column(
                    children: List.generate(n, (i) {
                      final sel = (1 - (pillPos - i).abs()).clamp(0.0, 1.0);
                      return SizedBox(
                        height: _kItemHeight,
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
      scale: 1.0 + (0.10 * selectedness) + (0.16 * wave),
      child: Icon(
        selectedness > 0.5 ? item.activeIcon : item.icon,
        color: color,
        size: 22,
      ),
    );

    final label = Text(
      item.label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: extended ? 12.5 : 10,
        fontWeight: selectedness > 0.5 ? FontWeight.w700 : FontWeight.w500,
        color: color,
      ),
    );

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Center(
        child: extended
            ? Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    icon,
                    const SizedBox(width: 12),
                    Flexible(child: label),
                  ],
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  icon,
                  const SizedBox(height: 3),
                  label,
                ],
              ),
      ),
    );
  }
}
