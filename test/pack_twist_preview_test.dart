// Cómo queda la animación de "retorcer el sobre", momento a momento.
//
//   flutter test test/pack_twist_preview_test.dart --update-goldens
//
// No es una maqueta: monta el juego DE VERDAD y le da vueltas al dedo
// alrededor del sobre. Si la animación cambia, las imágenes cambian.
import 'dart:math';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mirdaily_app/core/theme/app_theme.dart';
import 'package:mirdaily_app/features/quiz/game/pack_twist_game.dart';

const _asignaturas = [
  'Cardiología',
  'Digestivo',
  'Neurología',
  'Infecciosas',
  'Ginecología',
];

void main() {
  const w = 390.0, h = 780.0;
  const sobre = ValueKey('sobre');

  /// Avanza el reloj fotograma a fotograma. De un tirón no sirve: el juego
  /// acota el `dt` a 33 ms, así que un `pump` de un segundo avanzaría 33.
  Future<void> avanzar(WidgetTester tester, double segundos) async {
    for (var i = 0; i < (segundos / 0.016).round(); i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  testWidgets('el sobre que se retuerce, momento a momento', (tester) async {
    tester.view.physicalSize = const Size(w, h);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final game = PackTwistGame(specialties: _asignaturas, onComplete: (_) {});

    // Los PNG del sobre se decodifican de verdad, y eso no ocurre con el reloj
    // falso de `pump`: hay que dejar correr el reloj REAL o el juego se pinta
    // sin envoltorio y las fotos salen en blanco.
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          home: Scaffold(
            backgroundColor: AppColors.background,
            body: GameWidget(key: sobre, game: game),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await tester.pump();
    });
    await avanzar(tester, 0.3);

    // 1. En reposo: la flecha curva dando vueltas al sobre.
    await expectLater(
      find.byKey(sobre),
      matchesGoldenFile('goldens/pack_twist_1_reposo.png'),
    );

    // El dedo describe círculos alrededor del centro del sobre.
    final centro = game.debugPackRect.center;
    const radio = 105.0;

    Offset enAngulo(double a) =>
        Offset(centro.dx + cos(a) * radio, centro.dy + sin(a) * radio * 0.85);

    var angulo = 0.0;
    final gesto = await tester.startGesture(enAngulo(angulo));

    /// Gira el dedo [vueltas] de vuelta, en pasos cortos: el juego suma los
    /// saltos de ángulo, y a pasos largos se confundiría el sentido del giro.
    Future<void> girar(double vueltas) async {
      const pasos = 40;
      for (var i = 0; i < pasos; i++) {
        angulo += vueltas * 2 * pi / pasos;
        await gesto.moveTo(enAngulo(angulo));
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    // 2. Media vuelta: el cuello ya se ha escurrido.
    await girar(0.5);
    await expectLater(
      find.byKey(sobre),
      matchesGoldenFile('goldens/pack_twist_2_escurriendo.png'),
    );

    // 3. Una vuelta y cuarto: pliegues marcados y chispas saliendo del cuello.
    await girar(0.75);
    await expectLater(
      find.byKey(sobre),
      matchesGoldenFile('goldens/pack_twist_3_al_limite.png'),
    );

    // 4. Se rompe por el cuello.
    await girar(0.6);
    await avanzar(tester, 0.22);
    await expectLater(
      find.byKey(sobre),
      matchesGoldenFile('goldens/pack_twist_4_rotura.png'),
    );

    // 5. Las mitades saliendo, con las cartas ya en camino.
    await avanzar(tester, 0.5);
    await expectLater(
      find.byKey(sobre),
      matchesGoldenFile('goldens/pack_twist_5_mitades.png'),
    );

    // Romper el sobre encadena TODO el premio (repartir, revelar, recoger,
    // barajar y salir), que son unos 11 segundos de `Future.delayed`. Hay que
    // dejarlos terminar o el test acaba con temporizadores vivos y falla.
    await gesto.up();
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(seconds: 4));
    }
  });
}
