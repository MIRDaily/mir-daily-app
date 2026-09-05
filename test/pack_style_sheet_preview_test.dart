// Cómo queda la hoja de "Apertura del sobre" de Perfil > Jugabilidad.
//
//   flutter test test/pack_style_sheet_preview_test.dart --update-goldens
//
// La hoja de verdad vive dentro de ProfileScreen, que arrastra el backend
// entero. Aquí se monta su CONTENIDO —el mismo selector y las mismas
// explicaciones— para poder mirarlo sin red.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mirdaily_app/core/providers/settings_provider.dart';
import 'package:mirdaily_app/core/theme/app_theme.dart';
import 'package:mirdaily_app/features/quiz/widgets/pack_style_selector.dart';
import 'package:mirdaily_app/shared/sticker/sticker.dart';

/// Copia del texto de la hoja. Si cambia en ProfileScreen y no aquí, la imagen
/// deja de representar lo que ve el usuario — es el precio de poder mirarla
/// sin levantar media app.
String _como(PackOpeningStyle e) => switch (e) {
      PackOpeningStyle.tear =>
        'Desliza el dedo por la costura de arriba, donde pasa la tijera. '
            'El sobre se abre y la tapa sale volando.',
      PackOpeningStyle.burst =>
        'Mantén el dedo apretando el sobre. Se hincha, tiembla cada vez '
            'más y revienta en dos con confeti.',
      PackOpeningStyle.twist =>
        'Gira el dedo alrededor del sobre, en cualquier sentido. Se '
            'retuerce como un caramelo hasta romperse por el cuello.',
    };

void main() {
  testWidgets('la hoja de apertura del sobre', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 340);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => SettingsProvider(),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          home: Scaffold(
            backgroundColor: Colors.white,
            body: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Apertura del sobre',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 19,
                      color: kInk,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Las tres acaban en las mismas cinco cartas y en el mismo '
                    'quiz. Lo único que cambia es el gesto.',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Consumer<SettingsProvider>(
                    builder: (_, ajustes, __) => Column(
                      children: [
                        Center(
                          child: PackStyleSelector(
                            value: ajustes.packOpeningStyle,
                            onChanged: ajustes.setPackOpeningStyle,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          _como(ajustes.packOpeningStyle),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 13.5,
                            height: 1.45,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/pack_style_sheet.png'),
    );

    // Y de fábrica viene "Apretar" seleccionado.
    expect(find.text('Apretar'), findsOneWidget);
  });
}
