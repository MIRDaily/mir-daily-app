// Tanda 7a: la Biblioteca real por carpetas. Lógica con los casos de test/carpetasBiblioteca.test.ts y
// test/carpetasDominio.test.ts de la web (con el MISMO catálogo real de producción), las rutas de
// /api/carpetas con MockClient y las cuatro pantallas (portada, asignatura, carpeta, sin clasificar) en
// móvil y tablet sin desbordes.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mirdaily_app/core/models/analytics.dart';
import 'package:mirdaily_app/core/models/biblioteca.dart';
import 'package:mirdaily_app/core/services/api_service.dart';
import 'package:mirdaily_app/core/services/auth_service.dart';
import 'package:mirdaily_app/core/services/carpetas.dart';
import 'package:mirdaily_app/core/theme/app_theme.dart';
import 'package:mirdaily_app/features/library/asignatura_biblioteca_screen.dart';
import 'package:mirdaily_app/features/library/carpeta_biblioteca_screen.dart';
import 'package:mirdaily_app/features/library/library_screen.dart';
import 'package:mirdaily_app/features/library/sin_clasificar_screen.dart';
import 'package:provider/provider.dart';

final _crudo = jsonDecode(File('test/fixtures/catalogo-2026-10-16.json').readAsStringSync()) as List;
final arbol = _crudo.map(AsignaturaCatalogo.fromJson).whereType<AsignaturaCatalogo>().toList();
final reuma = arbol.firstWhere((a) => a.nombre == 'Reumatología');
final lupus = reuma.temas.firstWhere((t) => t.nombre == 'Lupus eritematoso sistémico');
final vasc = reuma.temas.firstWhere((t) => RegExp('vasculitis', caseSensitive: false).hasMatch(t.nombre));

ElementoMaterial el(TipoElemento tipo, String id, {String titulo = 'X', Carpeta carpeta = Carpeta.sinClasificar, ({String? descripcion, List<String> etiquetas, List<String> fuentes})? textos}) =>
    ElementoMaterial(tipo: tipo, id: id, titulo: titulo, carpeta: carpeta, elementos: tipo == TipoElemento.mapa ? null : 3, textos: textos);

final _tamanos = [('móvil', const Size(360, 780)), ('tablet', const Size(1024, 768))];

void _tam(WidgetTester tester, Size s) {
  tester.view.physicalSize = s;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// El servidor de mentira de /api/carpetas: Reumatología con un mapa en Lupus, un grupo de flashcards
/// en General, y un resumen sin clasificar que se parece a Lupus.
CarpetasApi _carpetas(List<String> pedidas, {bool dominio = true}) => CarpetasApi(
      token: () async => 'TOKEN',
      baseUrl: 'https://api.test',
      client: MockClient((req) async {
        pedidas.add('${req.method} ${req.url.path}${req.body.isEmpty ? '' : ' ${req.body}'}');
        final p = req.url.path;
        Map<String, dynamic> arbolJson(AsignaturaCatalogo a) => {
              'id': a.id,
              'nombre': a.nombre,
              'nombreCorto': a.nombreCorto,
              'sigla': a.sigla,
              'temas': [for (final t in a.temas) {'id': t.id, 'nombre': t.nombre}],
            };
        if (p.endsWith('/arbol')) return http.Response(jsonEncode({'asignaturas': [for (final a in arbol) arbolJson(a)]}), 200);
        if (p.endsWith('/recuento')) {
          return http.Response(jsonEncode({
            'total': 3,
            'sinClasificar': {'total': 1, 'mapas': 0, 'flashcards': 0, 'resumenes': 1},
            'asignaturas': [
              {
                'id': reuma.id, 'total': 2, 'mapas': 1, 'flashcards': 1, 'resumenes': 0,
                'general': {'total': 1, 'mapas': 0, 'flashcards': 1, 'resumenes': 0},
                'temas': [{'id': lupus.id, 'total': 1, 'mapas': 1, 'flashcards': 0, 'resumenes': 0}],
              },
            ],
          }), 200);
        }
        if (p.endsWith('/sin-clasificar')) {
          return http.Response(jsonEncode({
            'elementos': [
              {
                'tipo': 'resumenes', 'id': 'r1', 'titulo': 'Repaso del martes', 'actualizado': '2026-10-28T10:00:00Z',
                'carpeta': {'subjectId': null, 'topicId': null}, 'elementos': 6,
                'textos': {'descripcion': null, 'etiquetas': ['Lupus', 'Lupus eritematoso sistémico'], 'fuentes': ['Tema_06_Lupus.pdf']},
              },
            ],
          }), 200);
        }
        if (p.endsWith('/dominio')) {
          if (!dominio) return http.Response(jsonEncode({'disponible': false, 'carpetas': []}), 200);
          return http.Response(jsonEncode({
            'disponible': true,
            'carpetas': [
              {
                'topicId': null, 'elementos': 20, 'estudiados': 16, 'dominio': 0.84, 'cobertura': 0.8, 'ultimoRepaso': DateTime.now().toUtc().toIso8601String(),
                'grupos': [{'deckId': 'f1', 'tipo': 'flashcards', 'elementos': 20, 'estudiados': 16, 'dominio': 0.84, 'cobertura': 0.8}],
                'huecosDebiles': [{'itemId': 1, 'hueco': 0, 'texto': 'anti-ADNdc', 'fallos': 3, 'intentos': 4, 'falladoAhora': true}],
              },
            ],
          }), 200);
        }
        if (RegExp(r'/asignatura/\d+$').hasMatch(p)) {
          return http.Response(jsonEncode({
            'asignatura': arbolJson(reuma),
            'preguntas': {'total': 120, 'porTema': {'${lupus.id}': 14}},
            'elementos': [
              {'tipo': 'mapa', 'id': 'm1', 'titulo': 'Lupus en un mapa', 'actualizado': '2026-10-20T10:00:00Z', 'carpeta': {'subjectId': reuma.id, 'topicId': lupus.id}, 'elementos': null},
              {'tipo': 'flashcards', 'id': 'f1', 'titulo': 'Reuma general', 'actualizado': '2026-10-21T10:00:00Z', 'carpeta': {'subjectId': reuma.id, 'topicId': null}, 'elementos': 20},
            ],
          }), 200);
        }
        if (req.method == 'PATCH') return http.Response(jsonEncode({'movidos': 1}), 200);
        return http.Response('{"error":"no"}', 404);
      }),
    );

class _ApiFalsa extends ApiService {
  _ApiFalsa() : super(AuthService());

  @override
  Future<SubjectHeatmapResponse> getSubjectHeatmap(AnalyticsWindow window, AnalyticsMode mode) async => SubjectHeatmapResponse.fromJson({
        'window': 'all',
        'subjects': [
          {'subjectId': reuma.id, 'name': 'Reumatología', 'correct': 30, 'wrong': 10, 'blank': 0, 'total': 40, 'accuracy': 75},
        ],
      });

  @override
  Future<TopicHeatmapResponse> getTopicHeatmap(int subjectId, AnalyticsWindow window, AnalyticsMode mode) async => TopicHeatmapResponse.fromJson({
        'subjectId': subjectId,
        'window': 'all',
        'topics': [
          {'topicId': lupus.id, 'name': lupus.nombre, 'correct': 4, 'wrong': 4, 'blank': 2, 'total': 10, 'accuracy': 40},
        ],
      });
}

Widget _app(CarpetasApi carpetas, Widget home) => MultiProvider(
      providers: [
        Provider<CarpetasApi>.value(value: carpetas),
        Provider<ApiService>.value(value: _ApiFalsa()),
      ],
      child: MaterialApp(theme: AppTheme.lightTheme, home: home),
    );

void main() {
  group('lógica (casos de la web)', () {
    test('portada: TODAS las asignaturas, con lo que el usuario tiene en cada una', () {
      final recuento = Recuento.fromJson({
        'total': 4,
        'sinClasificar': {'total': 1, 'mapas': 1, 'flashcards': 0, 'resumenes': 0},
        'asignaturas': [
          {
            'id': reuma.id, 'total': 3, 'mapas': 2, 'flashcards': 1, 'resumenes': 0,
            'general': {'total': 1, 'mapas': 0, 'flashcards': 1, 'resumenes': 0},
            'temas': [{'id': lupus.id, 'total': 2, 'mapas': 2, 'flashcards': 0, 'resumenes': 0}],
          },
        ],
      });
      final t = tarjetasAsignaturas(arbol, recuento);
      expect(t.length, arbol.length);
      final r = t.firstWhere((x) => x.asignatura.id == reuma.id);
      expect([r.cuenta.total, r.temasConMaterial, r.tieneGeneral], [3, 1, true]);
      expect(r.carpetas, 2);
      final otra = t.firstWhere((x) => x.asignatura.id != reuma.id);
      expect([otra.cuenta.total, otra.temasConMaterial, otra.tieneGeneral], [0, 0, false]);
      expect(tarjetasAsignaturas(arbol, null).every((x) => x.cuenta.total == 0), isTrue);
    });

    test('textoCuenta en castellano', () {
      expect(textoCuenta(const Cuenta(total: 1, mapas: 1)), '1 mapa');
      expect(textoCuenta(const Cuenta(total: 6, mapas: 2, flashcards: 1, resumenes: 3)), '2 mapas · 1 grupo de flashcards · 3 grupos de resúmenes');
      expect(textoCuenta(Cuenta.vacia), '');
    });

    test('carpetas: General primero y solo temas con material, en el orden del catálogo', () {
      final elementos = [
        el(TipoElemento.mapa, 'a', carpeta: Carpeta(subjectId: reuma.id, topicId: vasc.id)),
        el(TipoElemento.flashcards, 'b', carpeta: Carpeta(subjectId: reuma.id)),
        el(TipoElemento.resumenes, 'c', carpeta: Carpeta(subjectId: reuma.id, topicId: lupus.id)),
        el(TipoElemento.mapa, 'd', carpeta: Carpeta(subjectId: reuma.id, topicId: lupus.id)),
        el(TipoElemento.mapa, 'e', carpeta: Carpeta(subjectId: reuma.id, topicId: 999999)),
        el(TipoElemento.mapa, 'f', carpeta: const Carpeta(subjectId: 2)),
      ];
      final c = carpetasDeAsignatura(reuma, elementos);
      final orden = reuma.temas.map((t) => t.id).toList();
      expect(c.first.topicId, isNull);
      expect(c.first.elementos.map((e) => e.id), ['b', 'e'], reason: 'un tema que ya no está en el catálogo cuenta como General');
      expect(c.skip(1).map((x) => x.topicId), [lupus.id, vasc.id]..sort((x, y) => orden.indexOf(x).compareTo(orden.indexOf(y))));
      expect(c.length, 3);
      final l = c.firstWhere((x) => x.topicId == lupus.id).cuenta;
      expect([l.total, l.mapas, l.flashcards, l.resumenes], [2, 1, 0, 1]);
      expect(carpetasDeAsignatura(reuma, [el(TipoElemento.mapa, 'a', carpeta: Carpeta(subjectId: reuma.id, topicId: lupus.id))]).map((x) => x.nombre),
          ['Lupus eritematoso sistémico']);
    });

    test('una selección mezclada se mueve por tipos', () {
      final m = agruparPorTipo([el(TipoElemento.mapa, '1'), el(TipoElemento.resumenes, '2'), el(TipoElemento.mapa, '3')]);
      expect(m[TipoElemento.mapa], ['1', '3']);
      expect(m[TipoElemento.resumenes], ['2']);
    });

    test('sugerencia de lo sin clasificar con el catálogo real', () {
      expect(sugerenciaDe(arbol, el(TipoElemento.mapa, 'm', titulo: 'Tema 06 Lupus eritematoso sistemico')), Carpeta(subjectId: reuma.id, topicId: lupus.id));
      expect(
        sugerenciaDe(arbol, el(TipoElemento.resumenes, 'r', titulo: 'Repaso del martes', textos: (descripcion: null, etiquetas: ['Lupus', 'Lupus eritematoso sistémico'], fuentes: ['Tema_06_Lupus.pdf']))),
        Carpeta(subjectId: reuma.id, topicId: lupus.id),
      );
      expect(
        sugerenciaDe(arbol, el(TipoElemento.flashcards, 'f', titulo: 'Reumatología', textos: (descripcion: null, etiquetas: ['Lupus eritematoso sistémico', 'Vasculitis', 'Gota', 'Artritis reumatoide'], fuentes: []))),
        Carpeta(subjectId: reuma.id),
        reason: 'un grupo que mezcla temas de una asignatura va a su General',
      );
      expect(sugerenciaDe(arbol, el(TipoElemento.mapa, 'x', titulo: 'Lista de la compra')), isNull);
    });

    test('dominio: el umbral de «bien llevado» y los estados', () {
      expect(umbralBienLlevado.dominio, 0.8);
      expect(umbralBienLlevado.cobertura, 0.7);
      expect(estadoDominio(elementos: 10, estudiados: 7, dominio: 0.8, cobertura: 0.7), EstadoDominio.bien);
      expect(estadoDominio(elementos: 10, estudiados: 9, dominio: 0.7999, cobertura: 0.9), EstadoDominio.enMarcha);
      expect(estadoDominio(elementos: 10, estudiados: 6, dominio: 0.95, cobertura: 0.6999), EstadoDominio.enMarcha);
      expect(estadoCarpeta(null), EstadoDominio.vacio);
      expect(estadoDominio(elementos: 0, estudiados: 0), EstadoDominio.vacio);
      expect(estadoDominio(elementos: 5, estudiados: 0, dominio: 0, cobertura: 0), EstadoDominio.sinEstudiar);
    });

    test('dominio: porcentajes y hace cuánto en días de calendario', () {
      expect(porcentajeDe(0.7234), 72);
      expect(porcentajeDe(0.725), 73);
      expect(porcentajeDe(1.2), 100);
      expect(porcentajeDe(-0.1), 0);
      expect(textoRecordarias(0.7234), 'recordarías hoy ~72 %');
      final ahora = DateTime(2026, 10, 17, 10);
      expect(haceCuanto(DateTime(2026, 10, 17, 0, 5), ahora: ahora), 'hoy');
      expect(haceCuanto(DateTime(2026, 10, 16, 23, 50), ahora: ahora), 'ayer');
      expect(haceCuanto(DateTime(2026, 10, 12), ahora: ahora), 'hace 5 días');
      expect(haceCuanto(DateTime(2026, 9, 30), ahora: ahora), 'hace 2 semanas');
      expect(haceCuanto(DateTime(2026, 6, 1), ahora: ahora), contains('jun'));
      expect(haceCuanto(DateTime(2025, 6, 1), ahora: ahora), contains('2025'));
      expect(haceCuanto(null, ahora: ahora), isNull);
    });

    test('la respuesta de dominio: «General» por null y los temas por su id', () {
      final r = RespuestaDominio.fromJson({
        'disponible': true,
        'carpetas': [
          {'topicId': null, 'elementos': 4, 'estudiados': 2, 'dominio': 0.5, 'cobertura': 0.5},
          {'topicId': 10, 'elementos': 3, 'estudiados': 0, 'dominio': 0, 'cobertura': 0},
        ],
      });
      expect(r.de(null)!.dominio, 0.5);
      expect(r.de(10)!.estudiados, 0);
      expect(r.de(99), isNull);
      expect(RespuestaDominio.fromJson('basura').disponible, isFalse);
    });

    test('la fila de detalle', () {
      final e = ElementoMaterial(tipo: TipoElemento.flashcards, id: 'f', titulo: 'T', elementos: 1, actualizado: DateTime(2026, 10, 3, 12));
      expect(detalleElemento(e), 'Flashcards · 1 tarjeta · 3 oct');
      expect(detalleElemento(const ElementoMaterial(tipo: TipoElemento.mapa, id: 'm', titulo: 'T')), 'Mapa');
    });
  });

  test('CarpetasApi: recuento, sin clasificar, asignatura y dominio', () async {
    final pedidas = <String>[];
    final api = _carpetas(pedidas);
    expect((await api.recuento()).sinClasificar.resumenes, 1);
    expect((await api.sinClasificar()).single.textos!.fuentes, ['Tema_06_Lupus.pdf']);
    final d = await api.asignatura(reuma.id);
    expect(d.preguntasTotal, 120);
    expect(d.preguntasDe(lupus.id), 14);
    expect(d.preguntasDe(null), 120);
    expect(d.elementos.map((e) => e.tipo), [TipoElemento.mapa, TipoElemento.flashcards]);
    expect((await api.dominio(reuma.id)).de(null)!.huecosDebiles.single.texto, 'anti-ADNdc');
    expect(pedidas, [
      'GET /api/carpetas/recuento',
      'GET /api/carpetas/sin-clasificar',
      'GET /api/carpetas/asignatura/${reuma.id}',
      'GET /api/carpetas/asignatura/${reuma.id}/dominio',
    ]);
  });

  for (final (nombre, tam) in _tamanos) {
    group('en $nombre', () {
      testWidgets('portada: sin clasificar, buscador y la tarjeta con material y acierto', (tester) async {
        _tam(tester, tam);
        await tester.pumpWidget(_app(_carpetas([]), const LibraryScreen()));
        await tester.pumpAndSettle();
        expect(find.text('Sin clasificar · 1'), findsOneWidget);
        expect(find.textContaining('1 grupo de resúmenes sin carpeta'), findsOneWidget);
        expect(find.text('3 en total'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.enterText(find.byType(TextField), 'reuma');
        await tester.pumpAndSettle();
        // La lista es perezosa: la tarjeta solo existe cuando se acerca a la vista.
        await tester.scrollUntilVisible(find.textContaining('75 %', findRichText: true), 200, scrollable: find.byType(Scrollable).first);
        expect(find.text('Reumatología'), findsOneWidget);
        expect(find.text('en 2 carpetas'), findsOneWidget);
        expect(find.textContaining('75 % de acierto', findRichText: true), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.enterText(find.byType(TextField), 'zzzz nada');
        await tester.pumpAndSettle();
        expect(find.text('Nada con «zzzz nada».'), findsOneWidget);
      });

      testWidgets('asignatura: cabecera, General y Lupus, dominio y temas ocultos', (tester) async {
        _tam(tester, tam);
        await tester.pumpWidget(_app(_carpetas([]), AsignaturaBibliotecaScreen(asignatura: reuma)));
        await tester.pumpAndSettle();
        expect(find.text('120'), findsNWidgets(2)); // la cabecera y la carpeta General («toda»)
        expect(find.text('preguntas MIR'), findsOneWidget);
        expect(find.text('General'), findsOneWidget);
        expect(find.text('Lupus eritematoso sistémico'), findsOneWidget);
        expect(find.text('recordarías ~84 %'), findsOneWidget);
        await tester.scrollUntilVisible(find.textContaining('del catálogo sin material'), 200, scrollable: find.byType(Scrollable).first);
        expect(find.textContaining('del catálogo sin material'), findsOneWidget);
        expect(find.textContaining('1 de 1 carpeta con flashcards o resúmenes está bien llevada'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('carpeta General: preguntas, señal de dominio, la fila y «Mover»', (tester) async {
        _tam(tester, tam);
        final pedidas = <String>[];
        await tester.pumpWidget(_app(_carpetas(pedidas), CarpetaBibliotecaScreen(asignatura: reuma, topicId: null)));
        await tester.pumpAndSettle();
        expect(find.text('en toda la asignatura'), findsOneWidget);
        expect(find.text('30 bien'), findsOneWidget);
        expect(find.text('~84 %'), findsOneWidget);
        expect(find.text('Bien llevado'), findsOneWidget);
        expect(find.text('anti-ADNdc'), findsOneWidget);
        expect(find.text('Reuma general'), findsOneWidget);
        expect(find.textContaining('16 de 20 estudiadas'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.ensureVisible(find.text('Mover'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Mover'));
        await tester.pumpAndSettle();
        // El selector de carpetas de la IA, reutilizado.
        expect(find.text('Sin clasificar'), findsWidgets);
        expect(tester.takeException(), isNull);
      });

      testWidgets('carpeta de un tema sin dominio disponible: el hueco «todavía no disponible»', (tester) async {
        _tam(tester, tam);
        await tester.pumpWidget(_app(_carpetas([], dominio: false), CarpetaBibliotecaScreen(asignatura: reuma, topicId: lupus.id)));
        await tester.pumpAndSettle();
        expect(find.text('de este tema'), findsOneWidget);
        expect(find.text('14'), findsOneWidget);
        expect(find.text('40 %'), findsOneWidget);
        expect(find.textContaining('todavía no disponible'), findsOneWidget);
        expect(find.text('Lupus en un mapa'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('sin clasificar: la sugerencia de un toque mueve y quita la fila', (tester) async {
        _tam(tester, tam);
        final pedidas = <String>[];
        await tester.pumpWidget(_app(_carpetas(pedidas), const SinClasificarScreen()));
        await tester.pumpAndSettle();
        expect(find.text('Repaso del martes'), findsOneWidget);
        expect(find.textContaining('¿A Reumatología › Lupus'), findsOneWidget);
        expect(tester.takeException(), isNull);

        // Seleccionar todo saca la barra de abajo.
        await tester.tap(find.text('Seleccionar todo'));
        await tester.pumpAndSettle();
        expect(find.text('1 seleccionado'), findsWidgets);
        expect(find.text('Mover a…'), findsWidgets);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Quitar'));
        await tester.pumpAndSettle();

        await tester.tap(find.textContaining('¿A Reumatología › Lupus'));
        await tester.pumpAndSettle();
        final patch = pedidas.singleWhere((p) => p.startsWith('PATCH'));
        final cuerpo = jsonDecode(patch.substring(patch.indexOf('{'))) as Map<String, dynamic>;
        expect(cuerpo, {'tipo': 'resumenes', 'ids': ['r1'], 'subjectId': reuma.id, 'topicId': lupus.id, 'origen': 'sugerencia'});
        expect(find.text('Repaso del martes'), findsNothing);
        expect(find.textContaining('Movido a'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });
  }
}
