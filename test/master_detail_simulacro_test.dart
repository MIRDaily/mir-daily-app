// Maestro-detalle del Historial de simulacros: mismo patrón que Mazos y
// Flashcards, pero maestro y detalle viven en el mismo fichero.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:mirdaily_app/core/models/models.dart';
import 'package:mirdaily_app/core/responsive/master_detail_scaffold.dart';
import 'package:mirdaily_app/core/services/api_service.dart';
import 'package:mirdaily_app/core/services/auth_service.dart';
import 'package:mirdaily_app/core/theme/app_theme.dart';
import 'package:mirdaily_app/features/simulacro/simulacro_historial_screen.dart';

SimSession _session(String id) => SimSession(
      id: id,
      mode: 'exam',
      totalQuestions: 60,
      correctCount: 40,
      wrongCount: 15,
      blankCount: 5,
      timeSpentSeconds: 3600,
      startedAt: DateTime(2026, 1, 1),
      finishedAt: DateTime(2026, 1, 1, 1),
      subjects: const ['Cardiología'],
    );

class _FakeApi extends ApiService {
  _FakeApi() : super(AuthService());

  @override
  Future<List<SimSession>> getSimulacroHistory(
          {int limit = 20, int offset = 0}) async =>
      [_session('s1'), _session('s2')];

  @override
  Future<List<SimCalendarDay>> getSimulacroCalendar(
          {required DateTime from, required DateTime to}) async =>
      const [];

  @override
  Future<SimHistoryDetail> getSimulacroHistoryDetail(String id) async =>
      const SimHistoryDetail(questions: [], answers: [], results: []);
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
        home: const SimulacroHistorialScreen(),
      ),
    ),
  );
  await tester.pump();
  for (var i = 0; i < 15; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

void main() {
  testWidgets(
      'tablet grande: tocar un simulacro lo abre en el panel derecho',
      (tester) async {
    await _pump(tester, const Size(1280, 800));

    expect(find.byType(MasterDetailScaffold), findsOneWidget);
    expect(find.text('Elige un simulacro'), findsOneWidget);

    await tester.tap(find.text('40 de 60 aciertos').first);
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }

    expect(find.byType(MasterDetailScaffold), findsOneWidget);
    expect(find.text('Repaso'), findsOneWidget);
    expect(find.text('Elige un simulacro'), findsNothing);
  });

  testWidgets('móvil: tocar un simulacro navega a pantalla completa',
      (tester) async {
    await _pump(tester, const Size(390, 844));
    expect(find.byType(MasterDetailScaffold), findsNothing);

    await tester.tap(find.text('40 de 60 aciertos').first);
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }

    expect(find.byType(SimulacroHistorialScreen), findsNothing);
    expect(find.text('Repaso'), findsOneWidget);
  });
}
