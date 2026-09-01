import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirdaily_app/core/responsive/adaptive_grid.dart';
import 'package:mirdaily_app/core/responsive/breakpoints.dart';

/// Comprueba que los breakpoints y el nº de columnas de la rejilla salen donde
/// deben. Es la base de todo el trabajo de tablet: si esto se descuadra, la
/// navegación y las rejillas se van con él.
void main() {
  Future<void> pumpAt(WidgetTester tester, Size size, ValueChanged<BuildContext> check) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(builder: (context) {
          check(context);
          return const SizedBox();
        }),
      ),
    );
  }

  testWidgets('móvil vertical = compact, barra inferior, un panel', (tester) async {
    await pumpAt(tester, const Size(390, 844), (c) {
      expect(c.windowSize, WindowSize.compact);
      expect(c.isWide, isFalse);
      expect(c.usesNavRail, isFalse);
      expect(c.usesTwoPane, isFalse);
      expect(c.contentMaxWidth(), double.infinity);
      expect(c.bodyGutter, 20);
    });
  });

  testWidgets('tablet vertical = medium, barra inferior (no raíl)', (tester) async {
    await pumpAt(tester, const Size(820, 1180), (c) {
      expect(c.windowSize, WindowSize.medium);
      expect(c.isWide, isTrue);
      expect(c.usesNavRail, isFalse, reason: 'vertical => barra inferior');
      expect(c.usesTwoPane, isFalse);
    });
  });

  testWidgets('tablet horizontal = expanded, raíl y dos paneles', (tester) async {
    await pumpAt(tester, const Size(1280, 800), (c) {
      expect(c.windowSize, WindowSize.expanded);
      expect(c.usesNavRail, isTrue);
      expect(c.usesExtendedNavRail, isTrue);
      expect(c.usesTwoPane, isTrue);
    });
  });

  testWidgets('tablet pequeña horizontal = raíl sin dos paneles', (tester) async {
    await pumpAt(tester, const Size(900, 600), (c) {
      expect(c.usesNavRail, isTrue);
      expect(c.usesTwoPane, isFalse);
    });
  });

  test('adaptiveColumnCount', () {
    expect(adaptiveColumnCount(390, target: 340), 1);
    expect(adaptiveColumnCount(700, target: 340), 2);
    expect(adaptiveColumnCount(1100, target: 340), 3);
    expect(adaptiveColumnCount(5000, target: 340, max: 4), 4);
    expect(adaptiveColumnCount(0), 1);
  });
}
