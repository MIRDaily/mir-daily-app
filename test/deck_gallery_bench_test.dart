// Medición de la galería de mazos completa: construir + rasterizar la lista
// mientras se hace scroll, en las dos texturas.
//
//   flutter test test/deck_gallery_bench_test.dart
//
// No es una prueba de regresión: es la herramienta con la que se compara si el
// modo "Personalizado" sigue costando más que el "Predeterminado".
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mirdaily_app/core/models/models.dart';
import 'package:mirdaily_app/core/theme/app_theme.dart';
import 'package:mirdaily_app/features/decks/decks_screen.dart';
import 'package:mirdaily_app/features/decks/widgets/deck_gradient.dart';
import 'package:mirdaily_app/shared/widgets/misc_widgets.dart';

const _gradientes = [
  'apricot',
  'slate',
  'ember',
  'violet',
  'inferno',
  'sage',
  'blueMist',
  'blueNight',
];

List<Deck> _decks(int n) => [
      for (var i = 0; i < n; i++)
        Deck(
          id: 'deck-$i',
          name: 'Perf ${i.toString().padLeft(2, '0')}',
          systemGenerated: false,
          autoType: 'none',
          accuracy: 0.4 + (i % 5) * 0.1,
          totalReviews: 40,
          visualState: i.isEven ? 'clean' : 'destroyed',
          description: i.isEven
              ? 'Lo que voy fallando en las simulaciones largas.'
              : null,
          bannerGradient: _gradientes[i % _gradientes.length],
          totalItems: 10 + i,
        ),
    ];

Future<double> _medir(
  WidgetTester tester, {
  required bool gradiente,
  required int cuantos,
  bool entrada = false,
}) async {
  final decks = _decks(cuantos);

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: Scaffold(
        backgroundColor: AppColors.background,
        body: ListView.builder(
          padding: const EdgeInsets.all(20),
          itemCount: decks.length,
          itemBuilder: (context, i) {
            final card = DeckGalleryCard(
              deck: decks[i],
              gradientStyle: gradiente,
              onOpen: () {},
              onDelete: () {},
            );
            if (!entrada) return card;
            return SlideFadeIn(
              delay: Duration(milliseconds: 70 * (i % 8)),
              beginOffset: const Offset(0, 0.12),
              child: card,
            );
          },
        ),
      ),
    ),
  );
  // Deja que terminen las animaciones de entrada de las barras de Dominio.
  await tester.pump(const Duration(milliseconds: 900));

  debugDeckGradientPaints = 0;
  debugDeckGradientBlurs = 0;

  final sw = Stopwatch()..start();
  const pasos = 40;
  for (var i = 0; i < pasos; i++) {
    await tester.drag(find.byType(ListView), const Offset(0, -40));
    // `pump` construye Y pinta el fotograma: es lo que queremos cronometrar.
    await tester.pump(const Duration(milliseconds: 16));
  }
  sw.stop();

  if (gradiente) {
    // ignore: avoid_print
    print('  fondos pintados durante el scroll: $debugDeckGradientPaints, '
        'de los que hubo que desenfocar de verdad: $debugDeckGradientBlurs');
  }

  return sw.elapsedMicroseconds / pasos / 1000;
}

void main() {
  testWidgets('coste de la galeria con 13 mazos', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    // Sin esto el test no rasteriza las sombras: solo mediría construir el
    // árbol. Se devuelve a su sitio al final del propio cuerpo del test —con
    // addTearDown llega tarde, porque el framework comprueba antes que ningún
    // ajuste de depuración de pintado se haya quedado tocado.
    debugDisableShadows = false;

    final personalizado =
        await _medir(tester, gradiente: true, cuantos: 13);
    final predeterminado =
        await _medir(tester, gradiente: false, cuantos: 13);
    final conEntrada =
        await _medir(tester, gradiente: true, cuantos: 13, entrada: true);

    // ignore: avoid_print
    print('personalizado (degradado): '
        '${personalizado.toStringAsFixed(2)} ms por fotograma');
    // ignore: avoid_print
    print('predeterminado (cartulina): '
        '${predeterminado.toStringAsFixed(2)} ms por fotograma');
    // ignore: avoid_print
    print('degradado + SlideFadeIn por tarjeta: '
        '${conEntrada.toStringAsFixed(2)} ms por fotograma');
    // ignore: avoid_print
    print('degradado vs cartulina: '
        '${(personalizado / predeterminado).toStringAsFixed(2)}x  |  '
        'la animacion de entrada anade '
        '${(conEntrada / personalizado).toStringAsFixed(2)}x');

    debugDisableShadows = true;
  });
}
