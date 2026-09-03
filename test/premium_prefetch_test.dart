// La precarga del mapa de calor y su caché, contadas en peticiones HTTP.
//
//   flutter test test/premium_prefetch_test.dart
//
// Existe porque el desglose de una asignatura costaba ~790 ms de red CADA vez
// que se abría, y porque la caché que lo arregló es estática: si deja de
// filtrar por asignatura+ventana+modo, o deja de caducar, el panel enseñaría
// datos viejos sin fallar de forma ruidosa.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:mirdaily_app/core/services/api_service.dart';
import 'package:mirdaily_app/core/services/auth_service.dart';
import 'package:mirdaily_app/core/theme/app_theme.dart';
import 'package:mirdaily_app/features/premium/widgets/panel_subsections.dart';

/// Apunta cada ruta pedida y responde con datos mínimos pero válidos.
class _Espia {
  final List<String> rutas = [];

  /// Asignaturas con pesos MUY distintos: así se ve si la precarga elige por
  /// número de preguntas o simplemente coge las primeras.
  final List<Map<String, Object>> asignaturas;

  _Espia(this.asignaturas);

  late final http.Client client = MockClient((req) async {
    final ruta = '${req.url.path}?${req.url.query}';
    rutas.add(ruta);

    if (req.url.path.endsWith('/heatmap/subjects')) {
      return http.Response(
        jsonEncode({'subjects': asignaturas}),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    if (req.url.path.endsWith('/heatmap/topics')) {
      return http.Response(jsonEncode({'topics': []}), 200,
          headers: {'content-type': 'application/json'});
    }
    if (req.url.path.endsWith('/trend')) {
      return http.Response(jsonEncode({'points': []}), 200,
          headers: {'content-type': 'application/json'});
    }
    return http.Response('{}', 200,
        headers: {'content-type': 'application/json'});
  });

  int contar(String fragmento) =>
      rutas.where((r) => r.contains(fragmento)).length;
}

ApiService _api(_Espia espia) => ApiService(AuthService(), client: espia.client)
  ..session = AuthSession(
    accessToken: 'token-de-prueba',
    refreshToken: 'r',
    expiresAt: DateTime.now().add(const Duration(hours: 1)),
    userId: 'u1',
  );

Map<String, Object> _asig(int id, String nombre, int total) => {
      'subjectId': id,
      'name': nombre,
      'correct': total,
      'wrong': 0,
      'blank': 0,
      'total': total,
      'accuracy': 100,
    };

Future<void> _montar(WidgetTester tester, _Espia espia) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1200, 2000);
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    Provider<ApiService>.value(
      value: _api(espia),
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: const Scaffold(
          body: SingleChildScrollView(child: SubjectHeatmapSubsection()),
        ),
      ),
    ),
  );

  // La rejilla llega tras su petición; la precarga espera 500 ms más y va de
  // una asignatura en una, así que hay que dejar correr el reloj.
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  testWidgets('precarga las 4 asignaturas con mas preguntas, y solo esas',
      (tester) async {
    // Ids altos y distintos en cada test: la caché es estática y vive entre
    // tests dentro del mismo fichero.
    final espia = _Espia([
      _asig(101, 'Poca A', 3),
      _asig(102, 'Muchisima', 600),
      _asig(103, 'Poca B', 1),
      _asig(104, 'Mucha', 90),
      _asig(105, 'Media alta', 40),
      _asig(106, 'Media', 25),
      _asig(107, 'Sin actividad', 0),
    ]);

    await _montar(tester, espia);
    expect(tester.takeException(), isNull);

    // Cuatro asignaturas x dos endpoints.
    expect(espia.contar('/heatmap/topics'), 4);
    expect(espia.contar('/trend'), 4);

    // Y son las de más peso, no las primeras de la lista.
    for (final id in [102, 104, 105, 106]) {
      expect(espia.contar('subjectId=$id'), 2, reason: 'precargada $id');
    }
    for (final id in [101, 103, 107]) {
      expect(espia.contar('subjectId=$id'), 0, reason: 'NO precargada $id');
    }
  });

  testWidgets('abrir una asignatura precargada no vuelve a la red',
      (tester) async {
    final espia = _Espia([
      _asig(201, 'Pesada', 500),
      _asig(202, 'Ligera', 2),
    ]);

    await _montar(tester, espia);
    final trasPrecarga = espia.rutas.length;
    expect(espia.contar('subjectId=201'), 2, reason: 'la precargó');

    // Abrir la pesada: sale de la caché, sin pedir nada.
    await tester.tap(find.text('PESADA'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(tester.takeException(), isNull);
    expect(espia.rutas.length, trasPrecarga,
        reason: 'ni una petición más al abrir lo ya precargado');

    // La ligera no se precargó, así que esa sí va a la red.
    await tester.tap(find.text('LIGERA'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(espia.contar('subjectId=202'), 2,
        reason: 'la no precargada sí se pide');
  });
}
