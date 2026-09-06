// Siglas e iconos de asignatura para las cartas del sobre.
//
//   flutter test test/subject_visuals_test.dart
//
// Es lógica pura con la misma trampa que `mir_weights`: los nombres del
// backend vienen con mil variantes, y "urologia" está dentro de "neurologia".
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import 'package:mirdaily_app/core/data/subject_visuals.dart';

void main() {
  test('casa el nombre exacto', () {
    expect(subjectVisual('Cardiología').sigla, 'CD');
    expect(subjectVisual('Cardiología').icon, LucideIcons.heart);
    expect(subjectVisual('Neurología').sigla, 'NR');
    expect(subjectVisual('Digestivo').sigla, 'DG');
  });

  test('aguanta tildes, mayúsculas y nombres compuestos', () {
    expect(subjectVisual('CARDIOLOGÍA').sigla, 'CD');
    expect(subjectVisual('Digestivo y Cirugía General').sigla, 'DG');
    expect(subjectVisual('Ginecología y Obstetricia').sigla, 'GC');
    expect(subjectVisual('Aparato digestivo').sigla, 'DG');
  });

  test('no cruza urología con neurología', () {
    expect(subjectVisual('Neurología').sigla, 'NR');
    expect(subjectVisual('Urología').sigla, 'UR');
    expect(subjectVisual('Neurología').icon == subjectVisual('Urología').icon,
        isFalse);
  });

  test('alias conocidos', () {
    expect(subjectVisual('COT').sigla, 'TM'); // traumatología
    expect(subjectVisual('ORL').sigla, 'OR'); // otorrino
    expect(subjectVisual('Microbiología').sigla, 'IF'); // infecciosas
  });

  test('asignatura desconocida: sigla de iniciales + icono genérico', () {
    final geriatria = subjectVisual('Geriatría');
    expect(geriatria.sigla, 'GE');
    expect(geriatria.icon, LucideIcons.stethoscope);

    expect(subjectVisual('Cuidados Paliativos').sigla, 'CP');
  });

  test('cada asignatura del MIR tiene una sigla distinta', () {
    const nombres = [
      'Digestivo', 'Cardiología', 'Neurología', 'Neumología', 'Infecciosas',
      'Endocrinología', 'Ginecología', 'Estadística', 'Reumatología',
      'Traumatología', 'Pediatría', 'Nefrología', 'Psiquiatría', 'Hematología',
      'Otorrinolaringología', 'Dermatología', 'Urología', 'Inmunología',
      'Oftalmología',
    ];
    final siglas = nombres.map((n) => subjectVisual(n).sigla).toList();
    expect(siglas.toSet().length, siglas.length, reason: 'siglas repetidas');
  });
}
