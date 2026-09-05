import 'dart:ui';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mirdaily_app/features/quiz/game/pack_opening_game.dart';

/// Rasgar el sobre en TABLET.
///
/// El sobre no se abría en tablet, ni en vertical ni en horizontal. La zona
/// que admite el gesto (`_tearZone`) vive en coordenadas del juego, pero los
/// manejadores de arrastre leían `info.eventPosition.global`, que es la
/// PANTALLA ENTERA (el `globalPosition` de Flutter).
///
/// En móvil los dos sistemas coinciden —el GameWidget arranca en (0,0) y ocupa
/// la pantalla— y por eso no se notaba nunca. En tablet, QuizScreen centra el
/// juego en una columna de 460 puntos y el raíl de navegación lo empuja
/// todavía más a la derecha: el toque llegaba corrido cientos de puntos y
/// caía fuera de la zona.
///
/// Lo que se comprueba aquí es justo eso: el juego DESPLAZADO dentro de la
/// ventana, que es el caso que fallaba y el que ningún test de móvil cubre.
void main() {
  const specialties = ['Cardiología', 'Digestivo', 'Neuro', 'Nefro', 'Endo'];
  const gameKey = ValueKey('sobre');

  /// Monta el juego en una columna centrada, como hace QuizScreen en tablet.
  /// Devuelve el rectángulo que ocupa el GameWidget en la ventana.
  Future<Rect> pumpOffsetGame(
    WidgetTester tester,
    PackOpeningGame game, {
    required Size window,
    double columnWidth = 460,
  }) async {
    await tester.binding.setSurfaceSize(window);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: columnWidth),
              child: GameWidget(key: gameKey, game: game),
            ),
          ),
        ),
      ),
    );

    // onLoad() carga sprites: hacen falta varios fotogramas para que el
    // FutureBuilder de GameWidget resuelva y el juego quede montado.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    return tester.getRect(find.byKey(gameKey));
  }

  /// Arrastra en horizontal desde [from] (coordenadas de la VENTANA) en pasos
  /// pequeños, como un dedo de verdad.
  Future<void> tearFrom(WidgetTester tester, Offset from, int steps) async {
    final gesture = await tester.startGesture(from);
    for (var i = 0; i < steps; i++) {
      await gesture.moveBy(const Offset(12, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 16));
  }

  for (final (name, window) in const <(String, Size)>[
    ('tablet vertical', Size(800, 1280)),
    ('tablet horizontal', Size(1280, 800)),
  ]) {
    testWidgets('el sobre se rasga en $name, con el juego descentrado',
        (tester) async {
      final game = PackOpeningGame(
        specialties: specialties,
        onComplete: (_) {},
      );

      final gameRect = await pumpOffsetGame(tester, game, window: window);

      // El juego NO ocupa la ventana: si ocupara, el test no probaría nada.
      expect(
        gameRect.left,
        greaterThan(0),
        reason: 'el caso que falla es el juego desplazado',
      );

      // La costura, en coordenadas del juego, llevada a la ventana.
      final seam = Offset(
            game.debugPackRect.center.dx,
            game.debugSeamY,
          ) +
          gameRect.topLeft;

      await tearFrom(tester, seam, 4);

      expect(
        game.tearProgress,
        greaterThan(0),
        reason: 'el gesto sobre la costura no llegó a rasgar en $name',
      );
    });
  }

  testWidgets('rasgar por el cuerpo del sobre no hace nada', (tester) async {
    // La apertura está limitada a la costura (donde salen la línea de puntos y
    // la tijera). Deslizar por el medio del sobre no es el gesto y no debe
    // abrirlo: si valiera cualquier sitio, el deslizamiento entre pestañas se
    // quedaría sin sitio donde vivir.
    final game = PackOpeningGame(
      specialties: specialties,
      onComplete: (_) {},
    );

    final gameRect =
        await pumpOffsetGame(tester, game, window: const Size(800, 1280));

    final pack = game.debugPackRect;
    final belowSeam = Offset(pack.center.dx, pack.bottom - 40) +
        gameRect.topLeft;

    await tearFrom(tester, belowSeam, 6);

    expect(game.tearProgress, 0);
  });

  // ---- Girar la tablet ----
  //
  // El sobre se colocaba en onLoad(), que corre UNA VEZ, con el tamaño que
  // tuviera la pantalla en ese momento. Al girar la tablet el juego cambiaba
  // de tamaño pero el sobre se quedaba con las cuentas de la orientación
  // anterior: cargado en horizontal y girado a vertical se quedaba pegado a
  // la parte de arriba, que es justo lo que se veía en la Tab.

  test('el sobre se recentra al cambiar de orientación', () {
    final game = PackOpeningGame(specialties: specialties, onComplete: (_) {});

    // Horizontal: la columna del sobre son 460 puntos y el alto ~800.
    game.onGameResize(Vector2(460, 800));
    expect(game.debugPackRect.center.dy, closeTo(800 / 2 - 30, 0.01));

    // Y ahora vertical, sin volver a cargar nada.
    game.onGameResize(Vector2(460, 1280));
    expect(
      game.debugPackRect.center.dy,
      closeTo(1280 / 2 - 30, 0.01),
      reason: 'el sobre se quedó donde lo dejó la otra orientación',
    );

    // La costura viaja con el sobre: si no, la zona de rasgado se quedaría
    // donde estaba y el sobre dejaría de abrirse tras girar.
    expect(game.debugTearZone.center.dy, closeTo(game.debugSeamY, 0.01));
  });

  testWidgets('tras girar la tablet, el sobre sigue rasgándose por su costura',
      (tester) async {
    final game = PackOpeningGame(specialties: specialties, onComplete: (_) {});

    // Se carga en horizontal...
    await pumpOffsetGame(tester, game, window: const Size(1280, 800));

    // ...y se gira a vertical.
    await tester.binding.setSurfaceSize(const Size(800, 1280));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final gameRect = tester.getRect(find.byKey(gameKey));

    // El sobre está centrado en el juego, no colgando de arriba.
    expect(
      game.debugPackRect.center.dy,
      closeTo(gameRect.height / 2 - 30, 1),
    );

    final seam =
        Offset(game.debugPackRect.center.dx, game.debugSeamY) +
            gameRect.topLeft;

    await tearFrom(tester, seam, 4);

    expect(game.tearProgress, greaterThan(0));
  });
}
