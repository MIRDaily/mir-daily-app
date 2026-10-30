// Que los nodos no se monten unos sobre otros: las tablas como tablas (geometría de table.ts), el
// texto sin tope de ancho (como la web) y el botón «Ordenar» (solo para mirar).
//
//   flutter test test/mapas_ordenar_test.dart
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mirdaily_app/core/models/mapas.dart';
import 'package:mirdaily_app/core/services/mapas_api.dart';
import 'package:mirdaily_app/core/theme/app_theme.dart';
import 'package:mirdaily_app/features/mapas/mapa_screen.dart';

const _tabla = {
  'title': 'Tipos de AIJ',
  'columns': ['Tipo', 'Articulaciones', 'Pronóstico'],
  'rows': [
    ['Oligoarticular', '≤4 en 6 meses; grandes, sobre todo rodillas', 'Uveítis anterior crónica asintomática'],
    ['Poliarticular', '≥5; pequeñas de manos y pies', 'FR positivo: peor pronóstico'],
    ['Sistémica', 'Variable', 'Puede complicarse con SAM'],
  ],
  'colStyles': [
    {'bold': true},
    null,
    null,
  ],
};

/// Un mapa con los nodos montados unos sobre otros (todos en el mismo sitio) y una tabla.
Map<String, dynamic> _amontonado() => {
      'version': 2,
      'nodes': [
        {
          'id': 'r',
          'type': 'mindmap',
          'position': {'x': 0, 'y': 0},
          'data': {'label': 'Artritis idiopática juvenil', 'style': estiloDeSerie(0, 'general', 'Artritis idiopática juvenil'), 'category': 'general'},
        },
        for (var i = 0; i < 4; i++)
          {
            'id': 'h$i',
            'type': 'mindmap',
            'position': {'x': 300, 'y': 10},
            'data': {
              'label': 'Rama $i con un texto bastante más largo de lo normal',
              'style': estiloDeSerie(1, 'clinica', ''),
              'parentId': 'r',
              'category': 'clinica',
            },
          },
        {
          'id': 't',
          'type': 'mindmap',
          'position': {'x': 300, 'y': 20},
          'data': {'label': 'x', 'style': estiloDeSerie(2, 'tratamiento', ''), 'parentId': 'r', 'category': 'tratamiento', 'table': _tabla},
        },
      ],
      'edges': [
        for (var i = 0; i < 4; i++) {'id': 'e$i', 'source': 'r', 'target': 'h$i', 'type': 'animated', 'data': {}},
        {'id': 'et', 'source': 'r', 'target': 't', 'type': 'animated', 'data': {}},
      ],
    };

class _Supabase {
  Map<String, dynamic> fila = {};
  final List<http.Request> pedidas = [];

  Future<http.Response> responder(http.Request r) async {
    pedidas.add(r);
    if (r.method == 'GET') {
      return http.Response.bytes(utf8.encode(jsonEncode([fila])), 200);
    }
    fila.addAll(jsonDecode(r.body) as Map<String, dynamic>);
    fila['updated_at'] = '2026-10-30T11:00:00+00:00';
    return http.Response(jsonEncode([{'updated_at': fila['updated_at']}]), 200);
  }

  MapasApi api() => MapasApi(token: () async => 't', supabaseUrl: 'https://sb.test', anonKey: 'a', client: MockClient(responder));
}

bool _seSolapan(Iterable<Rect> cajas) {
  final l = cajas.toList();
  for (var i = 0; i < l.length; i++) {
    for (var j = i + 1; j < l.length; j++) {
      if (l[i].deflate(1).overlaps(l[j].deflate(1))) return true;
    }
  }
  return false;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('tablas (tableGeometry)', () {
    final t = TablaMapa.desde(_tabla)!;

    test('lee celdas y estilos; la cabecera va en negrita y el estilo de columna se aplica', () {
      expect(t.columnas, ['Tipo', 'Articulaciones', 'Pronóstico']);
      expect(t.filas, hasLength(3));
      expect(t.estiloDe(-1, 1).negrita, isTrue);
      expect(t.estiloDe(0, 0).negrita, isTrue, reason: 'colStyles[0]');
      expect(t.estiloDe(0, 1).negrita, isNull);
    });

    test('columnas entre 56 y 240 px, la tabla hasta 640, y altos por líneas', () {
      final g = geometriaTabla(t);
      for (final w in g.anchosColumna) {
        expect(w, inInclusiveRange(56, 240));
      }
      expect(g.ancho, lessThanOrEqualTo(640));
      expect(g.altosFila, hasLength(4), reason: 'cabecera + 3 filas');
      expect(g.altosFila[1], greaterThan(g.altosFila[0]), reason: 'la fila 1 parte su texto en más líneas');
      expect(g.alto, closeTo(g.altoTitulo + g.altosFila.reduce((a, b) => a + b) + 4, 0.01));
    });

    test('una tabla de una columna corta llega al ancho mínimo (160)', () {
      final g = geometriaTabla(TablaMapa.desde({'title': '', 'columns': ['a'], 'rows': []})!);
      expect(g.ancho, 160);
    });
  });

  group('ordenar en árbol', () {
    test('nada se solapa, los hijos a la derecha del padre y en su orden', () {
      final r = math.Random(4);
      final ids = <String>['0'];
      final padres = <String, String?>{'0': null};
      for (var i = 1; i < 60; i++) {
        ids.add('$i');
        padres['$i'] = '${r.nextInt(i)}';
      }
      final cajas = ordenarEnArbol(ids: ids, padres: padres, tamano: (id) => Size(80.0 + int.parse(id) % 7 * 30, 30.0 + int.parse(id) % 3 * 25));
      expect(cajas, hasLength(60));
      expect(_seSolapan(cajas.values), isFalse);
      for (final id in ids.skip(1)) {
        expect(cajas[id]!.left, greaterThan(cajas[padres[id]]!.right), reason: id);
      }
    });

    test('varios árboles sueltos, uno debajo de otro', () {
      final c = ordenarEnArbol(ids: ['a', 'b', 'a1'], padres: {'a': null, 'b': null, 'a1': 'a'}, tamano: (_) => const Size(100, 40));
      expect(c['b']!.top, greaterThanOrEqualTo(c['a1']!.bottom + 90));
    });
  });

  for (final (nombre, size) in [('móvil', const Size(360, 780)), ('tablet', const Size(1024, 768))]) {
    group(nombre, () {
      Future<_Supabase> montar(WidgetTester tester) async {
        final s = _Supabase()
          ..fila = {'id': 'm', 'title': 'AIJ', 'subject': null, 'updated_at': '2026-10-30T10:00:00+00:00', 'doc': _amontonado()};
        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(Provider<MapasApi>.value(
          value: s.api(),
          child: MaterialApp(theme: AppTheme.lightTheme, home: const MapaScreen(mapaId: 'm')),
        ));
        await tester.pumpAndSettle();
        return s;
      }

      List<Rect> cajasNodos(WidgetTester tester) => [
            for (final id in ['r', 'h0', 'h1', 'h2', 'h3', 't'])
              // Sin el aire de los lados (el sitio del botón de plegar): solo va a izquierda y derecha.
              () {
                final r = tester.getRect(find.byKey(ValueKey(id)).first);
                return Rect.fromLTRB(r.left + 22, r.top, r.right - 22, r.bottom);
              }(),
          ];

      testWidgets('la tabla se ve como tabla, y el texto largo no se parte', (tester) async {
        await montar(tester);
        for (final c in ['Tipos de AIJ', 'Tipo', 'Oligoarticular', 'Puede complicarse con SAM']) {
          expect(find.text(c), findsOneWidget, reason: c);
        }
        final rama = tester.getSize(find.textContaining('Rama 0', findRichText: true).first);
        expect(rama.height, lessThan(30), reason: 'una sola línea, como en la web');
        expect(tester.takeException(), isNull);
      });

      testWidgets('«Ordenar» los separa sin guardar nada; editar después guarda ese orden', (tester) async {
        final s = await montar(tester);
        expect(_seSolapan(cajasNodos(tester)), isTrue, reason: 'el mapa viene amontonado');

        await tester.tap(find.byTooltip('Ordenar el mapa'));
        await tester.pumpAndSettle();
        expect(_seSolapan(cajasNodos(tester)), isFalse);
        await tester.pump(const Duration(seconds: 2));
        await tester.pumpAndSettle();
        expect(s.pedidas.where((r) => r.method == 'PATCH'), isEmpty, reason: 'mirar no guarda');

        // Volver a como está guardado.
        await tester.tap(find.byTooltip('Ver como está en la web'));
        await tester.pumpAndSettle();
        expect(_seSolapan(cajasNodos(tester)), isTrue);

        // Ordenar y editar: el orden pasa al mapa y se guarda.
        await tester.tap(find.byTooltip('Ordenar el mapa'));
        await tester.pumpAndSettle();
        await tester.tap(find.bySemanticsLabel('Artritis idiopática juvenil'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Editar texto'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'AIJ');
        await tester.tap(find.text('Guardar'));
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 2));
        await tester.pumpAndSettle();
        final guardado = DocMapa.desde(s.fila['doc']);
        final cajas = {for (final n in guardado.nodos) n.id: n.posicion};
        expect(cajas['h0'], isNot(cajas['h1']), reason: 'ya no están en el mismo sitio');
        expect(guardado.nodos.first.label, 'AIJ');
        expect(tester.takeException(), isNull);
      });
    });
  }
}
