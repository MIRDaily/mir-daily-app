import 'package:flutter/widgets.dart';

/// Nº de columnas para una rejilla de tarjetas, a partir del ancho disponible
/// y de un ancho de tarjeta objetivo. Siempre >= 1.
int adaptiveColumnCount(
  double available, {
  double target = 340,
  int max = 4,
}) {
  if (available <= 0) return 1;
  final n = (available / target).floor();
  return n.clamp(1, max);
}

/// Rejilla que decide sus columnas por el ancho real que recibe (via
/// `LayoutBuilder`), no por el de la pantalla. Con 1 columna se comporta como
/// una `Column` (mismo aspecto que la lista original en móvil).
///
/// No hace scroll: pensada para ir dentro de un `ListView`/`CustomScrollView`
/// existente, igual que las `Column` a las que sustituye.
class AdaptiveGrid extends StatelessWidget {
  const AdaptiveGrid({
    super.key,
    required this.children,
    this.targetItemWidth = 340,
    this.maxColumns = 4,
    this.spacing = 14,
    this.runSpacing = 14,
  });

  final List<Widget> children;
  final double targetItemWidth;
  final int maxColumns;
  final double spacing;
  final double runSpacing;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = adaptiveColumnCount(
          constraints.maxWidth,
          target: targetItemWidth,
          max: maxColumns,
        );

        if (cols == 1) {
          // Mismo layout que la lista original: una columna, separada por
          // `runSpacing`. Sin `Wrap` para no cambiar el comportamiento de
          // los hijos que asumen ancho completo.
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) SizedBox(height: runSpacing),
                children[i],
              ],
            ],
          );
        }

        final rows = <Widget>[];
        for (var i = 0; i < children.length; i += cols) {
          final rowItems = <Widget>[];
          for (var c = 0; c < cols; c++) {
            final idx = i + c;
            if (c > 0) rowItems.add(SizedBox(width: spacing));
            rowItems.add(Expanded(
              child: idx < children.length ? children[idx] : const SizedBox(),
            ));
          }
          if (rows.isNotEmpty) rows.add(SizedBox(height: runSpacing));
          rows.add(IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: rowItems,
            ),
          ));
        }
        return Column(children: rows);
      },
    );
  }
}
