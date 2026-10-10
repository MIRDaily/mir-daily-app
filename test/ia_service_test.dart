import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mirdaily_app/core/models/ia.dart';
import 'package:mirdaily_app/core/services/ia_service.dart';

IaService servicioCon(http.Client client) =>
    IaService(token: () async => 'TOKEN', baseUrl: 'https://api.test', client: client);

void main() {
  group('estado', () {
    test('devuelve null cuando la función no está disponible', () async {
      final client = MockClient((req) async {
        expect(req.method, 'GET');
        expect(req.url.toString(), 'https://api.test/api/admin/mapas-ia/estado');
        expect(req.headers['Authorization'], 'Bearer TOKEN');
        return http.Response(jsonEncode({'disponible': false}), 200);
      });
      expect(await servicioCon(client).estado(IaArea.mapas), isNull);
    });

    test('devuelve el cuerpo cuando está disponible', () async {
      final client = MockClient(
        (req) async => http.Response(jsonEncode({'disponible': true, 'modos': ['esquema']}), 200),
      );
      final e = await servicioCon(client).estado(IaArea.mapas);
      expect(e!['disponible'], true);
    });

    test('devuelve null ante un error del servidor', () async {
      final client = MockClient((req) async => http.Response('boom', 500));
      expect(await servicioCon(client).estado(IaArea.mapas), isNull);
    });
  });

  group('indice', () {
    test('manda el principio de cada sección y sanea los temas', () async {
      late Map<String, dynamic> enviado;
      final client = MockClient((req) async {
        expect(req.url.toString(), 'https://api.test/api/admin/resumenes-ia/indice');
        enviado = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'temas': [
              {'titulo': 'Tema Uno', 'desde': 0, 'hasta': 1, 'chars': 500},
              {'titulo': 'Solapado', 'desde': 0, 'hasta': 1},
            ],
          }),
          200,
        );
      });
      final temas = await servicioCon(client).indice(
        IaArea.resumenes,
        titulo: 'Doc',
        secciones: const [Seccion(titulo: 'A', texto: 'xxxx'), Seccion(texto: 'y')],
      );
      expect(enviado['titulo'], 'Doc');
      final primera = (enviado['secciones'] as List).first as Map;
      expect(primera['inicio'], 'A\nxxxx'); // título + texto al principio
      expect(temas.length, 1); // el solapado se descarta
      expect(temas.single.titulo, 'Tema Uno');
    });
  });

  group('post', () {
    test('respuesta JSON normal', () async {
      final client = MockClient((req) async {
        expect(req.method, 'POST');
        expect(req.headers['Content-Type'], startsWith('application/json'));
        return http.Response(jsonEncode({'titulo': 'T', 'nodos': 3}), 200);
      });
      final datos = await servicioCon(client).post(IaArea.mapas, cuerpo: {'titulo': 'T'});
      expect(datos['nodos'], 3);
    });

    test('streaming NDJSON: emite eventos y devuelve los datos de "fin"', () async {
      final client = MockClient.streaming((req, _) async {
        final cuerpo = [
          '{"tipo":"fase","fase":"leyendo"}',
          '{"tipo":"rama","parte":0,"d":1,"t":"Raíz"}',
          '{"tipo":"fin","titulo":"T","nodos":2}',
          '',
        ].join('\n');
        return http.StreamedResponse(
          Stream.value(utf8.encode(cuerpo)),
          200,
          headers: {'content-type': 'application/x-ndjson'},
        );
      });
      final eventos = <EventoIa>[];
      final datos = await servicioCon(client).post(
        IaArea.mapas,
        cuerpo: {'titulo': 'T'},
        onEvento: eventos.add,
      );
      expect(eventos.whereType<EventoFase>().single.fase, FaseIa.leyendo);
      expect(eventos.whereType<EventoRama>().single.t, 'Raíz');
      expect(datos['nodos'], 2);
    });

    test('streaming con evento de error lanza IaException con su código', () async {
      final client = MockClient.streaming((req, _) async {
        const cuerpo = '{"tipo":"error","error":"Cupo agotado","codigo":"cupo","status":429}\n';
        return http.StreamedResponse(
          Stream.value(utf8.encode(cuerpo)),
          200,
          headers: {'content-type': 'application/x-ndjson'},
        );
      });
      await expectLater(
        servicioCon(client).post(IaArea.mapas, cuerpo: const {}, onEvento: (_) {}),
        throwsA(isA<IaException>()
            .having((e) => e.codigo, 'codigo', 'cupo')
            .having((e) => e.status, 'status', 429)),
      );
    });

    test('error HTTP con cuerpo JSON lanza IaException con el mensaje del servidor', () async {
      final client = MockClient(
        (req) async => http.Response(jsonEncode({'error': 'No eres admin', 'codigo': 'no_admin'}), 403),
      );
      await expectLater(
        servicioCon(client).post(IaArea.mapas, cuerpo: const {}),
        throwsA(isA<IaException>()
            .having((e) => e.message, 'message', 'No eres admin')
            .having((e) => e.codigo, 'codigo', 'no_admin')),
      );
    });

    test('streaming que se corta sin "fin" lanza IaException', () async {
      final client = MockClient.streaming((req, _) async {
        return http.StreamedResponse(
          Stream.value(utf8.encode('{"tipo":"fase","fase":"leyendo"}\n')),
          200,
          headers: {'content-type': 'application/x-ndjson'},
        );
      });
      await expectLater(
        servicioCon(client).post(IaArea.mapas, cuerpo: const {}, onEvento: (_) {}),
        throwsA(isA<IaException>()),
      );
    });
  });
}
