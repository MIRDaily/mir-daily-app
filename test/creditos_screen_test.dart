import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mirdaily_app/core/services/creditos_ia_service.dart';
import 'package:mirdaily_app/features/profile/screens/creditos_screen.dart';
import 'package:provider/provider.dart';

CreditosIa _almacen() => CreditosIa(CreditosApi(
      token: () async => 'TOKEN',
      baseUrl: 'https://api.test',
      client: MockClient((req) async {
        switch (req.url.path) {
          case '/api/ia/tarifa':
            return http.Response(jsonEncode({
              'version': 1,
              'claves': {
                'resumenes:resumen': {'fijo': 2.3, 'por_mil': 0.174, 'factores': {'normal': 1}},
                'indice': {'fijo': 0, 'por_mil': 0},
              },
            }), 200);
          case '/api/ia/saldo':
            return http.Response(jsonEncode({
              'plan': 'mensual',
              'estado': 'activo',
              'puede_usar': true,
              'total': 1240,
              'cancelaciones_gratis_mes': 5,
              'cancelaciones_gratis_restantes': 4,
              'bolsas': [
                {'id': 1, 'tipo': 'periodo', 'iniciales': 700, 'saldo': 540, 'caduca_at': '2026-11-03T00:00:00Z'},
                {'id': 2, 'tipo': 'recarga', 'iniciales': 1000, 'saldo': 700, 'caduca_at': '2027-10-03T00:00:00Z', 'congelada': true},
              ],
            }), 200);
          default:
            return http.Response(jsonEncode({
              'movimientos': [
                {'id': 9, 'tipo': 'cargo', 'creditos': -14, 'creado_at': '2026-10-29T10:00:00Z', 'clave': 'resumenes:resumen', 'kind': 'resumenes', 'titulo': 'Lupus eritematoso sistémico'},
                {'id': 8, 'tipo': 'devolucion', 'creditos': 14, 'creado_at': '2026-10-28T10:00:00Z', 'motivo': 'error', 'titulo': 'Vasculitis'},
              ],
              'siguiente': 8,
            }), 200);
        }
      }),
    ));

void main() {
  for (final (nombre, tam) in [('móvil', const Size(360, 780)), ('tablet', const Size(1024, 768))]) {
    testWidgets('créditos de IA en $nombre: saldo, bolsas, ejemplos e historial sin desbordes', (tester) async {
      tester.view.physicalSize = tam;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(ChangeNotifierProvider<CreditosIa>.value(
        value: _almacen(),
        child: const MaterialApp(home: CreditosScreen()),
      ));
      await tester.pumpAndSettle();

      expect(find.text('1.240'), findsOneWidget);
      expect(find.text('Activo'), findsOneWidget);
      expect(find.textContaining('congelados'), findsOneWidget);
      expect(find.textContaining('te quedan 4 de 5'), findsOneWidget);
      expect(find.text('Qué gasta y qué no'.toUpperCase()), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Ver más'), 300);
      expect(find.text('Resumen activo · Lupus eritematoso sistémico'), findsOneWidget);
      expect(find.text('−14'), findsOneWidget);
      expect(find.text('+14'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
