import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mirdaily_app/core/responsive/breakpoints.dart';
import 'package:mirdaily_app/core/responsive/content_shell.dart';
import 'package:mirdaily_app/core/theme/app_theme.dart';
import 'package:mirdaily_app/features/biblioteca/biblioteca_hub_screen.dart';
import 'package:mirdaily_app/features/electros/electros_hub_screen.dart';
import 'package:mirdaily_app/features/premium/screens/premium_screen.dart';

/// Las pantallas clave se montan sin overflow ni excepciones en móvil,
/// tablet vertical y tablet horizontal, y las rejillas usan el nº de
/// columnas que toca.
void main() {
  Future<void> pumpAt(WidgetTester tester, Size size, Widget screen) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: screen,
    ));
    await tester.pump(const Duration(milliseconds: 600));
  }


  group('Hub de Studio', () {
    for (final size in const [
      Size(390, 844),
      Size(834, 1194),
      Size(1280, 800),
    ]) {
      testWidgets('se monta sin overflow en $size', (tester) async {
        await pumpAt(tester, size, const BibliotecaHubScreen());
        expect(tester.takeException(), isNull);
        // Las 5 herramientas están.
        for (final t in ['Mazos', 'Flashcards', 'Simulacros', 'Electros', 'Apuntes']) {
          expect(find.text(t), findsOneWidget, reason: '$t en $size');
        }
      });
    }

    testWidgets('una columna en móvil, varias en tablet', (tester) async {
      // Móvil: cada herramienta debajo de la anterior (misma x, y creciente).
      await pumpAt(tester, const Size(390, 844), const BibliotecaHubScreen());
      final mazosM = tester.getTopLeft(find.text('Mazos'));
      final flashM = tester.getTopLeft(find.text('Flashcards'));
      expect(flashM.dx, moreOrLessEquals(mazosM.dx, epsilon: 1));
      expect(flashM.dy, greaterThan(mazosM.dy + 40));

      // Tablet horizontal: 'Mazos' y 'Flashcards' en la misma fila.
      await pumpAt(tester, const Size(1280, 800), const BibliotecaHubScreen());
      final mazosT = tester.getTopLeft(find.text('Mazos'));
      final flashT = tester.getTopLeft(find.text('Flashcards'));
      expect(flashT.dy, moreOrLessEquals(mazosT.dy, epsilon: 1),
          reason: 'misma fila');
      expect(flashT.dx, greaterThan(mazosT.dx + 100), reason: 'otra columna');
    });
  });

  group('Pantallas simples se acotan y no desbordan en tablet', () {
    testWidgets('Electros hub', (tester) async {
      for (final s in const [Size(390, 844), Size(1280, 800)]) {
        await pumpAt(tester, s, const ElectrosHubScreen());
        expect(tester.takeException(), isNull, reason: '$s');
        expect(find.text('Academia ECG'), findsOneWidget);
      }
    });

    testWidgets('Premium', (tester) async {
      for (final s in const [Size(390, 844), Size(1280, 800)]) {
        await pumpAt(tester, s, const PremiumScreen());
        expect(tester.takeException(), isNull, reason: '$s');
      }
    });

    testWidgets('BodyConstraint acota el ancho del scroll en tablet',
        (tester) async {
      await pumpAt(tester, const Size(1280, 800), const PremiumScreen());
      final scrollW = tester
          .getSize(find.byType(SingleChildScrollView).first)
          .width;
      expect(scrollW, lessThan(1000), reason: 'el cuerpo no ocupa los 1280');

      await pumpAt(tester, const Size(390, 844), const PremiumScreen());
      final scrollWMobile = tester
          .getSize(find.byType(SingleChildScrollView).first)
          .width;
      expect(scrollWMobile, 390, reason: 'en móvil ocupa todo el ancho');
    });
  });
}
