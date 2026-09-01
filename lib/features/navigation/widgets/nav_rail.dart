import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../main_navigation.dart' show NavItem;

/// Ancho del raíl. Estrecho a propósito: icono + etiqueta pequeña debajo,
/// como los ítems de la barra inferior pero en vertical.
const double kNavRailWidth = 76;

/// Compatibilidad: el raíl ya no tiene variante "extendida".
const double kNavRailExtendedWidth = kNavRailWidth;

/// Alto de cada destino.
const double _kItemHeight = 60;

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
    final bottomPad = MediaQuery.paddingOf(context).bottom;

    // El Container se estira a todo el alto (el Row padre usa
    // CrossAxisAlignment.stretch). Además lleva sombra en el borde derecho,
    // como la barra inferior la lleva arriba: sin ella, blanco sobre beige
    // apenas se distingue y parecía "un cuadrado".
    return FractionalTranslation(
      translation: Offset(-0.16 * (1 - t), 0),
      child: Opacity(
        opacity: t,
        child: Container(
          width: kNavRailWidth,
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: const Border(
              right: BorderSide(color: AppColors.border, width: 1),
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.secondary.withValues(alpha: 0.10),
                blurRadius: 10,
                offset: const Offset(2, 0),
              ),
            ],
          ),
          padding: EdgeInsets.only(top: topPad, bottom: bottomPad),
          child: Center(
            // Grupo de destinos centrado verticalmente en el raíl.
            child: SizedBox(
              height: n * _kItemHeight,
              width: double.infinity,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: 6,
                    right: 6,
                    top: pillPos * _kItemHeight + 4,
                    height: _kItemHeight - 8,
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
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < n; i++)
                        SizedBox(
                          height: _kItemHeight,
                          child: _RailPip(
                            item: items[i],
                            selectedness:
                                (1 - (pillPos - i).abs()).clamp(0.0, 1.0),
                            wave: wave *
                                (1 - (pillPos - i).abs()).clamp(0.0, 1.0),
                            onTap: () => onTap(i),
                          ),
                        ),
                    ],
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
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Transform.scale(
            scale: 1.0 + (0.10 * selectedness) + (0.16 * wave),
            child: Icon(
              selectedness > 0.5 ? item.activeIcon : item.icon,
              color: color,
              size: 23,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            item.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 9.5,
              fontWeight:
                  selectedness > 0.5 ? FontWeight.w700 : FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
