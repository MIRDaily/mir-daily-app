// La lista de mapas ordenada por carpetas: agrupar, buscar, el cliente (carpeta y fijar) y la
// pantalla en móvil (360×780) y tablet (1024×768), con mover de carpeta por el selector de verdad.
//
//   flutter test test/mapas_organizar_test.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:mirdaily_app/core/services/carpetas.dart';
import 'package:mirdaily_app/core/services/mapas_api.dart';
import 'package:mirdaily_app/core/theme/app_theme.dart';
import 'package:mirdaily_app/features/mapas/mapas_agrupar.dart';
import 'package:mirdaily_app/features/mapas/mapas_screen.dart';

/// Supabase de mentira (mind_maps), solo lo que usa la lista.
class _Supabase {
  final Map<String, Map<String, dynamic>> filas = {};
  final List<http.Request> pedidas = [];
  bool sinCarpetas = false;
  int _reloj = 0;

  void meter(String id, String titulo, {int? asignatura, int? tema, bool fijado = false}) {
    filas[id] = {
      'id': id,
      'title': titulo,
      'subject': null,
      // Cada uno más reciente que el anterior.
      'updated_at': DateTime.utc(2026, 10, 30, 10, _reloj++).toIso8601String(),
      'pinned': fijado,
      'deleted_at': null,
      'folder_subject_id': asignatura,
      'folder_topic_id': tema,
    };
  }

  Future<http.Response> responder(http.Request r) async {
    pedidas.add(r);
    http.Response json(Object o, [int s = 200]) => http.Response.bytes(utf8.encode(jsonEncode(o)), s);
    final q = r.url.queryParameters;
    final select = (q['select'] ?? '').split(',');
    if (sinCarpetas && select.contains('folder_subject_id')) {
      return json({'message': 'column mind_maps.folder_subject_id does not exist'}, 400);
    }
    if (r.method == 'GET') {
      return json([
        for (final f in filas.values) {for (final c in select) c: f[c]},
      ]);
    }
    if (r.method == 'PATCH') {
      final id = q['id']!.substring(3);
      filas[id]!.addAll(jsonDecode(r.body) as Map<String, dynamic>);
      return json([]);
    }
    return json({'message': 'no'}, 405);
  }

  MapasApi api() => MapasApi(token: () async => 'tok', supabaseUrl: 'https://sb.test', anonKey: 'anon', client: MockClient(responder));
}

/// /api/carpetas del backend: el catálogo y mover.
class _Carpetas {
  final List<Map<String, dynamic>> movidos = [];
  final _Supabase sb;
  _Carpetas(this.sb);

  static const arbol = {
    'asignaturas': [
      {
        'id': 1,
        'nombre': 'Neumología',
        'nombreCorto': 'Neumo',
        'temas': [
          {'id': 11, 'nombre': 'Asma'},
          {'id': 12, 'nombre': 'EPOC'},
        ],
      },
      {
        'id': 2,
        'nombre': 'Cardiología',
        'nombreCorto': 'Cardio',
        'temas': [
          {'id': 21, 'nombre': 'Arritmias'},
        ],
      },
    ],
  };

  Future<http.Response> responder(http.Request r) async {
    if (r.url.path.endsWith('/arbol')) {
      // Como Express: con el charset, que el cliente usa para leer las tildes.
      return http.Response.bytes(utf8.encode(jsonEncode(arbol)), 200, headers: {'content-type': 'application/json; charset=utf-8'});
    }
    if (r.method == 'PATCH') {
      final b = jsonDecode(r.body) as Map<String, dynamic>;
      movidos.add(b);
      for (final id in b['ids'] as List) {
        sb.filas[id]!['folder_subject_id'] = b['subjectId'];
        sb.filas[id]!['folder_topic_id'] = b['topicId'];
      }
      return http.Response(jsonEncode({'movidos': (b['ids'] as List).length}), 200);
    }
    return http.Response('{}', 404);
  }

  CarpetasApi api() => CarpetasApi(token: () async => 'tok', baseUrl: 'https://api.test', client: MockClient(responder));
}

List<AsignaturaCatalogo> _catalogo() =>
    (_Carpetas.arbol['asignaturas'] as List).map(AsignaturaCatalogo.fromJson).whereType<AsignaturaCatalogo>().toList();

ResumenMapa _rm(String id, int minutos, {int? a, int? t}) => ResumenMapa(
      id: id,
      titulo: 'Mapa $id',
      asignatura: null,
      actualizado: DateTime(2026, 10, 30, 12).subtract(Duration(minutes: minutos)),
      fijado: false,
      carpeta: Carpeta(subjectId: a, topicId: a == null ? null : t),
    );

void main() {
  group('organizar', () {
    test('por asignatura: la más reciente primero, «Sin clasificar» al final; temas en orden del temario', () {
      final g = agruparPorCarpeta([
        _rm('n-epoc', 50, a: 1, t: 12),
        _rm('c', 5, a: 2, t: 21),
        _rm('n-asma', 30, a: 1, t: 11),
        _rm('n-gen', 40, a: 1),
        _rm('n-raro', 45, a: 1, t: 999),
        _rm('suelto', 1),
      ], _catalogo());
      expect(g.map((x) => x.nombre), ['Cardiología', 'Neumología', 'Sin clasificar']);
      final neumo = g[1];
      expect(neumo.temas.map((t) => t.nombre), ['General', 'Asma', 'EPOC']);
      expect(neumo.temas.first.mapas.map((m) => m.id), ['n-gen', 'n-raro'], reason: 'un tema desconocido va a General');
      expect(neumo.total, 4);
    });

    test('sin catálogo (no cargó), agrupa igual con un nombre genérico', () {
      expect(agruparPorCarpeta([_rm('x', 1, a: 1, t: 11)], null).single.nombre, 'Asignatura');
    });

    test('buscar mira el título y la carpeta, sin tildes ni mayúsculas', () {
      final l = [_rm('a', 1, a: 1, t: 11), _rm('b', 2, a: 2, t: 21)];
      expect(buscarMapas(l, 'neumo', _catalogo()).map((m) => m.id), ['a']);
      expect(buscarMapas(l, 'ARRITMIAS', _catalogo()).map((m) => m.id), ['b']);
      expect(buscarMapas(l, 'mapa b', _catalogo()).map((m) => m.id), ['b']);
    });

    test('el cliente trae la carpeta; sin esas columnas, pide sin ellas', () async {
      final s = _Supabase()..meter('m1', 'Uno', asignatura: 1, tema: 11);
      expect((await s.api().lista()).single.carpeta, const Carpeta(subjectId: 1, topicId: 11));
      final s2 = _Supabase()
        ..meter('m1', 'Uno')
        ..sinCarpetas = true;
      expect((await s2.api().lista()).single.carpeta, isNull);
      expect(s2.pedidas, hasLength(2));
    });

    test('fijar cambia la columna pinned', () async {
      final s = _Supabase()..meter('m1', 'Uno');
      await s.api().fijar('m1', true);
      expect(s.filas['m1']!['pinned'], isTrue);
      expect(s.pedidas.last.method, 'PATCH');
    });
  });

  for (final (nombre, size) in [('móvil', const Size(360, 780)), ('tablet', const Size(1024, 768))]) {
    testWidgets('$nombre: secciones por asignatura, fijados, mover de carpeta, recientes y buscar', (tester) async {
      final s = _Supabase()
        ..meter('m4', 'Apuntes sueltos')
        ..meter('m1', 'Asma bronquial', asignatura: 1, tema: 11)
        ..meter('m2', 'EPOC y enfisema', asignatura: 1, tema: 12, fijado: true)
        ..meter('m3', 'Fibrilación auricular', asignatura: 2, tema: 21);
      final c = _Carpetas(s);
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MultiProvider(
        providers: [
          Provider<MapasApi>.value(value: s.api()),
          Provider<CarpetasApi>.value(value: c.api()),
        ],
        child: MaterialApp(theme: AppTheme.lightTheme, home: const MapasScreen()),
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('4 mapas en 2 asignaturas'), findsOneWidget);
      expect(find.text('FIJADOS'), findsOneWidget);
      expect(find.text('Cardiología'), findsOneWidget);
      expect(find.text('Neumología'), findsOneWidget);
      expect(find.text('Sin clasificar'), findsOneWidget);
      // Tres secciones: solo la primera (Cardiología, la más reciente) abierta.
      expect(find.text('Fibrilación auricular'), findsOneWidget);
      expect(find.text('Asma bronquial'), findsNothing);
      await tester.tap(find.text('Neumología'));
      await tester.pumpAndSettle();
      expect(find.text('Asma bronquial'), findsOneWidget);
      expect(find.text('ASMA'), findsOneWidget, reason: 'rótulo del tema');
      expect(tester.takeException(), isNull);

      // Mover «Asma bronquial» a Cardiología › Arritmias desde su menú.
      await tester.ensureVisible(find.byTooltip('Opciones de Asma bronquial'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Opciones de Asma bronquial'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mover a carpeta'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cardiología').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Arritmias').last);
      await tester.pumpAndSettle();
      expect(c.movidos.single, {'tipo': 'mapa', 'ids': ['m1'], 'subjectId': 2, 'topicId': 21, 'origen': 'usuario'});
      expect(find.textContaining('Movido a Cardiología'), findsOneWidget);

      // Fijar desde el menú.
      await tester.ensureVisible(find.byTooltip('Opciones de Fibrilación auricular'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Opciones de Fibrilación auricular'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fijar arriba'));
      await tester.pumpAndSettle();
      expect(s.filas['m3']!['pinned'], isTrue);

      // Recientes: todos en una lista, con su carpeta debajo.
      await tester.scrollUntilVisible(find.text('Recientes'), -200, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Recientes'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Neumo › EPOC'), findsWidgets);

      // Buscar por asignatura.
      await tester.scrollUntilVisible(find.byType(TextField), -200, scrollable: find.byType(Scrollable).first);
      await tester.enterText(find.byType(TextField), 'cardio');
      await tester.pumpAndSettle();
      expect(find.text('Fibrilación auricular'), findsWidgets);
      expect(find.text('Apuntes sueltos'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
