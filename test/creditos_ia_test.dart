// Créditos de IA en la app: el precio (misma fórmula y mismos números que la web y el servidor),
// los caracteres como los cuenta el servidor, los textos y el cliente de /api/ia.
// Casos calcados de test/creditosIA.test.ts de la web.
import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mirdaily_app/core/models/creditos_ia.dart';
import 'package:mirdaily_app/core/models/ia.dart';
import 'package:mirdaily_app/core/services/creditos_ia_service.dart';
import 'package:mirdaily_app/core/services/ia_service.dart';
import 'package:mirdaily_app/core/services/ia_stream.dart';
import 'package:mirdaily_app/core/models/resumen.dart';
import 'package:mirdaily_app/core/models/resumen_ia.dart';
import 'package:mirdaily_app/features/resumenes/resumenes_ia.dart';

final tarifa = TarifaIa.fromJson({
  'version': 1,
  'cancelacionesGratisMes': 5,
  'cancelacionSinTextoSeg': 5,
  'claves': {
    'mapa:esquema': {'fijo': '2.300', 'por_mil': '0.1280', 'factores': {}},
    'mapa:esquema+tablas': {'fijo': 3.4, 'por_mil': 0.25, 'factores': {}},
    'mapa:detalle': {'fijo': 2.7, 'por_mil': 0.182, 'factores': {}},
    'mapa:detalle+tablas': {'fijo': 4.5, 'por_mil': 0.311, 'factores': {}},
    'flashcards:documento': {'fijo': 1.4, 'por_mil': 0.172, 'factores': {'pocas': 1, 'normal': 1, 'muchas': 1.45}},
    'flashcards:mapa': {'fijo': 1.8, 'por_mil': 0.164, 'factores': {'pocas': 1, 'normal': 1, 'muchas': 1.45}},
    'resumenes:resumen': {'fijo': 2.3, 'por_mil': 0.174, 'factores': {'pocas': 0.85, 'normal': 1, 'muchas': 1.1}},
    'resumenes:literal': {'fijo': 2.3, 'por_mil': 0.174, 'factores': {'pocas': 0.85, 'normal': 1, 'muchas': 1.1}},
    'rama': {'fijo': 5, 'por_mil': 0, 'factores': {}},
    'indice': {'fijo': 0, 'por_mil': 0, 'factores': {}},
  },
});

SaldoIa saldo({bool ilimitado = false, int restantes = 0, bool puedeUsar = true, int total = 500}) => SaldoIa.fromJson({
      'plan': 'mensual',
      'estado': 'activo',
      'periodo_fin': '2026-11-03T00:00:00Z',
      'ilimitado': ilimitado,
      'puede_usar': puedeUsar,
      'total': total,
      'bolsas': [
        {'id': 1, 'tipo': 'periodo', 'iniciales': 700, 'saldo': 100, 'caduca_at': '2026-11-03T00:00:00Z', 'congelada': false},
      ],
      'cancelaciones_gratis_mes': 5,
      'cancelaciones_gratis_restantes': restantes,
    });

void main() {
  test('precio: la misma fórmula que el servidor (tema grande de la especificación)', () {
    int? p(String clave, [String? densidad]) => precioIa(tarifa, clave: clave, caracteres: 84000, densidad: densidad);
    expect(p('mapa:esquema'), 14);
    expect(p('mapa:esquema+tablas'), 25);
    expect(p('mapa:detalle'), 18);
    expect(p('mapa:detalle+tablas'), 31);
    expect(p('flashcards:documento', 'normal'), 16);
    expect(p('flashcards:documento', 'muchas'), 23);
    expect(p('flashcards:mapa', 'pocas'), 16);
    expect(p(claveResumenes('literal'), 'pocas'), 15);
    expect(precioIa(tarifa, clave: 'mapa:esquema', caracteres: 421538, llamadas: 16), 91);
    expect(precioIa(tarifa, clave: 'rama', caracteres: 99999), 5);
    expect(precioIa(tarifa, clave: 'indice', caracteres: 99999), 0);
    expect(precioIa(tarifa, clave: 'inventada'), isNull);
    expect(precioIa(null, clave: 'mapa:esquema'), isNull);
    expect(claveResumenes('resumen'), 'resumenes:resumen');
  });

  test('caracteres: el saneado del servidor (espacios, saltos, invisibles) y secciones de menos de 10', () {
    expect(limpiarEntrada('  Hola​   mundo \r\n\r\n\r\n\r\nadiós  '), 'Hola mundo\n\nadiós');
    expect(limpiarEntrada('a\t\tb \n c'), 'a b\nc');
    expect(caracteresDocumento(const [Seccion(texto: 'corto'), Seccion(texto: '   '), Seccion(texto: 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx')]), 50);
    expect(caracteresDocumento(const [Seccion(texto: '0123456789')]), 10);
    expect(caracteresDocumento(const [Seccion(texto: '012345678')]), 0);
  });

  test('aviso antes de cancelar: solo sin cancelaciones gratis y pasados los segundos «sin texto»', () {
    final inicio = DateTime(2026, 10, 29, 12);
    final g = GeneracionIa(cobro: const CobroIa(creditosAnunciados: 20, tarifaVersion: 1, idempotencyKey: 'k'), inicio: inicio);
    expect(avisoAntesDeCancelar(g, saldo(), tarifa, ahora: inicio.add(const Duration(seconds: 6))), contains('como mucho 20 créditos'));
    expect(avisoAntesDeCancelar(g, saldo(), tarifa, ahora: inicio.add(const Duration(seconds: 4))), isNull);
    expect(avisoAntesDeCancelar(g, saldo(restantes: 2), tarifa, ahora: inicio.add(const Duration(hours: 1))), isNull);
    expect(avisoAntesDeCancelar(g, saldo(ilimitado: true), tarifa, ahora: inicio.add(const Duration(hours: 1))), isNull);
  });

  test('mensajes de cancelación, devolución y rechazo', () {
    final g = GeneracionIa()..cobrados = 14;
    PrevisionCancelacion prev(String p, int r) => PrevisionCancelacion(prevision: p, creditos: 14, cancelacionesGratisRestantes: r);
    expect(mensajeCancelacion(prev('gratis', 4), g), 'Cancelado. Te hemos devuelto 14 créditos · te quedan 4 cancelaciones gratis este mes.');
    expect(mensajeCancelacion(prev('gratis', 1), g), contains('te queda 1 cancelación gratis'));
    expect(mensajeCancelacion(prev('sin_texto', 5), g), contains('no cuenta como cancelación'));
    expect(mensajeCancelacion(prev('parcial', 0), g), contains('parte ya generada (como mucho 14 créditos)'));
    expect(mensajeCancelacion(null, g), 'Cancelado. Te hemos devuelto 14 créditos.');
    expect(mensajeDevolucion({'creditos': {'cobrados': 0, 'devueltos': 17, 'saldo': 300}}), ' No se ha cobrado nada.');
    expect(mensajeDevolucion({'creditos': {'cobrados': 9, 'devueltos': 11, 'saldo': 300}}), ' Te hemos devuelto 11 créditos.');
    expect(mensajeDevolucion(null), '');
    expect(mensajeRechazo('sin_creditos', {'necesarios': 25, 'saldo': 3}), contains('hacen falta 25 y tienes 3'));
    expect(mensajeRechazo('precio_cambiado', {'creditos': 12345}), contains('ahora son 12.345 créditos'));
    expect(mensajeRechazo('formato', {}), '');
    expect(
      mensajeErrorIa(const IaException('La IA falló', codigo: 'x', datos: {'creditos': {'cobrados': 0, 'devueltos': 5}}), 'por defecto'),
      'La IA falló. No se ha cobrado nada.',
    );
    expect(mensajeErrorIa(StateError('x'), 'por defecto'), 'por defecto');
  });

  test('saldo: la bolsa del mes y lo gastado; el historial en palabras', () {
    expect(saldo().bolsaDelMes?.saldo, 100);
    expect((saldo().fraccionGastada - 6 / 7).abs(), lessThan(1e-9));
    expect(SaldoIa.fromJson(const {'bolsas': []}).bolsaDelMes, isNull);
    MovimientoIa m(Map<String, dynamic> x) => MovimientoIa.fromJson({
          'id': 1, 'tipo': 'cargo', 'creditos': -14, 'creado_at': '', 'bolsa_tipo': 'periodo', 'motivo': null,
          'usage_id': 1, 'clave': 'mapa:esquema', 'kind': 'mapa', 'titulo': 'Vasculitis', ...x,
        });
    expect(describirMovimiento(m({})), 'Mapa · Vasculitis');
    expect(describirMovimiento(m({'tipo': 'devolucion', 'creditos': 17, 'motivo': 'error'})), 'Devuelto (error) · Vasculitis');
    expect(describirMovimiento(m({'tipo': 'alta', 'creditos': 700, 'titulo': null, 'clave': null, 'kind': null, 'motivo': 'renovacion'})), 'Renovación');
    expect(describirMovimiento(m({'tipo': 'caducidad', 'creditos': -120, 'titulo': null})), 'Caducados');
    expect(describirMovimiento(m({'clave': 'flashcards_mas', 'kind': 'flashcards_mas', 'titulo': null})), 'Más flashcards');
    expect(
      describirMovimiento(m({'tipo': 'alta', 'bolsa_tipo': 'ajuste', 'motivo': 'compensación', 'clave': null, 'kind': null, 'titulo': null})),
      'Regalo del equipo · compensación',
    );
  });

  test('la línea del precio: saldo, sin plan, sin saldo, sin límite y aviso del 80 %', () {
    expect(lineaPrecio(14, saldo()).texto, 'Usará 14 créditos · te quedan 500');
    expect(lineaPrecio(14, saldo()).aviso, isTrue); // 600 de 700 gastados
    expect(lineaPrecio(1, saldo(ilimitado: true)).texto, 'Usará 1 crédito · sin límite');
    expect(lineaPrecio(14, saldo(puedeUsar: false)).suficiente, isFalse);
    final corto = lineaPrecio(900, saldo(total: 1240));
    expect(corto.suficiente, isTrue);
    final sin = lineaPrecio(1300, saldo(total: 1240));
    expect(sin.suficiente, isFalse);
    expect(sin.texto, startsWith('Hacen falta 1.300 créditos y te quedan 1.240.'));
    expect(lineaPrecio(null, saldo()).suficiente, isFalse);
    expect(fmtCreditos(1234567), '1.234.567');
    expect(fmtCreditos(-14), '-14');
  });

  test('el evento «reserva» del streaming y el error con lo devuelto', () {
    final r = leerEvento(jsonEncode({'tipo': 'reserva', 'usageId': 812, 'creditos': {'cobrados': 14, 'saldo': 486}}));
    expect(r, isA<EventoReserva>());
    final g = GeneracionIa(cobro: const CobroIa(creditosAnunciados: 15, tarifaVersion: 1, idempotencyKey: 'k'))..anotar(r as EventoReserva);
    expect(g.usageId, 812);
    expect(g.cobrados, 14);
    expect(leerEvento(jsonEncode({'tipo': 'reserva'})), isNull);
    final e = leerEvento(jsonEncode({'tipo': 'error', 'error': 'Falló', 'status': 502, 'creditos': {'cobrados': 0, 'devueltos': 14}}));
    expect((e as EventoError).datos?['creditos'], {'cobrados': 0, 'devueltos': 14});
  });

  test('un rechazo del cobro llega con sus datos (402 sin créditos)', () async {
    final ia = IaService(
      token: () async => 'TOKEN',
      baseUrl: 'https://api.test',
      client: MockClient((req) async {
        final cuerpo = jsonDecode(req.body) as Map<String, dynamic>;
        expect(cuerpo['creditosAnunciados'], 14);
        expect(cuerpo['idempotencyKey'], 'k');
        return http.Response(
          jsonEncode({'error': 'No te quedan créditos', 'codigo': 'sin_creditos', 'necesarios': 14, 'saldo': 3}),
          402,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    try {
      await ia.post(IaArea.resumenes, cuerpo: const CobroIa(creditosAnunciados: 14, tarifaVersion: 1, idempotencyKey: 'k').toJson());
      fail('tenía que fallar');
    } on IaException catch (e) {
      expect(e.status, 402);
      expect(mensajeErrorIa(e, ''), 'No te quedan créditos suficientes: hacen falta 14 y tienes 3.');
    }
  });

  // Sin el cobro, con los créditos encendidos, el servidor contesta 409 `precio_cambiado`: es lo que le
  // pasaba a la app entre el 16/10/2026 y la tanda 1.
  test('generar resúmenes manda el cobro anunciado y la clave de idempotencia', () async {
    late Map<String, dynamic> cuerpo;
    final ia = ResumenesIa(IaService(
      token: () async => 'TOKEN',
      baseUrl: 'https://api.test',
      client: MockClient((req) async {
        cuerpo = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response(jsonEncode({'titulo': 'Lupus', 'parrafos': []}), 200, headers: {'content-type': 'application/json'});
      }),
    ));
    await ia.generar(
      titulo: 'Lupus',
      modo: ModoResumen.resumen,
      niveles: const [1, 2, 3, 4],
      densidad: Densidad.normal,
      secciones: const [Seccion(texto: 'El lupus es una enfermedad autoinmune sistémica.')],
      paginas: 1,
      cobro: const CobroIa(creditosAnunciados: 3, tarifaVersion: 1, idempotencyKey: 'clave'),
    );
    expect(cuerpo['creditosAnunciados'], 3);
    expect(cuerpo['tarifaVersion'], 1);
    expect(cuerpo['idempotencyKey'], 'clave');
    expect(cuerpo['densidad'], 'normal');
  });

  group('CreditosIa', () {
    CreditosIa almacen(MockClientHandler h) => CreditosIa(
          CreditosApi(token: () async => 'TOKEN', baseUrl: 'https://api.test', client: MockClient(h)),
          azar: Random(1),
        );

    test('con los créditos encendidos: saldo, tarifa y un cobro por generación', () async {
      final c = almacen((req) async {
        if (req.url.path == '/api/ia/tarifa') {
          return http.Response(jsonEncode({'version': 3, 'claves': {'rama': {'fijo': 5, 'por_mil': 0}}}), 200);
        }
        expect(req.url.path, '/api/ia/saldo');
        return http.Response(jsonEncode({'plan': 'mensual', 'puede_usar': true, 'total': 42, 'bolsas': []}), 200);
      });
      await c.refrescar();
      expect(c.activo, isTrue);
      expect(c.saldo!.total, 42);
      final g = c.nuevaGeneracion(5);
      expect(g.cobro!.creditosAnunciados, 5);
      expect(g.cobro!.tarifaVersion, 3);
      expect(g.cobro!.idempotencyKey, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
      expect(c.nuevaGeneracion(5).cobro!.idempotencyKey, isNot(g.cobro!.idempotencyKey));
    });

    test('con el interruptor apagado (503): sin cobro, como antes', () async {
      final c = almacen((req) async => http.Response(jsonEncode({'error': 'apagado', 'codigo': 'apagado'}), 503));
      await c.refrescar();
      expect(c.cargado, isTrue);
      expect(c.activo, isFalse);
      expect(c.nuevaGeneracion(5).cobro, isNull);
    });

    test('cancelar llama al servidor con el id de la reserva', () async {
      final c = almacen((req) async {
        expect(req.method, 'POST');
        expect(req.url.path, '/api/ia/cancelar/812');
        return http.Response(jsonEncode({'ok': true, 'prevision': 'gratis', 'creditos': 14, 'cancelacionesGratisRestantes': 4}), 200);
      });
      final p = await c.api.cancelar(812);
      expect(p.prevision, 'gratis');
      expect(p.cancelacionesGratisRestantes, 4);
    });

    test('el historial pagina por id', () async {
      final c = almacen((req) async {
        expect(req.url.queryParameters['antes'], '90');
        return http.Response(
          jsonEncode({
            'movimientos': [
              {'id': 89, 'tipo': 'cargo', 'creditos': -14, 'clave': 'resumenes:resumen', 'kind': 'resumenes', 'titulo': 'Lupus'},
            ],
            'siguiente': null,
          }),
          200,
        );
      });
      final r = await c.api.movimientos(antes: 90);
      expect(describirMovimiento(r.movimientos.single), 'Resumen activo · Lupus');
      expect(r.siguiente, isNull);
    });
  });
}
