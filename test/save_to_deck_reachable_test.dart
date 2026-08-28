// El botón de "guardar en mazo" tiene que estar AL ALCANCE, no solo existir
// en el código: la primera versión lo puso únicamente en la revisión del daily
// y en sitios del simulacro que dependían del modo elegido, así que en la
// práctica no aparecía casi nunca.
//
// Esta prueba monta la pantalla del daily EN PLENA PARTIDA y comprueba que el
// botón está y que abre el selector de mazo.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:mirdaily_app/core/models/models.dart';
import 'package:mirdaily_app/core/providers/daily_provider.dart';
import 'package:mirdaily_app/core/services/api_service.dart';
import 'package:mirdaily_app/core/services/auth_service.dart';
import 'package:mirdaily_app/core/theme/app_theme.dart';
import 'package:mirdaily_app/features/daily/daily_quiz_screen.dart';

const _pregunta = DailyQuestion(
  id: '346',
  year: 2024,
  subject: 'Cardiología y Cirugía Cardiovascular',
  statement: 'Varón de 68 años que acude por dolor torácico opresivo de dos '
      'horas de evolución. ¿Cuál es la actitud más adecuada?',
  options: [
    'Solicitar una ergometría ambulatoria.',
    'Realizar un ECG de 12 derivaciones de inmediato.',
    'Iniciar tratamiento con ansiolíticos.',
    'Derivar a consulta de cardiología en una semana.',
  ],
  correctAnswer: 2,
  explanation: 'El ECG debe hacerse en los primeros 10 minutos.',
);

class _FakeApi extends ApiService {
  _FakeApi() : super(AuthService());

  @override
  Future<List<Deck>> getDecks() async => const [
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
      ];

  // Sin red: la comprobación de en qué mazos está la pregunta se responde en
  // seco, que aquí lo que se prueba es que el botón se pueda alcanzar.
  @override
  Future<Map<String, String>> findQuestionInDecks(
    List<String> deckIds,
    String questionId,
  ) async =>
      const {};
}

/// En partida, con una pregunta servida.
class _FakeDaily extends DailyProvider {
  _FakeDaily(super.api);

  @override
  DailyStatus get status => DailyStatus.playing;

  @override
  List<DailyQuestion> get questions => const [_pregunta];

  @override
  DailyQuestion? get currentQuestion => _pregunta;

  @override
  int get currentIndex => 0;
}

void main() {
  testWidgets('durante el daily se puede guardar la pregunta en un mazo',
      (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final api = _FakeApi();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ApiService>.value(value: api),
          ChangeNotifierProvider<DailyProvider>(create: (_) => _FakeDaily(api)),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          home: const DailyQuizScreen(),
        ),
      ),
    );
    // Varios fotogramas: las opciones entran con SlideFadeIn y un solo pump
    // largo las dejaría a media animación, invisibles.
    await tester.pump();
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    // Está, sin haber contestado todavía.
    final boton = find.byIcon(Icons.bookmark_add_outlined);
    expect(boton, findsOneWidget);

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/daily_save_to_deck.png'),
    );

    // Y abre el selector de mazo de verdad.
    await tester.tap(boton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('GUARDAR EN MAZO'), findsOneWidget);
    expect(find.text('madre mia'), findsOneWidget);
  });
}
