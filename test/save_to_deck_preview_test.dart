// Muestrario y comportamiento del popup "Guardar en mazo", con un ApiService
// de mentira. Es el port del popover de la web: enseña TODOS los mazos y en
// cuáles está ya la pregunta, y deja guardar y quitar sin cerrarse.
//
//   flutter test test/save_to_deck_preview_test.dart --update-goldens
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:mirdaily_app/core/models/models.dart';
import 'package:mirdaily_app/core/services/api_service.dart';
import 'package:mirdaily_app/core/services/auth_service.dart';
import 'package:mirdaily_app/core/theme/app_theme.dart';
import 'package:mirdaily_app/features/decks/widgets/save_to_deck.dart';

const _pregunta = '346';

class _FakeApi extends ApiService {
  _FakeApi() : super(AuthService());

  /// deckId -> itemId, lo que "hay" en el servidor de mentira.
  Map<String, String> guardadas = {'d2': 'item-99'};

  final List<String> llamadas = [];

  @override
  Future<List<Deck>> getDecks() async => const [
        // El automático de fallos NO debe aparecer: el backend lo rechaza.
        Deck(
          id: 'auto',
          name: 'Mis preguntas falladas',
          systemGenerated: true,
          autoType: 'failed_global',
          accuracy: 0.24,
          totalReviews: 40,
          visualState: 'failed',
          totalItems: 50,
        ),
        Deck(
          id: 'd1',
          name: 'madre mia',
          systemGenerated: false,
          autoType: 'none',
          accuracy: 0.72,
          totalReviews: 40,
          visualState: 'clean',
          bannerGradient: 'blueMist',
          totalItems: 3,
        ),
        Deck(
          id: 'd2',
          name: 'Cardio que se me atraganta',
          systemGenerated: false,
          autoType: 'none',
          accuracy: 0.4,
          totalReviews: 10,
          visualState: 'destroyed',
          bannerGradient: 'ember',
          totalItems: 1,
        ),
        Deck(
          id: 'd3',
          name: 'Perf 07',
          systemGenerated: false,
          autoType: 'none',
          accuracy: 0,
          totalReviews: 0,
          visualState: 'clean',
          bannerGradient: 'violet',
          totalItems: 15,
        ),
      ];

  @override
  Future<Map<String, String>> findQuestionInDecks(
    List<String> deckIds,
    String questionId,
  ) async =>
      {
        for (final id in deckIds)
          if (guardadas.containsKey(id)) id: guardadas[id]!,
      };

  @override
  Future<void> addDeckItems(String deckId, List<String> questionIds) async {
    llamadas.add('add:$deckId:${questionIds.join(",")}');
    guardadas[deckId] = 'item-nuevo';
  }

  @override
  Future<void> removeDeckItem(String deckId, String itemId) async {
    llamadas.add('remove:$deckId:$itemId');
    guardadas.remove(deckId);
  }
}

Future<void> _abrir(WidgetTester tester, _FakeApi api) async {
  await tester.pumpWidget(
    Provider<ApiService>.value(
      value: api,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: const Scaffold(
          backgroundColor: AppColors.background,
          body: Center(child: SaveToDeckButton(questionId: _pregunta)),
        ),
      ),
    ),
  );
  await tester.tap(find.byType(IconButton));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  testWidgets('enseña en qué mazos está ya la pregunta', (tester) async {
    tester.view.physicalSize = const Size(420, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final api = _FakeApi();
    await _abrir(tester, api);

    // El mazo automático de fallos no se ofrece: responde 403.
    expect(find.text('Mis preguntas falladas'), findsNothing);
    expect(find.text('madre mia'), findsOneWidget);

    // "Cardio" ya la tiene, los otros dos no.
    expect(find.text('QUITAR'), findsOneWidget);
    expect(find.text('GUARDAR'), findsNWidgets(2));

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/save_to_deck.png'),
    );
  });

  testWidgets('guarda en varios mazos sin cerrarse', (tester) async {
    tester.view.physicalSize = const Size(420, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final api = _FakeApi();
    await _abrir(tester, api);

    await tester.tap(find.text('madre mia'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Sigue abierto, avisa de lo que ha hecho, y ese mazo pasa a "QUITAR".
    expect(find.text('GUARDAR EN MAZO'), findsOneWidget);
    expect(find.text('Guardada en "madre mia"'), findsOneWidget);
    expect(find.text('QUITAR'), findsNWidgets(2));

    await tester.tap(find.text('Perf 07'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(api.llamadas, ['add:d1:346', 'add:d3:346']);
    expect(find.text('QUITAR'), findsNWidgets(3));
  });

  testWidgets('tocar un mazo donde ya está la quita', (tester) async {
    tester.view.physicalSize = const Size(420, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final api = _FakeApi();
    await _abrir(tester, api);

    await tester.tap(find.text('Cardio que se me atraganta'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(api.llamadas, ['remove:d2:item-99']);
    expect(find.text('Quitada de "Cardio que se me atraganta"'), findsOneWidget);
    expect(find.text('QUITAR'), findsNothing);
  });

  testWidgets('el aviso desaparece solo a los 2,5 s', (tester) async {
    tester.view.physicalSize = const Size(420, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final api = _FakeApi();
    await _abrir(tester, api);

    await tester.tap(find.text('madre mia'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Guardada en "madre mia"'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 2600));
    expect(find.text('Guardada en "madre mia"'), findsNothing);
  });
}
