// Sugerencia de carpeta (lib/core/services/carpetas.dart) contra el catálogo REAL de producción del
// 16/10/2026, el mismo que usa la web en test/carpetasSugerir.test.ts: la app tiene que proponer lo
// mismo que la web para el mismo documento.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mirdaily_app/core/services/carpetas.dart';

void main() {
  final arbol = (jsonDecode(File('test/fixtures/catalogo-2026-10-16.json').readAsStringSync()) as List)
      .map(AsignaturaCatalogo.fromJson)
      .whereType<AsignaturaCatalogo>()
      .toList();
  Sugerencia sugerir(String titulo, [List<List<String>> listas = const []]) =>
      sugerirCarpeta(arbol, textosDocumento(titulo, listas));
  String nombre(String titulo, [List<List<String>> listas = const []]) => nombreCarpeta(arbol, sugerir(titulo, listas).carpeta);

  group('sugerirCarpeta', () {
    test('un título que es un tema va a ese tema, con confianza alta', () {
      expect(nombre('Tema 06 Lupus eritematoso sistemico'), 'Reumatología › Lupus eritematoso sistémico');
      expect(sugerir('Tema 06 Lupus eritematoso sistemico').confianza, 'alta');
      expect(nombre('Tema 09 Esclerosis sistemica'), 'Reumatología › Esclerosis sistémica');
      expect(nombre('Insuficiencia cardiaca (ejemplo)'), 'Cardiología y Cirugía Cardiovascular › Insuficiencia cardiaca');
    });

    test('aguanta variantes de nombre (plurales, sin tildes, palabras de más)', () {
      expect(nombre('Artritis microcristalinas'), 'Reumatología › Artritis por microcristales');
      expect(nombre('Enfermedad metabólica osea'), 'Reumatología › Enfermedades metabólicas óseas');
      expect(nombre('apuntes asma bronquial'), 'Neumología y Cirugía Torácica › Asma');
    });

    test('un título sin sentido va a «Sin clasificar»', () {
      for (final t in ['JIJI', 'caca', 'acaca', 'Mis apuntes']) {
        expect(sugerir(t).carpeta, Carpeta.sinClasificar, reason: t);
        expect(sugerir(t).confianza, 'baja', reason: t);
      }
    });

    test('un documento de toda una asignatura va a su «General»', () {
      final s = sugerir('Reumatología - repaso completo', [
        ['Lupus eritematoso sistémico', 'Vasculitis', 'Artrosis', 'Síndrome de Sjögren', 'Artritis reumatoide'],
      ]);
      expect(nombreCarpeta(arbol, s.carpeta), 'Reumatología › General');
      expect(s.confianza, 'media');
      expect(s.candidatas, isNotEmpty);
      expect(s.candidatas.every((c) => c.subjectId == 3080), isTrue);
    });

    test('las etiquetas deciden cuando el título no dice nada', () {
      final s = sugerir('JIJI', [
        ['Nefritis lúpica', 'Lupus eritematoso sistémico', 'Lupus eritematoso sistémico', 'Anticuerpos antinucleares'],
      ]);
      expect(nombreCarpeta(arbol, s.carpeta), 'Reumatología › Lupus eritematoso sistémico');
    });

    test('Mosaico por su nombre corto', () {
      expect(nombre('Mosaico: repaso'), 'Mosaico › General');
      expect(nombre('Geriatría'), 'Mosaico › Geriatría');
    });

    test('una etiqueta suelta entre muchas sin sentido no decide', () {
      final ruido = [for (var i = 0; i < 49; i++) 'Tarjeta $i jiji'];
      final s = sugerirCarpeta(arbol, textosDocumento('JIJI', [[...ruido, 'Asma']]));
      expect(s.carpeta, Carpeta.sinClasificar);
    });
  });

  group('nombreCarpeta y parecido', () {
    test('nombre largo y corto', () {
      expect(nombreCarpeta(arbol, const Carpeta(subjectId: 4), corto: true), 'Traumatología › General');
      expect(nombreCarpeta(arbol, Carpeta.sinClasificar), 'Sin clasificar');
    });

    test('parecido simétrico en lo básico', () {
      expect(parecidoCarpeta('Valvulopatías', 'valvulopatias'), 1);
      expect(parecidoCarpeta('Asma', 'Insuficiencia cardiaca'), lessThan(0.2));
    });
  });

  group('CarpetasApi', () {
    test('el árbol se pide una vez y se guarda', () async {
      var pedidos = 0;
      final api = CarpetasApi(
        token: () async => 'TOKEN',
        baseUrl: 'https://api.test',
        client: MockClient((req) async {
          pedidos++;
          expect(req.url.toString(), 'https://api.test/api/carpetas/arbol');
          return http.Response(
            jsonEncode({
              'asignaturas': [
                {'id': 1, 'nombre': 'Reumatología', 'nombreCorto': 'Reuma', 'temas': [{'id': 9, 'nombre': 'Lupus'}]},
                {'nombre': 'sin id'},
              ],
            }),
            200,
          );
        }),
      );
      final a = await api.arbol();
      await api.arbol();
      expect(pedidos, 1);
      expect(a.single.temas.single.nombre, 'Lupus');
    });

    test('mover manda tipo, ids, carpeta y origen', () async {
      late Map<String, dynamic> cuerpo;
      final api = CarpetasApi(
        token: () async => 'TOKEN',
        baseUrl: 'https://api.test',
        client: MockClient((req) async {
          expect(req.method, 'PATCH');
          expect(req.url.toString(), 'https://api.test/api/carpetas');
          cuerpo = jsonDecode(req.body) as Map<String, dynamic>;
          return http.Response(jsonEncode({'movidos': 1}), 200);
        }),
      );
      final n = await api.mover('resumenes', ['g1'], const Carpeta(subjectId: 3080), origen: 'sugerencia');
      expect(n, 1);
      expect(cuerpo, {'tipo': 'resumenes', 'ids': ['g1'], 'subjectId': 3080, 'topicId': null, 'origen': 'sugerencia'});
    });
  });
}
