// El carné del perfil, en sus dos estados.
//
//   flutter test test/profile_card_test.dart --update-goldens
//
// Se puede pintar sin providers ni red porque el avatar se inyecta ya
// construido; ese fue justo el motivo de sacarlo de la pantalla.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mirdaily_app/core/theme/app_theme.dart';
import 'package:mirdaily_app/features/profile/widgets/profile_card.dart';
import 'package:mirdaily_app/shared/sticker/sticker.dart';

Widget _avatarFalso() => const ColoredBox(
      color: Color(0xFFD8CFC9),
      child: Icon(Icons.person_rounded, size: 44, color: Colors.white),
    );

void main() {
  testWidgets('carne con bio y sin bio', (tester) async {
    tester.view.physicalSize = const Size(420, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: Scaffold(
          backgroundColor: AppColors.background,
          body: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionLabel('Con bio'),
                ProfileCard(
                  name: 'Alejandro',
                  handle: '@alejandro',
                  avatar: _avatarFalso(),
                  chips: const ['Alergología', 'Universidad de Sevilla'],
                  bio: 'Probando el carné nuevo desde producción. '
                      'Opositor de segunda vuelta.',
                  seed: 'demo-user-id',
                  onTapAvatar: () {},
                  onTapBio: () {},
                ),
                const SizedBox(height: 18),
                // Contenido CENTRADO dentro de una StickerCard: es lo que se
                // descentraba, porque el Stack de la textura aflojaba las
                // restricciones y la columna se encogía a su texto más ancho.
                const SectionLabel('Cifras'),
                Row(
                  children: [
                    for (final t in const [
                      ('Racha', '12'),
                      ('Récord', '31'),
                      ('Dailys', '148'),
                    ]) ...[
                      Expanded(
                        child: StickerCard(
                          depth: 4,
                          radius: 20,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          child: Column(
                            children: [
                              const Icon(Icons.local_fire_department_rounded,
                                  color: Color(0xFFEF8354), size: 24),
                              const SizedBox(height: 6),
                              Text(t.$2,
                                  style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w900,
                                      color: kInk)),
                              Text(t.$1,
                                  style: const TextStyle(
                                      fontSize: 12, color: kMuted)),
                            ],
                          ),
                        ),
                      ),
                      if (t.$1 != 'Dailys') const SizedBox(width: 12),
                    ],
                  ],
                ),
                const SizedBox(height: 18),
                const SectionLabel('Sin bio'),
                ProfileCard(
                  name: 'admin2',
                  handle: '@admin2',
                  avatar: _avatarFalso(),
                  chips: const [],
                  seed: 'otro-usuario',
                  onTapAvatar: () {},
                  onTapBio: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // El destello del laminado va en bucle, así que no se puede `pumpAndSettle`.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);
    // Sin bio hay que ver la invitación: si no, el campo no existe a ojos
    // del usuario.
    expect(find.text('Escribe algo sobre ti'), findsOneWidget);

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/profile_card.png'),
    );
  });
}
