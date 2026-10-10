import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:mirdaily_app/core/models/resumen.dart';
import 'package:mirdaily_app/features/resumenes/resumenes_api.dart';

ResumenesApi apiCon(http.Client client) =>
    ResumenesApi(token: () async => 'TOKEN', baseUrl: 'https://api.test', client: client);

void main() {
  group('sanearGrupo', () {
    test('devuelve null si falta id o nombre', () {
      expect(sanearGrupo({'id': 'x'}), isNull);
      expect(sanearGrupo({'name': 'x'}), isNull);
    });

    test('sanea las cuentas y recorta el nombre', () {
      final g = sanearGrupo({
        'id': 'a',
        'name': 'Un nombre muy largo'.padRight(90, 'x'),
        'color': '#fff',
        'total': 5,
        'pendientes': 2,
        'resumen': {'new': 1, 'failed': 2, 'learning': 1, 'mastered': 1},
      });
      expect(g, isNotNull);
      expect(g!.total, 5);
      expect(g.resumen.failed, 2);
      expect(g.name.length, 80);
    });
  });

  group('sanearParrafo', () {
    test('sanea huecos, modo, origen y estado', () {
      final p = sanearParrafo({
        'itemId': 7,
        'id': 'pid',
        'tema': 'Anemia',
        'modo': 'literal',
        'texto': 'La anemia ferropénica es frecuente',
        'huecos': [
          {'i': 3, 'f': 9, 'n': 2},
          {'i': -5, 'f': 3, 'n': 1}, // inválido: se descarta
        ],
        'aiGenerated': true,
        'origen': {'name': 'doc.pdf', 'page': 3, 'unit': 'pagina'},
        'status': 'learning',
        'fallos': 2,
      });
      expect(p, isNotNull);
      expect(p!.modo, ModoResumen.literal);
      expect(p.huecos.length, 1);
      expect(p.huecos.single.n, 2);
      expect(p.origen!.name, 'doc.pdf');
      expect(p.status, EstadoParrafoSrs.learning);
      expect(p.fallos, 2);
    });
  });

  group('listarGrupos / cargarGrupo', () {
    test('parsea los grupos', () async {
      final client = MockClient((req) async {
        expect(req.url.toString(), 'https://api.test/api/resumenes');
        return http.Response(jsonEncode({
          'grupos': [
            {'id': 'g1', 'name': 'Cardio', 'total': 3, 'pendientes': 1, 'resumen': {'new': 3, 'failed': 0, 'learning': 0, 'mastered': 0}},
          ],
        }), 200);
      });
      final grupos = await apiCon(client).listarGrupos();
      expect(grupos.single.name, 'Cardio');
    });

    test('carga grupo y párrafos', () async {
      final client = MockClient((req) async {
        expect(req.url.path, '/api/resumenes/g1');
        return http.Response(jsonEncode({
          'grupo': {'id': 'g1', 'name': 'Cardio'},
          'parrafos': [
            {'itemId': 1, 'id': 'p1', 'texto': 'La anemia ferropénica es frecuente', 'huecos': [], 'aiGenerated': false},
          ],
          'max': 300,
        }), 200);
      });
      final r = await apiCon(client).cargarGrupo('g1');
      expect(r.grupo.name, 'Cardio');
      expect(r.parrafos.length, 1);
      expect(r.max, 300);
    });
  });

  group('errores', () {
    test('lleva caben y limite cuando el grupo se llena', () async {
      final client = MockClient((req) async => http.Response(
          jsonEncode({'error': 'El grupo superaría el máximo', 'limite': true, 'caben': 4}), 400));
      await expectLater(
        apiCon(client).anadirParrafos('g1', [ParrafoNuevo(texto: 'x' * 30, huecos: const [])]),
        throwsA(isA<ResumenesApiError>()
            .having((e) => e.limite, 'limite', true)
            .having((e) => e.caben, 'caben', 4)),
      );
    });
  });

  group('siguiente', () {
    test('devuelve fin cuando no hay más', () async {
      final client = MockClient((req) async => http.Response(jsonEncode({'done': true}), 200));
      final s = await apiCon(client).siguiente('g1', 'ses');
      expect(s.tipo, SiguienteTipoResumen.fin);
    });

    test('devuelve el párrafo cuando lo hay', () async {
      final client = MockClient((req) async => http.Response(jsonEncode({
            'parrafo': {'itemId': 1, 'id': 'p1', 'texto': 'La anemia ferropénica es frecuente', 'huecos': [], 'aiGenerated': false},
          }), 200));
      final s = await apiCon(client).siguiente('g1', 'ses');
      expect(s.tipo, SiguienteTipoResumen.parrafo);
      expect(s.parrafo!.id, 'p1');
    });
  });

  group('empezarSesion', () {
    test('omite levels si es vacío o 4+', () async {
      late Map<String, dynamic> enviado;
      final client = MockClient((req) async {
        enviado = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response(jsonEncode({'sessionId': 'ses'}), 200);
      });
      final sid = await apiCon(client).empezarSesion('g1', const AjustesEstudio(levels: [1, 2, 3, 4]));
      expect(sid, 'ses');
      expect(enviado.containsKey('levels'), isFalse);
    });
  });
}
