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
/// El texto se pinta como texto de verdad (un `Text.rich` con un tramo por
/// racha de palabras en el mismo estado), no como una caja por palabra. Así
/// dos palabras seguidas marcadas salen como UN bloque amarillo continuo, con
/// su espacio dentro, en vez de dos manchas separadas.
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

  /// Un tramo por racha de palabras en el mismo estado. Las marcadas van con
  /// `background`, que pinta por detrás del texto sin huecos: por eso dos
  /// palabras seguidas salen unidas y no como dos bloques.
  List<InlineSpan> _spans() {
    final words = _words;
    final marcadas = widget.highlighted;
    final pintura = Paint()..color = HighlightableStatement.highlightColor;

    final spans = <InlineSpan>[];
    var i = 0;
    while (i < words.length) {
      final on = marcadas.contains(i);
      var j = i;
      while (j + 1 < words.length && marcadas.contains(j + 1) == on) {
        j++;
      }

      spans.add(TextSpan(
        text: words.sublist(i, j + 1).join(' '),
        style: on ? _style.copyWith(background: pintura) : _style,
      ));

      // El espacio ENTRE rachas nunca va marcado: separa dos estados
      // distintos, así que el amarillo termina justo donde termina la palabra.
      if (j + 1 < words.length) spans.add(TextSpan(text: ' ', style: _style));

      i = j + 1;
    }
    return spans;
  }

  /// Qué palabra cae bajo un punto, en coordenadas locales del texto.
  ///
  /// Se le pregunta al propio párrafo ya maquetado en vez de recalcular la
  /// disposición: así el reparto en renglones es exactamente el que se ve.
  ///
  /// Los índices de carácter se cuentan sobre `_words.join(' ')`, que es
  /// exactamente el texto que componen los tramos de [_spans].
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
      // `RichText` y no `Text.rich` a propósito: la clave tiene que dar en el
      // `RenderParagraph` para poder preguntarle qué palabra hay bajo el dedo,
      // y `Text` envuelve su `RichText` en otros render objects.
      child: RichText(
        key: _textKey,
        text: TextSpan(style: _style, children: _spans()),
      ),
    );
  }
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
