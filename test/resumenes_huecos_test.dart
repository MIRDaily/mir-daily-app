import 'package:flutter_test/flutter_test.dart';

import 'package:mirdaily_app/core/models/resumen.dart';
import 'package:mirdaily_app/features/resumenes/resumenes_huecos.dart';

const _texto = 'La anemia ferropénica es frecuente';

void main() {
  group('notaDeRepaso', () {
    test('0 fallos = Bien; 1 = Difícil; 2+ = Otra vez', () {
      expect(notaDeRepaso(0), 3);
      expect(notaDeRepaso(1), 2);
      expect(notaDeRepaso(2), 1);
      expect(notaDeRepaso(5), 1);
    });
  });

  group('claveParrafo', () {
    test('normaliza a minúsculas y espacios', () {
      expect(claveParrafo('  La   ANEMIA  '), 'la anemia');
    });
  });

  group('sanearHuecos', () {
    test('descarta huecos inválidos, solapados y ordena', () {
      final raw = [
        {'i': 25, 'f': 34, 'n': 2}, // frecuente (válido)
        {'i': 3, 'f': 9, 'n': 1}, // anemia (válido)
        {'i': 3, 'f': 8, 'n': 2}, // solapa con anemia
        {'i': -1, 'f': 3, 'n': 1}, // fuera
        {'i': 0, 'f': 99, 'n': 1}, // fuera
        {'i': 1, 'f': 2, 'n': 5}, // nivel no válido
      ];
      final out = sanearHuecos(raw, _texto);
      expect(out.length, 2);
      expect(out[0].i, 3);
      expect(out[1].i, 25);
    });
  });

  group('errorHuecos', () {
    test('detecta vacío, solapamiento y fuera de rango', () {
      expect(errorHuecos(_texto, []), 'Marca al menos un hueco');
      expect(
        errorHuecos(_texto, [const Hueco(3, 9, 1), const Hueco(8, 15, 2)]),
        'Dos huecos se solapan',
      );
      expect(errorHuecos(_texto, [const Hueco(3, 99, 1)]), 'Un hueco se sale del texto');
      expect(errorHuecos(_texto, [const Hueco(3, 9, 1)]), isNull);
    });
  });

  group('segmentos', () {
    test('parte el texto en huecos y no-huecos', () {
      final s = segmentos(_texto, [const Hueco(3, 9, 1)]);
      expect(s[0].t, 'La ');
      expect(s[1].t, 'anemia');
      expect(s[1].k, 0);
      expect(s[2].t, ' ferropénica es frecuente');
    });
  });

  group('palabraEn / ajustarSeleccion', () {
    test('encuentra la palabra entera en una posición', () {
      expect(palabraEn(_texto, 5), (i: 3, f: 9)); // dentro de «anemia»
    });

    test('devuelve null sobre un espacio', () {
      expect(palabraEn(_texto, 2), isNull);
    });

    test('quita la puntuación de los bordes', () {
      expect(palabraEn('(anemia)', 3), (i: 1, f: 7));
    });
  });

  group('crearHueco / alternarPalabra', () {
    test('crear un hueco funde los que toca', () {
      final r = crearHueco(_texto, [const Hueco(3, 9, 1)], 12, 15, 3);
      // 12-15 cae dentro de «ferropénica» [10,21) y se funde con anemia [3,9)? No:
      // tocados = huecos que se solapan con la selección; anemia no se solapa.
      expect(r.error, isNull);
      expect(r.huecos.length, 2);
    });

    test('alternar quita el hueco si la palabra ya lo es', () {
      final r = alternarPalabra(_texto, [const Hueco(3, 9, 1)], 5, 2);
      expect(r.huecos, isEmpty);
    });
  });

  group('desplazarNiveles', () {
    test('sube y baja sin salir de 1-4', () {
      final sube = desplazarNiveles([const Hueco(0, 2, 4), const Hueco(3, 5, 1)], 1);
      expect(sube.huecos[0].n, 4);
      expect(sube.huecos[1].n, 2);
      expect(sube.cambiados, 1);
      expect(sube.enTope, 1);
    });
  });

  group('ajustarTrasEditar', () {
    test('mueve el hueco si su texto se conserva', () {
      final r = ajustarTrasEditar('Hola mundo', 'Hola precioso mundo', [const Hueco(5, 10, 1)]);
      expect(r.perdidos, 0);
      expect(r.huecos.single.i, 14);
      expect(r.huecos.single.f, 19);
    });

    test('pierde el hueco si su texto desaparece', () {
      final r = ajustarTrasEditar('Hola mundo', 'Hola chico', [const Hueco(5, 10, 1)]);
      expect(r.perdidos, 1);
      expect(r.huecos, isEmpty);
    });
  });

  group('estudio', () {
    final huecos = [const Hueco(3, 9, 1), const Hueco(10, 21, 3), const Hueco(25, 34, 2)];

    test('empezarParrafo tapa los huecos del nivel elegido', () {
      final e = empezarParrafo(huecos, [1, 2]);
      expect(e.tapados, [0, 2]);
    });

    test('solo huecos fallados tapa solo esos', () {
      final e = empezarParrafo(huecos, null, [2]);
      expect(e.tapados, [2]);
    });

    test('responder y terminar', () {
      var e = empezarParrafo(huecos, null);
      expect(terminado(e), isFalse);
      e = responder(e, 0, Respuesta.sabia);
      e = responder(e, 1, Respuesta.no);
      e = responder(e, 2, Respuesta.sabia);
      expect(terminado(e), isTrue);
      expect(fallos(e), 1);
    });

    test('reabrir y cambiarRespuesta', () {
      var e = responder(empezarParrafo(huecos, null), 0, Respuesta.no);
      e = cambiarRespuesta(e, 0);
      expect(e.respuestas[0], Respuesta.sabia);
      e = reabrir(e, 0);
      expect(e.respuestas.containsKey(0), isFalse);
    });

    test('resultados manda cada hueco tapado por su posición', () {
      final e = responder(responder(empezarParrafo(huecos, null), 0, Respuesta.no), 1, Respuesta.sabia);
      final r = resultados(e, huecos);
      expect(r, [(i: 3, f: 9, sabia: false), (i: 10, f: 21, sabia: true)]);
    });
  });

  group('sanearFallados / sanearFragmento', () {
    test('posiciones válidas sin repetir', () {
      expect(sanearFallados([1, 2, 2, 8, -1]), [1, 2]);
      expect(sanearFallados('no'), isNull);
    });

    test('fragmento recortado a 300', () {
      expect(sanearFragmento('  '), isNull);
      expect(sanearFragmento('hola')!.length, 4);
    });
  });
}
