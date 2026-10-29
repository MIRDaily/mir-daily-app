// Resúmenes activos, tanda 3: acciones en bloque y previsión (API), «Más» y «Rehacer» con su cobro,
// y las pantallas (grupo con selección y previsión, ajustes del estudio, estudio con «Escribir la
// respuesta» y deslizar). En móvil y tablet, sin desbordes.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mirdaily_app/core/models/creditos_ia.dart';
import 'package:mirdaily_app/core/models/resumen.dart';
import 'package:mirdaily_app/core/services/ia_service.dart';
import 'package:mirdaily_app/core/theme/app_theme.dart';
import 'package:mirdaily_app/features/resumenes/resumen_detail_screen.dart';
import 'package:mirdaily_app/features/resumenes/resumen_study_screen.dart';
import 'package:mirdaily_app/features/resumenes/resumenes_api.dart';
import 'package:mirdaily_app/features/resumenes/resumenes_ia.dart';
import 'package:mirdaily_app/features/resumenes/resumenes_logica.dart';
import 'package:mirdaily_app/features/resumenes/widgets/ajustes_estudio_resumen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _texto = 'La gota se trata con colchicina y la crisis con AINE.';
Map<String, dynamic> _parrafo(int item, String tema, {String status = 'new', List<int>? fallados}) => {
      'itemId': item,
      'id': 'p$item',
      'tema': tema,
      'modo': 'resumen',
      'texto': _texto,
      'huecos': [
        {'i': 26, 'f': 36, 'n': 2},
        {'i': 50, 'f': 54, 'n': 1},
      ],
      'status': status,
      'due': true,
      if (fallados != null) 'huecosFallados': fallados,
    };

const _prevision = {
  'grupos': 1,
  'parrafos': 3,
  'nuevos': 2,
  'pendientes': 3,
  'repasoAhora': 1,
  'prevision': {
    'atrasados': 1,
    'hoy': 1,
    'manana': 0,
    'semana': 2,
    'mes': 3,
    'dias': [
      {'fecha': '2026-10-29', 'n': 1},
      {'fecha': '2026-10-30', 'n': 0},
      {'fecha': '2026-11-02', 'n': 2},
    ],
  },
  'estados': {'new': 2, 'failed': 1, 'learning': 0, 'mastered': 0},
  'retencion': {'programados': 4, 'recordados': 3, 'tasa': 0.75},
  'huecos': {'repasados': 6, 'sabidos': 4, 'tasa': 0.67},
  'masFallados': [
    {'itemId': 3, 'tema': 'Gota', 'hueco': 0, 'texto': 'colchicina', 'nivel': 2, 'fallos': 2, 'intentos': 3, 'falladoAhora': true},
  ],
};

class _Servidor {
  final List<http.Request> pedidas = [];
  int servidos = 0;

  late final http.Client client = MockClient((req) async {
    pedidas.add(req);
    final ruta = req.url.path.replaceFirst('/api/resumenes', '');
    Object cuerpo = switch (ruta) {
      '' => {
          'grupos': [
            {'id': 'g1', 'name': 'Reuma', 'total': 3, 'pendientes': 3},
            {'id': 'g2', 'name': 'Infecciosas', 'total': 5, 'pendientes': 0},
          ],
        },
      '/prevision' || '/g1/prevision' => {'prevision': _prevision},
      '/g1' => {
          'grupo': {'id': 'g1', 'name': 'Reuma'},
          'parrafos': [_parrafo(1, 'Gota'), _parrafo(2, 'Gota', status: 'failed', fallados: [0]), _parrafo(3, 'Lupus')],
        },
      '/g1/sesion' => {'sessionId': 's1'},
      '/g1/siguiente' => servidos++ == 0 ? {'parrafo': _parrafo(1, 'Gota')} : {'done': true},
      '/g1/repaso' => {'grade': 3, 'sugerida': 3},
      '/g1/fin' => {'fallados': []},
      '/g1/bloque' => {'movidos': 2, 'duplicados': 0, 'destino': {'id': 'g2', 'name': 'Infecciosas'}},
      _ => {},
    };
    return http.Response(jsonEncode(cuerpo), 200, headers: {'content-type': 'application/json; charset=utf-8'});
  });

  Map<String, dynamic> cuerpoDe(String ruta) =>
      jsonDecode(pedidas.lastWhere((r) => r.url.path.endsWith(ruta)).body) as Map<String, dynamic>;
}

ResumenesApi _api(_Servidor s) => ResumenesApi(token: () async => 'T', baseUrl: 'https://api.test', client: s.client);

Future<void> _settle(WidgetTester tester, [int frames = 20]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<_Servidor> _montar(WidgetTester tester, Size size, Widget home) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final s = _Servidor();
  await tester.pumpWidget(Provider<ResumenesApi>.value(
    value: _api(s),
    child: MaterialApp(theme: AppTheme.lightTheme, home: home),
  ));
  await _settle(tester);
  return s;
}

void main() {
  group('API', () {
    test('acción en bloque: mover con destino; tema con null lo quita', () async {
      final s = _Servidor();
      final r = await _api(s).accionBloque('g1', 'mover', [1, 2], destino: 'g2');
      expect((r.hechos, r.destino), (2, 'Infecciosas'));
      expect(s.cuerpoDe('/bloque'), {'accion': 'mover', 'itemIds': [1, 2], 'destino': 'g2'});
      await _api(s).accionBloque('g1', 'tema', [1], tema: null);
      expect(s.cuerpoDe('/bloque'), {'accion': 'tema', 'itemIds': [1], 'tema': null});
    });

    test('previsión global y de un grupo', () async {
      final s = _Servidor();
      final g = await _api(s).cargarPrevision();
      expect(s.pedidas.last.url.path, '/api/resumenes/prevision');
      expect((g.pendientes, g.atrasados, g.masFallados.length), (3, 1, 1));
      await _api(s).cargarPrevision('g1');
      expect(s.pedidas.last.url.path, '/api/resumenes/g1/prevision');
    });

    test('«Más» y «Rehacer» mandan el cobro (sin él, con créditos, el servidor rechaza)', () async {
      final cuerpos = <Map<String, dynamic>>[];
      final ia = ResumenesIa(IaService(
        token: () async => 'T',
        baseUrl: 'https://api.test',
        client: MockClient((req) async {
          cuerpos.add(jsonDecode(req.body) as Map<String, dynamic>);
          final r = cuerpos.last.containsKey('rehacer')
              ? {
                  'parrafo': {
                    'tema': 'Gota',
                    'texto': 'Otra versión con colchicina.',
                    'huecos': [
                      {'i': 17, 'f': 27, 'n': 2},
                    ],
                  },
                }
              : {'parrafos': [], 'stats': {'repetidos': 1}};
          return http.Response(jsonEncode(r), 200, headers: {'content-type': 'application/json'});
        }),
      ));
      const cobro = CobroIa(creditosAnunciados: 2, tarifaVersion: 3, idempotencyKey: 'k1');
      final m = await ia.mas(
        titulo: 'T',
        modo: ModoResumen.resumen,
        secciones: const [],
        paginas: 1,
        niveles: const [3, 4],
        tema: 'Gota',
        cantidad: 5,
        existentes: const ['a'],
        vecinos: const ['Lupus'],
        cobro: cobro,
      );
      expect(m.repetidos, 1);
      expect(cuerpos.last['creditosAnunciados'], 2);
      expect(cuerpos.last['idempotencyKey'], 'k1');
      expect(cuerpos.last['ampliar'], {'tema': 'Gota', 'cantidad': 5, 'existentes': ['a'], 'vecinos': ['Lupus']});
      final r = await ia.rehacer(
        titulo: 'T',
        modo: ModoResumen.resumen,
        secciones: const [],
        paginas: 1,
        tema: 'Gota',
        texto: _texto,
        huecos: const [Hueco(26, 36, 2)],
        cobro: cobro,
      );
      expect(r.texto, 'Otra versión con colchicina.');
      expect(cuerpos.last['tarifaVersion'], 3);
    });
  });

  for (final (nombre, tam) in [('móvil', const Size(360, 780)), ('tablet', const Size(1024, 768))]) {
    testWidgets('grupo en $nombre: previsión, filtros por nivel y selección en bloque', (tester) async {
      final s = await _montar(tester, tam, const ResumenDetailScreen(grupo: GrupoResumen(id: 'g1', name: 'Reuma', total: 3, pendientes: 3, resumen: ResumenEstados(nuevo: 2, failed: 1, learning: 0, mastered: 0))));
      expect(find.text('LO QUE TE ESPERA'), findsOneWidget);
      expect(find.text('LOS HUECOS QUE MÁS SE TE RESISTEN'), findsOneWidget);
      expect(find.text('SIGUE FALLADO'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Media (Med)'), 200, scrollable: find.byType(Scrollable).first);
      expect(find.text('Media (Med)'), findsOneWidget, reason: 'filtro de nivel con etiqueta corta');
      // Cada párrafo lleva su lápiz: se mantiene pulsado ahí (el texto son trozos sueltos).
      final lapiz = find.byIcon(Icons.edit_rounded);
      for (var i = 0; i < 10 && lapiz.evaluate().isEmpty; i++) {
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -250));
        await _settle(tester, 3);
      }
      await tester.ensureVisible(lapiz.first);
      await _settle(tester, 3);
      await tester.longPress(lapiz.first);
      await _settle(tester, 5);
      expect(find.text('1 seleccionado'), findsOneWidget);
      await tester.tap(find.byTooltip('Mover a otro grupo'));
      await _settle(tester);
      await tester.tap(find.text('Infecciosas'));
      await _settle(tester);
      expect(s.cuerpoDe('/bloque')['accion'], 'mover');
      expect(s.cuerpoDe('/bloque')['destino'], 'g2');
      expect(find.textContaining('movidos a «Infecciosas»'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('ajustes del estudio en $nombre: cuenta, temas y lo que se guarda', (tester) async {
      AjustesResumen? elegido;
      final ps = [
        for (final (i, t, st) in [(1, 'Gota', EstadoParrafoSrs.new_), (2, 'Gota', EstadoParrafoSrs.failed), (3, 'Lupus', EstadoParrafoSrs.learning)])
          Parrafo(itemId: i, id: 'p$i', tema: t, modo: ModoResumen.resumen, texto: _texto, huecos: const [Hueco(26, 36, 2)], aiGenerated: false, status: st, due: true, fallos: 0),
      ];
      await _montar(
        tester,
        tam,
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  elegido = await showDialog<AjustesResumen>(
                    context: context,
                    builder: (_) => Dialog(child: SizedBox(height: 700, child: AjustesEstudioResumenPanel(grupoName: 'Reuma', parrafos: ps, inicial: const AjustesResumen()))),
                  );
                },
                child: const Text('Estudiar'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Estudiar'));
      await _settle(tester);
      expect(find.text('Vas a estudiar 3 párrafos.'), findsOneWidget);
      await tester.tap(find.text('Lupus'));
      await _settle(tester, 5);
      expect(find.text('Vas a estudiar 2 párrafos.'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Escribir la respuesta'),
        200,
        scrollable: find.descendant(of: find.byType(Dialog), matching: find.byType(Scrollable)).first,
      );
      await _settle(tester, 5);
      await tester.tap(find.text('Escribir la respuesta'));
      await _settle(tester, 5);
      await tester.tap(find.text('Empezar'));
      await _settle(tester);
      expect(elegido?.temas, ['Gota']);
      expect(elegido?.escribir, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('estudio en $nombre: escribir la respuesta, propuesta y deslizar para contestar', (tester) async {
      final s = await _montar(
        tester,
        tam,
        const ResumenStudyScreen(grupoId: 'g1', grupoName: 'Reuma', ajustes: AjustesResumen(niveles: [2], escribir: true), todosLosTemas: ['Gota', 'Lupus']),
      );
      expect(s.cuerpoDe('/sesion')['levels'], [2], reason: 'solo se tapa el nivel elegido');
      expect(find.text('Escribir el último'), findsOneWidget, reason: 'un solo hueco de nivel 2');
      await tester.tap(find.text('Escribir el último'));
      await _settle(tester, 8);
      await tester.enterText(find.byType(TextField), 'Colchicina');
      await tester.tap(find.text('Comprobar'));
      await _settle(tester, 8);
      expect(find.textContaining('coincide', findRichText: true), findsOneWidget);
      // Deslizar a la derecha = «Lo sabía».
      await tester.drag(find.textContaining('La gota', findRichText: true).first, const Offset(220, 0));
      await _settle(tester, 8);
      expect(find.text('Siguiente'), findsOneWidget);
      await tester.tap(find.text('Siguiente'));
      await _settle(tester, 20);
      final repaso = s.cuerpoDe('/repaso');
      expect(repaso['huecos'], [
        {'i': 26, 'f': 36, 'sabia': true},
      ]);
      expect(find.text('Sesión terminada'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  test('estudiarResumenes existe para la lista y el grupo', () {
    expect(estudiarResumenes, isA<Function>());
  });
}
