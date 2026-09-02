// `showAdaptiveModal` es una hoja en móvil y un diálogo centrado en tablet.
// El mismo `builder` sirve en los dos casos.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mirdaily_app/core/responsive/adaptive_modal.dart';

Future<void> _pumpAt(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => showAdaptiveModal<void>(
                context: context,
                builder: (_) => const SafeArea(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('contenido modal'),
                  ),
                ),
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('móvil (390x844): sale como bottom sheet', (tester) async {
    await _pumpAt(tester, const Size(390, 844));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    expect(find.text('contenido modal'), findsOneWidget);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('tablet (1280x800): sale como diálogo centrado y acotado',
      (tester) async {
    await _pumpAt(tester, const Size(1280, 800));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    expect(find.text('contenido modal'), findsOneWidget);
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);

    // El contenido del diálogo va acotado, no a todo el ancho de la tablet.
    final w = tester
        .getSize(find.byType(SingleChildScrollView).first)
        .width;
    expect(w, lessThan(700));
  });
}
