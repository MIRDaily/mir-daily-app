// Muestrario y comportamiento del popup "Guardar en mazo", con un ApiService
// de mentira. Es el port del popover de la web: enseña TODOS los mazos y en
// cuáles está ya la pregunta, y deja guardar y quitar sin cerrarse.
//
//   flutter test test/save_to_deck_preview_test.dart --update-goldens
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:mirdaily_app/core/models/models.dart';
import 'package:mirdaily_app/core/providers/saved_questions_provider.dart';
import 'package:mirdaily_app/core/services/api_service.dart';
import 'package:mirdaily_app/core/services/auth_service.dart';
import 'package:mirdaily_app/core/theme/app_theme.dart';
import 'package:mirdaily_app/features/decks/widgets/save_to_deck.dart';

const _pregunta = '346';

class _FakeApi extends ApiService {
  _FakeApi() : super(AuthService());

  /// deckId -> itemId, lo que "hay" en el servidor de mentira.
  ///
  /// 'auto' es el mazo automático de fallos: el backend lo contesta como
  /// cualquier otro, pero no se ofrece y no debe contar como "guardada".
  Map<String, String> guardadas = {'d2': 'item-99', 'auto': 'item-auto'};

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
  Future<({List<Deck> decks, Map<String, String> membership})> getDecksWithSaved(
    String questionId,
  ) async {
    llamadas.add('decks:$questionId');
    return (decks: await getDecks(), membership: {...guardadas});
  }

  @override
  Future<Map<String, String>> addDeckItems(
    String deckId,
    List<String> questionIds,
  ) async {
    llamadas.add('add:$deckId:${questionIds.join(",")}');
    guardadas[deckId] = 'item-nuevo';
    return {for (final q in questionIds) q: 'item-nuevo'};
  }

  @override
  Future<void> removeDeckItem(String deckId, String itemId) async {
    llamadas.add('remove:$deckId:$itemId');
    guardadas.remove(deckId);
  }
}

Future<void> _abrir(WidgetTester tester, _FakeApi api) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<ApiService>.value(value: api),
        ChangeNotifierProvider(create: (_) => SavedQuestionsProvider()),
      ],
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

    // Abrir la hoja es UNA petición, no una por mazo: los mazos y en cuáles
    // está ya la pregunta vienen juntos.
    expect(api.llamadas, ['decks:346', 'add:d1:346', 'add:d3:346']);
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

    expect(api.llamadas, ['decks:346', 'remove:d2:item-99']);
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

  // Regresión: el badge verde se caía al pulsar "Comprobar" en el simulacro y
  // al pasar a la revisión final. La causa era que "guardada" vivía dentro del
  // propio botón, así que se perdía en cuanto Flutter tiraba su State.
  testWidgets('la marca de guardada sobrevive a reconstruir el botón',
      (tester) async {
    final api = _FakeApi();
    final saved = SavedQuestionsProvider();

    Widget arbol(Key key) => MultiProvider(
          providers: [
            Provider<ApiService>.value(value: api),
            ChangeNotifierProvider<SavedQuestionsProvider>.value(value: saved),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              body: Center(
                child: SaveToDeckButton(key: key, questionId: _pregunta),
              ),
            ),
          ),
        );

    IconData iconoActual() => tester
        .widget<Icon>(find.descendant(
          of: find.byType(SaveToDeckButton),
          matching: find.byType(Icon),
        ))
        .icon!;

    await tester.pumpWidget(arbol(const ValueKey('antes')));
    expect(iconoActual(), Icons.bookmark_add_outlined);

    saved.setSaved(_pregunta, true);
    await tester.pump();
    expect(iconoActual(), Icons.bookmark_added_rounded);

    // Otra Key = State nuevo, que es justo lo que pasaba al corregir.
    await tester.pumpWidget(arbol(const ValueKey('despues')));
    expect(iconoActual(), Icons.bookmark_added_rounded);

    // Y al quitarla del último mazo vuelve a blanco.
    saved.setSaved(_pregunta, false);
    await tester.pump();
    expect(iconoActual(), Icons.bookmark_add_outlined);
  });

  // Regresión: el mazo automático de fallos se rellena solo, así que una
  // pregunta fallada aparecía como "guardada" (icono verde) sin que el usuario
  // la hubiera guardado, y en un mazo que ni sale en la lista.
  testWidgets('estar en el mazo automático de fallos no cuenta como guardada',
      (tester) async {
    final api = _FakeApi();
    // Solo está en el automático: el usuario no la ha guardado en ninguno.
    api.guardadas = {'auto': 'item-auto'};

    final saved = SavedQuestionsProvider();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ApiService>.value(value: api),
          ChangeNotifierProvider<SavedQuestionsProvider>.value(value: saved),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: Center(child: SaveToDeckButton(questionId: _pregunta)),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(IconButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Ningún mazo de los ofrecidos la tiene.
    expect(find.text('QUITAR'), findsNothing);
    expect(saved.isSaved(_pregunta), isFalse);
  });

  // Mientras cargaba se veía un puntito girando en una caja de 26px y el
  // popup abría diminuto para estirarse de golpe al llegar los mazos.
  testWidgets('mientras carga enseña la silueta de la lista, no un spinner',
      (tester) async {
    tester.view.physicalSize = const Size(420, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final api = _FakeApi();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ApiService>.value(value: api),
          ChangeNotifierProvider(create: (_) => SavedQuestionsProvider()),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: Center(child: SaveToDeckButton(questionId: _pregunta)),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(IconButton));
    await tester.pump(); // abierto, sin que haya vuelto la peticion

    expect(find.byType(CircularProgressIndicator), findsNothing);
    final alturaCargando = tester.getSize(find.byType(Dialog)).height;

    await tester.pump(const Duration(milliseconds: 500));
    final alturaCargado = tester.getSize(find.byType(Dialog)).height;

    // Con 3 mazos propios y 3 filas de esqueleto, el alto no debe pegar un
    // salto: es lo que se veia como "una pestaña que luego se reescala".
    expect((alturaCargado - alturaCargando).abs(), lessThan(24),
        reason: 'de $alturaCargando a $alturaCargado');
  });

  testWidgets('la marca no se arrastra a otra pregunta', (tester) async {
    final api = _FakeApi();
    final saved = SavedQuestionsProvider()..setSaved(_pregunta, true);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ApiService>.value(value: api),
          ChangeNotifierProvider<SavedQuestionsProvider>.value(value: saved),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: Center(child: SaveToDeckButton(questionId: 'otra-pregunta')),
          ),
        ),
      ),
    );

    final icono = tester
        .widget<Icon>(find.descendant(
          of: find.byType(SaveToDeckButton),
          matching: find.byType(Icon),
        ))
        .icon;
    expect(icono, Icons.bookmark_add_outlined);
  });
}
