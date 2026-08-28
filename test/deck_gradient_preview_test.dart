// Muestrario de la portada de un mazo: los ocho presets, las muestras del
// selector, la insignia de dominio y las dos texturas que puede tener una
// tarjeta de la galería.
//
//   flutter test test/deck_gradient_preview_test.dart --update-goldens
//
// Deja la imagen en test/goldens/deck_gradient.png. No es una prueba de
// regresión: es la hoja de contactos con la que comparar el resultado contra
// el de la web sin levantar la app.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mirdaily_app/core/theme/app_theme.dart';
import 'package:mirdaily_app/features/decks/widgets/deck_gradient.dart';
import 'package:mirdaily_app/shared/sticker/sticker.dart';
import 'package:mirdaily_app/shared/sticker/textures.dart';

void main() {
  testWidgets('muestrario de gradientes de mazo', (tester) async {
    tester.view.physicalSize = const Size(420, 1560);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: Scaffold(
          backgroundColor: AppColors.background,
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionLabel('Portadas'),
                for (final id in kDeckGradientIds)
                  Container(
                    height: 74,
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: kInk, width: 2),
                      boxShadow: inkShadow(4),
                      color: Colors.white,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: DeckBannerGradient(id: id, animated: false),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(14),
                            child: Text(
                              deckGradientOf(id).label,
                              style: const TextStyle(
                                color: kInk,
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 10),
                const SectionLabel('Selector'),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final id in kDeckGradientIds)
                      DeckGradientSwatch(
                        id: id,
                        size: 40,
                        selected: id == 'violet',
                      ),
                  ],
                ),
                const SizedBox(height: 22),
                const SectionLabel('Dominio'),
                const Row(
                  children: [
                    DeckMasteryBadge(percent: 72),
                    SizedBox(width: 14),
                    DeckMasteryBadge(percent: 33),
                    SizedBox(width: 14),
                    DeckMasteryBadge(percent: null),
                  ],
                ),
                const SizedBox(height: 22),
                const SectionLabel('Texturas de tarjeta'),
                StickerCard(
                  margin: const EdgeInsets.only(bottom: 12),
                  depth: 4,
                  radius: 20,
                  padding: const EdgeInsets.all(15),
                  texture: tintedPaper(AppColors.success, step: 24),
                  child: const SizedBox(
                    height: 78,
                    width: double.infinity,
                    child: Text(
                      'Predeterminado',
                      style: TextStyle(
                        color: kInk,
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                      ),
                    ),
                  ),
                ),
                StickerCard(
                  depth: 4,
                  radius: 20,
                  padding: const EdgeInsets.all(15),
                  texture: deckGradientTexture('blueMist'),
                  child: const SizedBox(
                    height: 78,
                    width: double.infinity,
                    child: Text(
                      'Personalizado',
                      style: TextStyle(
                        color: kInk,
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // La insignia de dominio anima su anillo y las portadas van a la deriva en
    // bucle, así que `pumpAndSettle` no terminaría: se avanza a mano hasta un
    // punto concreto del ciclo.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1200));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/deck_gradient.png'),
    );
  });
}
