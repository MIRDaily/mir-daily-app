// El aro del nivel sobre el icono de Perfil.
//
//   flutter test test/anillo_nivel_test.dart
//
// La lección que costó tiempo en la web: el aro tiene que caber DENTRO del
// hueco que ya ocupaba el icono. Si crece por fuera sube el alto de toda la
// barra y desplaza el resto, así que aquí se mide — con datos y sin ellos,
// porque el salto se daría justo al llegar el progreso.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mirdaily_app/core/providers/progress_provider.dart';
import 'package:mirdaily_app/core/services/api_service.dart';
import 'package:mirdaily_app/core/services/auth_service.dart';
import 'package:mirdaily_app/features/progress/widgets/anillo_nivel.dart';

/// Un provider que responde con un nivel 12 a medio recorrer.
ProgressProvider _conDatos() {
  final api = ApiService(
    AuthService(),
    client: MockClient((_) async => http.Response(
          jsonEncode({
            'progress': {
              'level': 12,
              'maxLevel': 100,
              'xpTotal': 3665,
              'xpIntoLevel': 90,
              'xpForNext': 475,
              'currentStreak': 4,
              'longestStreak': 9,
              'streakFreezes': 1,
              'streakMultiplier': 1.07,
              'lastActiveDay': '2026-09-08',
              'xpToday': 60,
              'xpTodayTotal': 60,
              'dailyCap': 300,
            },
            'daily': const [],
            'weekly': const [],
          }),
          200,
          headers: {'content-type': 'application/json'},
        )),
  )..session = AuthSession(
      accessToken: 't',
      refreshToken: 'r',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
      userId: 'u1',
    );
  return ProgressProvider(api);
}

/// La misma caja que le da la barra inferior: 58 px de alto por 76 de ancho.
Widget _barra({ProgressProvider? p}) {
  const arbol = MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          height: 58,
          width: 76,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnilloNivel(lado: 26, child: Icon(Icons.person, size: 22)),
              SizedBox(height: 3),
              Text('Perfil', style: TextStyle(fontSize: 11)),
            ],
          ),
        ),
      ),
    ),
  );
  return p == null
      ? arbol
      : ChangeNotifierProvider<ProgressProvider>.value(value: p, child: arbol);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // El provider guarda la referencia de logros en shared_preferences. Sin
    // valores de mentira, el canal de plataforma no contesta nunca y el test
    // se queda colgado esperando.
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('fuera del provider el icono se pinta tal cual, sin reventar',
      (tester) async {
    // La barra se monta en sitios donde no está el árbol entero: un adorno no
    // puede tumbar la navegación.
    await tester.pumpWidget(_barra());
    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.person), findsOneWidget);
    expect(tester.getSize(find.byType(AnilloNivel)), const Size(26, 26));
  });

  testWidgets('el hueco es el mismo antes y después de llegar el progreso',
      (tester) async {
    final p = _conDatos();
    addTearDown(p.dispose);

    await tester.pumpWidget(_barra(p: p));
    // Sin datos todavía: mejor sin aro que con un aro a cero, que se leería
    // como "vas por 0".
    expect(tester.getSize(find.byType(AnilloNivel)), const Size(26, 26));
    final altoSinDatos = tester.getSize(find.byType(Column).first);

    // runAsync porque la recarga toca red y disco de mentira: dentro del
    // reloj falso de testWidgets esos futuros no avanzarían solos.
    await tester.runAsync(() async {
      p.setAutenticado(true);
      await p.refresh();
    });
    await tester.pump();

    // Ya con nivel 12: el aro y el número están dentro del MISMO hueco, y la
    // columna de la pestaña no ha crecido ni un píxel.
    expect(find.text('12'), findsOneWidget, reason: 'el número, pegado al aro');
    expect(tester.getSize(find.byType(AnilloNivel)), const Size(26, 26));
    expect(tester.getSize(find.byType(Column).first), altoSinDatos,
        reason: 'si el aro creciera por fuera, subiría el alto de la barra');
    expect(tester.takeException(), isNull, reason: 'y sin desbordar');
  });
}
