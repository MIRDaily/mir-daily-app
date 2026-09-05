import 'dart:math';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mirdaily_app/features/quiz/game/pack_twist_game.dart';

/// El gesto de la tercera apertura: **retorcer**.
///
/// Lo que se comprueba aquí es lo que tiene de particular frente a las otras
/// dos: que suma vueltas en los DOS sentidos, que cruzar el eje de las 9 en
/// punto no cuenta como una vuelta entera de golpe, y que solo responde si el
/// dedo cae sobre el sobre —si valiera cualquier sitio, se abriría al deslizar
/// entre pestañas—.
void main() {
  const specialties = ['Cardiología', 'Digestivo', 'Neuro', 'Nefro', 'Endo'];
  const gameKey = ValueKey('sobre');

  Future<Rect> pumpGame(
    WidgetTester tester,
    PackTwistGame game, {
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

  Future<void> avanzar(WidgetTester tester, double segundos) async {
    for (var i = 0; i < (segundos / 0.016).round(); i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  /// Da [vueltas] al dedo alrededor del centro del sobre. En sentido horario
  /// si [vueltas] es positivo. A pasos cortos: el juego suma saltos de ángulo,
  /// y a pasos largos no podría saber hacia dónde se ha girado.
  Future<TestGesture> girar(
    WidgetTester tester,
    PackTwistGame game,
    Rect rect,
    double vueltas, {
    TestGesture? conGesto,
    double desde = 0,
  }) async {
    final centro = game.debugPackRect.center + rect.topLeft;
    const radio = 100.0;
    Offset en(double a) =>
        centro + Offset(cos(a) * radio, sin(a) * radio * 0.85);

    var angulo = desde;
    final gesto = conGesto ?? await tester.startGesture(en(angulo));

    const pasosPorVuelta = 40;
    final pasos = (pasosPorVuelta * vueltas.abs()).round();
    for (var i = 0; i < pasos; i++) {
      angulo += vueltas.sign * 2 * pi / pasosPorVuelta;
      await gesto.moveTo(en(angulo));
      await tester.pump(const Duration(milliseconds: 16));
    }
    return gesto;
  }

  testWidgets('girar el dedo alrededor del sobre lo va retorciendo',
      (tester) async {
    final game = PackTwistGame(specialties: specialties, onComplete: (_) {});
    final rect = await pumpGame(tester, game);

    expect(game.openProgress, 0);

    final gesto = await girar(tester, game, rect, 0.5);

    expect(game.openProgress, greaterThan(0.2));
    expect(game.opened, isFalse, reason: 'media vuelta no basta');

    await gesto.up();
    await tester.pump(const Duration(milliseconds: 16));
  });

  // Un envoltorio se retuerce en los dos sentidos. Si solo contara uno, media
  // clientela lo giraría "mal" y no pasaría nada.
  //
  // Media vuelta son pi radianes de las 3,4·pi que hacen falta, o sea 1/3,4
  // del recorrido. Se afirma ese número y no una comparación entre los dos
  // sentidos: cada juego va en su propio test para que no compartan el estado
  // del GameWidget, que es lo que hacía salir cuentas distintas.
  for (final (nombre, vueltas) in const [('horario', 0.5), ('antihorario', -0.5)]) {
    testWidgets('media vuelta en sentido $nombre retuerce lo mismo',
        (tester) async {
      final game = PackTwistGame(specialties: specialties, onComplete: (_) {});
      final rect = await pumpGame(tester, game);

      final gesto = await girar(tester, game, rect, vueltas);

      expect(game.openProgress, closeTo(1 / 3.4, 0.02));

      await gesto.up();
      await tester.pump(const Duration(milliseconds: 16));
    });
  }

  testWidgets('soltar a medias lo destuerce del todo', (tester) async {
    final game = PackTwistGame(specialties: specialties, onComplete: (_) {});
    final rect = await pumpGame(tester, game);

    final gesto = await girar(tester, game, rect, 0.5);
    expect(game.openProgress, greaterThan(0.2));

    await gesto.up();
    await avanzar(tester, 1.0); // se destuerce en 0,7 s

    expect(game.openProgress, 0);
    expect(game.opened, isFalse);
  });

  testWidgets('dar las vueltas enteras lo rompe por el cuello',
      (tester) async {
    var completado = false;
    final game = PackTwistGame(
      specialties: specialties,
      onComplete: (_) => completado = true,
    );
    final rect = await pumpGame(tester, game);

    // Hacen falta 1,7 vueltas; se dan 2 para no quedarse justo en el borde.
    final gesto = await girar(tester, game, rect, 2);

    expect(game.openProgress, 1.0, reason: 'debería haberse roto');

    // El premio no arranca en el mismo fotograma: las mitades tienen un
    // cuarto de segundo para despejar el centro antes de la primera carta.
    await avanzar(tester, 0.35);
    expect(game.opened, isTrue);

    await gesto.up();

    // Romperlo encadena todo el premio. Hay que dejarlo terminar o el test
    // acaba con temporizadores vivos.
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(seconds: 4));
    }
    expect(completado, isTrue, reason: 'el premio no llegó a su fin');
  });

  testWidgets('girar lejos del sobre no hace nada', (tester) async {
    final game = PackTwistGame(specialties: specialties, onComplete: (_) {});
    final rect = await pumpGame(tester, game);

    // Arriba del todo, donde vive el selector: fuera de la corona de giro.
    final fuera = Offset(game.debugPackRect.center.dx, 20);
    expect(game.debugTurnZone.contains(fuera), isFalse);

    final gesto = await tester.startGesture(fuera + rect.topLeft);
    for (var i = 0; i < 40; i++) {
      await gesto.moveBy(const Offset(9, 5));
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(game.openProgress, 0);
    expect(game.opened, isFalse);

    await gesto.up();
    await tester.pump(const Duration(milliseconds: 16));
  });

  testWidgets('el sobre que se retuerce también se recoloca al girar la '
      'pantalla', (tester) async {
    final game = PackTwistGame(specialties: specialties, onComplete: (_) {});

    await pumpGame(tester, game, window: const Size(1280, 800));

    await tester.binding.setSurfaceSize(const Size(800, 1280));
    await avanzar(tester, 0.1);
    final rect = tester.getRect(find.byKey(gameKey));

    expect(game.debugPackRect.center.dy, closeTo(rect.height / 2 - 30, 1));

    final gesto = await girar(tester, game, rect, 0.4);
    expect(game.openProgress, greaterThan(0));

    await gesto.up();
    await tester.pump(const Duration(milliseconds: 16));
  });
}
