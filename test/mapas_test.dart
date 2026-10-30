// Mapas mentales en la app: modelo, cliente (Supabase de mentira) y pantallas en móvil (360×780) y
// tablet (1024×768).
//
//   flutter test test/mapas_test.dart
import 'dart:convert';

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
import 'package:mirdaily_app/features/mapas/mapas_screen.dart';

/// Un mapa como lo guarda el editor de la web, con cosas que la app no sabe tocar.
Map<String, dynamic> _grafo() => {
      'version': 2,
      'nodes': [
        {
          'id': 'root',
          'type': 'mindmap',
          'position': {'x': -58, 'y': -58},
          'width': 116,
          'height': 116,
          'data': {
            'label': 'Asma',
            'style': estiloDeSerie(0, 'general', 'Asma'),
            'category': 'general',
          },
        },
        {
          'id': 'a',
          'type': 'mindmap',
          'position': {'x': 150, 'y': -120},
          'data': {
            'label': '<b>Clínica</b>',
            'style': estiloDeSerie(1, 'clinica', 'Clínica'),
            'parentId': 'root',
            'category': 'clinica',
            'ia': {'pagina': 3, 'revisado': false},
          },
        },
        {
          'id': 'a1',
          'type': 'mindmap',
          'position': {'x': 400, 'y': -140},
          'data': {
            'label': 'Sibilancias<br>espiratorias',
            'style': estiloDeSerie(2, 'clinica', 'Sibilancias'),
            'parentId': 'a',
            'category': 'clinica',
            'futuro': {'campo': 'que la web añada mañana'},
          },
        },
        {
          'id': 't',
          'type': 'mindmap',
          'position': {'x': 150, 'y': 80},
          'data': {
            'label': '<b>Fármacos</b><br>SABA | Salbutamol',
            'style': estiloDeSerie(2, 'tratamiento', ''),
            'parentId': 'root',
            'category': 'tratamiento',
            'table': {
              'title': 'Fármacos',
              'columns': ['Grupo', 'Ejemplo'],
              'rows': [
                ['SABA', 'Salbutamol'],
              ],
            },
          },
        },
      ],
      'edges': [
        {'id': 'e-root-a', 'source': 'root', 'target': 'a', 'sourceHandle': 'right', 'targetHandle': 'left', 'type': 'animated', 'data': {'color': '#E8A598', 'strokeWidth': 1.8}},
        {'id': 'e-a-a1', 'source': 'a', 'target': 'a1', 'sourceHandle': null, 'targetHandle': null, 'type': 'animated', 'data': {'variant': 'dashed'}},
        {'id': 'e-root-t', 'source': 'root', 'target': 't', 'sourceHandle': null, 'targetHandle': null, 'type': 'animated', 'data': {}},
      ],
      'settings': {
        'theme': 'light',
        'categoryStyles': {
          'clinica': {'color': '#123456'},
        },
      },
    };

Map<String, dynamic> _arbol(int bloques) => {
      'version': 1,
      'nodes': [
        {'id': 'r', 'parentId': null, 'text': 'Neumología', 'category': 'general'},
        for (var i = 0; i < bloques; i++) {'id': 'b$i', 'parentId': 'r', 'text': 'Bloque $i', 'category': 'clinica'},
        {'id': 'h', 'parentId': 'b0', 'text': 'Detalle', 'category': 'clinica'},
      ],
    };

/// Supabase de mentira: guarda los mapas y sube `updated_at` en cada escritura, como el disparador.
class _Supabase {
  final Map<String, Map<String, dynamic>> filas = {};
  final List<http.Request> pedidas = [];
  int _reloj = 0;
  bool sinPinned = false;

  String _marca() => '2026-10-30T10:00:${(_reloj++).toString().padLeft(2, '0')}.123456+00:00';

  void meter(String id, Object doc, {String titulo = 'Asma', bool fijado = false}) {
    filas[id] = {'id': id, 'title': titulo, 'subject': null, 'updated_at': _marca(), 'pinned': fijado, 'doc': doc, 'deleted_at': null};
  }

  /// Otro dispositivo guarda el mapa.
  void tocarDesdeFuera(String id) => filas[id]!['updated_at'] = _marca();

  Future<http.Response> responder(http.Request r) async {
    pedidas.add(r);
    final q = r.url.queryParameters;
    http.Response json(Object o, [int s = 200]) => http.Response.bytes(utf8.encode(jsonEncode(o)), s);
    final select = (q['select'] ?? '').split(',');
    if (sinPinned && select.contains('pinned')) {
      return json({'message': 'column mind_maps.pinned does not exist'}, 400);
    }
    var filasQ = filas.values.where((f) => f['deleted_at'] == null);
    if (q['id'] != null) filasQ = filasQ.where((f) => 'eq.${f['id']}' == q['id']);
    if (r.method == 'GET') {
      return json([
        for (final f in filasQ) {for (final c in select) c: f[c]},
      ]);
    }
    if (r.method == 'PATCH') {
      if (q['updated_at'] != null) filasQ = filasQ.where((f) => 'eq.${f['updated_at']}' == q['updated_at']);
      final hits = filasQ.toList();
      final cambios = jsonDecode(r.body) as Map<String, dynamic>;
      for (final f in hits) {
        f.addAll(cambios);
        f['updated_at'] = _marca();
      }
      return json([for (final f in hits) {'updated_at': f['updated_at']}]);
    }
    return json({'message': 'no'}, 405);
  }

  MapasApi api() => MapasApi(
        token: () async => 'tok',
        supabaseUrl: 'https://sb.test',
        anonKey: 'anon',
        client: MockClient(responder),
      );

  Map<String, dynamic> doc(String id) => filas[id]!['doc'] as Map<String, dynamic>;
}

Size _t(String _) => const Size(150, 50);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('texto de los nodos (HTML de la web)', () {
    test('negrita, saltos, bloques, entidades y color', () {
      final t = trozosDeLabel('<b>Hola</b> &amp; <span style="color: #FF0000">rojo</span><br>abajo<div>bloque</div>');
      expect(t.map((x) => x.texto).join(), 'Hola & rojo\nabajo\nbloque');
      expect(t.first.negrita, isTrue);
      expect(t.firstWhere((x) => x.texto == 'rojo').color, const Color(0xFFFF0000));
      expect(labelTieneFormato('<b>x</b>'), isTrue);
      expect(labelTieneFormato('uno<br>dos &lt;3'), isFalse);
      expect(textoDeLabel('uno<br>dos &lt;3'), 'uno\ndos <3');
    });

    test('lo escrito en la app se escapa y las líneas van con <br>', () {
      expect(labelDeTexto('  a < b & c\nsegunda  '), 'a &lt; b &amp; c<br>segunda');
    });

    test('colores de CSS', () {
      expect(colorCss('#E8A598'), const Color(0xFFE8A598));
      expect(colorCss('#abc'), const Color(0xFFAABBCC));
      expect(colorCss('#11223380'), const Color(0x80112233));
      expect(colorCss('rgba(0, 0, 0, 0.5)')!.a, closeTo(0.5, 0.01));
      expect(colorCss('nada'), isNull);
    });
  });

  group('documento (grafo)', () {
    test('lee nodos, aristas, padres y lo que es tabla', () {
      final d = DocMapa.desde(_grafo());
      expect(d.editable, isTrue);
      expect(d.nodos.map((n) => n.id), ['root', 'a', 'a1', 't']);
      expect(d.nodos.firstWhere((n) => n.id == 't').textoEditable, isFalse);
      expect(d.padres, {'root': null, 'a': 'root', 'a1': 'a', 't': 'root'});
      expect(d.descendientes('a'), {'a1'});
      expect(d.aristas.firstWhere((e) => e.id == 'e-a-a1').variante, 'dashed');
    });

    test('el padre sale de la arista si el nodo no lo trae, y un ciclo no cuelga', () {
      final g = _grafo();
      ((g['nodes'] as List)[2]['data'] as Map).remove('parentId');
      expect(DocMapa.desde(g).padres['a1'], 'a', reason: 'por la arista e-a-a1');
      final c = _grafo();
      (c['edges'] as List).add({'id': 'x', 'source': 'a1', 'target': 'root', 'data': {}});
      (((c['nodes'] as List)[0])['data'] as Map)['parentId'] = 'a1';
      expect(DocMapa.desde(c).nodos, hasLength(4), reason: 'no se queda colgado');
    });

    test('las ediciones conservan TODO lo que la app no toca', () {
      final original = _grafo();
      final d = DocMapa.desde(original);
      expect(d.cambiarTexto('a1', 'Tos\nnocturna'), isTrue);
      d.moverRama('a', const Offset(10, 20));
      final nuevo = d.anadirHijo('a1', tamano: _t);
      expect(d.borrarRama(nuevo), 1);
      final j = d.json;
      final a1 = (j['nodes'] as List).firstWhere((n) => n['id'] == 'a1') as Map;
      expect(a1['data']['label'], 'Tos<br>nocturna');
      expect(a1['data']['futuro'], {'campo': 'que la web añada mañana'});
      expect(a1['data']['style'], original['nodes'][2]['data']['style']);
      final a = (j['nodes'] as List).firstWhere((n) => n['id'] == 'a') as Map;
      expect(a['data']['ia'], {'pagina': 3, 'revisado': false});
      expect(a['data']['label'], '<b>Clínica</b>', reason: 'no se ha tocado: conserva su formato');
      expect(j['settings'], original['settings']);
      expect((j['nodes'] as List).firstWhere((n) => n['id'] == 't')['data']['table'], original['nodes'][3]['data']['table']);
      expect(j['edges'], original['edges'], reason: 'el hijo añadido y borrado se lleva su arista');
      expect(original['nodes'][2]['data']['label'], 'Sibilancias<br>espiratorias', reason: 'el original no se toca');
    });

    test('un mapa vacío o sin documento se lee sin romper', () {
      for (final raw in [null, <String, dynamic>{}, {'version': 1, 'nodes': []}, {'version': 2, 'nodes': [], 'edges': []}]) {
        final d = DocMapa.desde(raw);
        expect(d.nodos, isEmpty, reason: '$raw');
        expect(d.aristas, isEmpty);
      }
    });

    test('una tabla no cambia de texto en la app', () {
      final d = DocMapa.desde(_grafo());
      expect(d.cambiarTexto('t', 'otra cosa'), isFalse);
    });

    test('mover lleva la rama entera y nada más', () {
      final d = DocMapa.desde(_grafo());
      d.moverRama('a', const Offset(10, -5));
      final p = {for (final n in d.nodos) n.id: n.posicion};
      expect(p['a'], const Offset(160, -125));
      expect(p['a1'], const Offset(410, -145));
      expect(p['t'], const Offset(150, 80));
      expect(p['root'], const Offset(-58, -58));
    });

    test('añadir: a la derecha del padre, con su arista, estilo de su nivel y la rama desplegada', () {
      final g = _grafo();
      (g['nodes'] as List)[1]['data']['collapsed'] = true;
      final d = DocMapa.desde(g);
      final id = d.anadirHijo('a', tamano: _t);
      final n = d.nodos.firstWhere((x) => x.id == id);
      expect(n.padre, 'a');
      expect(n.categoria, 'clinica');
      expect(n.label, 'Nueva idea');
      expect(n.estilo.forma, FormaNodo.rectangulo, reason: 'nivel 2: caja con borde');
      // Ya hay un hermano (a1) a la derecha: misma columna y debajo de él.
      expect(n.posicion, const Offset(400, -140 + 50 + 16));
      expect(d.aristas.any((e) => e.origen == 'a' && e.destino == id), isTrue);
      expect(d.nodos.firstWhere((x) => x.id == 'a').plegado, isFalse);
      // Primer hijo de una hoja: a 90 px de su borde derecho.
      final id2 = d.anadirHijo('a1', tamano: _t);
      expect(d.nodos.firstWhere((x) => x.id == id2).posicion, const Offset(400 + 150 + 90, -140));
    });

    test('borrar se lleva la rama y sus aristas; la raíz no se borra', () {
      final d = DocMapa.desde(_grafo());
      expect(d.borrarRama('root'), 0);
      expect(d.borrarRama('a'), 2);
      expect(d.nodos.map((n) => n.id), ['root', 't']);
      expect(d.aristas.map((e) => e.id), ['e-root-t']);
    });
  });

  group('mapas en árbol (aún sin abrir en la web)', () {
    test('se ven ordenados como en la web, pero no se editan', () {
      final d = DocMapa.desde(_arbol(3));
      expect(d.desdeArbol, isTrue);
      expect(d.editable, isFalse);
      expect(() => d.cambiarTexto('r', 'x'), throwsStateError);
      final p = {for (final n in d.nodos) n.id: n.posicion};
      expect(p['r']!.dx, 0);
      expect(p['b0']!.dx, greaterThan(100), reason: 'a la derecha de la raíz');
      expect(p['b1']!.dy, greaterThan(p['b0']!.dy), reason: 'hermanos uno debajo de otro');
      expect(p['h']!.dx, greaterThan(p['b0']!.dx));
      expect(d.nodos.first.estilo.forma, FormaNodo.circulo, reason: 'raíz corta: círculo');
      expect(d.aristas, hasLength(4));
    });

    test('con 8 bloques o más, el abanico va a los dos lados', () {
      final d = DocMapa.desde(_arbol(10));
      final x = {for (final n in d.nodos) n.id: n.posicion.dx};
      expect(x.values.where((v) => v < 0), isNotEmpty);
      expect(x.values.where((v) => v > 0), isNotEmpty);
    });
  });

  test('las líneas salen por el lado que mira al otro nodo', () {
    const a = Rect.fromLTWH(0, 0, 100, 40);
    expect(ladosDeConexion(a, const Rect.fromLTWH(200, 0, 100, 40)), (LadoNodo.derecha, LadoNodo.izquierda));
    expect(ladosDeConexion(a, const Rect.fromLTWH(-300, 0, 100, 40)), (LadoNodo.izquierda, LadoNodo.derecha));
    expect(ladosDeConexion(a, const Rect.fromLTWH(10, 200, 100, 40)), (LadoNodo.abajo, LadoNodo.arriba));
    final (s, _, _, t) = curvaEntre(a, const Rect.fromLTWH(200, 100, 100, 40));
    expect((s, t), (const Offset(100, 20), const Offset(200, 120)));
  });

  group('cliente', () {
    test('la lista no baja los mapas enteros, lleva la sesión y pone los fijados arriba', () async {
      final s = _Supabase()
        ..meter('m1', _grafo(), titulo: 'Uno')
        ..meter('m2', _grafo(), titulo: 'Dos', fijado: true)
        ..meter('m3', _grafo(), titulo: 'Tres');
      final l = await s.api().lista();
      expect(l.map((m) => m.titulo), ['Dos', 'Tres', 'Uno']);
      final r = s.pedidas.single;
      expect(r.url.toString(), startsWith('https://sb.test/rest/v1/mind_maps?'));
      expect(r.url.queryParameters['select'], isNot(contains('doc')));
      expect(r.headers['apikey'], 'anon');
      expect(r.headers['Authorization'], 'Bearer tok');
    });

    test('sin la columna pinned, la lista se pide sin ella', () async {
      final s = _Supabase()
        ..meter('m1', _grafo())
        ..sinPinned = true;
      expect(await s.api().lista(), hasLength(1));
      expect(s.pedidas, hasLength(2));
    });

    test('guardar «sin pisar»: con la marca que se leyó, y si cambió fuera no escribe', () async {
      final s = _Supabase()..meter('m1', _grafo());
      final api = s.api();
      final m = (await api.abrir('m1'))!;
      m.doc.cambiarTexto('a1', 'Cambio');
      final marca = await api.guardar('m1', actualizadoEn: m.actualizadoEn, doc: m.doc);
      expect(marca, isNot(m.actualizadoEn));
      expect(s.pedidas.last.method, 'PATCH');
      expect(s.pedidas.last.url.queryParameters['updated_at'], 'eq.${m.actualizadoEn}', reason: 'el «+» de la zona horaria llega bien');
      expect(s.pedidas.last.headers['Prefer'], 'return=representation');
      expect(((s.doc('m1')['nodes'] as List)[2] as Map)['data']['label'], 'Cambio');

      s.tocarDesdeFuera('m1');
      m.doc.cambiarTexto('a1', 'Otro');
      await expectLater(api.guardar('m1', actualizadoEn: marca, doc: m.doc), throwsA(isA<MapaCambiadoException>()));
      expect(((s.doc('m1')['nodes'] as List)[2] as Map)['data']['label'], 'Cambio', reason: 'no ha pisado');
      await api.guardar('m1', actualizadoEn: marca, doc: m.doc, forzar: true);
      expect(((s.doc('m1')['nodes'] as List)[2] as Map)['data']['label'], 'Otro');
    });
  });

  for (final (nombre, size) in [('móvil', const Size(360, 780)), ('tablet', const Size(1024, 768))]) {
    group(nombre, () {
      Future<_Supabase> montar(WidgetTester tester, Object doc, {Widget? home}) async {
        final s = _Supabase()..meter('m1', doc);
        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(Provider<MapasApi>.value(
          value: s.api(),
          child: MaterialApp(theme: AppTheme.lightTheme, home: home ?? const MapaScreen(mapaId: 'm1')),
        ));
        await tester.pumpAndSettle();
        return s;
      }

      Future<void> esperarGuardado(WidgetTester tester) async {
        await tester.pump(const Duration(milliseconds: 1600));
        await tester.pumpAndSettle();
      }

      Finder nodo(String texto) => find.bySemanticsLabel(texto);

      testWidgets('se ve entero y la tabla y el formato se pintan', (tester) async {
        await montar(tester, _grafo());
        expect(find.text('Asma'), findsNWidgets(2), reason: 'el título y la raíz');
        expect(find.textContaining('Clínica', findRichText: true), findsWidgets);
        // La tabla, como tabla: título, cabecera y celdas por separado.
        for (final c in ['Fármacos', 'Grupo', 'Ejemplo', 'SABA', 'Salbutamol']) {
          expect(find.text(c), findsOneWidget, reason: c);
        }
        expect(tester.takeException(), isNull);
      });

      testWidgets('editar texto, añadir y borrar ramas, deshacer: y se guarda solo', (tester) async {
        final s = await montar(tester, _grafo());
        // «Clínica» se ve al abrir en los dos tamaños (en el móvil, el mapa abre centrado en la raíz).
        await tester.tap(nodo('Clínica'));
        await tester.pumpAndSettle();
        expect(find.text('Editar texto'), findsOneWidget);

        await tester.tap(find.text('Editar texto'));
        await tester.pumpAndSettle();
        expect(find.textContaining('tiene formato'), findsOneWidget, reason: 'es <b>Clínica</b>');
        await tester.enterText(find.byType(TextField), 'Clínica típica');
        await tester.tap(find.text('Guardar'));
        await tester.pumpAndSettle();
        expect(find.text('Clínica típica'), findsOneWidget);
        await esperarGuardado(tester);
        expect(((s.doc('m1')['nodes'] as List)[1] as Map)['data']['label'], 'Clínica típica');

        // Añadir una rama: nace «Nueva idea» y se abre su texto.
        await tester.tap(find.text('Añadir rama'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Disnea');
        await tester.tap(find.text('Guardar'));
        await tester.pumpAndSettle();
        expect(find.bySemanticsLabel('Disnea'), findsOneWidget);

        // Borrar la rama (con sus dos hijos): pide confirmación.
        await tester.tap(nodo('Clínica típica'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Borrar'));
        await tester.pumpAndSettle();
        expect(find.text('¿Borrar esta rama?'), findsOneWidget);
        expect(find.textContaining('los 2 que cuelgan'), findsOneWidget);
        await tester.tap(find.widgetWithText(TextButton, 'Borrar'));
        await tester.pumpAndSettle();
        expect(find.bySemanticsLabel('Clínica típica'), findsNothing);

        // Deshacer la devuelve.
        await tester.tap(find.byTooltip('Deshacer'));
        await tester.pumpAndSettle();
        expect(find.bySemanticsLabel('Clínica típica'), findsOneWidget);
        await esperarGuardado(tester);
        final nodos = s.doc('m1')['nodes'] as List;
        expect(nodos.map((n) => n['data']['label']), containsAll(['Clínica típica', 'Disnea', 'Sibilancias<br>espiratorias']));
        expect(s.doc('m1')['settings'], _grafo()['settings'], reason: 'lo que no se toca, intacto');
        expect(tester.takeException(), isNull);
      });

      testWidgets('un nodo seleccionado se arrastra con su rama; sin seleccionar, no se mueve', (tester) async {
        final s = await montar(tester, _grafo());
        Offset pos(String id) {
          final n = (s.doc('m1')['nodes'] as List).firstWhere((n) => n['id'] == id) as Map;
          return Offset((n['position']['x'] as num).toDouble(), (n['position']['y'] as num).toDouble());
        }

        await tester.drag(nodo('Clínica'), const Offset(60, 40));
        await tester.pumpAndSettle();
        await esperarGuardado(tester);
        expect(pos('a'), const Offset(150, -120), reason: 'sin seleccionar se mueve el lienzo, no el nodo');

        await tester.tap(nodo('Clínica'));
        await tester.pumpAndSettle();
        await tester.drag(nodo('Clínica'), const Offset(60, 40));
        await tester.pumpAndSettle();
        await esperarGuardado(tester);
        expect(pos('a').dx, greaterThan(150));
        expect(pos('a1').dx - pos('a').dx, closeTo(250, 0.2), reason: 'la rama va con él');
        expect(pos('t'), const Offset(150, 80));
        expect(tester.takeException(), isNull);
      });

      testWidgets('si la web guardó entre medias, pregunta y no pisa sin permiso', (tester) async {
        final s = await montar(tester, _grafo());
        s.tocarDesdeFuera('m1');
        // El título de la barra también dice «Asma»: se toca la raíz, la del lienzo.
        await tester.tap(find.descendant(of: find.byType(InteractiveViewer), matching: find.text('Asma')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Editar texto'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Asma bronquial');
        await tester.tap(find.text('Guardar'));
        await tester.pumpAndSettle();
        await esperarGuardado(tester);
        expect(find.text('El mapa ha cambiado en otro sitio'), findsOneWidget);
        expect(((s.doc('m1')['nodes'] as List)[0] as Map)['data']['label'], 'Asma');
        await tester.tap(find.text('Quedarme con esta'));
        await tester.pumpAndSettle();
        expect(((s.doc('m1')['nodes'] as List)[0] as Map)['data']['label'], 'Asma bronquial');
      });

      testWidgets('un mapa en árbol se ve con su aviso y sin barra de edición', (tester) async {
        await montar(tester, _arbol(3));
        expect(find.textContaining('Ábrelo una vez en la web'), findsOneWidget);
        await tester.tap(nodo('Bloque 1'));
        await tester.pumpAndSettle();
        expect(find.text('Editar texto'), findsNothing);
        expect(find.byTooltip('Deshacer'), findsNothing);
        expect(tester.takeException(), isNull);
      });

      testWidgets('plegar una rama la oculta (sin guardar nada)', (tester) async {
        final s = await montar(tester, _grafo());
        await tester.tap(find.bySemanticsLabel('Plegar la rama').first);
        await tester.pumpAndSettle();
        expect(find.bySemanticsLabel(RegExp(r'^Desplegar la rama')), findsWidgets);
        await esperarGuardado(tester);
        expect(s.pedidas.where((r) => r.method == 'PATCH'), isEmpty);
      });

      testWidgets('la lista abre el mapa', (tester) async {
        await montar(tester, _grafo(), home: const MapasScreen());
        expect(find.text('Asma'), findsOneWidget);
        await tester.tap(find.text('Asma'));
        await tester.pumpAndSettle();
        expect(find.byType(MapaScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });
  }
}
