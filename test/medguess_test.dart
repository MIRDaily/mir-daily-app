// Tanda 10: MedGuess. Modelo, cliente, controlador y pantalla (móvil 360×780 y tablet 1024×768).
//
//   flutter test test/medguess_test.dart
//
// `_Servidor` reproduce la lógica de src/services/medguessService.js del backend (máscaras, found /
// known / absent, una pista por fallo, 6 intentos) para que los tests jueguen partidas de verdad.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:mirdaily_app/core/models/medguess.dart';
import 'package:mirdaily_app/core/services/medguess_api.dart';
import 'package:mirdaily_app/core/theme/app_theme.dart';
import 'package:mirdaily_app/features/medguess/medguess_controller.dart';
import 'package:mirdaily_app/features/medguess/medguess_screen.dart';

class _Servidor {
  final List<String> terminos;
  final List<String> pistas = const ['Sibilancias espiratorias', 'Responde a broncodilatadores', 'Eosinofilia'];
  final Set<String> diccionario = const {
    'casas', 'malas', 'sabio', 'perro', 'lunes', 'gordo', 'cupid', 'tribu', 'dulce', 'hielo', //
  };
  final List<Map<String, dynamic>> intentos = [];
  final List<http.Request> pedidas = [];
  bool resuelto = false;
  String? errorHoy;

  _Servidor({this.terminos = const ['Asma', 'Broncoespasmo']});

  static String _sinTildes(String s) => s
      .toLowerCase()
      .replaceAll(RegExp('[áà]'), 'a')
      .replaceAll(RegExp('[éè]'), 'e')
      .replaceAll(RegExp('[íì]'), 'i')
      .replaceAll(RegExp('[óò]'), 'o')
      .replaceAll(RegExp('[úùü]'), 'u')
      .replaceAll('ñ', 'n')
      .replaceAll(RegExp('[^a-z]'), '');

  Set<String> get _objetivo => {for (final t in terminos) ..._sinTildes(t).split('')};

  Set<String> get _descubiertas => {
        for (final a in intentos)
          for (var i = 0; i < 5; i++)
            if ((a['result'] as List)[i] != 'absent') (a['guess'] as String)[i],
      };

  bool get _terminado => resuelto || intentos.length >= 6;

  Map<String, dynamic> _estado() {
    final d = _descubiertas;
    final fallos = resuelto ? intentos.length - 1 : intentos.length;
    return {
      'category': 'Neumología',
      'maxAttempts': 6,
      'attemptsUsed': intentos.length,
      'solved': resuelto,
      'isFinished': _terminado,
      'discoveredLetters': d.toList(),
      'cluesUnlocked': pistas.take(fallos.clamp(0, pistas.length)).toList(),
      'totalClues': pistas.length,
      'terms': [
        for (final t in terminos)
          {
            'display': t,
            'mask': t.split('').map((c) {
              final l = _sinTildes(c);
              return l.isEmpty ? c : (d.contains(l) ? c : '_');
            }).join(),
          },
      ],
      'attempts': intentos,
    };
  }

  http.Response _json(Object o, [int status = 200]) =>
      http.Response.bytes(utf8.encode(jsonEncode(o)), status, headers: {'content-type': 'application/json'});

  Future<http.Response> responder(http.Request r) async {
    pedidas.add(r);
    if (r.url.path.endsWith('/today')) {
      if (errorHoy != null) return _json({'error': errorHoy}, 500);
      return _json(_estado());
    }
    final palabra = _sinTildes((jsonDecode(r.body) as Map)['guess'] as String);
    if (resuelto) return _json({'error': 'Already solved'}, 400);
    if (palabra.length != 5) return _json({'error': 'Guess must be exactly 5 letters'}, 400);
    if (!diccionario.contains(palabra)) return _json({'error': 'INVALID_WORD'}, 400);
    final antes = _descubiertas;
    final obj = _objetivo;
    final res = [
      for (final l in palabra.split('')) obj.contains(l) ? (antes.contains(l) ? 'known' : 'found') : 'absent',
    ];
    intentos.add({'guess': palabra, 'result': res, 'attempt_number': intentos.length + 1});
    final d = _descubiertas;
    resuelto = terminos.any((t) => _sinTildes(t).split('').every(d.contains));
    final e = _estado();
    return _json({
      'attempt': {'guess': palabra, 'result': res, 'attemptNumber': intentos.length},
      ...e,
      'finished': _terminado ? {'success': resuelto, 'answer': terminos.first, 'terms': terminos} : null,
    });
  }

  MedGuessApi api() => MedGuessApi(token: () async => 'tok', baseUrl: 'https://api.test', client: MockClient(responder));
}

const _movil = Size(360, 780);
const _tablet = Size(1024, 768);

Future<void> _montar(WidgetTester tester, Size size, _Servidor s) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(theme: AppTheme.lightTheme, home: MedGuessScreen(api: s.api())));
  await tester.pumpAndSettle();
}

Future<void> _escribir(WidgetTester tester, String palabra) async {
  for (final l in palabra.toUpperCase().split('')) {
    await tester.tap(find.bySemanticsLabel(l).last);
    await tester.pump(const Duration(milliseconds: 30));
  }
}

Future<void> _enviar(WidgetTester tester) async {
  await tester.tap(find.bySemanticsLabel('Enviar intento'));
  await tester.pumpAndSettle();
  // El resultado sale con un temporizador, al acabar de voltearse las casillas.
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpAndSettle();
}

void main() {
  group('modelo', () {
    test('mientras se juega NO se pinta el término completo, aunque el servidor lo mande', () {
      final e = EstadoMedGuess.fromJson({
        'attemptsUsed': 1,
        'solved': false,
        'isFinished': false,
        'terms': [
          {'display': 'Asma bronquial', 'mask': 'As_a ___n__a_'},
        ],
        'attempts': [
          {'guess': 'casas', 'result': ['absent', 'found', 'found', 'known', 'known']},
        ],
      });
      expect(e.terminado, isFalse);
      expect(e.respuesta, isNull);
      expect(e.terminos.single.completo, isNull);
      expect(e.terminos.single.casillas.join('|'), contains('A|S|null|A'));
      expect(e.terminos.single.palabras, hasLength(2), reason: 'dos palabras: no se parten de línea');
      expect(e.intentos.single.palabra, 'CASAS');
      expect(e.intentos.single.resultado, [
        LetraMedGuess.ausente,
        LetraMedGuess.encontrada,
        LetraMedGuess.encontrada,
        LetraMedGuess.conocida,
        LetraMedGuess.conocida,
      ]);
    });

    test('al terminar, la respuesta y los términos completos', () {
      final e = EstadoMedGuess.fromJson({
        'attemptsUsed': 6,
        'solved': false,
        'terms': [
          {'display': 'Asma', 'mask': 'As_a'},
        ],
        'finished': {'success': false, 'answer': 'Asma'},
      });
      expect(e.terminado, isTrue);
      expect(e.respuesta, 'ASMA');
      expect(e.terminos.single.casillas, ['A', 'S', 'M', 'A']);
      expect(e.intentosRestantes, 0);
    });

    test('intentos mal formados se descartan', () {
      final e = EstadoMedGuess.fromJson({
        'attempts': [
          {'guess': 'casa', 'result': ['absent', 'absent', 'absent', 'absent']},
          {'guess': 'casas', 'result': 'x'},
          null,
        ],
      });
      expect(e.intentos, isEmpty);
    });

    test('lo tecleado: solo A-Z, sin tildes, como mucho 5', () {
      expect(limpiarIntentoMedGuess('árbol'), 'ARBOL');
      expect(limpiarIntentoMedGuess('niño s7'), 'NINOS');
      expect(limpiarIntentoMedGuess('abcdefg'), 'ABCDE');
    });

    test('el teclado guarda lo mejor que se sabe de cada letra', () {
      final t = estadoTeclasMedGuess([
        const IntentoMedGuess('CASAS', [
          LetraMedGuess.ausente,
          LetraMedGuess.encontrada,
          LetraMedGuess.encontrada,
          LetraMedGuess.conocida,
          LetraMedGuess.conocida,
        ]),
      ]);
      expect(t['C'], LetraMedGuess.ausente);
      expect(t['A'], LetraMedGuess.encontrada);
      expect(t['S'], LetraMedGuess.encontrada);
    });

    test('los errores del servidor, en castellano', () {
      expect(mensajeErrorMedGuess('INVALID_WORD'), contains('diccionario'));
      expect(mensajeErrorMedGuess('Guess must be exactly 5 letters'), contains('5 letras'));
      expect(mensajeErrorMedGuess('No medguess daily configured for today'), contains('Hoy no hay'));
      expect(mensajeErrorMedGuess(null), 'Algo ha fallado');
    });
  });

  group('cliente', () {
    test('GET today y POST attempt con el token y la palabra', () async {
      final s = _Servidor();
      final api = s.api();
      final hoy = await api.hoy();
      expect(hoy.categoria, 'Neumología');
      expect(hoy.terminos, hasLength(2));
      final tras = await api.intentar('LUNES');
      expect(s.pedidas.last.method, 'POST');
      expect(s.pedidas.last.url.toString(), 'https://api.test/api/medguess/attempt');
      expect(s.pedidas.last.headers['Authorization'], 'Bearer tok');
      expect(jsonDecode(s.pedidas.last.body), {'guess': 'LUNES'});
      expect(tras.intentos.single.palabra, 'LUNES');
      expect(tras.pistas, ['Sibilancias espiratorias'], reason: 'un fallo, una pista');
    });

    test('una palabra fuera del diccionario no gasta intento y se marca como no válida', () async {
      final s = _Servidor();
      await expectLater(
        s.api().intentar('XXXXX'),
        throwsA(isA<MedGuessException>().having((e) => e.palabraNoValida, 'noValida', isTrue)),
      );
      expect(s.intentos, isEmpty);
    });

    test('sin sesión no se llama al servidor', () async {
      final s = _Servidor();
      final api = MedGuessApi(token: () async => '', baseUrl: 'x', client: MockClient(s.responder));
      await expectLater(api.hoy(), throwsA(isA<MedGuessException>().having((e) => e.status, 'status', 401)));
      expect(s.pedidas, isEmpty);
    });
  });

  group('controlador', () {
    test('teclear, borrar, enviar y no dejar seguir al terminar', () async {
      final s = _Servidor(terminos: const ['Asma']);
      final c = MedGuessController(s.api());
      await c.cargar();
      for (final l in 'MALASX'.split('')) {
        c.teclear(l);
      }
      expect(c.actual, 'MALAS');
      c.borrar();
      expect(c.puedeEnviar, isFalse);
      expect(await c.enviar(), ResultadoEnvio.noValida, reason: 'cuatro letras');
      expect(c.sacudidas, 1);
      c.teclear('S');
      expect(await c.enviar(), ResultadoEnvio.revelado);
      expect(c.estado!.resuelto, isTrue, reason: 'MALAS destapa M, A y S: ASMA entera');
      expect(c.filaRevelando, 0);
      c.teclear('C');
      expect(c.actual, isEmpty, reason: 'terminado: el teclado ya no escribe');
    });

    test('hoy sin reto: mensaje claro', () async {
      final s = _Servidor()..errorHoy = 'No medguess daily configured for today';
      final c = MedGuessController(s.api());
      await c.cargar();
      expect(c.estado, isNull);
      expect(c.errorCarga, 'Hoy no hay MedGuess. Vuelve mañana');
    });
  });

  for (final (nombre, size) in [('móvil', _movil), ('tablet', _tablet)]) {
    group(nombre, () {
      testWidgets('una partida ganada: casillas, pistas, término destapado y resultado', (tester) async {
        final s = _Servidor();
        await _montar(tester, size, s);
        expect(find.text('NEUMOLOGÍA'), findsOneWidget);
        expect(find.text('o también'), findsOneWidget);
        expect(find.textContaining('se abre si este intento'), findsOneWidget);
        expect(tester.takeException(), isNull);

        // Un intento sin ninguna letra del término: se gasta y abre la primera pista.
        await _escribir(tester, 'lunes');
        await _enviar(tester);
        expect(s.intentos.single['guess'], 'lunes');
        // En el móvil también se repite en la tarjeta del término.
        expect(find.text('Sibilancias espiratorias'), size == _movil ? findsNWidgets(2) : findsOneWidget);

        // Una palabra que no existe: aviso y no gasta intento.
        await _escribir(tester, 'xxxxx');
        await _enviar(tester);
        expect(find.textContaining('diccionario'), findsOneWidget);
        expect(s.intentos, hasLength(1));
        for (var i = 0; i < 5; i++) {
          await tester.tap(find.bySemanticsLabel('Borrar'));
          await tester.pump();
        }

        // MALAS destapa ASMA entera.
        await _escribir(tester, 'malas');
        await _enviar(tester);
        expect(s.resuelto, isTrue);
        expect(find.text('Reto completado'), findsWidgets);
        expect(find.text('ASMA'), findsOneWidget, reason: 'la respuesta en el resultado');
        expect(find.bySemanticsLabel('Enviar intento'), findsNothing, reason: 'sin teclado al terminar');
        expect(tester.takeException(), isNull);

        await tester.tap(find.text('Cerrar'));
        await tester.pumpAndSettle();
        expect(find.text('Reto completado'), findsOneWidget, reason: 'queda la tarjeta del final');
      });

      testWidgets('una partida ya terminada se abre sin teclado y con el término entero', (tester) async {
        final s = _Servidor(terminos: const ['Asma']);
        for (final p in ['perro', 'gordo', 'cupid', 'tribu', 'dulce', 'hielo']) {
          await s.responder(http.Request('POST', Uri.parse('https://api.test/api/medguess/attempt'))
            ..body = jsonEncode({'guess': p}));
        }
        await _montar(tester, size, s);
        expect(find.text('Intentos agotados'), findsOneWidget);
        expect(find.bySemanticsLabel('Enviar intento'), findsNothing);
        expect(find.textContaining('6 / 6 intentos', findRichText: true), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });
  }
}
