// Cómo queda la animación de "apretar hasta que revienta", fotograma a
// fotograma.
//
//   flutter test test/pack_burst_preview_test.dart --update-goldens
//
// No es una maqueta: monta el juego DE VERDAD, mantiene el dedo apretado y
// fotografía los momentos que importan. Si la animación cambia, las imágenes
// cambian.
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mirdaily_app/core/theme/app_theme.dart';
import 'package:mirdaily_app/features/quiz/game/pack_burst_game.dart';

const _asignaturas = [
  'Cardiología',
  'Digestivo',
  'Neurología',
  'Infecciosas',
  'Ginecología',
];

void main() {
  const w = 390.0, h = 780.0;

  /// Avanza el reloj en pasos de un fotograma.
  ///
  /// De uno en uno y no de un tirón porque el juego ACOTA el `dt` a 33 ms para
  /// no dar saltos: un `pump` de un segundo avanzaría 33 ms, no mil.
  Future<void> avanzar(WidgetTester tester, double segundos) async {
    final frames = (segundos / 0.016).round();
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  testWidgets('el sobre que revienta, momento a momento', (tester) async {
    tester.view.physicalSize = const Size(w, h);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final game = PackBurstGame(specialties: _asignaturas, onComplete: (_) {});

    // Los PNG del sobre se decodifican de verdad, y eso no ocurre con el
    // reloj falso de `pump`: hay que dejar correr el reloj REAL o el juego se
    // pinta sin envoltorio y las fotos salen en blanco.
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          home: Scaffold(
            backgroundColor: AppColors.background,
            body: GameWidget(key: const ValueKey('sobre'), game: game),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await tester.pump();
    });

    await avanzar(tester, 0.4); // un poco de flotado

    final sobre = find.byKey(const ValueKey('sobre'));

    // 1. En reposo, con la pista asomando: el dedo baja sobre el centro.
    await avanzar(tester, 0.5); // dentro de la ventana de aparición
    await expectLater(
      sobre,
      matchesGoldenFile('goldens/pack_burst_1_reposo.png'),
    );

    // 1b. Y en el descanso NO hay nada encima del sobre. La pista solo asoma
    // dos segundos de cada siete y medio: un dedo dando toques en bucle deja
    // de leerse como indicación y pasa a ser ruido sobre la ilustración.
    await avanzar(tester, 2.2);
    await expectLater(
      sobre,
      matchesGoldenFile('goldens/pack_burst_1b_sin_pista.png'),
    );

    // El dedo cae en el centro del sobre y NO se levanta.
    final centro = Offset(
      game.debugPackRect.center.dx,
      game.debugPackRect.center.dy,
    );
    final gesto = await tester.startGesture(centro);

    // 2. A medio apretar: ya se ha ensanchado y las chispas se acercan.
    await avanzar(tester, 0.55);
    await expectLater(
      sobre,
      matchesGoldenFile('goldens/pack_burst_2_apretando.png'),
    );

    // 3. Al límite: temblando y a punto de romperse.
    await avanzar(tester, 0.45);
    await expectLater(
      sobre,
      matchesGoldenFile('goldens/pack_burst_3_al_limite.png'),
    );

    // 4. El reventón: estrella de impacto y confeti.
    await avanzar(tester, 0.25);
    await expectLater(
      sobre,
      matchesGoldenFile('goldens/pack_burst_4_reventon.png'),
    );

    // 5. Las dos mitades saliendo despedidas, con las cartas ya asomando.
    await avanzar(tester, 0.45);
    await expectLater(
      sobre,
      matchesGoldenFile('goldens/pack_burst_5_mitades.png'),
    );

    // Reventar el sobre encadena TODO el premio (repartir, revelar, recoger,
    // barajar y salir), que son unos 11 segundos de `Future.delayed`. Hay que
    // dejar que terminen o el test acaba con temporizadores vivos y falla.
    await gesto.up();
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(seconds: 4));
    }
  });
}
