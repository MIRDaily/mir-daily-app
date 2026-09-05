import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/providers/settings_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/sticker/sticker.dart';

/// Selector de cómo se abre el sobre, para la propia pantalla del daily.
///
/// Es un control con la pastilla deslizante de la barra de navegación,
/// vestido con el lenguaje de pegatina de la marca: relleno blanco, trazo de
/// tinta y sombra dura sin desenfoque.
///
/// Va en la pantalla del sobre y no enterrado en Preferencias a propósito. Lo
/// que se elige aquí es una animación, y una animación hay que verla para
/// elegirla: se toca, se abre el sobre, y si no gusta se toca otra. Metido en
/// un menú, nadie llegaría a saber que existen las demás.
class PackStyleSelector extends StatelessWidget {
  const PackStyleSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final PackOpeningStyle value;
  final ValueChanged<PackOpeningStyle> onChanged;

  /// Alto de la cápsula. Fijo, porque la pastilla se coloca contra él.
  static const double _height = 44;

  /// Ancho de cada opción.
  ///
  /// Con tres caben 3x100 + bordes = 312, que entra con margen en los 360 del
  /// móvil más estrecho que soporta la app. Si algún día hubiera una cuarta,
  /// esto tendría que dejar de ser fijo y pasar a repartirse el ancho.
  static const double _segment = 100;

  /// Aire entre la cápsula y la pastilla.
  static const double _pad = 4;

  /// El trazo de tinta. Cuenta para el ancho total: Flutter pinta el borde
  /// POR DENTRO de la caja, así que sin sumarlo las opciones no caben y el
  /// Row se desborda por esos cuatro píxeles.
  static const double _stroke = 2;

  @override
  Widget build(BuildContext context) {
    const opciones = PackOpeningStyle.values;
    final indice = opciones.indexOf(value);

    return Container(
      height: _height,
      width: _segment * opciones.length + 2 * (_pad + _stroke),
      padding: const EdgeInsets.all(_pad),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_height),
        border: Border.all(color: kInk, width: _stroke),
        boxShadow: inkShadow(4),
      ),
      child: Stack(
        children: [
          // La pastilla, por debajo de las etiquetas. Se coloca con una
          // alineación de -1 a 1 en vez de con posiciones en píxeles: así
          // sigue cayendo en su sitio con cualquier número de opciones.
          AnimatedAlign(
            duration: const Duration(milliseconds: 320),
            curve: kEaseOut,
            alignment: Alignment(
              opciones.length == 1
                  ? 0
                  : indice / (opciones.length - 1) * 2 - 1,
              0,
            ),
            child: Container(
              width: _segment,
              height: _height - 2 * (_pad + _stroke),
              decoration: BoxDecoration(
                // Coral PÁLIDO con el contenido en coral intenso, que es como
                // pinta la app su pastilla de "seleccionado" en la barra de
                // navegación. En coral saturado con el texto en blanco —la
                // otra opción— el contraste se queda en 1,9:1 y la etiqueta
                // apenas se lee.
                //
                // El tinte es OPACO (ver `tinted`): la cápsula lleva sombra
                // dura, y un relleno con alfa la dejaría pasar.
                color: tinted(AppColors.primary, 0.3),
                borderRadius: BorderRadius.circular(_height),
                border: Border.all(color: kInk, width: _stroke),
              ),
            ),
          ),
          Row(
            children: [
              for (final estilo in opciones)
                _Segmento(
                  estilo: estilo,
                  activo: estilo == value,
                  width: _segment,
                  onTap: () {
                    if (estilo == value) return;
                    HapticFeedback.selectionClick();
                    onChanged(estilo);
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Segmento extends StatelessWidget {
  const _Segmento({
    required this.estilo,
    required this.activo,
    required this.width,
    required this.onTap,
  });

  final PackOpeningStyle estilo;
  final bool activo;
  final double width;
  final VoidCallback onTap;

  /// El icono cuenta el gesto: las tijeras recorren la costura, el dedo
  /// aprieta, la flecha curva gira.
  IconData get _icono => switch (estilo) {
        PackOpeningStyle.tear => Icons.content_cut_rounded,
        PackOpeningStyle.burst => Icons.touch_app_rounded,
        PackOpeningStyle.twist => Icons.rotate_right_rounded,
      };

  /// La etiqueta nombra el GESTO, no el resultado: es lo que hay que hacer
  /// con el dedo, y es lo único que distingue una opción de otra.
  String get _etiqueta => switch (estilo) {
        PackOpeningStyle.tear => 'Rasgar',
        PackOpeningStyle.burst => 'Apretar',
        PackOpeningStyle.twist => 'Retorcer',
      };

  @override
  Widget build(BuildContext context) {
    // Coral intenso sobre la pastilla pálida; el otro, en el gris de los
    // textos secundarios. Es el par que ya usa la barra de navegación.
    final color = activo ? AppColors.primaryDark : kMuted;

    return SizedBox(
      width: width,
      child: Semantics(
        button: true,
        selected: activo,
        label: 'Abrir el sobre: $_etiqueta',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          // El contenido se encoge antes que desbordar. Hace falta de verdad:
          // "Retorcer" es bastante más largo que "Rasgar", y con el texto del
          // sistema agrandado o en otra tipografía se sale de su hueco.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // El icono crece un pelo al activarse: el mismo guiño de
                // rebote que hace la pastilla de la barra de navegación.
                AnimatedScale(
                  duration: const Duration(milliseconds: 320),
                  curve: kEaseOut,
                  scale: activo ? 1.0 : 0.88,
                  child: Icon(_icono, size: 16, color: color),
                ),
                const SizedBox(width: 5),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 320),
                  curve: kEaseOut,
                  style: TextStyle(
                    color: color,
                    fontSize: 12.5,
                    fontWeight: activo ? FontWeight.w900 : FontWeight.w700,
                  ),
                  child: Text(_etiqueta),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
