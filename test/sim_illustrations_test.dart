// Las ilustraciones de la disposición del test, en tres momentos del ciclo.
//
//   flutter test test/sim_illustrations_test.dart --update-goldens
//
// No es una prueba de regresión: es para poder MIRAR si el gesto se entiende
// sin levantar la app.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mirdaily_app/core/theme/app_theme.dart';
import 'package:mirdaily_app/features/simulacro/widgets/sim_illustrations.dart';

void main() {
  testWidgets('clasico y deslizar', (tester) async {
    tester.view.physicalSize = const Size(360, 380);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: Scaffold(
          backgroundColor: AppColors.background,
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Clásico  ·  Deslizar, en 3 momentos'),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: const [
                    ClassicLayoutArt(),
                    SwipeLayoutArt(),
                    ClassicLayoutArt(),
                    SwipeLayoutArt(),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // Las dos se animan en bucle: se avanza a un punto concreto del ciclo.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1200));

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/sim_illustrations.png'),
    );
  });
}
