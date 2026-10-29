// Tanda 7b: la pantalla de la guía con los datos reales de las 7 guías (assets/guides/), en móvil y tablet
// sin desbordes; corregirse una pregunta, el marcador, saltar a un tema y reportar un trozo de la guía
// (contentType 'guide', guideRef `<guía>/q<n>` y la foto de la pregunta, como la web).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mirdaily_app/core/services/guias_assets.dart';
import 'package:mirdaily_app/core/services/reportes_api.dart';
import 'package:mirdaily_app/core/theme/app_theme.dart';
import 'package:mirdaily_app/features/library/guia/guia_screen.dart';
import 'package:provider/provider.dart';

final _tamanos = [('móvil', const Size(360, 780)), ('tablet', const Size(1024, 768))];
const _claves = ['neurologia', 'cirugia-general', 'reumatologia', 'inmunologia', 'oftalmologia', 'urologia', 'dermatologia'];

void _tam(WidgetTester tester, Size s) {
  tester.view.physicalSize = s;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _asentar(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Widget _app(Widget home, {List<Map<String, dynamic>>? envios}) => Provider<ReportesApi>.value(
      value: ReportesApi(
        token: () async => 'TOKEN',
        baseUrl: 'https://api.test',
        client: MockClient((req) async {
          if (req.url.path.endsWith('/mine')) return http.Response('{"reports":[]}', 200);
          envios?.add(jsonDecode(req.body) as Map<String, dynamic>);
          return http.Response('{"ok":true,"updated":false}', 200);
        }),
      ),
      child: MaterialApp(theme: AppTheme.lightTheme, home: home),
    );

/// Lee los assets del disco y de forma síncrona: con `rootBundle`, la carga que empieza la pantalla dentro
/// del reloj falso de testWidgets no termina nunca (y `rootBundle` la guarda en caché).
class _Disco extends AssetBundle {
  @override
  Future<ByteData> load(String key) async => ByteData.sublistView(File(key).readAsBytesSync());

  @override
  Future<String> loadString(String key, {bool cache = true}) => SynchronousFuture(File(key).readAsStringSync());
}

void main() {
  setUp(() {
    GuiasAssets.olvidar();
    GuiasAssets.bundle = _Disco();
  });

  for (final (nombre, tam) in _tamanos) {
    for (final clave in _claves) {
      testWidgets('$clave en $nombre: se pinta entera sin desbordes', (tester) async {
        _tam(tester, tam);
        await tester.pumpWidget(_app(GuiaScreen(clave: clave)));
        await _asentar(tester);
        expect(find.textContaining('Guía de estudio · MIR 2027'), findsOneWidget);
        expect(tester.takeException(), isNull);
        // Recorre la página hasta el final: todo se construye y nada se sale.
        final lista = find.byType(Scrollable).first;
        for (var i = 0; i < 40; i++) {
          await tester.drag(lista, const Offset(0, -700));
          await tester.pump(const Duration(milliseconds: 30));
          expect(tester.takeException(), isNull, reason: 'paso $i');
        }
        expect(find.text('¿Has visto un error en esta guía?'), findsOneWidget);
      });
    }

    testWidgets('urología en $nombre: corregir, marcador, reintentar y saltar al tema', (tester) async {
      _tam(tester, tam);
      await tester.pumpWidget(_app(const GuiaScreen(clave: 'urologia')));
      await _asentar(tester);

      // El índice lleva al MIR comentado.
      // El chip del índice (fila con scroll horizontal): primero se trae a la vista.
      await tester.ensureVisible(find.text('MIR 2026 comentado').first);
      await _asentar(tester);
      await tester.tap(find.text('MIR 2026 comentado').first);
      await _asentar(tester);
      expect(find.textContaining('Marca tu respuesta y pulsa'), findsOneWidget);

      final ver = find.text('Ver respuesta').first;
      await tester.ensureVisible(ver);
      await _asentar(tester);
      await tester.tap(ver);
      await _asentar(tester);
      expect(find.textContaining('Sin marcar · la correcta es la'), findsOneWidget);
      expect(find.text('1 de 11 corregidas'), findsOneWidget);
      expect(find.text('1 sin marcar'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(find.text('Empezar de nuevo'));
      await _asentar(tester);
      await tester.tap(find.text('Empezar de nuevo'));
      await _asentar(tester);
      expect(find.textContaining('Sin marcar · la correcta es la'), findsNothing);
      expect(find.textContaining('Marca tu respuesta y pulsa'), findsOneWidget);

      // «Repasar el tema» abre la tarjeta del tema y baja hasta ella.
      await tester.ensureVisible(find.text('Ver respuesta').first);
      await _asentar(tester);
      await tester.tap(find.text('Ver respuesta').first);
      await _asentar(tester);
      final repasar = find.text('Repasar el tema →').first;
      await tester.ensureVisible(repasar);
      await _asentar(tester);
      await tester.tap(repasar);
      await _asentar(tester);
      expect(find.text('Lo que tienes que saber'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('reportar una pregunta de la guía en $nombre manda la foto y la referencia', (tester) async {
      _tam(tester, tam);
      final envios = <Map<String, dynamic>>[];
      await tester.pumpWidget(_app(const GuiaScreen(clave: 'urologia'), envios: envios));
      await _asentar(tester);
      // El chip del índice (fila con scroll horizontal): primero se trae a la vista.
      await tester.ensureVisible(find.text('MIR 2026 comentado').first);
      await _asentar(tester);
      await tester.tap(find.text('MIR 2026 comentado').first);
      await _asentar(tester);
      final bandera = find.byIcon(Icons.report_outlined).first;
      await tester.ensureVisible(bandera);
      await _asentar(tester);
      await tester.tap(bandera);
      await _asentar(tester);
      expect(find.text('Reportar un error'), findsOneWidget);
      expect(find.text('Dato incorrecto'), findsOneWidget);
      expect(find.text('Problema con la imagen'), findsNothing, reason: 'las de imagen y duplicada son solo del banco');
      await tester.tap(find.text('Errata en enunciado u opciones'));
      await _asentar(tester);
      await tester.tap(find.text('Enviar'));
      await _asentar(tester);
      final b = envios.single;
      expect(b['contentType'], 'guide');
      expect(b['guideRef'], matches(RegExp(r'^urologia/q\d+$')));
      expect(b['origin'], 'guide');
      expect((b['snapshot'] as Map)['guide_title'], 'Urología');
      expect((b['snapshot'] as Map)['stem'], isA<String>());
      expect(b.containsKey('questionId'), isFalse);
      await tester.pump(const Duration(seconds: 3));
      await _asentar(tester);
      expect(tester.takeException(), isNull);
    });
  }
}
