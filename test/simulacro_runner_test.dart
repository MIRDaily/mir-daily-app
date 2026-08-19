// La rejilla de corrección del simulacro, que comparten la fase de resultados
// y el repaso del historial.
//
//   flutter test test/simulacro_runner_test.dart
//
// Los runners (clásico y carrusel) son privados y solo se llega a ellos
// atravesando el creador entero, así que aquí no entran: lo que se sujeta es
// la pieza compartida y el contrato de datos que le pasan los dos.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mirdaily_app/core/models/models.dart';
import 'package:mirdaily_app/core/theme/app_theme.dart';
import 'package:mirdaily_app/features/simulacro/simulacro_screen.dart';

final _preguntas = [
  for (var i = 1; i <= 3; i++)
    SimQuestion(
      id: i,
      statement: 'Enunciado de la pregunta $i con varias palabras sueltas',
      subject: 'Cardiología',
      options: const ['Opción A', 'Opción B', 'Opción C', 'Opción D'],
    ),
];

void main() {
  testWidgets('la rejilla cuenta aciertos, fallos y blancos', (tester) async {
    tester.view.physicalSize = const Size(420, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: SimResultsView(
            questions: _preguntas,
            // Acierto, fallo y sin contestar.
            answers: const [0, 1, null],
            results: const [
              SimResult(questionId: 1, correctIndex: 0, isCorrect: true),
              SimResult(questionId: 2, correctIndex: 0, isCorrect: false),
              null,
            ],
            onRestart: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    // 1 de 3: el blanco no cuenta como acierto.
    expect(find.text('1 / 3 aciertos'), findsOneWidget);
  });

  testWidgets('el repaso del historial cambia los rotulos', (tester) async {
    tester.view.physicalSize = const Size(420, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: SimResultsView(
            questions: _preguntas,
            answers: const [0, 0, 0],
            results: const [
              SimResult(questionId: 1, correctIndex: 0, isCorrect: true),
              SimResult(questionId: 2, correctIndex: 0, isCorrect: true),
              SimResult(questionId: 3, correctIndex: 0, isCorrect: true),
            ],
            eyebrow: 'SIMULACRO GUARDADO',
            restartLabel: 'Volver al historial',
            onRestart: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('SIMULACRO GUARDADO'), findsOneWidget);
    expect(find.text('Volver al historial'), findsOneWidget);
    // Sin `onClose` no debe salir el botón de volver.
    expect(find.text('Volver'), findsNothing);
  });
}
