// Muestrario del kit visual: renderiza las primitivas y las texturas a una
// imagen, para poder mirar el resultado sin levantar la app.
//
//   flutter test test/sticker_kit_preview_test.dart --update-goldens
//
// Deja la imagen en test/goldens/sticker_kit.png. No es una prueba de
// regresión: es una hoja de contactos del sistema de diseño.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mirdaily_app/core/theme/app_theme.dart';
import 'package:mirdaily_app/shared/sticker/sticker.dart';
import 'package:mirdaily_app/shared/sticker/textures.dart';
import 'package:mirdaily_app/features/biblioteca/widgets/studio_card_art.dart';

void main() {
  testWidgets('muestrario del kit sticker', (tester) async {
    tester.view.physicalSize = const Size(420, 1500);
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
                const StickerHero(
                  badge: 'Studio',
                  badgeIcon: Icons.auto_awesome_rounded,
                  title: 'Tu centro de estudio',
                  subtitle: 'Repasa, ponte a prueba y consulta el temario.',
                ),
                const SizedBox(height: 22),
                const SectionLabel('Ilustraciones del hub'),
                StickerCard(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: const [
                      DeckCardArt(),
                      ExamSheetArt(),
                      FlashcardFlipArt(),
                      EcgMonitorArt(),
                    ],
                  ),
                ),
                const SectionLabel('Texturas'),
                StickerCard(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  texture: ruledPaper(),
                  child: const SizedBox(
                    height: 150,
                    width: double.infinity,
                    child: Text('Cartulina rayada — flashcards y mazos'),
                  ),
                ),
                StickerCard(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  texture: graphPaper(tint: const Color(0xFFC45B4B)),
                  child: const Text('Papel milimetrado — electros'),
                ),
                StickerCard(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  texture: laminatedPaper(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Carné plastificado — perfil'),
                      const SizedBox(height: 12),
                      const SerialBarcode(seed: 'demo-user-id'),
                      const SizedBox(height: 6),
                      Text('Nº ${serialOf('demo-user-id')}'),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                const SectionLabel('Controles'),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    const StepBadge(n: 1, active: true),
                    const StepBadge(n: 2),
                    const StatChip(value: '87', label: 'por repasar'),
                    const DocChip(
                        label: 'Público', icon: Icons.visibility_rounded),
                    const DocChip(label: 'Acierto', tone: DocTone.success),
                    const DocChip(label: 'Fallo', tone: DocTone.error),
                    const DocChip(label: 'Coral', tone: DocTone.accent),
                    InkSwitch(value: true, onChanged: (_) {}),
                    InkIconButton(icon: Icons.delete_outline_rounded, onTap: () {}),
                  ],
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    StickerButton(
                        label: 'Principal',
                        icon: Icons.check_rounded,
                        onPressed: () {}),
                    GhostButton(label: 'Secundario', onPressed: () {}),
                  ],
                ),
                const SizedBox(height: 12),
                const StickerButton(label: 'Deshabilitado'),
                const SizedBox(height: 18),
                const SectionLabel('Campo de texto'),
                InkInput(
                  controller: TextEditingController(text: 'alejandro'),
                  prefix: '@',
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // Las ilustraciones se animan en bucle, así que `pumpAndSettle` no
    // terminaría nunca: se avanza a mano hasta un punto concreto del ciclo.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/sticker_kit.png'),
    );
  });
}
