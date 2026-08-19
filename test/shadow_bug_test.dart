// Comprobación del fallo de la sombra dura sobre relleno translúcido, y del
// hundimiento de la tarjeta pulsable.
//
//   flutter test test/shadow_bug_test.dart --update-goldens
//
// Arriba, el caso roto que llegó a producción: relleno con alpha + sombra dura
// opaca detrás, que se transparenta y deja la tarjeta azul marino. Debajo, los
// estados reales ya corregidos con `tinted()`.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mirdaily_app/core/theme/app_theme.dart';
import 'package:mirdaily_app/shared/sticker/sticker.dart';

void main() {
  testWidgets('sombra dura, relleno opaco y pulsacion', (tester) async {
    tester.view.physicalSize = const Size(420, 620);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    Widget caso(String label, Color fill) => Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: kInk, width: 2),
            boxShadow: inkShadow(3),
          ),
          child: Text(label),
        );

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: Scaffold(
          backgroundColor: AppColors.background,
          body: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionLabel('El fallo'),
                caso('alpha 0.14 — se ve la sombra a traves',
                    AppColors.primary.withValues(alpha: 0.14)),
                const SectionLabel('Los estados ya corregidos'),
                caso('Elegida', tinted(AppColors.primary, 0.20)),
                caso('Acierto', tinted(AppColors.success, 0.18)),
                caso('Fallo', tinted(AppColors.error, 0.16)),
                const SectionLabel('Tarjeta pulsable'),
                StickerCard(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.all(16),
                  onTap: () {},
                  child: const Text('En reposo'),
                ),
                StickerCard(
                  key: const Key('pulsada'),
                  padding: const EdgeInsets.all(16),
                  onTap: () {},
                  child: const Text('Hundida contra su sombra'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // Se deja una con el dedo encima para ver el hundimiento.
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('pulsada'))),
    );
    await tester.pump(const Duration(milliseconds: 150));

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/shadow_bug.png'),
    );
    await gesture.up();
  });
}
