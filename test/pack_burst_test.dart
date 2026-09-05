import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mirdaily_app/features/quiz/game/pack_burst_game.dart';

/// El gesto de la apertura alternativa: **apretar hasta que revienta**.
///
/// Lo que se comprueba aquí es que el apretón se comporta como se promete: se
/// carga mientras el dedo aguanta, se desinfla si se suelta antes de tiempo, y
/// solo cuenta si el dedo cae SOBRE el sobre —si valiera cualquier sitio de la
/// pantalla, el sobre se abriría al deslizar entre pestañas—.
void main() {
  const specialties = ['Cardiología', 'Digestivo', 'Neuro', 'Nefro', 'Endo'];
  const gameKey = ValueKey('sobre');

  /// Monta el juego en una columna centrada, como hace QuizScreen en tablet.
  /// Devuelve el rectángulo que ocupa el GameWidget en la ventana.
  Future<Rect> pumpGame(
    WidgetTester tester,
    PackBurstGame game, {
    Size window = const Size(800, 1280),
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

    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    return tester.getRect(find.byKey(gameKey));
  }

  /// Avanza fotograma a fotograma. De un tirón no sirve: el juego acota el
  /// `dt` a 33 ms, así que un `pump` de un segundo avanzaría 33 ms.
  Future<void> avanzar(WidgetTester tester, double segundos) async {
    for (var i = 0; i < (segundos / 0.016).round(); i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  testWidgets('apretar sobre el sobre lo va cargando', (tester) async {
    final game = PackBurstGame(specialties: specialties, onComplete: (_) {});
    final rect = await pumpGame(tester, game);

    expect(game.openProgress, 0);

    final centro =
        Offset(game.debugPackRect.center.dx, game.debugPackRect.center.dy) +
        rect.topLeft;

    final gesto = await tester.startGesture(centro);
    await avanzar(tester, 0.5);

    expect(game.openProgress, greaterThan(0.2));
    expect(game.opened, isFalse, reason: 'medio segundo no basta');

    await gesto.up();
    await tester.pump(const Duration(milliseconds: 16));
  });

  testWidgets('el mecido se apaga poco a poco al agarrar el sobre',
      (tester) async {
    // El sobre se mece mientras nadie lo toca, y se queda quieto en cuanto se
    // agarra. Apagando ese mecido de golpe, saltaba de donde estuviera del
    // vaivén —hasta 5 puntos— a su altura de reposo en un solo fotograma, y
    // se notaba como un tic seco justo al empezar el gesto.
    //
    // Lo que se comprueba es que el apagado TARDA: ni se queda encendido ni
    // se corta en el mismo fotograma en que cae el dedo.
    final game = PackBurstGame(specialties: specialties, onComplete: (_) {});
    final rect = await pumpGame(tester, game);

    expect(game.debugFloatAmount, 1.0, reason: 'en reposo, meciéndose');

    final centro =
        Offset(game.debugPackRect.center.dx, game.debugPackRect.center.dy) +
            rect.topLeft;
    final gesto = await tester.startGesture(centro);

    // Un par de fotogramas después ya ha empezado a apagarse, pero no está
    // apagado: eso es lo que hace que no se vea el corte.
    await avanzar(tester, 0.033);
    expect(game.debugFloatAmount, lessThan(1.0));
    expect(game.debugFloatAmount, greaterThan(0.3));

    // Y para cuando el dedo lleva un rato, el sobre está quieto del todo.
    await avanzar(tester, 0.5);
    expect(game.debugFloatAmount, lessThan(0.02));

    await gesto.up();
    await tester.pump(const Duration(milliseconds: 16));
  });

  testWidgets('soltar antes de tiempo lo desinfla del todo', (tester) async {
    final game = PackBurstGame(specialties: specialties, onComplete: (_) {});
    final rect = await pumpGame(tester, game);

    final centro =
        Offset(game.debugPackRect.center.dx, game.debugPackRect.center.dy) +
        rect.topLeft;

    final gesto = await tester.startGesture(centro);
    await avanzar(tester, 0.5);
    expect(game.openProgress, greaterThan(0.2));

    await gesto.up();
    // El desinflado es elástico y dura menos de medio segundo.
    await avanzar(tester, 0.7);

    expect(game.openProgress, 0);
    expect(game.opened, isFalse);
  });

  testWidgets('aguantar hasta el final lo revienta', (tester) async {
    var completado = false;
    final game = PackBurstGame(
      specialties: specialties,
      onComplete: (_) => completado = true,
    );
    final rect = await pumpGame(tester, game);

    final centro =
        Offset(game.debugPackRect.center.dx, game.debugPackRect.center.dy) +
        rect.topLeft;

    final gesto = await tester.startGesture(centro);
    await avanzar(tester, 1.3); // el apretón dura 1,15 s

    expect(game.openProgress, 1.0, reason: 'debería haber reventado');

    // El premio no arranca en el mismo fotograma que el reventón: las dos
    // mitades tienen un cuarto de segundo para despejar el centro antes de que
    // salga la primera carta.
    expect(game.opened, isFalse);
    await avanzar(tester, 0.35);
    expect(game.opened, isTrue, reason: 'las cartas deberían venir ya');

    await gesto.up();

    // Reventar encadena todo el premio (repartir, revelar, barajar, salir).
    // Hay que dejarlo terminar o el test acaba con temporizadores vivos.
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(seconds: 4));
    }
    expect(completado, isTrue, reason: 'el premio no llegó a su fin');
  });

  testWidgets('apretar fuera del sobre no hace nada', (tester) async {
    final game = PackBurstGame(specialties: specialties, onComplete: (_) {});
    final rect = await pumpGame(tester, game);

    // Bien lejos del sobre: arriba del todo, donde vive el selector.
    final fuera = Offset(game.debugPackRect.center.dx, 24) + rect.topLeft;
    expect(game.debugPressZone.contains(fuera - rect.topLeft), isFalse);

    final gesto = await tester.startGesture(fuera);
    await avanzar(tester, 0.9);

    expect(game.openProgress, 0);
    expect(game.opened, isFalse);

    await gesto.up();
    await tester.pump(const Duration(milliseconds: 16));
  });

  testWidgets('el sobre que revienta también se recoloca al girar', (
    tester,
  ) async {
    final game = PackBurstGame(specialties: specialties, onComplete: (_) {});

    // Se carga en horizontal...
    await pumpGame(tester, game, window: const Size(1280, 800));

    // ...y se gira a vertical.
    await tester.binding.setSurfaceSize(const Size(800, 1280));
    await avanzar(tester, 0.1);
    final rect = tester.getRect(find.byKey(gameKey));

    expect(game.debugPackRect.center.dy, closeTo(rect.height / 2 - 30, 1));

    // Y se sigue pudiendo abrir donde se ve.
    final centro =
        Offset(game.debugPackRect.center.dx, game.debugPackRect.center.dy) +
        rect.topLeft;
    final gesto = await tester.startGesture(centro);
    await avanzar(tester, 0.4);
    expect(game.openProgress, greaterThan(0));

    await gesto.up();
    await tester.pump(const Duration(milliseconds: 16));
  });
}
