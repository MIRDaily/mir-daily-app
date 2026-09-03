import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mirdaily_app/core/theme/app_theme.dart';
import 'package:mirdaily_app/features/biblioteca/biblioteca_hub_screen.dart';
import 'package:mirdaily_app/features/electros/electros_hub_screen.dart';
import 'package:mirdaily_app/features/premium/screens/premium_screen.dart';
import 'package:mirdaily_app/features/premium/widgets/premium_showcase.dart';

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

    // Premium ya no se acota con `BodyConstraint` sino con el gutter centrado
    // de `centeringGutter(wide: true)`, como el hub de Studio: el scroll ocupa
    // todo el ancho y lo que se acota es el CONTENIDO.
    testWidgets('el contenido se acota y se centra en tablet', (tester) async {
      await pumpAt(tester, const Size(1280, 800), const PremiumScreen());
      final heroTablet = tester.getRect(find.byType(PremiumHeroCard));
      expect(heroTablet.width, lessThan(1200),
          reason: 'el contenido no ocupa los 1280');
      expect(heroTablet.left, greaterThan(40),
          reason: 'centrado, no pegado al borde');

      await pumpAt(tester, const Size(390, 844), const PremiumScreen());
      final heroMovil = tester.getRect(find.byType(PremiumHeroCard));
      expect(heroMovil.left, 20, reason: 'en móvil, el gutter de siempre');
      expect(heroMovil.width, 350, reason: '390 menos los dos gutters');
    });

    testWidgets('las ventajas pasan a rejilla en tablet', (tester) async {
      // Móvil: una debajo de otra.
      await pumpAt(tester, const Size(390, 844), const PremiumScreen());
      final ilimitadasM = tester.getTopLeft(find.text('Preguntas ilimitadas'));
      final statsM = tester.getTopLeft(find.text('Estadísticas avanzadas'));
      expect(statsM.dx, moreOrLessEquals(ilimitadasM.dx, epsilon: 1));
      expect(statsM.dy, greaterThan(ilimitadasM.dy + 40));

      // Tablet horizontal: en la misma fila.
      await pumpAt(tester, const Size(1280, 800), const PremiumScreen());
      final ilimitadasT = tester.getTopLeft(find.text('Preguntas ilimitadas'));
      final statsT = tester.getTopLeft(find.text('Estadísticas avanzadas'));
      expect(statsT.dy, moreOrLessEquals(ilimitadasT.dy, epsilon: 1),
          reason: 'misma fila');
      expect(statsT.dx, greaterThan(ilimitadasT.dx + 100),
          reason: 'otra columna');
    });
  });
}
