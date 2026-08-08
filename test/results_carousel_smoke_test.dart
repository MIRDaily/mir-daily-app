import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:mirdaily_app/core/models/models.dart';
import 'package:mirdaily_app/core/providers/auth_provider.dart';
import 'package:mirdaily_app/core/providers/daily_provider.dart';
import 'package:mirdaily_app/core/services/api_service.dart';
import 'package:mirdaily_app/core/services/auth_service.dart';
import 'package:mirdaily_app/features/results/results_screen.dart';

/// ApiService falso: devuelve datos de ejemplo para poder renderizar la
/// pantalla de resultados sin tocar el backend real.
class _FakeApi extends ApiService {
  _FakeApi() : super(AuthService());

  @override
  Future<DailyResults> getResultsToday() async => DailyResults(
        score: 1240,
        correctCount: 4,
        totalQuestions: 5,
        totalTime: 210,
        breakdown:
            const ScoreBreakdown(knowledgeScore: 800, timeBonus: 440, total: 1240),
        mean: 900,
        stdDev: 220,
        zScore: 1.4,
        reviewQuestions: List.generate(
          5,
          (i) => ReviewQuestion(
            questionId: 'q$i',
            statement:
                'Enunciado de ejemplo número ${i + 1} para revisar en el carrusel de resultados.',
            options: const ['Opción A', 'Opción B', 'Opción C', 'Opción D'],
            correctAnswer: 1,
            selectedAnswer: i == 2 ? 3 : 1,
            isCorrect: i != 2,
            explanation: 'Explicación de ejemplo para la pregunta ${i + 1}.',
          ),
        ),
      );

  @override
  Future<List<RankingEntry>> getRanking() async => List.generate(
        20,
        (i) => RankingEntry(
          position: i + 1,
          displayName: 'Opositor ${i + 1}',
          avatarId: 1,
          score: 1500 - i * 30,
          correctCount: 5 - (i % 3),
          totalTime: 200 + i,
          isBot: false,
          userId: 'user$i',
        ),
      );

  @override
  Future<ScoreDistribution> getScoreDistribution() async => ScoreDistribution(
        scores: List.generate(60, (i) => 600 + (i * 17) % 900),
        mean: 950,
        median: 940,
        percentile: 78,
        totalUsers: 60,
        sameScoreCount: 3,
        userScore: 1240,
      );

  @override
  Future<StatsSummary> getStatsSummary() async => const StatsSummary(
        avgPercentage: 72,
        totalQuestions: 120,
        trend: 4.5,
        trendType: 'full',
        insufficientData: false,
        dailys30: 24,
      );

  @override
  Future<ActivityHeatmap> getActivityHeatmap() async => ActivityHeatmap(
        days: List.generate(
            30, (i) => HeatDay(date: '2026-07-${i + 1}', level: i % 3)),
        currentStreak: 6,
        longestStreak: 12,
        totalActiveDays: 40,
        totalDailyDays: 24,
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildApp(_FakeApi api) {
    final authService = AuthService();
    return MultiProvider(
      providers: [
        Provider<ApiService>.value(value: api),
        ChangeNotifierProvider<DailyProvider>(create: (_) => DailyProvider(api)),
        ChangeNotifierProvider<AuthProvider>(
          create: (_) =>
              AuthProvider(authService: authService, apiService: api),
        ),
      ],
      child: const MaterialApp(home: ResultsScreen()),
    );
  }

  testWidgets('El carrusel de resultados se monta y navega sin excepciones',
      (tester) async {
    // Silencia los canales del plugin app_links (usado por AuthProvider).
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.llfbandit.app_links/messages'),
      (call) async => null,
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.llfbandit.app_links/events'),
      (call) async => null,
    );

    // Tamaño de móvil.
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _FakeApi();
    await tester.pumpWidget(buildApp(api));

    // Deja que _prepare() cargue los datos y se compongan los slides.
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 90));
    }
    expect(tester.takeException(), isNull);

    // Slide 1 (hero) visible: anillo de aciertos + control inferior.
    expect(find.text('ACIERTOS'), findsOneWidget);
    expect(find.text('Siguiente'), findsOneWidget);

    // Bombea hasta que aparezca un finder (o se agote el tiempo), tolerando
    // las animaciones en repeat (no se puede usar pumpAndSettle).
    Future<void> pumpUntil(Finder finder,
        {int maxMs = 6000, int step = 100}) async {
      var waited = 0;
      while (waited < maxMs && finder.evaluate().isEmpty) {
        await tester.pump(Duration(milliseconds: step));
        waited += step;
      }
    }

    Future<void> advance(String expectText) async {
      await tester.tap(find.text('Siguiente'), warnIfMissed: false);
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 90));
      }
      await pumpUntil(find.text(expectText));
      expect(tester.takeException(), isNull,
          reason: 'Excepción al llegar al slide "$expectText"');
      expect(find.text(expectText), findsWidgets,
          reason: 'No se encontró el slide "$expectText"');
    }

    // hero → desglose → comparativo → progreso → distribución.
    await advance('Desglose de puntuación');
    await advance('Rendimiento comparativo');
    await advance('Progreso');
    await advance('Distribución de hoy');

    // Ranking: primero la REVELACIÓN del puesto (nombre + posición), y luego
    // la transición automática a la clasificación completa.
    await tester.tap(find.text('Siguiente'), warnIfMissed: false);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 90));
    }
    expect(tester.takeException(), isNull, reason: 'Excepción en el reveal');
    expect(find.text('TU POSICIÓN DE HOY'), findsOneWidget,
        reason: 'La fase de revelación del puesto no apareció');
    expect(find.text('Tú'), findsWidgets); // nombre del usuario
    // Espera a que auto-transicione a la tabla.
    await pumpUntil(find.text('Ranking Global'), maxMs: 7000);
    // Deja terminar la transición A → B.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.takeException(), isNull);
    expect(find.text('Ranking Global'), findsWidgets);
    expect(find.text('TU PUESTO ACTUAL'), findsOneWidget);
    // La fase de revelación ya no está.
    expect(find.text('TU POSICIÓN DE HOY'), findsNothing);

    // Revisiones + actividad.
    await advance('Revisión · 1/5');
    await advance('Revisión · 2/5');
    await advance('Revisión · 3/5');
    await advance('Revisión · 4/5');
    await advance('Revisión · 5/5');
    await advance('Tu actividad');

    // Desmonta para liberar los AnimationController en repeat.
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
}
