// Pantallas de flashcards (tanda 2): lista tipo Anki con previsión, grupo con temas y escalera,
// ajustes de la sesión y estudio con las cuatro notas y deshacer. En móvil y tablet, sin desbordes.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:mirdaily_app/core/models/flashcards.dart';
import 'package:mirdaily_app/core/models/models.dart';
import 'package:mirdaily_app/core/providers/progress_provider.dart';
import 'package:mirdaily_app/core/services/api_service.dart';
import 'package:mirdaily_app/core/services/auth_service.dart';
import 'package:mirdaily_app/core/theme/app_theme.dart';
import 'package:mirdaily_app/features/flashcards/flashcard_deck_screen.dart';
import 'package:mirdaily_app/features/flashcards/flashcard_study_screen.dart';
import 'package:mirdaily_app/features/flashcards/flashcards_screen.dart';
import 'package:mirdaily_app/features/flashcards/widgets/ajustes_sesion_sheet.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _ahora = DateTime.now();

Map<int, GradePreview> _preview() => {
      1: GradePreview(0, _ahora.add(const Duration(minutes: 1))),
      2: GradePreview(0, _ahora.add(const Duration(minutes: 6))),
      3: GradePreview(0, _ahora.add(const Duration(minutes: 10))),
      4: GradePreview(8, _ahora.add(const Duration(days: 8))),
    };

const _cards = [
  Flashcard(itemId: 1, flashcardId: 'a', front: '¿Cristales de la gota?', back: 'Urato monosódico', topic: 'Gota', level: 1, status: FlashStatus.failed),
  Flashcard(itemId: 2, flashcardId: 'b', front: '¿Tratamiento de la crisis?', back: 'AINE, colchicina o corticoides', topic: 'Gota', level: 2),
  Flashcard(itemId: 3, flashcardId: 'c', front: '¿Condrocalcinosis?', back: 'Pirofosfato cálcico', topic: 'Condrocalcinosis', level: 1, status: FlashStatus.mastered, isDue: false),
  Flashcard(itemId: 4, flashcardId: 'd', front: 'Suelta', back: 'Sin tema', status: FlashStatus.learning),
];

Escalera _escalera({required bool abierta}) => Escalera([
      TemaEscalera('Gota', [
        const EscalonEscalera(level: 1, total: 1, unlocked: true),
        EscalonEscalera(level: 2, total: 1, lowerTotal: 1, needed: 1, unlocked: abierta),
      ]),
    ]);

class _FakeApi extends ApiService {
  _FakeApi() : super(AuthService());

  final List<int> grados = [];
  Map<String, dynamic>? opciones;
  int _servidas = 0;
  bool _deshecho = false;
  int _escaleras = 0;

  @override
  Future<List<FlashDeck>> getFlashDecks() async => const [
        FlashDeck(
          id: 'd1',
          name: 'Reumatología',
          totalCards: 4,
          dueCards: 3,
          dueReviewCards: 2,
          summary: FlashSummary(nuevas: 1, failed: 1, learning: 1, mastered: 1),
        ),
        FlashDeck(id: 'd2', name: 'Digestivo', totalCards: 12, dueCards: 0),
        FlashDeck(id: 'd3', name: 'Mis chuletas de fórmulas', totalCards: 3, dueCards: 3, summary: FlashSummary(nuevas: 3)),
      ];

  @override
  Future<List<Flashcard>> getFlashcards(String deckId) async => _cards;

  // La primera foto (la del grupo, o la de antes de la sesión) tiene Media cerrada; la siguiente, abierta.
  @override
  Future<Escalera> getFlashcardLadder(String deckId) async => _escalera(abierta: ++_escaleras > 1);

  @override
  Future<FlashForecast> getFlashcardForecast({int days = 30}) async => FlashForecast(
        overdue: 2,
        days: [for (var i = 0; i < 30; i++) (date: '2026-11-${(i % 28 + 1).toString().padLeft(2, '0')}', count: i % 4)],
      );

  @override
  Future<FlashStats> getFlashcardStats() async =>
      const FlashStats(nuevas: 5, learning: 3, young: 4, mature: 2, reviews: 10, passed: 8, rate: 0.8);

  @override
  Future<String> startFlashcardSession(String deckId, int limit, {Map<String, dynamic> opciones = const {}}) async {
    this.opciones = {'limit': limit, ...opciones};
    _servidas = 0;
    return 's1';
  }

  @override
  Future<FlashNext> getNextFlashcard(String deckId, String sessionId) async {
    if (_servidas >= 2) return const FlashNext(FlashNextKind.done);
    final card = _cards[_servidas++];
    return FlashNext(FlashNextKind.card, card, _preview());
  }

  @override
  Future<void> logFlashcard({required String deckId, required int deckItemId, required int grade, required String sessionId, int timeSpent = 0}) async {
    grados.add(grade);
  }

  @override
  Future<({int deckItemId, Map<int, GradePreview> preview})?> undoFlashcardReview(String deckId, String sessionId) async {
    _deshecho = true;
    _servidas--;
    return (deckItemId: _cards[_servidas].itemId, preview: _preview());
  }

  bool get deshecho => _deshecho;

  @override
  Future<void> endDeckSession(String sessionId) async {}
}

Future<void> _settle(WidgetTester tester, [int frames = 20]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<_FakeApi> _montar(WidgetTester tester, Size size, Widget home) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final api = _FakeApi();
  final progreso = ProgressProvider(ApiService(AuthService(), client: MockClient((_) async => throw 'sin red')));
  await tester.pumpWidget(MultiProvider(
    providers: [
      Provider<ApiService>.value(value: api),
      ChangeNotifierProvider<ProgressProvider>.value(value: progreso),
    ],
    child: MaterialApp(theme: AppTheme.lightTheme, home: home),
  ));
  await _settle(tester);
  return api;
}

const _grupo = FlashDeck(id: 'd1', name: 'Reumatología', totalCards: 4);

void main() {
  for (final (nombre, tam) in [('móvil', const Size(360, 780)), ('tablet', const Size(1024, 768))]) {
    testWidgets('lista en $nombre: secciones por categoría, columnas, previsión y estado', (tester) async {
      await _montar(tester, tam, const FlashcardsScreen());
      expect(find.text('Próximos 30 días'.toUpperCase()), findsOneWidget);
      expect(find.text('2 atrasadas'), findsOneWidget);
      expect(find.text('80% de retención'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Mis chuletas de fórmulas'), 200, scrollable: find.byType(Scrollable).first);
      expect(find.text('MÉDICAS · 1'), findsOneWidget);
      expect(find.text('QUIRÚRGICAS · 1'), findsOneWidget);
      expect(find.text('OTROS · 1'), findsOneWidget);
      expect(find.text('RM'), findsOneWidget, reason: 'la sigla de la asignatura');
      expect(tester.takeException(), isNull);
    });

    testWidgets('grupo en $nombre: dominio, escalera y temas; dentro de un tema, sus tarjetas', (tester) async {
      await _montar(tester, tam, const FlashcardDeckScreen(deck: _grupo));
      expect(find.text('Escalera de niveles'), findsOneWidget);
      expect(find.text('1 nivel cerrado'), findsOneWidget);
      expect(find.text('Media: 0 de 1 dominadas de fácil (hacen falta 1)'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Gota'), 200, scrollable: find.byType(Scrollable).first);
      expect(find.text('3 temas'.toUpperCase()), findsOneWidget);
      await tester.tap(find.text('Gota'));
      await _settle(tester);
      expect(find.text('Mis flashcards › Reumatología › Gota'), findsOneWidget);
      expect(find.text('¿Cristales de la gota?'), findsOneWidget);
      expect(find.text('¿Condrocalcinosis?'), findsNothing);
      // Mantener pulsado entra en la selección.
      await tester.longPress(find.text('¿Cristales de la gota?'));
      await _settle(tester, 5);
      expect(find.text('1 seleccionada'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('estudio en $nombre: cuatro notas con su intervalo, deshacer y resumen final', (tester) async {
      final api = await _montar(
        tester,
        tam,
        const FlashcardStudyScreen(deck: _grupo, limit: 20, opciones: {'ladder': true}),
      );
      expect(find.text('¿Cristales de la gota?'), findsOneWidget);
      await tester.tap(find.text('Mostrar respuesta'));
      await _settle(tester, 10);
      expect(find.text('Otra vez'), findsOneWidget);
      expect(find.text('10 min'), findsOneWidget);
      expect(find.text('8 d'), findsOneWidget);

      await tester.tap(find.text('Bien'));
      await _settle(tester, 10);
      expect(api.grados, [3]);
      expect(find.text('1 repasadas'), findsOneWidget);
      expect(find.text('¿Tratamiento de la crisis?'), findsOneWidget);

      // Deshacer: vuelve la anterior, ya girada, y el contador baja.
      await tester.tap(find.byTooltip('Deshacer el último repaso'));
      await _settle(tester, 10);
      expect(api.deshecho, isTrue);
      expect(find.text('0 repasadas'), findsOneWidget);
      expect(find.text('8 d'), findsOneWidget, reason: 'vuelve con la respuesta a la vista');

      await tester.tap(find.text('Fácil').last);
      await _settle(tester, 10);
      await tester.tap(find.text('Mostrar respuesta'));
      await _settle(tester, 10);
      await tester.tap(find.text('Otra vez'));
      await _settle(tester, 20);
      expect(api.grados, [3, 4, 1]);
      expect(find.text('¡Sesión completada!'), findsOneWidget);
      expect(find.text('Has desbloqueado Media en Gota'), findsOneWidget);
      expect(find.text('Repasar de nuevo'), findsOneWidget);
      expect(tester.takeException(), isNull);
      // Se agota la ventana del permiso de celebrar (ProgressProvider), que deja un temporizador.
      await tester.pump(const Duration(seconds: 10));
    });
  }

  testWidgets('ajustes de la sesión: avisa de cuántas salen y devuelve lo elegido', (tester) async {
    AjustesSesion? elegido;
    await _montar(
      tester,
      const Size(390, 844),
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async {
                elegido = await elegirAjustesSesion(context, deckName: 'Reumatología', cards: _cards, inicial: kAjustesPorDefecto, escalera: _escalera(abierta: false));
              },
              child: const Text('Estudiar'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Estudiar'));
    await _settle(tester);
    // Las 4 menos la nueva de Media (cerrada por la escalera).
    expect(find.textContaining('Vas a estudiar 3 tarjetas.'), findsOneWidget);
    await tester.tap(find.text('Solo falladas'));
    await _settle(tester, 5);
    expect(find.textContaining('Vas a estudiar 1 tarjeta.'), findsOneWidget);
    await tester.tap(find.text('Empezar'));
    await _settle(tester);
    expect(elegido?.solo, SoloTarjetas.failed);
    expect(tester.takeException(), isNull);
  });
}
