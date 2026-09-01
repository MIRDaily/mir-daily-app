// Maestro-detalle de Flashcards: igual patrón que Mazos.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:mirdaily_app/core/models/models.dart';
import 'package:mirdaily_app/core/responsive/master_detail_scaffold.dart';
import 'package:mirdaily_app/core/services/api_service.dart';
import 'package:mirdaily_app/core/services/auth_service.dart';
import 'package:mirdaily_app/core/theme/app_theme.dart';
import 'package:mirdaily_app/features/flashcards/flashcard_deck_screen.dart';
import 'package:mirdaily_app/features/flashcards/flashcards_screen.dart';

class _FakeApi extends ApiService {
  _FakeApi() : super(AuthService());

  @override
  Future<List<FlashDeck>> getFlashDecks() async => const [
        FlashDeck(id: 'f1', name: 'Grupo Uno', totalCards: 4, dueCards: 1),
        FlashDeck(id: 'f2', name: 'Grupo Dos', totalCards: 2),
      ];

  @override
  Future<List<Flashcard>> getFlashcards(String deckId) async => const [];
}

Future<void> _pump(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final api = _FakeApi();
  await tester.pumpWidget(
    Provider<ApiService>.value(
      value: api,
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: const FlashcardsScreen(),
      ),
    ),
  );
  await tester.pump();
  for (var i = 0; i < 15; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

void main() {
  testWidgets('tablet grande: tocar un grupo lo abre en el panel derecho',
      (tester) async {
    await _pump(tester, const Size(1280, 800));

    expect(find.byType(MasterDetailScaffold), findsOneWidget);
    expect(find.text('Elige un grupo'), findsOneWidget);

    await tester.tap(find.text('Grupo Uno'));
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }

    expect(find.byType(MasterDetailScaffold), findsOneWidget);
    expect(
      find.descendant(
          of: find.byType(MasterDetailScaffold),
          matching: find.byType(FlashcardDeckScreen)),
      findsOneWidget,
    );
  });

  testWidgets('móvil: tocar un grupo navega a pantalla completa',
      (tester) async {
    await _pump(tester, const Size(390, 844));
    expect(find.byType(MasterDetailScaffold), findsNothing);

    await tester.tap(find.text('Grupo Uno'));
    await tester.pump();
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }

    expect(find.byType(FlashcardsScreen), findsNothing);
    expect(find.byType(FlashcardDeckScreen), findsOneWidget);
  });
}
