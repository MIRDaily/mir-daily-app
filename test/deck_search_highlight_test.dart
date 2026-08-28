// El buscador del mazo tiene que marcar en amarillo lo que coincide, y solo
// eso: ni de más (texto que el backend no habría encontrado) ni de menos.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mirdaily_app/features/decks/widgets/highlighted_text.dart';

const _style = TextStyle(fontSize: 14, color: Color(0xFF2C3E50));
const _marker = Color(0xFFFDE68A);

/// Los trozos del texto pintados con el marcador amarillo.
List<String> _marcados(WidgetTester tester) {
  final widget = tester.widget<Text>(find.byType(Text));
  final span = widget.textSpan;
  // Sin coincidencias se pinta un Text llano, sin trozos que inspeccionar.
  if (span is! TextSpan) return const [];
  return [
    for (final child in span.children ?? const <InlineSpan>[])
      if (child is TextSpan && child.style?.backgroundColor == _marker)
        child.text!,
  ];
}

Future<void> _pump(WidgetTester tester, String text, String query) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: HighlightedText(text: text, query: query, style: _style),
      ),
    ),
  );
}

void main() {
  testWidgets('marca todas las apariciones, sin distinguir mayúsculas',
      (tester) async {
    await _pump(
      tester,
      'Las proteínas plasmáticas y otras Proteínas del suero.',
      'proteínas',
    );
    expect(_marcados(tester), ['proteínas', 'Proteínas']);
  });

  testWidgets('sin búsqueda no marca nada', (tester) async {
    await _pump(tester, 'Un enunciado cualquiera.', '');
    // Sin consulta se pinta un Text normal, sin trozos.
    final widget = tester.widget<Text>(find.byType(Text));
    expect(widget.data, 'Un enunciado cualquiera.');
    expect(widget.textSpan, isNull);
  });

  testWidgets('respeta las tildes, igual que el ilike del backend',
      (tester) async {
    // El servidor busca con ILIKE, que distingue tildes: "proteinas" no
    // devuelve "proteínas". Si aquí se ignorasen, el resaltado marcaría algo
    // que el backend nunca habría encontrado.
    await _pump(tester, 'Las proteínas plasmáticas.', 'proteinas');
    expect(_marcados(tester), isEmpty);
  });

  testWidgets('no se come texto alrededor de la coincidencia', (tester) async {
    await _pump(tester, 'abc DEF ghi', 'def');
    final widget = tester.widget<Text>(find.byType(Text));
    final span = widget.textSpan! as TextSpan;
    final completo = (span.children ?? const <InlineSpan>[])
        .whereType<TextSpan>()
        .map((s) => s.text)
        .join();
    expect(completo, 'abc DEF ghi');
  });
}
