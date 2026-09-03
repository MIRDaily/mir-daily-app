import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../core/theme/app_theme.dart';

/// Enunciado en el que se puede subrayar.
///
/// Nació en el modo Deslizar y ahora lo usan los dos runners: no había razón
/// para que en Clásico no se pudiera marcar el dato que importa. El estado
/// vive fuera (el runner), porque hay que poder limpiarlo al cambiar de
/// pregunta y saber desde la cabecera si hay algo marcado.
///
/// Dos formas de marcar, como en cualquier texto de Android:
///
///  - **Toque** sobre una palabra: la marca o la desmarca. Es lo de siempre y
///    sigue siendo lo cómodo cuando solo interesa un dato suelto.
///  - **Mantener pulsado y arrastrar**: marca la oración entera por la que
///    pases. Si empiezas sobre algo YA marcado el arrastre borra en vez de
///    pintar, y el sentido se decide al empezar: ir alternando palabra por
///    palabra dejaría un damero de huecos amarillos.
///
/// Hace falta mantener pulsado antes de arrastrar, y no arrastrar a secas,
/// porque en el modo Deslizar el enunciado va dentro de un `PageView`
/// horizontal: un arrastre normal es el gesto de cambiar de pregunta. Una
/// pulsación larga no compite con él.
///
/// El texto se pinta como texto de verdad, no como una caja por palabra, y el
/// amarillo va por debajo: un rectángulo redondeado por cada racha de palabras
/// seguidas marcadas. De ahí que dos palabras contiguas salgan como UN bloque
/// continuo, con su espacio dentro, en vez de dos manchas separadas.
class HighlightableStatement extends StatefulWidget {
  final String statement;

  /// Índices de las palabras marcadas. Lo guarda el runner.
  final Set<int> highlighted;

  /// Toque simple sobre una palabra.
  final ValueChanged<int> onToggle;

  /// Arrastre tras mantener pulsado.
  ///
  /// Entrega el conjunto COMPLETO que debe quedar marcado, no lo que se añade:
  /// así, al volver sobre tus pasos dentro del mismo arrastre, el tramo se
  /// encoge igual que una selección de texto normal.
  ///
  /// Si es null, el arrastre no hace nada y solo queda el toque.
  final ValueChanged<Set<int>>? onPaint;

  final double fontSize;
  final FontWeight fontWeight;

  /// Interlineado.
  final double lineHeight;

  const HighlightableStatement({
    super.key,
    required this.statement,
    required this.highlighted,
    required this.onToggle,
    this.onPaint,
    this.fontSize = 19,
    this.fontWeight = FontWeight.w600,
    this.lineHeight = 1.25,
  });

  static const highlightColor = Color(0xFFFFE082);

  @override
  State<HighlightableStatement> createState() => _HighlightableStatementState();
}

class _HighlightableStatementState extends State<HighlightableStatement> {
  final GlobalKey _textKey = GlobalKey();

  /// Palabra donde empezó el arrastre.
  int? _anchor;

  /// Qué había marcado al empezar el arrastre. El tramo se aplica sobre esto,
  /// no sobre lo último pintado, que es lo que permite encoger.
  Set<int> _baseline = const {};

  /// El arrastre borra (empezó sobre algo ya marcado) en vez de pintar.
  bool _erasing = false;

  List<String> get _words => widget.statement.trim().split(RegExp(r'\s+'));

  TextStyle get _style => TextStyle(
        fontSize: widget.fontSize,
        height: widget.lineHeight,
        color: AppColors.textPrimary,
        fontWeight: widget.fontWeight,
      );

  /// El texto tal cual se compone: las palabras separadas por un espacio.
  String get _plain => _words.join(' ');

  /// Los tramos de CARACTERES que van marcados, uno por racha de palabras
  /// seguidas.
  ///
  /// Que la racha sea un solo tramo es lo que une dos palabras contiguas: el
  /// espacio de en medio cae dentro del mismo rango y se pinta con ellas, en
  /// vez de quedar un hueco entre dos manchas.
  List<(int, int)> _runs() {
    final words = _words;
    final marcadas = widget.highlighted;

    final runs = <(int, int)>[];
    var charIndex = 0;
    var i = 0;

    while (i < words.length) {
      if (!marcadas.contains(i)) {
        charIndex += words[i].length + 1; // +1 por el espacio
        i++;
        continue;
      }

      final inicio = charIndex;
      var fin = charIndex + words[i].length;
      charIndex = fin + 1;
      i++;

      while (i < words.length && marcadas.contains(i)) {
        fin = charIndex + words[i].length;
        charIndex = fin + 1;
        i++;
      }

      runs.add((inicio, fin));
    }
    return runs;
  }

  /// Qué palabra cae bajo un punto, en coordenadas locales del texto.
  ///
  /// Se le pregunta al propio párrafo ya maquetado en vez de recalcular la
  /// disposición: así el reparto en renglones es exactamente el que se ve.
  ///
  /// Los índices de carácter se cuentan sobre [_plain], que es exactamente el
  /// texto que se pinta.
  int? _wordAt(Offset localPosition) {
    final render = _textKey.currentContext?.findRenderObject();
    if (render is! RenderParagraph) return null;

    final offset = render.getPositionForOffset(localPosition).offset;
    final words = _words;

    var start = 0;
    for (var i = 0; i < words.length; i++) {
      final end = start + words[i].length;
      // `<= end` para que el espacio de después cuente como la palabra
      // anterior; si no, tocar justo en el hueco no marcaría nada.
      if (offset <= end) return i;
      start = end + 1; // +1 por el espacio
    }
    return words.isEmpty ? null : words.length - 1;
  }

  Offset _toLocal(Offset global) {
    final render = _textKey.currentContext?.findRenderObject();
    if (render is! RenderBox) return global;
    return render.globalToLocal(global);
  }

  void _onTapUp(TapUpDetails d) {
    final i = _wordAt(_toLocal(d.globalPosition));
    if (i != null) widget.onToggle(i);
  }

  void _onLongPressStart(LongPressStartDetails d) {
    if (widget.onPaint == null) return;
    final i = _wordAt(_toLocal(d.globalPosition));
    if (i == null) return;

    _anchor = i;
    _baseline = {...widget.highlighted};
    // El sentido se fija aquí y no cambia en todo el arrastre.
    _erasing = widget.highlighted.contains(i);
    _applyTo(i);
  }

  void _onLongPressMoveUpdate(LongPressMoveUpdateDetails d) {
    if (_anchor == null) return;
    final i = _wordAt(_toLocal(d.globalPosition));
    if (i != null) _applyTo(i);
  }

  void _onLongPressEnd(LongPressEndDetails _) {
    _anchor = null;
    _baseline = const {};
  }

  /// Aplica el tramo que va del ancla a [hasta] sobre lo que había al empezar.
  void _applyTo(int hasta) {
    final desde = _anchor;
    if (desde == null) return;

    final tramo = [
      for (var k = desde < hasta ? desde : hasta;
          k <= (desde < hasta ? hasta : desde);
          k++)
        k,
    ];

    final nuevo = {..._baseline};
    if (_erasing) {
      nuevo.removeAll(tramo);
    } else {
      nuevo.addAll(tramo);
    }
    widget.onPaint?.call(nuevo);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: _onTapUp,
      onLongPressStart: _onLongPressStart,
      onLongPressMoveUpdate: _onLongPressMoveUpdate,
      onLongPressEnd: _onLongPressEnd,
      // El amarillo NO se pinta con `TextStyle.background`: eso solo sabe
      // hacer rectángulos a escuadra. Va por debajo, como rectángulos
      // redondeados, y el texto encima.
      //
      // `RichText` y no `Text.rich` a propósito: la clave tiene que dar en el
      // `RenderParagraph` para poder preguntarle qué palabra hay bajo el dedo,
      // y `Text` envuelve su `RichText` en otros render objects.
      child: CustomPaint(
        painter: _HighlightPainter(
          text: _plain,
          style: _style,
          runs: _runs(),
          color: HighlightableStatement.highlightColor,
          textScaler: MediaQuery.textScalerOf(context),
          textDirection: Directionality.of(context),
        ),
        child: RichText(
          key: _textKey,
          text: TextSpan(text: _plain, style: _style),
        ),
      ),
    );
  }
}

/// Pinta el amarillo del subrayado por debajo del texto.
///
/// Existe porque `TextStyle.background` solo dibuja rectángulos a escuadra, y
/// un subrayado con las esquinas en pico parece un error de pintado más que un
/// rotulador. Aquí cada tramo sale como rectángulo redondeado.
///
/// Rehace la maquetación del texto con los mismos parámetros que el `RichText`
/// de al lado (mismo texto, estilo, escala y dirección), así que las cajas que
/// devuelve caen exactamente donde están las letras.
class _HighlightPainter extends CustomPainter {
  const _HighlightPainter({
    required this.text,
    required this.style,
    required this.runs,
    required this.color,
    required this.textScaler,
    required this.textDirection,
  });

  final String text;
  final TextStyle style;

  /// Tramos de caracteres a marcar, en pares (inicio, fin).
  final List<(int, int)> runs;

  final Color color;
  final TextScaler textScaler;
  final TextDirection textDirection;

  /// Cuánto se redondean las esquinas.
  static const double _radio = 6;

  /// El tramo se ensancha un pelín a los lados para que la primera y la última
  /// letra no queden pegadas al borde del color.
  static const double _aire = 2.5;

  /// Y se recorta arriba y abajo: la caja de la línea incluye el interlineado,
  /// y sin esto el amarillo de dos renglones seguidos se toca.
  static const double _recorte = 2;

  @override
  void paint(Canvas canvas, Size size) {
    if (runs.isEmpty) return;

    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: textDirection,
      textScaler: textScaler,
    )..layout(maxWidth: size.width);

    final brocha = Paint()..color = color;

    for (final (inicio, fin) in runs) {
      final cajas = painter.getBoxesForSelection(
        TextSelection(baseOffset: inicio, extentOffset: fin),
      );
      // Una caja por renglón: un tramo que parte de línea sale como dos
      // rectángulos redondeados, cada uno cerrado por su lado.
      for (final caja in cajas) {
        final r = caja.toRect();
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(
              r.left - _aire,
              r.top + _recorte,
              r.right + _aire,
              r.bottom - _recorte,
            ),
            const Radius.circular(_radio),
          ),
          brocha,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_HighlightPainter old) =>
      old.text != text ||
      old.style != style ||
      old.color != color ||
      old.textScaler != textScaler ||
      old.textDirection != textDirection ||
      !listEquals(old.runs, runs);
}

/// Botón de "Limpiar" para el subrayado.
///
/// Cuando no hay nada marcado NO se quita del árbol: se queda transparente
/// ocupando su hueco. Si desaparece, al subrayar la primera palabra de cada
/// pregunta el enunciado pega un salto para hacerle sitio.
class ClearHighlightButton extends StatelessWidget {
  final VoidCallback onTap;

  /// A `false` sigue midiendo igual, pero ni se ve ni recibe toques.
  final bool visible;

  const ClearHighlightButton({
    super.key,
    required this.onTap,
    this.visible = true,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 160),
        child: _button(),
      ),
    );
  }

  Widget _button() {
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
