// La leyenda de siglas al pie del sobre.
//
//   flutter test test/subject_legend_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mirdaily_app/features/quiz/widgets/subject_legend.dart';

Future<void> _pump(WidgetTester tester, List<String> specialties) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: SubjectLegend(specialties: specialties)),
    ),
  );
  await tester.pump(const Duration(milliseconds: 400)); // entra con fundido
}

void main() {
  testWidgets('enseña sigla + nombre de cada asignatura del sobre',
      (tester) async {
    await _pump(tester, const [
      'Cardiología',
      'Neurología',
      'Digestivo',
      'Pediatría',
      'Urología',
    ]);

    for (final s in ['CD', 'NR', 'DG', 'PD', 'UR']) {
      expect(find.textContaining(s, findRichText: true), findsWidgets,
          reason: 'falta la sigla $s');
    }
    expect(find.textContaining('Cardiología', findRichText: true), findsWidgets);
  });

  testWidgets('una asignatura repetida sale una sola vez', (tester) async {
    await _pump(tester, const [
      'Cardiología',
      'Cardiología',
      'Neurología',
      'Cardiología',
      'Digestivo',
    ]);

    final cd = tester
        .widgetList<RichText>(find.byType(RichText))
        .where((w) => w.text.toPlainText().contains('CD'))
        .length;
    expect(cd, 1, reason: 'la sigla CD debería aparecer una vez');
  });

  testWidgets('sin asignaturas no pinta nada', (tester) async {
    await _pump(tester, const []);
    expect(find.byType(Wrap), findsNothing);
    expect(find.byType(RichText), findsNothing);
  });
}
