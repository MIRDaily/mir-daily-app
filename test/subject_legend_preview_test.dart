// Cómo queda la leyenda de siglas al pie del sobre.
//
//   flutter test test/subject_legend_preview_test.dart --update-goldens
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mirdaily_app/core/theme/app_theme.dart';
import 'package:mirdaily_app/features/quiz/widgets/subject_legend.dart';

void main() {
  testWidgets('leyenda con las 5 asignaturas del sobre', (tester) async {
    tester.view.physicalSize = const Size(390, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: const Scaffold(
          backgroundColor: AppColors.background,
          body: SubjectLegend(
            specialties: [
              'Cardiología',
              'Enfermedades infecciosas',
              'Ginecología y Obstetricia',
              'Traumatología',
              'Geriatría',
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/subject_legend.png'),
    );
  });
}
