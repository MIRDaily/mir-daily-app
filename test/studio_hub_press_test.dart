// El hundimiento de las tarjetas pulsables.
//
//   flutter test test/studio_hub_press_test.dart
//
// Lo que importa aquí es el TOQUE RÁPIDO dentro de una lista, que es como se
// usa la app de verdad. Dentro de un scrollable, el reconocedor de toque
// compite con el de arrastre y no avisa del `onTapDown` hasta que gana la
// puja — normalmente al levantar el dedo. Así que en un toque corto el
// `onTapDown` y el `onTapUp` llegan casi juntos y el hundimiento no llega a
// pintarse ni un fotograma.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

import 'package:mirdaily_app/core/theme/app_theme.dart';
import 'package:mirdaily_app/features/biblioteca/biblioteca_hub_screen.dart';
import 'package:mirdaily_app/shared/sticker/sticker.dart';

Vector3 _traslacion(WidgetTester tester, Finder card) => tester
    .widget<AnimatedContainer>(
      find.descendant(of: card, matching: find.byType(AnimatedContainer)).first,
    )
    .transform!
    .getTranslation();

void main() {
  testWidgets('un toque rapido dentro de una lista se ve hundir',
      (tester) async {
    var pulsada = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          // La lista es parte del caso: fuera de un scrollable el gesto se
          // resuelve al instante y el fallo no se reproduce.
          body: ListView(
            children: [
              StickerCard(
                onTap: () => pulsada++,
                pressDelay: const Duration(milliseconds: 120),
                padding: const EdgeInsets.all(20),
                child: const Text('Mazos'),
              ),
            ],
          ),
        ),
      ),
    );

    final card = find.byType(StickerCard);
    expect(_traslacion(tester, card).x, 0);

    // Toque rápido, como el de un dedo de verdad.
    await tester.tap(card);
    await tester.pump(const Duration(milliseconds: 60));

    expect(_traslacion(tester, card).x, greaterThan(0),
        reason: 'a mitad del toque tiene que verse hundida');
    expect(pulsada, 0, reason: 'la accion espera a que se vea el gesto');

    // Y al terminar, sube y ejecuta.
    await tester.pump(const Duration(milliseconds: 300));
    expect(pulsada, 1);
    expect(_traslacion(tester, card).x, 0);
  });

  testWidgets('el hub de Studio pasa onTap y pressDelay a sus tarjetas',
      (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const BibliotecaHubScreen(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    // Las cinco herramientas: Mazos, Flashcards, Simulacros, Electros, Apuntes.
    // La lista construye solo lo que se ve, así que aquí no salen las cinco.
    final cards = tester.widgetList<StickerCard>(find.byType(StickerCard));
    expect(cards.length, greaterThanOrEqualTo(4));
    for (final c in cards) {
      expect(c.onTap, isNotNull, reason: 'toda tarjeta del hub se pulsa');
      expect(c.pressDelay, const Duration(milliseconds: 120));
    }
  });
}
