// El selector de animación del sobre.
//
//   flutter test test/pack_style_selector_test.dart --update-goldens
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mirdaily_app/core/providers/settings_provider.dart';
import 'package:mirdaily_app/core/theme/app_theme.dart';
import 'package:mirdaily_app/features/quiz/widgets/pack_style_selector.dart';

void main() {
  Widget host(
    PackOpeningStyle value,
    ValueChanged<PackOpeningStyle> onChanged,
  ) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: PackStyleSelector(value: value, onChanged: onChanged),
        ),
      ),
    );
  }

  testWidgets('cómo se ve el selector, con la pastilla en cada sitio',
      (tester) async {
    tester.view.physicalSize = const Size(360, 120);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    for (final estilo in PackOpeningStyle.values) {
      await tester.pumpWidget(host(estilo, (_) {}));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(PackStyleSelector),
        matchesGoldenFile('goldens/pack_style_selector_${estilo.name}.png'),
      );
    }
  });

  testWidgets('cabe en el móvil más estrecho que soporta la app',
      (tester) async {
    // 360 puntos de ancho. Con tres opciones el control ya no sobra de
    // tamaño: si alguien añade una cuarta, esto es lo que va a avisar.
    tester.view.physicalSize = const Size(360, 200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(PackOpeningStyle.tear, (_) {}));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(PackStyleSelector)).width,
      lessThanOrEqualTo(360),
    );
  });

  testWidgets('tocar otra opción avisa del cambio', (tester) async {
    PackOpeningStyle? elegido;
    await tester.pumpWidget(host(PackOpeningStyle.tear, (v) => elegido = v));

    await tester.tap(find.text('Apretar'));
    await tester.pump();
    expect(elegido, PackOpeningStyle.burst);

    await tester.tap(find.text('Retorcer'));
    await tester.pump();
    expect(elegido, PackOpeningStyle.twist);

    // Tocar la que ya está puesta no avisa: rehacer el juego por nada
    // reiniciaría la animación del sobre delante del usuario.
    elegido = null;
    await tester.tap(find.text('Rasgar'));
    await tester.pump();
    expect(elegido, isNull);
  });

  test('el estilo elegido se recuerda entre sesiones', () async {
    SharedPreferences.setMockInitialValues({});

    final ajustes = SettingsProvider();
    expect(
      ajustes.packOpeningStyle,
      PackOpeningStyle.burst,
      reason: 'de fábrica, apretar: es el gesto que se descubre solo',
    );

    await ajustes.setPackOpeningStyle(PackOpeningStyle.twist);

    // Otra sesión: se relee de disco.
    final siguiente = SettingsProvider();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(siguiente.packOpeningStyle, PackOpeningStyle.twist);
  });

}
