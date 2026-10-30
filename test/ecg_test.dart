// Tanda 9: el motor del Explorador de 12 derivaciones.
//
//   flutter test test/ecg_test.dart
//
// test/fixtures/ecg_sintesis_web.json lo escribe tools/export_electros.mjs con el ecgCore.ts REAL de la
// web: si la web cambia el motor o un patrón, se vuelve a lanzar el script y estos tests dicen si la
// app sigue dibujando lo mismo.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:mirdaily_app/core/models/ecg_core.dart';
import 'package:mirdaily_app/core/models/ecg_patrones.dart';

PatronEcg _p(String id) => patronesEcg.firstWhere((p) => p.id == id);

void main() {
  final fixture = jsonDecode(File('test/fixtures/ecg_sintesis_web.json').readAsStringSync()) as Map<String, dynamic>;
  final web = fixture['sintesis'] as Map<String, dynamic>;
  final paso = fixture['paso'] as int;

  group('catálogo', () {
    test('los 33 patrones de la web, con ids únicos y en categorías conocidas', () {
      expect(patronesEcg, hasLength(33));
      expect(web.keys.toList(), [for (final p in patronesEcg) p.id]);
      expect({for (final p in patronesEcg) p.id}, hasLength(33));
      for (final p in patronesEcg) {
        expect(categoriasEcg, contains(p.categoria), reason: p.id);
        expect(p.busqueda.take(2), [p.nombre, p.sigla], reason: 'nombre y sigla abren los sinónimos');
        expect(p.claves, isNotEmpty, reason: p.id);
      }
    });

    test('todos los mods de los patrones existen en el motor', () {
      for (final p in patronesEcg) {
        for (final m in p.morfologia.mods) {
          expect(modsEcg.containsKey(m.split(':').first), isTrue, reason: '${p.id}: $m');
        }
      }
    });
  });

  group('síntesis igual que la web', () {
    for (final p in patronesEcg) {
      test(p.id, () {
        final s = sintetizar(p);
        final w = web[p.id] as Map<String, dynamic>;
        expect((s.fs, s.dur, s.fc), (w['fs'], w['dur'], w['hr']));
        final latidos = (w['beats'] as List).cast<num>();
        expect(s.latidos, hasLength(latidos.length));
        for (var i = 0; i < latidos.length; i++) {
          expect(s.latidos[i], closeTo(latidos[i], 1e-5), reason: 'latido $i');
        }
        final leads = w['leads'] as Map<String, dynamic>;
        expect(s.derivaciones.keys.toList(), ordenDerivaciones);
        for (final nombre in ordenDerivaciones) {
          final buf = s.derivaciones[nombre]!;
          final e = leads[nombre] as Map<String, dynamic>;
          final muestras = (e['muestras'] as List).cast<num>();
          for (var k = 0; k < muestras.length; k++) {
            expect(buf[k * paso], closeTo(muestras[k], 2e-5), reason: '$nombre muestra ${k * paso}');
          }
          var suma = 0.0;
          var min = double.infinity;
          var max = -double.infinity;
          for (final v in buf) {
            suma += v;
            min = math.min(min, v);
            max = math.max(max, v);
          }
          expect(suma, closeTo(e['suma'] as num, 1e-2), reason: '$nombre suma');
          expect(min, closeTo(e['min'] as num, 2e-5), reason: '$nombre mínimo');
          expect(max, closeTo(e['max'] as num, 2e-5), reason: '$nombre máximo');
        }
      });
    }
  });

  group('tabla de derivaciones', () {
    test('las de miembros salen del eje: con eje +60 la R más alta es la de II y aVR es negativa', () {
      final l = baseDerivaciones();
      expect(l['II']!.r, greaterThan(l['I']!.r));
      expect(l['II']!.r, greaterThan(l['III']!.r));
      expect(l['aVR']!.r, 0.06);
      expect(l['aVR']!.s, lessThan(-1));
    });

    test('`w.t || 0.2` de JS: una T a cero se trata como 0,2 en el BRD', () {
      final l = baseDerivaciones()..['V3']!.t = 0;
      aplicarMods(l, ['rbbb']);
      expect(l['V3']!.t, -0.2);
    });

    test('un mod desconocido no hace nada', () {
      final a = baseDerivaciones();
      final b = aplicarMods(baseDerivaciones(), ['inventado:x']);
      expect(b['V1']!.r, a['V1']!.r);
    });

    test('el SCACEST inferior sube el ST en II/III/aVF y lo baja en I/aVL', () {
      final l = aplicarMods(baseDerivaciones(), ['stemi:inferior']);
      for (final n in ['II', 'III', 'aVF']) {
        expect(l[n]!.j, 0.32);
      }
      for (final n in ['I', 'aVL']) {
        expect(l[n]!.j, -0.14);
      }
    });
  });

  group('monitor', () {
    test('el voltaje da la vuelta a la tira de 10 s', () {
      final s = sintetizar(_p('sinus'));
      final buf = s.derivaciones['II']!;
      expect(voltajeEn(buf, 0.55), buf[(0.55 * fsEcg).floor()]);
      expect(voltajeEn(buf, 10.55), voltajeEn(buf, 0.55));
      expect(voltajeEn(buf, -9.45), voltajeEn(buf, 0.55));
    });

    test('avisa de cada R al cruzarla, una sola vez, también al dar la vuelta', () {
      const latidos = [0.5, 3.0, 9.8];
      expect(latidoCruzado(latidos, 0.4, 0.6, null), 0);
      expect(latidoCruzado(latidos, 0.4, 0.6, 0), isNull, reason: 'no repite el último');
      expect(latidoCruzado(latidos, 1.0, 2.0, null), isNull);
      expect(latidoCruzado(latidos, 9.7, 10.2, null), 2, reason: 'la R de 9,8 s antes de la vuelta');
      expect(latidoCruzado(latidos, 19.95, 20.6, null), 0, reason: 'tras la vuelta, la de 0,5 s');
      expect(latidoCruzado(const [], 0, 1, null), isNull);
    });
  });

  group('modo examen', () {
    test('normaliza como la web', () {
      final n = (fixture['normalizar'] as Map<String, dynamic>).cast<String, String>();
      n.forEach((texto, esperado) => expect(normalizarRespuesta(texto), esperado, reason: texto));
    });

    test('el buscador encuentra por sigla y sinónimo, con la coincidencia exacta primero', () {
      expect(buscarPatrones('fa', patronesEcg).first.id, 'afib');
      expect(buscarPatrones('BRD', patronesEcg).first.id, 'rbbb');
      expect(buscarPatrones('wenckebach', patronesEcg).first.id, 'avb2_mobitz1');
      expect(buscarPatrones('Fibrilación', patronesEcg).map((p) => p.id), containsAll(['afib', 'vfib']));
      expect(buscarPatrones('   ', patronesEcg), isEmpty);
      expect(buscarPatrones('a', patronesEcg), hasLength(6), reason: 'como mucho 6');
      expect(buscarPatrones('xyzzy', patronesEcg), isEmpty);
    });

    test('escribir el nombre completo vale como elección', () {
      expect(patronPorNombreExacto('fibrilacion AURICULAR', patronesEcg)?.id, 'afib');
      expect(patronPorNombreExacto('fibrila', patronesEcg), isNull);
    });

    test('una tanda son 10 patrones distintos', () {
      final t = barajarExamen(patronesEcg, math.Random(3));
      expect(t, hasLength(largoExamenEcg));
      expect({for (final p in t) p.id}, hasLength(largoExamenEcg));
    });

    test('el mensaje final según los aciertos', () {
      expect(resultadoExamen(10).emoji, '🏆');
      expect(resultadoExamen(7).tono, GravedadEcg.normal);
      expect(resultadoExamen(4).tono, GravedadEcg.warn);
      expect(resultadoExamen(3).mensaje, startsWith('3 de 10.'));
    });
  });
}
