// La pestaña Premium rediseñada, en móvil y en tablet.
//
//   flutter test test/premium_preview_test.dart --update-goldens
//
// Se pinta la pantalla ENTERA (no solo el escaparate) para ver el gutter y la
// rejilla de ventajas reaccionar al ancho. El Panel de abajo necesita
// `ApiService`; sin sesión sus tres peticiones fallan solas y se quedan en su
// tarjeta de error, que es justo lo que se quiere comprobar que sigue cabiendo.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:mirdaily_app/core/services/api_service.dart';
import 'package:mirdaily_app/core/services/auth_service.dart';
import 'package:mirdaily_app/core/theme/app_theme.dart';
import 'package:mirdaily_app/features/premium/screens/premium_screen.dart';
import 'package:mirdaily_app/features/premium/widgets/premium_showcase.dart';

Future<void> _pump(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);

  final api = ApiService(AuthService());

  await tester.pumpWidget(
    Provider<ApiService>.value(
      value: api,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: const PremiumScreen(),
      ),
    ),
  );

  // Nada de `pumpAndSettle`: el medallón, las ilustraciones y la campana van
  // en bucle, así que el árbol no queda quieto nunca.
  //
  // Y tampoco vale un solo pump largo: `SlideFadeIn` arranca su controlador
  // desde un `Future.delayed`, y el reloj del ticker no empieza a contar hasta
  // el fotograma SIGUIENTE al `forward()`. Con uno o dos pumps las tarjetas se
  // quedaban congeladas en opacidad cero y el golden salía en blanco. Con una
  // tanda de fotogramas cortos, cada entrada escalonada llega a su sitio.
  await tester.pump();
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

void main() {
  // Ancho de móvil real, pero alto de sobra: la lista es perezosa y a 844 px
  // el aviso ni se llega a construir. Lo que se está mirando es el ANCHO.
  testWidgets('premium en movil', (tester) async {
    await _pump(tester, const Size(390, 1360));

    // Las piezas de siempre siguen ahí.
    expect(find.text('Próximamente'), findsOneWidget);
    expect(find.text('Preguntas ilimitadas'), findsOneWidget);
    expect(find.text('Estadísticas avanzadas'), findsOneWidget);
    expect(find.text('Simulacros de examen'), findsOneWidget);
    expect(find.text('Te avisaremos cuando esté disponible'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/premium_movil.png'),
    );
  });

  testWidgets('premium en tablet vertical', (tester) async {
    await _pump(tester, const Size(834, 1600));

    expect(find.byType(PremiumFeatureCard), findsNWidgets(3));
    expect(tester.takeException(), isNull);

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/premium_tablet_vertical.png'),
    );
  });

  testWidgets('premium en tablet apaisada', (tester) async {
    // Igual que en móvil, alto de sobra para que la lista construya también el
    // Panel y se vea su fila de dos columnas.
    await _pump(tester, const Size(1280, 1700));

    // La cabecera se pone en fila y las ventajas en rejilla, pero el contenido
    // es exactamente el mismo.
    expect(find.byType(PremiumHeroCard), findsOneWidget);
    expect(find.byType(PremiumFeatureCard), findsNWidgets(3));
    expect(find.text('Te avisaremos cuando esté disponible'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/premium_tablet.png'),
    );
  });
}
