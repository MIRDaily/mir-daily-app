// Tanda 4: el botón de reportar dentro de las pantallas reales de preguntas, en móvil y tablet, sin
// desbordes y con el contexto que manda la web (origen, si ya respondió, qué y si acertó).
//   - Detalle de la corrección del simulacro (es el mismo del historial): origen simulacro_review.
//   - Estudio de un mazo: origen deck, la sesión y la respuesta tras «Comprobar».
// El daily lo cubre save_to_deck_reachable_test (golden de la cabecera).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mirdaily_app/core/models/models.dart';
import 'package:mirdaily_app/core/providers/saved_questions_provider.dart';
import 'package:mirdaily_app/core/services/api_service.dart';
import 'package:mirdaily_app/core/services/auth_service.dart';
import 'package:mirdaily_app/core/services/reportes_api.dart';
import 'package:mirdaily_app/core/theme/app_theme.dart';
import 'package:mirdaily_app/features/decks/deck_study_screen.dart';
import 'package:mirdaily_app/features/decks/widgets/deck_study_options.dart';
import 'package:mirdaily_app/features/simulacro/simulacro_screen.dart';
import 'package:provider/provider.dart';

final _tamanos = [('móvil', const Size(360, 780)), ('tablet', const Size(1024, 768))];

ReportesApi _api(List<Map<String, dynamic>> envios) => ReportesApi(
      token: () async => 'TOKEN',
      baseUrl: 'https://api.test',
      client: MockClient((req) async {
        if (req.url.path.endsWith('/mine')) return http.Response('{"reports":[]}', 200);
        envios.add(jsonDecode(req.body) as Map<String, dynamic>);
        return http.Response('{"ok":true,"updated":false}', 200);
      }),
    );

/// Elige «Errata» (sale antes y después de responder) y envía.
Future<void> _reportarErrata(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.report_outlined));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  await tester.tap(find.text('Errata en enunciado u opciones'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Enviar'));
  await tester.pumpAndSettle();
  expect(find.text('¡Gracias por avisar!'), findsOneWidget);
  await tester.pump(const Duration(seconds: 3));
  await tester.pumpAndSettle();
}

class _FakeApi extends ApiService {
  _FakeApi() : super(AuthService());

  @override
  Future<String> startDeckSession(String deckId, int limit) async => 'ses-1';

  @override
  Future<DeckCard?> getNextDeckItem(String deckId, String sessionId,
          {int? subjectId, String? status, String mode = 'normal'}) async =>
      const DeckCard(
        itemId: '11',
        questionId: '4265',
        statement: 'Mujer de 34 años con fiebre, artralgias y eritema malar. ¿Qué anticuerpo es más específico?',
        options: ['Anti-ADN de doble cadena', 'Antinucleares', 'Anti-Ro', 'Factor reumatoide'],
        correctAnswer: 1,
        subject: 'Reumatología',
      );

  @override
  Future<bool> logDeckItem({
    required String deckId,
    required String deckItemId,
    required int selectedOption,
    required String sessionId,
  }) async =>
      false;

  @override
  Future<void> endDeckSession(String sessionId) async {}
}

void main() {
  setUp(Reportadas.instancia.olvidar);

  for (final (nombre, tam) in _tamanos) {
    testWidgets('simulacro en $nombre: el detalle de la corrección reporta como simulacro_review', (tester) async {
      tester.view.physicalSize = tam;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final envios = <Map<String, dynamic>>[];

      await tester.pumpWidget(MultiProvider(
        providers: [
          Provider<ReportesApi>.value(value: _api(envios)),
          ChangeNotifierProvider(create: (_) => SavedQuestionsProvider()),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: SimResultsView(
              questions: const [
                SimQuestion(id: 31, statement: 'Enunciado uno', subject: 'Cardiología', options: ['A1', 'B1', 'C1', 'D1']),
                SimQuestion(id: 32, statement: 'Enunciado dos', subject: 'Cardiología', options: ['A2', 'B2', 'C2', 'D2']),
              ],
              answers: const [1, null],
              results: const [
                SimResult(questionId: 31, correctIndex: 0, isCorrect: false),
                null,
              ],
              onRestart: () {},
            ),
          ),
        ),
      ));
      await tester.pump();
      // La celda 1 de la rejilla (hay más «1» en los contadores).
      await tester.tap(find.text('1').last);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.report_outlined), findsOneWidget);
      expect(tester.takeException(), isNull);

      await _reportarErrata(tester);
      final b = envios.single;
      expect(b['questionId'], 31);
      expect(b['origin'], 'simulacro_review');
      expect(b['answered'], true);
      expect(b['userAnswer'], 2);
      expect(b['isCorrect'], false);
      // Vuelve al detalle con la bandera rellena.
      expect(find.byIcon(Icons.report_rounded), findsOneWidget);
    });

    testWidgets('mazo en $nombre: antes y después de comprobar, con la sesión', (tester) async {
      tester.view.physicalSize = tam;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final envios = <Map<String, dynamic>>[];

      await tester.pumpWidget(MultiProvider(
        providers: [
          Provider<ApiService>.value(value: _FakeApi()),
          Provider<ReportesApi>.value(value: _api(envios)),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const DeckStudyScreen(
            deck: Deck(
              id: 'd1',
              name: 'Reuma',
              systemGenerated: false,
              autoType: 'none',
              accuracy: 0.5,
              totalReviews: 3,
              visualState: 'clean',
              totalItems: 1,
            ),
            options: DeckStudyOptions(limit: 10),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.report_outlined), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Sin responder: no se ofrece «Respuesta correcta errónea».
      await tester.tap(find.byIcon(Icons.report_outlined));
      await tester.pumpAndSettle();
      expect(find.text('Respuesta correcta errónea'), findsNothing);
      await tester.tap(find.byTooltip('Cerrar'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Antinucleares'));
      await tester.pump();
      await tester.tap(find.text('COMPROBAR'));
      await tester.pumpAndSettle();

      await _reportarErrata(tester);
      final b = envios.single;
      expect(b['questionId'], 4265);
      expect(b['origin'], 'deck');
      expect(b['sessionRef'], 'ses-1');
      expect(b['answered'], true);
      expect(b['userAnswer'], 2);
      expect(b['isCorrect'], false);
      expect(tester.takeException(), isNull);
    });
  }
}
