// Muestrario de la galería de mazos con los dos grupos separados: los de
// MIRDaily (con el hueco reservado del futuro mazo rotatorio) y los del
// usuario.
//
//   flutter test test/decks_gallery_preview_test.dart --update-goldens
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mirdaily_app/core/models/models.dart';
import 'package:mirdaily_app/core/providers/auth_provider.dart';
import 'package:mirdaily_app/core/services/api_service.dart';
import 'package:mirdaily_app/core/services/auth_service.dart';
import 'package:mirdaily_app/core/theme/app_theme.dart';
import 'package:mirdaily_app/features/decks/decks_screen.dart';

Deck _deck(
  String name, {
  bool auto = false,
  String? gradient,
  String? bio,
  int items = 0,
  int reviews = 0,
  double accuracy = 0,
  String visual = 'clean',
}) =>
    Deck(
      id: name,
      name: name,
      systemGenerated: auto,
      autoType: auto ? 'failed_global' : 'none',
      accuracy: accuracy,
      totalReviews: reviews,
      visualState: visual,
      description: bio,
      bannerGradient: gradient,
      totalItems: items,
    );

class _FakeApi extends ApiService {
  _FakeApi(this.decks) : super(AuthService());

  final List<Deck> decks;

  @override
  Future<List<Deck>> getDecks() async => decks;
}

Future<void> _pump(WidgetTester tester, List<Deck> decks) async {
  final api = _FakeApi(decks);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<ApiService>.value(value: api),
        ChangeNotifierProvider(
          create: (_) =>
              AuthProvider(authService: AuthService(), apiService: api),
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: const DecksScreen(),
      ),
    ),
  );
  // Un solo pump largo NO basta: adelanta el reloj pero solo dibuja un
  // fotograma, así que las tarjetas se quedarían con la opacidad inicial de su
  // animación de entrada (invisibles). Hay que pintar varios fotogramas.
  await tester.pump();
  for (var i = 0; i < 25; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

void main() {
  // La pantalla real usa dos plugins que en un test no existen: el de enlaces
  // profundos (AuthProvider) y el almacenamiento local (la preferencia de
  // orden). Se silencian para poder montar la pantalla de verdad en vez de una
  // copia recortada de ella.
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.llfbandit.app_links/events'),
      (_) async => null,
    );
  });

  testWidgets('galería con los dos grupos', (tester) async {
    tester.view.physicalSize = const Size(420, 1500);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await _pump(tester, [
      _deck('Mis preguntas falladas',
          auto: true, items: 50, reviews: 40, accuracy: 0.24,
          visual: 'failed'),
      _deck('madre mia',
          gradient: 'blueMist',
          bio: 'Lo que voy fallando en las simulaciones largas.',
          items: 3,
          reviews: 40,
          accuracy: 0.72),
      _deck('Perf 01', gradient: 'violet', items: 13),
      _deck('ZZZ Vacio 1',
          gradient: 'blueNight', items: 2, reviews: 40, accuracy: 0.31,
          visual: 'destroyed'),
    ]);

    expect(find.text('DE MIRDAILY'), findsOneWidget);
    expect(find.text('MIS MAZOS (3)'), findsOneWidget);
    // Con un solo mazo del sistema se reserva el hueco del siguiente.
    expect(find.text('¡En construcción!'), findsOneWidget);

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/decks_gallery.png'),
    );
  });

  testWidgets('sin mazos propios, el grupo del usuario explica qué hacer',
      (tester) async {
    tester.view.physicalSize = const Size(420, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await _pump(tester, [
      _deck('Mis preguntas falladas',
          auto: true, items: 50, reviews: 40, accuracy: 0.24,
          visual: 'failed'),
    ]);

    expect(find.text('DE MIRDAILY'), findsOneWidget);
    expect(find.text('MIS MAZOS'), findsOneWidget);
    expect(find.text('Aún no tienes mazos propios'), findsOneWidget);

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/decks_gallery_vacia.png'),
    );
  });
}
