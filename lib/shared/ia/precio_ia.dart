import 'package:flutter/material.dart';

import '../../core/models/creditos_ia.dart';
import '../../core/theme/app_theme.dart';
import '../sticker/sticker.dart';

/// «Usará 14 créditos · te quedan 1.240» bajo el botón de generar (puerto de <PrecioIA> de la web).
/// Sin créditos encendidos no pinta nada: entonces se genera como antes.
class PrecioIa extends StatelessWidget {
  final LineaPrecio linea;

  const PrecioIa({super.key, required this.linea});

  @override
  Widget build(BuildContext context) {
    final color = !linea.suficiente
        ? AppColors.error
        : linea.aviso
            ? const Color(0xFFB98A12)
            : AppColors.textSecondary;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 20,
          height: 20,
          margin: const EdgeInsets.only(top: 1, right: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFFC9A227),
            shape: BoxShape.circle,
            border: Border.all(color: kInk, width: 1.5),
          ),
          child: const Icon(Icons.bolt_rounded, size: 13, color: Colors.white),
        ),
        Expanded(
          child: Text(
            linea.texto,
            style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w700, height: 1.4),
          ),
        ),
      ],
    );
  }
}
