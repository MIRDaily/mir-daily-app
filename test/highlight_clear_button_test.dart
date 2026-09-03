// El botón "Limpiar" del subrayado no debe cambiar el alto de su fila al
// aparecer: si lo hace, el enunciado pega un salto al subrayar la primera
// palabra de cada pregunta.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mirdaily_app/features/simulacro/widgets/highlightable_statement.dart';

Future<double> _rowHeight(WidgetTester tester, {required bool visible}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Row(
          children: [
            const Spacer(),
            ClearHighlightButton(visible: visible, onTap: () {}),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return tester.getSize(find.byType(ClearHighlightButton)).height;
}

void main() {
  testWidgets('ocupa el mismo alto con y sin subrayado', (tester) async {
    final sinNada = await _rowHeight(tester, visible: false);
    final conAlgo = await _rowHeight(tester, visible: true);

    expect(sinNada, greaterThan(0));
    expect(sinNada, conAlgo);
  });

  testWidgets('invisible no recibe toques', (tester) async {
    var pulsado = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: ClearHighlightButton(
              visible: false,
              onTap: () => pulsado = true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(ClearHighlightButton), warnIfMissed: false);
    await tester.pump();
    expect(pulsado, isFalse);
  });
}
