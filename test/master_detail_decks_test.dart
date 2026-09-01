// Maestro-detalle de Mazos: en tablet grande, tocar un mazo lo abre en el
// panel derecho sin navegar; en móvil/tablet pequeña sigue empujando una
// pantalla completa como siempre.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mirdaily_app/core/models/models.dart';
import 'package:mirdaily_app/core/providers/auth_provider.dart';
import 'package:mirdaily_app/core/responsive/master_detail_scaffold.dart';
import 'package:mirdaily_app/core/services/api_service.dart';
import 'package:mirdaily_app/core/services/auth_service.dart';
import 'package:mirdaily_app/core/theme/app_theme.dart';
import 'package:mirdaily_app/features/decks/deck_detail_screen.dart';
import 'package:mirdaily_app/features/decks/decks_screen.dart';

class _FakeApi extends ApiService {
  _FakeApi() : super(AuthService());

  @override
  Future<List<Deck>> getDecks() async => const [
        Deck(
          id: 'd1',
          name: 'Mazo Uno',
          systemGenerated: false,
          autoType: 'none',
          accuracy: 0.5,
          totalReviews: 10,
          visualState: 'clean',
          totalItems: 5,
        ),
        Deck(
          id: 'd2',
          name: 'Mazo Dos',
          systemGenerated: false,
          autoType: 'none',
          accuracy: 0.5,
          totalReviews: 10,
          visualState: 'clean',
          totalItems: 7,
        ),
      ];

  @override
  Future<DeckItemsPage> getDeckItems(String deckId,
          {int page = 1, String query = ''}) async =>
      const DeckItemsPage(items: [], total: 0, page: 1, totalPages: 1);

  @override
  Future<DeckSummary> getDeckSummary(String deckId) async =>
      const DeckSummary(newCount: 0, failed: 0, learning: 0, mastered: 0);

  @override
  Future<List<DeckSubject>> getDeckSubjects(String deckId) async => const [];
}

Future<void> _pump(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  SharedPreferences.setMockInitialValues({});
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('com.llfbandit.app_links/events'),
    (_) async => null,
  );

  final api = _FakeApi();
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
        theme: AppTheme.lightTheme,
        home: const DecksScreen(),
      ),
    ),
  );
  await tester.pump();
  for (var i = 0; i < 15; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

void main() {
  testWidgets('tablet grande: tocar un mazo lo abre en el panel derecho',
      (tester) async {
    await _pump(tester, const Size(1280, 800));

    expect(find.byType(MasterDetailScaffold), findsOneWidget);
    expect(find.text('Elige un mazo'), findsOneWidget);
    expect(find.byType(DeckDetailScreen), findsNothing);

    await tester.tap(find.text('Mazo Uno'));
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }

    // Sigue siendo la MISMA pantalla (no hubo push): el maestro-detalle
    // continúa ahí, y ahora el detalle está embebido dentro.
    expect(find.byType(MasterDetailScaffold), findsOneWidget);
    expect(
      find.descendant(
          of: find.byType(MasterDetailScaffold),
          matching: find.byType(DeckDetailScreen)),
      findsOneWidget,
    );
    expect(find.text('Elige un mazo'), findsNothing);
  });

  testWidgets('tablet grande: el detalle embebido tiene botón Estudiar y la '
      'lista se puede plegar', (tester) async {
    await _pump(tester, const Size(1280, 800));
    await tester.tap(find.text('Mazo Uno'));
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }

    // "Estudiar" está en el AppBar del detalle (no un FAB perdido).
    expect(find.widgetWithText(FilledButton, 'Estudiar'), findsOneWidget);

    // Plegar la lista: la columna maestra se anima a ancho 0 y el tirador
    // "Lista" se vuelve tocable.
    final masterPane = tester.getSize(find.ancestor(
      of: find.text('Mazos'),
      matching: find.byType(ClipRect),
    ));
    expect(masterPane.width, greaterThan(200));

    await tester.tap(find.byIcon(Icons.chevron_left_rounded));
    await tester.pump();
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    expect(
      tester
          .getSize(find.ancestor(
            of: find.text('Mazos'),
            matching: find.byType(ClipRect),
          ))
          .width,
      lessThan(2),
      reason: 'la columna maestra está plegada',
    );
    // El tirador "Lista" ahora recibe toques.
    await tester.tap(find.text('Lista'));
    await tester.pump();
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    expect(
      tester
          .getSize(find.ancestor(
            of: find.text('Mazos'),
            matching: find.byType(ClipRect),
          ))
          .width,
      greaterThan(200),
      reason: 'el tirador vuelve a sacar la lista',
    );

    // El detalle nunca se fue.
    expect(find.byType(DeckDetailScreen), findsOneWidget);
  });

  testWidgets('deslizar la lista a la izquierda la pliega', (tester) async {
    await _pump(tester, const Size(1280, 800));
    await tester.tap(find.text('Mazo Uno'));
    await tester.pump();
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }

    Size paneSize() => tester.getSize(find.ancestor(
          of: find.text('Mazos'),
          matching: find.byType(ClipRect),
        ).first);
    expect(paneSize().width, greaterThan(200));

    // Fling horizontal hacia la izquierda sobre la propia lista.
    await tester.fling(find.text('Mazo Dos'), const Offset(-300, 0), 1000);
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    expect(paneSize().width, lessThan(2), reason: 'plegada tras el swipe');
    expect(find.byType(DeckDetailScreen), findsOneWidget);

    // Y ahora deslizar a la DERECHA desde el borde izquierdo la vuelve a sacar.
    await tester.flingFrom(
        const Offset(6, 400), const Offset(320, 0), 1000);
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    expect(paneSize().width, greaterThan(200), reason: 'desplegada tras el swipe derecha');
  });

  testWidgets('móvil: tocar un mazo navega a pantalla completa',
      (tester) async {
    await _pump(tester, const Size(390, 844));

    expect(find.byType(MasterDetailScaffold), findsNothing);

    await tester.tap(find.text('Mazo Uno'));
    await tester.pump(); // arranca la transición
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }

    // Pantalla completa empujada: ya no se ve la galería detrás.
    expect(find.byType(DecksScreen), findsNothing);
    expect(find.byType(DeckDetailScreen), findsOneWidget);
  });
}
