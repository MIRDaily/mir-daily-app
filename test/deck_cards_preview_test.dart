// Muestrario de las tarjetas de mazo: la portada del detalle y la tarjeta de
// la galería en sus dos texturas, con los casos que el informe del 24/08 pide
// vigilar — mazo sin bio, mazo con bio, mazo de fallos (sin Dominio) y mazo
// sin datos suficientes de dominio.
//
//   flutter test test/deck_cards_preview_test.dart --update-goldens
//
// Deja la imagen en test/goldens/deck_cards.png.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mirdaily_app/core/models/models.dart';
import 'package:mirdaily_app/core/theme/app_theme.dart';
import 'package:mirdaily_app/features/decks/deck_detail_screen.dart';
import 'package:mirdaily_app/features/decks/decks_screen.dart';
import 'package:mirdaily_app/shared/sticker/sticker.dart';

Deck _deck({
  required String id,
  required String name,
  String? description,
  String? gradient,
  bool auto = false,
  double accuracy = 0,
  int reviews = 0,
  int items = 0,
  String visual = 'clean',
}) =>
    Deck(
      id: id,
      name: name,
      systemGenerated: auto,
      autoType: auto ? 'failed_global' : 'none',
      accuracy: accuracy,
      totalReviews: reviews,
      visualState: visual,
      description: description,
      bannerGradient: gradient,
      totalItems: items,
    );

void main() {
  testWidgets('muestrario de tarjetas de mazo', (tester) async {
    tester.view.physicalSize = const Size(420, 1700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final conBio = _deck(
      id: '1',
      name: 'madre mia',
      description: 'Vale ahora si.',
      gradient: 'blueMist',
      accuracy: 0.72,
      reviews: 40,
      items: 3,
    );
    final sinBio = _deck(
      id: '2',
      name: 'ZZZ Vacio 1',
      gradient: 'blueNight',
      reviews: 40,
      accuracy: 0.31,
      items: 2,
      visual: 'destroyed',
    );
    final sinDatos = _deck(
      id: '3',
      name: 'Recién creado',
      description: 'Todavía sin repasos suficientes para estimar el dominio.',
      gradient: 'violet',
      items: 12,
    );
    final fallos = _deck(
      id: '4',
      name: 'Mis preguntas falladas',
      auto: true,
      accuracy: 0.24,
      reviews: 40,
      items: 50,
      visual: 'failed',
    );

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
                const SectionLabel('Portada del mazo'),
                DeckCover(deck: conBio, onEditBio: () {}),
                const SizedBox(height: 14),
                DeckCover(deck: fallos, onEditBio: null),
                const SizedBox(height: 22),
                const SectionLabel('Galeria: personalizado'),
                DeckGalleryCard(
                  deck: conBio,
                  gradientStyle: true,
                  onOpen: () {},
                  onDelete: () {},
                ),
                DeckGalleryCard(
                  deck: sinBio,
                  gradientStyle: true,
                  onOpen: () {},
                  onDelete: () {},
                ),
                const SizedBox(height: 8),
                const SectionLabel('Galeria: predeterminado'),
                DeckGalleryCard(
                  deck: sinDatos,
                  gradientStyle: false,
                  onOpen: () {},
                  onDelete: () {},
                ),
                DeckGalleryCard(
                  deck: fallos,
                  gradientStyle: false,
                  onOpen: () {},
                  onDelete: null,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // La portada va a la deriva en bucle y las barras de Dominio animan su
    // llenado: `pumpAndSettle` no terminaria, se avanza a mano.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1200));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/deck_cards.png'),
    );
  });
}
