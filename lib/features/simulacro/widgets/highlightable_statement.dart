import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Enunciado en el que se puede subrayar tocando palabras.
///
/// Nació en el modo Deslizar y ahora lo usan los dos runners: no había razón
/// para que en Clásico no se pudiera marcar el dato que importa. El estado
/// vive fuera (el runner), porque hay que poder limpiarlo al cambiar de
/// pregunta y saber desde la cabecera si hay algo marcado.
class HighlightableStatement extends StatelessWidget {
  final String statement;

  /// Índices de las palabras marcadas. Lo guarda el runner.
  final Set<int> highlighted;
  final ValueChanged<int> onToggle;

  final double fontSize;
  final FontWeight fontWeight;

  /// Interlineado. En Deslizar la palabra va en su propia caja dentro de un
  /// `Wrap`, así que este valor manda de verdad en cuánto separa los renglones.
  final double lineHeight;

  const HighlightableStatement({
    super.key,
    required this.statement,
    required this.highlighted,
    required this.onToggle,
    this.fontSize = 19,
    this.fontWeight = FontWeight.w600,
    this.lineHeight = 1.25,
  });

  static const highlightColor = Color(0xFFFFE082);

  @override
  Widget build(BuildContext context) {
    final words = statement.trim().split(RegExp(r'\s+'));

    return Wrap(
      spacing: 5,
      // Muy poco: la altura del renglón ya la pone `lineHeight` dentro de cada
      // palabra, así que sumarle separación de fila lo dejaba todo suelto.
      runSpacing: 2,
      children: [
        for (var i = 0; i < words.length; i++)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onToggle(i),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 1.5, vertical: 1),
              decoration: BoxDecoration(
                color: highlighted.contains(i)
                    ? highlightColor
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                words[i],
                style: TextStyle(
                  fontSize: fontSize,
                  height: lineHeight,
                  color: AppColors.textPrimary,
                  fontWeight: fontWeight,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Botón de "Limpiar" para el subrayado. Solo aparece si hay algo marcado.
class ClearHighlightButton extends StatelessWidget {
  final VoidCallback onTap;

  const ClearHighlightButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.format_clear_rounded,
              size: 16, color: AppColors.textSecondary),
          SizedBox(width: 4),
          Text('Limpiar',
              style: TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w700,
                  fontSize: 12)),
        ],
      ),
    );
  }
}
