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
