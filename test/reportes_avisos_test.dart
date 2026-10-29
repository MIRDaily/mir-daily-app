// Tanda 4: reportar pregunta (POST /api/reports, GET /api/reports/mine) y bandeja de avisos
// (/api/notifications). La lógica copia las reglas de src/utils/reportes.js del backend (casos de
// test/reportes.test.js) y de src/service/api/notifications.js de la web.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mirdaily_app/core/models/avisos.dart';
import 'package:mirdaily_app/core/models/reportes.dart';
import 'package:mirdaily_app/core/services/avisos_service.dart';
import 'package:mirdaily_app/core/services/reportes_api.dart';
import 'package:mirdaily_app/features/profile/screens/avisos_screen.dart';
import 'package:mirdaily_app/shared/report/report_button.dart';
import 'package:provider/provider.dart';

const _antes = ContextoReporte(origin: OrigenReporte.daily, answered: false);
const _despues = ContextoReporte(origin: OrigenReporte.dailyReview, answered: true, userAnswer: 2, isCorrect: false);

final _tamanos = [('móvil', const Size(360, 780)), ('tablet', const Size(1024, 768))];

void _tam(WidgetTester tester, Size s) {
  tester.view.physicalSize = s;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  setUp(Reportadas.instancia.olvidar);

  group('reportes · lógica', () {
    test('las categorías son las del backend y del CHECK de content_reports', () {
      expect(categoriasPregunta.map((c) => c.key), [
        'respuesta_erronea', 'explicacion', 'errata', 'imagen', 'desactualizada', 'duplicada', 'otro',
      ]);
      expect(subcategoriasImagen.map((s) => s.key), ['no_carga', 'no_corresponde', 'no_se_ve']);
      expect(OrigenReporte.values.map((o) => o.valor),
          ['daily', 'daily_review', 'simulacro', 'simulacro_review', 'deck', 'versus']);
    });

    test('antes de responder se ocultan respuesta y explicación', () {
      expect(categoriasVisibles(answered: false).map((c) => c.key),
          ['errata', 'imagen', 'desactualizada', 'duplicada', 'otro']);
      expect(categoriasVisibles(answered: true).length, 7);
    });

    test('"otro" exige texto; el resto no', () {
      expect(puedeEnviarReporte(categoria: 'otro', mensaje: ''), isFalse);
      expect(puedeEnviarReporte(categoria: 'otro', mensaje: '   '), isFalse);
      expect(puedeEnviarReporte(categoria: 'otro', mensaje: 'Falta una opción'), isTrue);
      expect(puedeEnviarReporte(categoria: 'errata', mensaje: ''), isTrue);
      expect(puedeEnviarReporte(categoria: null, mensaje: 'algo'), isFalse);
      expect(puedeEnviarReporte(categoria: 'errata', mensaje: '', enviando: true), isFalse);
    });

    test('el cuerpo: clave, plataforma app, sugerida solo en respuesta errónea, subcategoría solo en imagen', () {
      final b = cuerpoReporte(questionId: 4265, contexto: _antes, categoria: 'errata', sugerida: 3, subcategoria: 'no_carga');
      expect(claveContenido(4265), 'q:4265');
      expect(b['contentType'], 'question');
      expect(b['questionId'], 4265);
      expect(b['platform'], 'app');
      expect(b['origin'], 'daily');
      expect(b['suggestedAnswer'], isNull);
      expect(b['subcategory'], isNull);
      expect(cuerpoReporte(questionId: 1, contexto: _despues, categoria: 'respuesta_erronea', sugerida: 3)['suggestedAnswer'], 3);
      expect(cuerpoReporte(questionId: 1, contexto: _antes, categoria: 'imagen', subcategoria: 'no_carga')['subcategory'], 'no_carga');
    });

    test('lo que respondió solo cuenta si ya había respondido', () {
      const raro = ContextoReporte(origin: OrigenReporte.daily, answered: false, userAnswer: 2, isCorrect: false);
      final antes = cuerpoReporte(questionId: 1, contexto: raro, categoria: 'errata');
      expect(antes['answered'], false);
      expect(antes['userAnswer'], isNull);
      expect(antes['isCorrect'], isNull);
      final despues = cuerpoReporte(questionId: 1, contexto: _despues, categoria: 'errata');
      expect(despues['userAnswer'], 2);
      expect(despues['isCorrect'], false);
    });

    test('opción de la app (0-based, -1 en blanco) → la 1-based del servidor', () {
      expect(respuestaUnoBased(0), 1);
      expect(respuestaUnoBased(3), 4);
      expect(respuestaUnoBased(-1), isNull);
      expect(respuestaUnoBased(null), isNull);
    });

    test('«Ya lo reportaste» con las etiquetas en minúscula', () {
      expect(textoYaReportado(const [MiReporte(category: 'errata'), MiReporte(category: 'duplicada')]),
          'Ya lo reportaste (errata en enunciado u opciones, duplicada). Puedes corregir tu reporte o añadir otro tipo.');
    });
  });

  group('avisos · lógica', () {
    final ahora = DateTime(2026, 10, 29, 18);

    test('la hora como la web', () {
      expect(horaAviso(null), '');
      expect(horaAviso(ahora.subtract(const Duration(minutes: 20)), ahora: ahora), 'Hace unos minutos');
      expect(horaAviso(ahora.subtract(const Duration(hours: 3, minutes: 10)), ahora: ahora), 'Hace 3 h');
      expect(horaAviso(DateTime(2026, 10, 28, 9), ahora: DateTime(2026, 10, 29, 10)), 'Ayer');
      expect(horaAviso(DateTime(2026, 10, 2, 9), ahora: ahora), '02/10/2026');
    });

    test('el icono: por tipo, por daily, el del servidor o la campana', () {
      Aviso a({String type = '', String icon = '', String kind = '', String title = ''}) =>
          Aviso(id: '1', title: title, body: '', type: type, icon: icon, kind: kind, unread: true);
      expect(iconoAviso(a(type: 'daily_available')), 'mail');
      expect(iconoAviso(a(type: 'daily_expiring', kind: 'study')), 'hourglass_bottom');
      expect(iconoAviso(a(kind: 'study')), 'mail');
      expect(iconoAviso(a(icon: 'fact_check', kind: 'system')), 'fact_check');
      expect(iconoAviso(a(icon: '<script>')), 'notifications');
      expect(iconoAviso(a()), 'notifications');
    });

    test('adónde lleva: /dashboard es el daily; el resto, a ninguna parte', () {
      expect(destinoAviso('/dashboard'), DestinoAviso.daily);
      expect(destinoAviso('/dashboard?from=noti'), DestinoAviso.daily);
      expect(destinoAviso('/studio'), isNull);
      expect(destinoAviso(null), isNull);
    });

    test('el globo', () {
      expect(textoGlobo(0), isNull);
      expect(textoGlobo(3), '3');
      expect(textoGlobo(12), '9+');
    });

    test('Aviso.fromJson lee lo que manda el servidor', () {
      final a = Aviso.fromJson({
        'id': 77, 'title': 'Hemos revisado tu reporte', 'body': 'Gracias', 'kind': 'system', 'type': 'report_resolved',
        'icon': 'fact_check', 'actionUrl': null, 'unread': true, 'createdAt': '2026-10-29T10:00:00Z',
        'metricValue': 12, 'metricUnit': 'preguntas',
      });
      expect(a.id, '77');
      expect(a.unread, isTrue);
      expect(a.actionUrl, isNull);
      expect(a.metrica, '12 preguntas');
      expect(a.leido().unread, isFalse);
    });
  });

  group('ReportesApi', () {
    test('manda el reporte con su token, marca la pregunta y devuelve si actualizó', () async {
      late http.Request enviada;
      final api = ReportesApi(
        token: () async => 'TOKEN',
        baseUrl: 'https://api.test',
        client: MockClient((req) async {
          enviada = req;
          return http.Response(jsonEncode({'ok': true, 'reportId': 5, 'updated': true}), 200);
        }),
      );
      final actualizado = await api.enviar(questionId: 4265, contexto: _despues, categoria: 'errata', mensaje: '  pone «hipo» ');
      expect(actualizado, isTrue);
      expect(enviada.method, 'POST');
      expect(enviada.url.toString(), 'https://api.test/api/reports');
      expect(enviada.headers['Authorization'], 'Bearer TOKEN');
      final b = jsonDecode(enviada.body) as Map<String, dynamic>;
      expect(b['message'], 'pone «hipo»');
      expect(b['platform'], 'app');
      expect(Reportadas.instancia.contiene('q:4265'), isTrue);
    });

    test('el 429 del límite diario llega con el mensaje del servidor y no marca nada', () async {
      final api = ReportesApi(
        token: () async => 'TOKEN',
        baseUrl: 'https://api.test',
        client: MockClient((_) async => http.Response(
            jsonEncode({'error': 'Has llegado al límite de reportes de hoy. ¡Gracias por tanta ayuda! Vuelve mañana.'}), 429)),
      );
      await expectLater(
        api.enviar(questionId: 9, contexto: _antes, categoria: 'errata'),
        throwsA(isA<ReporteException>()
            .having((e) => e.status, 'status', 429)
            .having((e) => e.message, 'message', contains('límite de reportes'))),
      );
      expect(Reportadas.instancia.contiene('q:9'), isFalse);
    });

    test('mis reportes de la pregunta por contentKey', () async {
      late Uri pedida;
      final api = ReportesApi(
        token: () async => 'TOKEN',
        baseUrl: 'https://api.test',
        client: MockClient((req) async {
          pedida = req.url;
          return http.Response(jsonEncode({
            'reports': [
              {'category': 'imagen', 'subcategory': 'no_carga', 'suggested_answer': null, 'message': 'Sale en blanco', 'updated_at': 'x'},
            ],
          }), 200);
        }),
      );
      final r = await api.mios(4265);
      expect(pedida.path, '/api/reports/mine');
      expect(pedida.queryParameters['contentKey'], 'q:4265');
      expect(r.single.category, 'imagen');
      expect(r.single.subcategory, 'no_carga');
      expect(r.single.message, 'Sale en blanco');
    });

    test('sin sesión no sale ninguna petición', () async {
      var llamadas = 0;
      final api = ReportesApi(
        token: () async => '',
        baseUrl: 'https://api.test',
        client: MockClient((_) async {
          llamadas++;
          return http.Response('{}', 200);
        }),
      );
      await expectLater(api.enviar(questionId: 1, contexto: _antes, categoria: 'errata'), throwsA(isA<ReporteException>()));
      expect(llamadas, 0);
    });
  });

  group('AvisosApi y contador', () {
    test('lista, contador y marcar leídas, con las rutas y el filtro de la web', () async {
      final pedidas = <String>[];
      final api = AvisosApi(
        token: () async => 'TOKEN',
        baseUrl: 'https://api.test',
        client: MockClient((req) async {
          pedidas.add('${req.method} ${req.url.path}${req.url.hasQuery ? '?${req.url.query}' : ''} ${req.body}');
          if (req.url.path == '/api/notifications') {
            return http.Response(jsonEncode({
              'items': [
                {'id': 'a1', 'title': 'Tu daily ya está', 'body': 'x', 'kind': 'study', 'type': 'daily_available', 'actionUrl': '/dashboard', 'unread': true},
              ],
              'unreadCount': 4,
              'nextCursor': null,
            }), 200);
          }
          if (req.url.path.endsWith('/unread-count')) return http.Response(jsonEncode({'unreadCount': 4}), 200);
          return http.Response(jsonEncode({'ok': true}), 200);
        }),
      );
      final l = await api.lista(filtro: FiltroAvisos.noLeidos);
      expect(l.avisos.single.actionUrl, '/dashboard');
      expect(l.noLeidas, 4);
      expect(await api.noLeidas(), 4);
      await api.marcarLeido('a1');
      await api.marcarTodos();
      expect(pedidas, [
        'GET /api/notifications?filter=unread&limit=20 ',
        'GET /api/notifications/unread-count ',
        'POST /api/notifications/a1/read {}',
        'POST /api/notifications/read-all {"filter":"all"}',
      ]);
    });

    test('el contador es por cuenta: se pide al entrar y vuelve a cero al salir', () async {
      var n = 3;
      final avisos = Avisos(AvisosApi(
        token: () async => 'TOKEN',
        baseUrl: 'https://api.test',
        client: MockClient((_) async => http.Response(jsonEncode({'unreadCount': n}), 200)),
      ));
      avisos.setUsuario('u1');
      await Future<void>.delayed(Duration.zero);
      await avisos.refrescar();
      expect(avisos.noLeidas, 3);
      avisos.restarUno();
      expect(avisos.noLeidas, 2);
      n = 0;
      avisos.setUsuario(null);
      expect(avisos.noLeidas, 0);
      await avisos.refrescar(); // sin sesión no pregunta
      expect(avisos.noLeidas, 0);
    });
  });

  group('ventana de reporte', () {
    ReportesApi apiCon(List<http.Request> envios, {List<Map<String, dynamic>> mios = const []}) => ReportesApi(
          token: () async => 'TOKEN',
          baseUrl: 'https://api.test',
          client: MockClient((req) async {
            if (req.url.path.endsWith('/mine')) return http.Response(jsonEncode({'reports': mios}), 200);
            envios.add(req);
            return http.Response(jsonEncode({'ok': true, 'reportId': 1, 'updated': mios.isNotEmpty}), 200);
          }),
        );

    Widget app(ReportesApi api, ContextoReporte contexto) => Provider<ReportesApi>.value(
          value: api,
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: ReportButton(questionId: 4265, contexto: contexto, optionCount: 4, subtitle: 'MIR 2024'),
              ),
            ),
          ),
        );

    for (final (nombre, tam) in _tamanos) {
      testWidgets('en $nombre: antes de responder, errata con texto, enviar y bandera rellena', (tester) async {
        _tam(tester, tam);
        final envios = <http.Request>[];
        await tester.pumpWidget(app(apiCon(envios), _antes));
        expect(find.byIcon(Icons.report_outlined), findsOneWidget);

        await tester.tap(find.byType(ReportButton));
        await tester.pumpAndSettle();
        expect(find.text('Reportar pregunta'), findsOneWidget);
        expect(find.text('MIR 2024'), findsOneWidget);
        expect(find.text('Respuesta correcta errónea'), findsNothing);
        expect(find.text('Responde primero si lo que falla es la respuesta o la explicación.'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.tap(find.text('Errata en enunciado u opciones'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Pone «hipo» y es «hiper»');
        await tester.tap(find.text('Enviar'));
        await tester.pumpAndSettle();

        expect(find.text('¡Gracias por avisar!'), findsOneWidget);
        final b = jsonDecode(envios.single.body) as Map<String, dynamic>;
        expect(b['category'], 'errata');
        expect(b['message'], 'Pone «hipo» y es «hiper»');
        expect(b['origin'], 'daily');
        expect(b['answered'], false);
        expect(tester.takeException(), isNull);

        await tester.pump(const Duration(milliseconds: 2700));
        await tester.pumpAndSettle();
        expect(find.text('¡Gracias por avisar!'), findsNothing);
        expect(find.byIcon(Icons.report_rounded), findsOneWidget);
      });

      testWidgets('en $nombre: ya respondida, precarga lo tuyo y «Actualizar»; «otro» sin texto no envía',
          (tester) async {
        _tam(tester, tam);
        final envios = <http.Request>[];
        await tester.pumpWidget(app(
          apiCon(envios, mios: [
            {'category': 'respuesta_erronea', 'subcategory': null, 'suggested_answer': 3, 'message': 'Según la guía ESC 2024', 'updated_at': 'x'},
          ]),
          _despues,
        ));
        await tester.tap(find.byType(ReportButton));
        await tester.pumpAndSettle();

        expect(find.textContaining('Ya lo reportaste (respuesta correcta errónea)'), findsOneWidget);
        expect(find.text('Según la guía ESC 2024'), findsOneWidget);
        expect(find.text('Actualizar'), findsOneWidget);
        expect(find.text('E'), findsNothing); // 4 opciones: A-D
        expect(tester.takeException(), isNull);

        await tester.tap(find.text('Otro'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Enviar'));
        await tester.pumpAndSettle();
        expect(envios, isEmpty);

        await tester.tap(find.text('Respuesta correcta errónea'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Actualizar'));
        await tester.pumpAndSettle();
        final b = jsonDecode(envios.single.body) as Map<String, dynamic>;
        expect(b['suggestedAnswer'], 3);
        expect(b['userAnswer'], 2);
        expect(find.text('Reporte actualizado'), findsOneWidget);
        await tester.pump(const Duration(seconds: 3));
        await tester.pumpAndSettle();
      });
    }

    testWidgets('sin id de pregunta no hay botón', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: ReportButton(questionId: null, contexto: _antes)));
      expect(find.byType(IconButton), findsNothing);
    });
  });

  group('bandeja de avisos', () {
    Avisos almacen(List<String> pedidas) {
      var leidos = <String>{};
      List<Map<String, dynamic>> items() => [
            {'id': 'a1', 'title': 'Tu daily de hoy ya está listo', 'body': 'Diez preguntas te esperan.', 'kind': 'study', 'type': 'daily_available', 'actionUrl': '/dashboard', 'unread': !leidos.contains('a1'), 'createdAt': DateTime.now().toUtc().toIso8601String()},
            {'id': 'a2', 'title': 'Hemos revisado tu reporte', 'body': 'Tras revisarla, la pregunta 45 del MIR 2019 es correcta tal y como está. Gracias por avisar.', 'kind': 'system', 'type': 'report_resolved', 'icon': 'fact_check', 'unread': !leidos.contains('a2'), 'createdAt': '2026-10-02T10:00:00Z'},
            {'id': 'a3', 'title': 'Racha de 7 días', 'body': 'Sigue así.', 'kind': 'system', 'unread': false, 'createdAt': '2026-09-30T10:00:00Z', 'metricValue': 7, 'metricUnit': 'días'},
          ];
      return Avisos(AvisosApi(
        token: () async => 'TOKEN',
        baseUrl: 'https://api.test',
        client: MockClient((req) async {
          pedidas.add('${req.method} ${req.url.path}');
          if (req.url.path.endsWith('/read-all')) {
            leidos = {'a1', 'a2'};
            return http.Response('{"ok":true}', 200);
          }
          if (req.url.path.endsWith('/read')) {
            leidos.add(req.url.pathSegments[2]);
            return http.Response('{"ok":true}', 200);
          }
          final todos = items();
          final noLeidas = todos.where((i) => i['unread'] == true).length;
          if (req.url.path.endsWith('/unread-count')) return http.Response(jsonEncode({'unreadCount': noLeidas}), 200);
          final filtro = req.url.queryParameters['filter'];
          return http.Response(jsonEncode({
            'items': filtro == 'unread' ? todos.where((i) => i['unread'] == true).toList() : todos,
            'unreadCount': noLeidas,
          }), 200);
        }),
      ));
    }

    for (final (nombre, tam) in _tamanos) {
      testWidgets('en $nombre: lista, marcar una, filtro y marcar todas; el contador baja igual', (tester) async {
        _tam(tester, tam);
        final pedidas = <String>[];
        final avisos = almacen(pedidas);
        await tester.pumpWidget(ChangeNotifierProvider<Avisos>.value(
          value: avisos,
          child: const MaterialApp(home: AvisosScreen()),
        ));
        await tester.pumpAndSettle();

        expect(find.text('Tu daily de hoy ya está listo'), findsOneWidget);
        expect(find.text('Hace unos minutos'), findsOneWidget);
        expect(find.text('02/10/2026'), findsOneWidget);
        expect(find.text('7 días'), findsOneWidget);
        expect(find.text('2 sin leer'), findsOneWidget);
        expect(avisos.noLeidas, 2);
        expect(tester.takeException(), isNull);

        await tester.tap(find.text('Marcar leída').last);
        await tester.pumpAndSettle();
        expect(pedidas, contains('POST /api/notifications/a2/read'));
        expect(avisos.noLeidas, 1);
        expect(find.text('1 sin leer'), findsOneWidget);

        await tester.tap(find.text('No leídas'));
        await tester.pumpAndSettle();
        expect(find.text('Hemos revisado tu reporte'), findsNothing);
        expect(find.text('Tu daily de hoy ya está listo'), findsOneWidget);

        await tester.tap(find.text('Marcar todo como leído'));
        await tester.pumpAndSettle();
        expect(pedidas, contains('POST /api/notifications/read-all'));
        expect(avisos.noLeidas, 0);
        expect(find.text('Lo tienes todo leído'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('el globo cuelga del icono con el número y desaparece a cero', (tester) async {
      final avisos = Avisos(AvisosApi(token: () async => '', baseUrl: 'https://api.test'));
      await tester.pumpWidget(ChangeNotifierProvider<Avisos>.value(
        value: avisos,
        child: const MaterialApp(home: Scaffold(body: Center(child: GloboAvisos(child: Icon(Icons.person))))),
      ));
      expect(find.text('3'), findsNothing);
      avisos.poner(3);
      await tester.pump();
      expect(find.text('3'), findsOneWidget);
      avisos.poner(14);
      await tester.pump();
      expect(find.text('9+'), findsOneWidget);
      avisos.poner(0);
      await tester.pump();
      expect(find.text('9+'), findsNothing);
    });

    testWidgets('sin Avisos en el árbol el globo no rompe', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: GloboAvisos(child: Icon(Icons.person))));
      expect(find.byIcon(Icons.person), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
