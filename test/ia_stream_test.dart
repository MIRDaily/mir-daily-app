import 'package:flutter_test/flutter_test.dart';
import 'package:mirdaily_app/core/models/ia.dart';
import 'package:mirdaily_app/core/services/ia_stream.dart';

void main() {
  group('LectorLineas', () {
    test('entrega líneas completas aunque los trozos corten a mitad', () {
      final vistas = <String>[];
      final lector = LectorLineas(vistas.add);
      lector.push('{"a":1}\n{"b":');
      lector.push('2}\n');
      lector.fin();
      expect(vistas, ['{"a":1}', '{"b":2}']);
    });

    test('la última línea sin salto se entrega en fin()', () {
      final vistas = <String>[];
      final lector = LectorLineas(vistas.add);
      lector.push('uno');
      expect(vistas, isEmpty);
      lector.fin();
      expect(vistas, ['uno']);
    });
  });

  group('leerEvento', () {
    test('fase válida', () {
      final e = leerEvento('{"tipo":"fase","fase":"estructura"}');
      expect(e, isA<EventoFase>());
      expect((e as EventoFase).fase, FaseIa.estructura);
    });

    test('fase desconocida devuelve null', () {
      expect(leerEvento('{"tipo":"fase","fase":"inventada"}'), isNull);
    });

    test('rama válida con tema', () {
      final e = leerEvento('{"tipo":"rama","parte":2,"tema":1,"d":3,"t":"Anemia"}') as EventoRama;
      expect(e.parte, 2);
      expect(e.tema, 1);
      expect(e.d, 3);
      expect(e.t, 'Anemia');
    });

    test('rama con nivel fuera de rango devuelve null', () {
      expect(leerEvento('{"tipo":"rama","parte":0,"d":99,"t":"x"}'), isNull);
    });

    test('reinicio conserva parte y tema', () {
      final e = leerEvento('{"tipo":"reinicio","parte":1,"tema":4}') as EventoReinicio;
      expect(e.parte, 1);
      expect(e.tema, 4);
    });

    test('error trae mensaje, código y status', () {
      final e = leerEvento('{"tipo":"error","error":"Cupo agotado","codigo":"cupo","status":429}') as EventoError;
      expect(e.error, 'Cupo agotado');
      expect(e.codigo, 'cupo');
      expect(e.status, 429);
    });

    test('fin extrae los datos sin el campo tipo', () {
      final e = leerEvento('{"tipo":"fin","titulo":"T","nodos":5}') as EventoFin;
      expect(e.datos['titulo'], 'T');
      expect(e.datos['nodos'], 5);
      expect(e.datos.containsKey('tipo'), isFalse);
    });

    test('latido', () {
      expect(leerEvento('{"tipo":"latido"}'), isA<EventoLatido>());
    });

    test('json inválido, vacío, array o escalar devuelven null', () {
      expect(leerEvento(''), isNull);
      expect(leerEvento('   '), isNull);
      expect(leerEvento('no es json'), isNull);
      expect(leerEvento('[]'), isNull);
      expect(leerEvento('123'), isNull);
    });
  });

  group('aplicarEvento', () {
    test('acumula ramas y el reinicio borra solo su parte y tema', () {
      var lineas = <LineaProvisional>[];
      lineas = aplicarEvento(lineas, const EventoRama(parte: 0, d: 1, t: 'A'));
      lineas = aplicarEvento(lineas, const EventoRama(parte: 0, d: 2, t: 'B'));
      lineas = aplicarEvento(lineas, const EventoRama(parte: 1, d: 1, t: 'C'));
      expect(lineas.map((l) => l.t), ['A', 'B', 'C']);

      lineas = aplicarEvento(lineas, const EventoReinicio(parte: 0));
      expect(lineas.map((l) => l.t), ['C']);
    });
  });

  group('arbolProvisional', () {
    test('un nivel nunca salta más de uno y cuelga del último inferior', () {
      const lineas = [
        LineaProvisional(parte: 0, d: 1, t: 'Raíz'),
        LineaProvisional(parte: 0, d: 2, t: 'Hijo'),
        LineaProvisional(parte: 0, d: 3, t: 'Nieto'),
        LineaProvisional(parte: 0, d: 2, t: 'Hijo2'),
      ];
      final arbol = arbolProvisional(lineas);
      expect(arbol.length, 1);
      expect(arbol.first.t, 'Raíz');
      expect(arbol.first.hijos.map((n) => n.t), ['Hijo', 'Hijo2']);
      expect(arbol.first.hijos.first.hijos.single.t, 'Nieto');
    });
  });

  group('arbolLibro', () {
    test('agrupa por tema con su título', () {
      const lineas = [
        LineaProvisional(parte: 0, tema: 0, d: 1, t: 'T0-A'),
        LineaProvisional(parte: 1, tema: 1, d: 1, t: 'T1-A'),
      ];
      final arbol = arbolLibro(lineas, ['Tema Cero', 'Tema Uno']);
      expect(arbol.length, 2);
      expect(arbol[0].t, 'Tema Cero');
      expect(arbol[1].t, 'Tema Uno');
      expect(arbol[0].hijos.single.t, 'T0-A');
    });
  });
}
