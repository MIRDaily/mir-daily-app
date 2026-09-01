import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../main_navigation.dart' show NavItem;

/// Ancho del raíl. Estrecho a propósito: icono + etiqueta pequeña debajo,
/// como los ítems de la barra inferior pero en vertical.
const double kNavRailWidth = 74;

/// Compatibilidad: el raíl ya no tiene variante "extendida".
const double kNavRailExtendedWidth = kNavRailWidth;

/// Alto de cada destino. Fijo: van agrupados arriba, no repartidos por todo
/// el alto (eso los hacía enormes).
const double _kItemHeight = 58;
const double _kTopGap = 8;

/// Raíl de navegación lateral para tablet en horizontal. Equivalente vertical
/// de la barra inferior: mismos destinos, misma "pastilla" deslizante (aquí en
/// Y), mismo `onTap`. Sin estado propio — el padre lo reconstruye dentro de un
/// `AnimatedBuilder` con la posición de la pastilla ya calculada.
class NavRail extends StatelessWidget {
  const NavRail({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.pillPos,
    required this.wave,
    required this.entry,
    required this.onTap,
  });

  final List<NavItem> items;
  final int selectedIndex;
  final double pillPos;
  final double wave;
  final double entry;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final n = items.length;
    final t = entry.clamp(0.0, 1.0);
    final topPad = MediaQuery.paddingOf(context).top;

    // El Container se estira a todo el alto (el Row padre usa
    // CrossAxisAlignment.stretch): el raíl "toca" arriba y abajo y su borde
    // derecho recorre todo el lateral, no es un rectángulo flotante.
    return FractionalTranslation(
      translation: Offset(-0.16 * (1 - t), 0),
      child: Opacity(
        opacity: t,
        child: Container(
          width: kNavRailWidth,
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(
              right: BorderSide(color: AppColors.hairline, width: 2),
            ),
          ),
          padding: EdgeInsets.only(top: topPad + _kTopGap, bottom: 12),
          child: SizedBox(
            height: n * _kItemHeight,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: 6,
                  right: 6,
                  top: pillPos * _kItemHeight + 3,
                  height: _kItemHeight - 6,
                  child: Transform.scale(
                    scale: 1 + 0.04 * wave,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.primary
                            .withValues(alpha: 0.12 + 0.06 * wave),
                        borderRadius: BorderRadius.circular(15),
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
    );
  }
}

class _RailPip extends StatelessWidget {
  const _RailPip({
    required this.item,
    required this.selectedness,
    required this.wave,
    required this.onTap,
  });

  final NavItem item;
  final double selectedness;
  final double wave;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = Color.lerp(
      AppColors.navInactive,
      AppColors.primary,
      selectedness,
    )!;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Transform.scale(
              scale: 1.0 + (0.10 * selectedness) + (0.16 * wave),
              child: Icon(
                selectedness > 0.5 ? item.activeIcon : item.icon,
                color: color,
                size: 22,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 9.5,
                fontWeight:
                    selectedness > 0.5 ? FontWeight.w700 : FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
