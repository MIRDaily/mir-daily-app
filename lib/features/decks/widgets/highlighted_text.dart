import 'package:flutter/material.dart';

/// Resalta, "subrayado con marcador", las coincidencias de una búsqueda dentro
/// de un texto — para localizar de un vistazo qué parte del enunciado encajó.
///
/// Port de `HighlightedText` (`src/components/studio/deckUi.tsx`), con el mismo
/// amarillo `#FDE68A`.
///
/// La comparación es **sin distinguir mayúsculas, pero SÍ tildes**, igual que
/// el `ilike` de Postgres que hace la búsqueda en el servidor: si aquí se
/// ignorasen las tildes, se marcarían coincidencias que el backend nunca
/// devolvió y el resaltado mentiría sobre por qué salió esa pregunta.
class HighlightedText extends StatelessWidget {
  final String text;
  final String query;
  final TextStyle style;
  final int? maxLines;
  final TextOverflow? overflow;

  const HighlightedText({
    super.key,
    required this.text,
    required this.query,
    required this.style,
    this.maxLines,
    this.overflow,
  });

  static const Color _marker = Color(0xFFFDE68A);

  @override
  Widget build(BuildContext context) {
    final needle = query.trim();
    if (needle.isEmpty) {
      return Text(
        text,
        style: style,
        maxLines: maxLines,
        overflow: overflow,
      );
    }

    final haystack = text.toLowerCase();
    final lower = needle.toLowerCase();
    final spans = <TextSpan>[];

    var from = 0;
    while (true) {
      final at = haystack.indexOf(lower, from);
      if (at < 0) break;
      if (at > from) {
        spans.add(TextSpan(text: text.substring(from, at)));
      }
      spans.add(TextSpan(
        text: text.substring(at, at + needle.length),
        style: style.copyWith(
          backgroundColor: _marker,
          fontWeight: FontWeight.w900,
        ),
      ));
      from = at + needle.length;
    }

    if (spans.isEmpty) {
      return Text(text, style: style, maxLines: maxLines, overflow: overflow);
    }
    if (from < text.length) {
      spans.add(TextSpan(text: text.substring(from)));
    }

    return Text.rich(
      TextSpan(style: style, children: spans),
      maxLines: maxLines,
      overflow: overflow ?? TextOverflow.clip,
    );
  }
}
