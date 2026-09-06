// Cómo queda la slide "Distribución de hoy" de la revisión del daily: la
// campana KDE (media azul, mediana naranja, tu marca roja) portada de la web,
// con su fondo de puntitos a la deriva. En tablet va más grande.
//
//   flutter test test/distribution_slide_preview_test.dart --update-goldens
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:mirdaily_app/core/models/models.dart';
import 'package:mirdaily_app/core/providers/auth_provider.dart';
import 'package:mirdaily_app/core/providers/daily_provider.dart';
import 'package:mirdaily_app/core/providers/saved_questions_provider.dart';
import 'package:mirdaily_app/core/services/api_service.dart';
import 'package:mirdaily_app/core/services/auth_service.dart';
import 'package:mirdaily_app/features/results/results_screen.dart';

class _FakeApi extends ApiService {
  _FakeApi() : super(AuthService());

  // Una campana creíble: normal(700, 110) redondeada, ~200 puntuaciones.
  static List<int> _bell() {
    final r = Random(7);
    return List.generate(200, (_) {
      final g = (r.nextDouble() + r.nextDouble() + r.nextDouble() - 1.5) * 2;
      return (700 + g * 110).round().clamp(200, 1300);
    });
  }

  @override
  Future<DailyResults> getResultsToday() async => const DailyResults(
        // correctCount < 3 a propósito: con 3+ el hero lanza confeti + una
        // háptica con temporizadores encadenados que dejan el test sucio.
        score: 900,
        correctCount: 2,
        totalQuestions: 5,
        totalTime: 190,
        breakdown:
            ScoreBreakdown(knowledgeScore: 400, timeBonus: 500, total: 900),
        reviewQuestions: [],
        mean: 687,
        stdDev: 110,
        zScore: 1.9,
      );

  @override
  Future<ScoreDistribution> getScoreDistribution() async {
    final s = _bell()..sort();
    return ScoreDistribution(
      scores: s,
      mean: 687.0,
      median: 705.5,
      percentile: 91,
      totalUsers: s.length,
      sameScoreCount: 3,
      userScore: 900,
    );
  }

  @override
  Future<List<RankingEntry>> getRanking() async => const [];

  @override
  Future<StatsSummary> getStatsSummary() async => const StatsSummary(
        avgPercentage: null,
        totalQuestions: 0,
        trend: null,
        trendType: 'insufficient',
        insufficientData: true,
        dailys30: 1,
      );
}

void main() {
  for (final (slug, size, dpr) in [
    ('movil', const Size(1080, 2160), 3.0),
    ('tablet', const Size(1700, 2200), 2.0),
  ]) {
    testWidgets('la campana de la distribución · $slug', (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('com.llfbandit.app_links/messages'),
        (call) async => null,
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('com.llfbandit.app_links/events'),
        (call) async => null,
      );

      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = dpr;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final authService = AuthService();
      final api = _FakeApi();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<ApiService>.value(value: api),
            ChangeNotifierProvider(create: (_) => SavedQuestionsProvider()),
            ChangeNotifierProvider<DailyProvider>(
                create: (_) => DailyProvider(api)),
            ChangeNotifierProvider<AuthProvider>(
              create: (_) =>
                  AuthProvider(authService: authService, apiService: api),
            ),
          ],
          child: const MaterialApp(home: ResultsScreen()),
        ),
      );

      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 90));
      }

      // hero → desglose → comparativo → distribución (sin ranking/progreso).
      var waited = 0;
      while (waited < 12000 &&
          find.text('Distribución de hoy').evaluate().isEmpty) {
        await tester.tap(find.text('Siguiente'), warnIfMissed: false);
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 90));
        }
        waited += 800;
      }
      expect(find.text('Distribución de hoy'), findsWidgets);

      // Deja terminar la animación de entrada de la curva.
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/distribution_slide_$slug.png'),
      );

      // Suelta los AnimationController en repeat (fondo vivo, deriva…).
      await tester.pumpWidget(const SizedBox());
    });
  }
}
