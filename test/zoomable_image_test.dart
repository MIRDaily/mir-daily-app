// Cuando una imagen de pregunta no carga, tiene que NOTARSE y poder
// reintentarse. Antes desaparecía en silencio: en el simulacro en modo
// deslizar quedaba la página "IMAGEN" vacía, sin explicación y sin salida.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mirdaily_app/shared/widgets/zoomable_image.dart';

Future<void> _pump(WidgetTester tester, {bool expand = false}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        // En los tests todas las peticiones de red devuelven 400, así que
        // cualquier Image.network falla: justo el caso que se quiere probar.
        body: SizedBox(
          height: 300,
          child: ZoomableImage(
            url: 'https://ejemplo.invalido/questions/2022/20.png',
            expand: expand,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('una imagen que falla lo dice y ofrece reintentar',
      (tester) async {
    await _pump(tester);

    expect(find.text('No se pudo cargar la imagen'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
  });

  testWidgets('también en la página de imagen del carrusel (expand)',
      (tester) async {
    await _pump(tester, expand: true);

    expect(find.text('No se pudo cargar la imagen'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
  });

  testWidgets('reintentar vuelve a pedir la imagen', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('Reintentar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Vuelve a fallar (sigue sin red), pero el botón sigue disponible: la
    // pregunta no se queda sin salida como antes.
    expect(find.text('Reintentar'), findsOneWidget);
  });
}
