// Los pesos del MIR y el reparto de preguntas.
//
//   flutter test test/mir_weights_test.dart
//
// Es lógica pura y con trampas conocidas: en la web hubo que corregir nueve
// porcentajes desplazados y un cruce de asignaturas ("urologia" está dentro de
// "neurologia"). Merece la pena tenerlo sujeto.
import 'package:flutter_test/flutter_test.dart';

import 'package:mirdaily_app/core/data/mir_weights.dart';

void main() {
  group('pesos', () {
    test('la tabla no se ha desviado', () {
      // Los porcentajes de la fuente vienen redondeados a una decimal y suman
      // 100,1, no 100 (el comentario de la web dice 100; los veinte valores
      // dan 100,1). Da igual para el reparto, porque `allocateByWeight`
      // normaliza sobre la suma real — pero el margen tiene que ser estrecho
      // para que cambiar un peso a mano salte aquí.
      final sum = kMirWeights.values.fold<double>(0, (a, b) => a + b);
      expect(sum, closeTo(100.1, 0.05));
      expect(kMirWeights.length, 20);
    });

    test('no cruza urologia con neurologia', () {
      expect(weightForSubject('Neurología'), kMirWeights['neurologia']);
      expect(weightForSubject('Urología'), kMirWeights['urologia']);
      // El fallo clásico: comparar por subcadena daría el mismo peso a las dos.
      expect(weightForSubject('Neurología') == weightForSubject('Urología'),
          isFalse);
    });

    test('aguanta tildes, mayusculas y nombres compuestos', () {
      expect(weightForSubject('CARDIOLOGÍA'), kMirWeights['cardiologia']);
      expect(weightForSubject('Digestivo y cirugía general'),
          kMirWeights['digestivo']);
      expect(weightForSubject('Ginecología y Obstetricia'),
          kMirWeights['ginecologia']);
    });

    test('los alias van a su asignatura', () {
      expect(weightForSubject('ORL'), kMirWeights['otorrinolaringologia']);
      expect(weightForSubject('Endocrino'), kMirWeights['endocrinologia']);
      expect(weightForSubject('Traumatología y COT'),
          kMirWeights['traumatologia']);
    });

    test('una asignatura desconocida no se queda fuera', () {
      expect(weightForSubject('Bioética y legislación'), kDefaultWeight);
      expect(weightForSubject(''), kDefaultWeight);
    });
  });

  group('reparto', () {
    List<({int id, String name})> subjectsOf(List<String> names) => [
          for (var i = 0; i < names.length; i++) (id: i + 1, name: names[i])
        ];

    test('la suma cuadra exactamente con el total', () {
      final subjects = subjectsOf(kMirWeights.keys.toList());
      for (final total in [10, 25, 50, 100, 210, 7, 213]) {
        final alloc = allocateByWeight(total, subjects);
        final sum = alloc.fold<int>(0, (a, b) => a + b.count);
        expect(sum, total, reason: 'con total=$total');
      }
    });

    test('reparte proporcionalmente al peso', () {
      final alloc = allocateByWeight(
        210,
        subjectsOf(['Digestivo', 'Oftalmología']),
      );
      final dig = alloc.firstWhere((a) => a.name == 'Digestivo').count;
      final oft = alloc.firstWhere((a) => a.name == 'Oftalmología').count;
      // 9,8 frente a 1,6: al primero le toca bastante más que al segundo.
      expect(dig, greaterThan(oft));
      expect(dig + oft, 210);
    });

    test('con mas asignaturas que preguntas no se pierde ninguna pregunta', () {
      final subjects = subjectsOf(kMirWeights.keys.toList());
      final alloc = allocateByWeight(3, subjects);
      expect(alloc.fold<int>(0, (a, b) => a + b.count), 3);
    });

    test('los casos vacios no revientan', () {
      expect(allocateByWeight(0, subjectsOf(['Digestivo'])), isEmpty);
      expect(allocateByWeight(10, const []), isEmpty);
    });
  });
}
