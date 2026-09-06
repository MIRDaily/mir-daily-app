// Regresión: en la cabecera de la tarjeta de pregunta del daily, el año y el
// botón de guardar tienen que quedar pegados al borde derecho de la tarjeta.
//
// El fallo: el badge de asignatura iba en un `Flexible` (flex 1) compitiendo
// con un `Spacer` (flex 1). Con una asignatura corta el badge no llenaba su
// mitad del hueco y el año + botón se quedaban a media tarjeta, descentrados.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:mirdaily_app/core/models/models.dart';
import 'package:mirdaily_app/core/providers/saved_questions_provider.dart';
import 'package:mirdaily_app/core/providers/daily_provider.dart';
import 'package:mirdaily_app/core/services/api_service.dart';
import 'package:mirdaily_app/core/services/auth_service.dart';
import 'package:mirdaily_app/core/theme/app_theme.dart';
import 'package:mirdaily_app/features/daily/daily_quiz_screen.dart';

DailyQuestion _q(String subject) => DailyQuestion(
      id: '1',
      year: 2017,
      subject: subject,
      statement: 'Un hombre de 57 años acude a su consulta buscando información '
          'sobre el tratamiento quirúrgico de los síntomas del tracto urinario '
          'inferior secundarios a crecimiento prostático.',
      options: const ['A', 'B', 'C', 'D'],
      correctAnswer: 1,
      explanation: '',
    );

class _FakeApi extends ApiService {
  _FakeApi() : super(AuthService());
}

class _FakeDaily extends DailyProvider {
  _FakeDaily(super.api, this._q);
  final DailyQuestion _q;

  @override
  DailyStatus get status => DailyStatus.playing;
  @override
  List<DailyQuestion> get questions => [_q];
  @override
  DailyQuestion? get currentQuestion => _q;
  @override
  int get currentIndex => 0;
}

Future<void> _pump(WidgetTester tester, Size size, String subject) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final api = _FakeApi();
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<ApiService>.value(value: api),
        ChangeNotifierProvider(create: (_) => SavedQuestionsProvider()),
        ChangeNotifierProvider<DailyProvider>(
          create: (_) => _FakeDaily(api, _q(subject)),
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: const DailyQuizScreen(),
      ),
    ),
  );
  await tester.pump();
  for (var i = 0; i < 15; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

void main() {
  for (final (name, size, subject) in [
    ('ancho · asignatura corta', const Size(1100, 1400), 'Urología'),
    ('ancho · asignatura larga', const Size(1100, 1400),
        'Digestivo y Cirugía General'),
    ('móvil · asignatura corta', const Size(390, 850), 'Urología'),
  ]) {
    testWidgets('el año + guardar quedan a la derecha ($name)', (tester) async {
      await _pump(tester, size, subject);

      // La tarjeta de pregunta: el primer Container con el radio de 24.
      final cardRight = tester
          .getRect(find.ancestor(
            of: find.text('MIR 2017'),
            matching: find.byType(Container),
          ).first)
          .right;
      final saveRight =
          tester.getRect(find.byIcon(Icons.bookmark_add_outlined)).right;

      // El borde de la tarjeta lleva 22 px de padding y el IconButton centra su
      // icono de 20 px en ~36; con eso, "pegado a la derecha" son ~34 px. Roto
      // (Flexible + Spacer con asignatura corta) eran ~155.
      expect(cardRight - saveRight, lessThan(45),
          reason: 'guardar a ${cardRight - saveRight}px del borde: descentrado');
    });
  }
}
