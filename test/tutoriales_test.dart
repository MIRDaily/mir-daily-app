// Tanda 8: los tutoriales de la mascota. Lógica pura, cliente de la API y controlador.
//
//   flutter test test/tutoriales_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mirdaily_app/core/models/models.dart';
import 'package:mirdaily_app/core/models/tutoriales.dart';
import 'package:mirdaily_app/core/services/tutoriales_api.dart';
import 'package:mirdaily_app/features/tutorial/tutoriales_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Un servidor de mentira para /api/profile/tutorials.
class _Servidor {
  final List<http.Request> pedidas = [];
  int fallarCon = 0;
  final Set<String> vistos = {};

  late final http.Client client = MockClient((req) async {
    pedidas.add(req);
    if (fallarCon != 0) {
      return http.Response(jsonEncode({'error': 'Error guardando el tutorial.'}), fallarCon);
    }
    if (req.method == 'DELETE') {
      vistos.clear();
      return http.Response(jsonEncode({'success': true, 'tutorials_seen': []}), 200);
    }
    final clave = (jsonDecode(req.body) as Map)['key'] as String;
    if (!formatoClaveTutorial.hasMatch(clave)) {
      return http.Response(jsonEncode({'error': 'Clave de tutorial no válida.'}), 400);
    }
    vistos.add(clave);
    return http.Response(jsonEncode({'success': true, 'tutorials_seen': vistos.toList()}), 200);
  });

  TutorialesApi api() => TutorialesApi(token: () async => 'T', baseUrl: 'https://api.test', client: client);

  List<String> marcadas() =>
      [for (final r in pedidas.where((r) => r.method == 'POST')) (jsonDecode(r.body) as Map)['key'] as String];
}

Future<void> _esperar([int ms = 10]) => Future.delayed(Duration(milliseconds: ms));

UserProfile _perfil({List<String> vistos = const []}) => UserProfile(id: 'u1', tutorialsSeen: vistos);

void main() {
  group('guiones', () {
    test('las claves son las de la web y valen para el backend; mapas.v1 se queda fuera', () {
      expect(tutorialesApp.keys, ['daily.v2', 'studio.v3', 'resumenes.v1']);
      for (final id in tutorialesApp.keys) {
        expect(formatoClaveTutorial.hasMatch(id), isTrue, reason: id);
      }
      expect(tutorialesApp.containsKey('mapas.v1'), isFalse);
    });

    test('cada pose tiene su PNG en assets/mascota (las 11 de la web)', () {
      expect(PoseMascota.values, hasLength(11));
      for (final p in PoseMascota.values) {
        expect(File(p.asset).existsSync(), isTrue, reason: p.asset);
      }
    });

    test('los pasos centrados no buscan ancla y los demás apuntan a anclas conocidas', () {
      const conocidas = {
        anclaDailySobre,
        anclaNavPestanas,
        anclaStudioSimulacro,
        anclaStudioSimulacros,
        anclaStudioMazos,
        anclaStudioFlashcards,
        anclaResumenesZona,
        anclaResumenesNuevo,
      };
      for (final t in tutorialesApp.values) {
        for (final p in armarGuion(t)) {
          if (p.colocacion == ColocacionPaso.centro) {
            expect(p.anclaEfectiva, isNull);
          } else {
            expect(conocidas, contains(p.ancla), reason: p.texto);
          }
          expect(p.texto.trim(), isNotEmpty);
        }
      }
    });

    test('el daily lleva su despedida al final; Studio y resúmenes no repiten el adiós', () {
      final daily = armarGuion(tutorialDaily);
      expect(daily, hasLength(4));
      expect(daily[2].ancla, anclaNavPestanas);
      expect(daily.last.pose, PoseMascota.despedida);
      expect(daily.last.texto, contains('Perfil'));
      expect(tutorialStudio.cierre, isEmpty);
      expect(tutorialResumenes.cierre, isEmpty);
      expect(armarGuion(tutorialStudio), hasLength(7));
      expect(armarGuion(tutorialResumenes), hasLength(4));
    });

    test('ningún texto habla de lo que la app no tiene (Configuración, Sala Zen, la app móvil)', () {
      for (final t in tutorialesApp.values) {
        for (final p in armarGuion(t)) {
          expect(p.texto, isNot(contains('Configuración')));
          expect(p.texto.toLowerCase(), isNot(contains('zen')));
          expect(p.texto, isNot(contains('Android')));
          expect(p.texto, isNot(contains('arriba')));
        }
      }
    });
  });

  group('qué tutorial toca', () {
    String? toca({
      String? candidato = 'studio.v3',
      String? enCurso,
      bool conSesion = true,
      bool activos = true,
      bool celebrando = false,
      Set<String> vistos = const {},
    }) =>
        tutorialQueToca(
          candidato: candidato,
          enCurso: enCurso,
          conSesion: conSesion,
          activos: activos,
          celebrando: celebrando,
          vistos: vistos,
        );

    test('arranca el candidato si nada lo impide', () => expect(toca(), 'studio.v3'));
    test('sin pantalla lista, nada', () => expect(toca(candidato: null), isNull));
    test('uno cada vez', () => expect(toca(enCurso: 'daily.v2'), isNull));
    test('sin sesión, nada', () => expect(toca(conSesion: false), isNull));
    test('apagados, nada', () => expect(toca(activos: false), isNull));
    test('la celebración va primero', () => expect(toca(celebrando: true), isNull));
    test('lo visto no se repite', () => expect(toca(vistos: {'studio.v3'}), isNull));
    test('otra versión vista no cuenta', () => expect(toca(vistos: {'studio.v2'}), 'studio.v3'));
    test('un id que la app no tiene (mapas) no arranca', () => expect(toca(candidato: 'mapas.v1'), isNull));

    test('lo visto une servidor, caché y sesión', () {
      expect(unirVistos(['a.v1'], ['b.v1'], ['c.v1', 'a.v1']), {'a.v1', 'b.v1', 'c.v1'});
    });
  });

  group('colocar el bocadillo', () {
    const pantalla = Size(360, 780);
    const bocadillo = Size(300, 200);

    test('sin foco, centrado', () {
      expect(colocarBocadillo(pantalla: pantalla, bocadillo: bocadillo, foco: null), const Offset(30, 290));
    });

    test('debajo del foco si cabe', () {
      final o = colocarBocadillo(pantalla: pantalla, bocadillo: bocadillo, foco: const Rect.fromLTWH(20, 100, 320, 120));
      expect(o.dy, 100 + 120 + 24);
    });

    test('encima si debajo no cabe', () {
      final o = colocarBocadillo(pantalla: pantalla, bocadillo: bocadillo, foco: const Rect.fromLTWH(20, 480, 320, 120));
      expect(o.dy, 480 - 24 - 200);
    });

    test('pegado al fondo (sobre la barra de Saltar) si no cabe en ninguno: el sobre a pantalla completa', () {
      final o = colocarBocadillo(pantalla: pantalla, bocadillo: bocadillo, foco: const Rect.fromLTWH(0, 40, 360, 700));
      expect(o.dy, 780 - 72 - 200);
    });

    test('centrado sobre el foco pero sin salirse por los lados', () {
      final derecha = colocarBocadillo(pantalla: pantalla, bocadillo: bocadillo, foco: const Rect.fromLTWH(300, 100, 50, 50));
      expect(derecha.dx, 360 - 300 - 16);
      final izquierda = colocarBocadillo(pantalla: pantalla, bocadillo: bocadillo, foco: const Rect.fromLTWH(0, 100, 40, 50));
      expect(izquierda.dx, 16);
    });

    test('la mascota mira a la izquierda con el foco en el tercio derecho', () {
      expect(mascotaMiraIzquierda(const Rect.fromLTWH(280, 0, 60, 60), 360), isTrue);
      expect(mascotaMiraIzquierda(const Rect.fromLTWH(20, 0, 60, 60), 360), isFalse);
      expect(mascotaMiraIzquierda(null, 360), isFalse);
    });

    test('en tablet, en fila; en móvil, apilado', () {
      expect(bocadilloEnFila(360), isFalse);
      expect(bocadilloEnFila(1024), isTrue);
    });

    test('varias cajas de una ancla se iluminan juntas; las vacías no cuentan', () {
      expect(
        unirRectangulos(const [Rect.fromLTWH(10, 10, 50, 50), Rect.fromLTWH(100, 200, 20, 20), Rect.zero]),
        const Rect.fromLTRB(10, 10, 120, 220),
      );
      expect(unirRectangulos(const [Rect.zero]), isNull);
    });

    test('cada toque acelera la máquina de escribir hasta un suelo', () {
      expect(retardoAcelerado(msPorCaracter), 7);
      expect(retardoAcelerado(7), msMinimo);
      expect(retardoAcelerado(msMinimo), msMinimo);
    });
  });

  group('perfil', () {
    test('lee tutorials_seen y lo deja vacío si no viene', () {
      expect(UserProfile.fromJson({'id': 'u1', 'tutorials_seen': ['daily.v2', 3]}).tutorialsSeen, ['daily.v2']);
      expect(UserProfile.fromJson({'id': 'u1'}).tutorialsSeen, isEmpty);
    });
  });

  group('API', () {
    test('marcar manda POST con la clave y el token', () async {
      final s = _Servidor();
      final quedan = await s.api().marcar('daily.v2');
      final r = s.pedidas.single;
      expect((r.method, r.url.path), ('POST', '/api/profile/tutorials'));
      expect(r.headers['Authorization'], 'Bearer T');
      expect(jsonDecode(r.body), {'key': 'daily.v2'});
      expect(quedan, ['daily.v2']);
    });

    test('reiniciar manda DELETE', () async {
      final s = _Servidor();
      await s.api().reiniciar();
      expect((s.pedidas.single.method, s.pedidas.single.url.path), ('DELETE', '/api/profile/tutorials'));
    });

    test('un error trae el mensaje del servidor', () async {
      final s = _Servidor()..fallarCon = 500;
      expect(
        () => s.api().marcar('daily.v2'),
        throwsA(isA<TutorialesException>()
            .having((e) => e.message, 'message', 'Error guardando el tutorial.')
            .having((e) => e.status, 'status', 500)),
      );
    });

    test('sin sesión no llama', () async {
      final s = _Servidor();
      final api = TutorialesApi(token: () async => '', baseUrl: 'https://api.test', client: s.client);
      expect(() => api.marcar('daily.v2'), throwsA(isA<TutorialesException>()));
      expect(s.pedidas, isEmpty);
    });
  });

  group('controlador', () {
    late _Servidor s;
    late Tutoriales t;

    Future<void> conSesion({List<String> vistos = const [], bool celebrando = false}) async {
      t.sincronizar(usuario: 'u1', perfil: _perfil(vistos: vistos), celebrando: celebrando);
      await _esperar();
    }

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      s = _Servidor();
      t = Tutoriales(s.api());
    });

    tearDown(() => t.dispose());

    test('arranca cuando la pantalla está lista, recorre los pasos y al final lo marca', () async {
      await conSesion();
      t.declararListo('resumenes.v1', true);
      expect(t.enCurso, isNull, reason: 'un fotograma de margen');
      await _esperar();
      expect(t.enCurso, 'resumenes.v1');
      expect(t.total, 4);
      expect(t.pasoActual!.pose, PoseMascota.saludo);
      for (var i = 0; i < 3; i++) {
        t.avanzar();
      }
      expect(t.indice, 3);
      t.avanzar();
      expect(t.enCurso, isNull);
      await _esperar();
      expect(s.marcadas(), ['resumenes.v1']);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList(Tutoriales.claveVistos('u1')), contains('resumenes.v1'));

      // Volver a la pantalla no lo repite.
      t.declararListo('resumenes.v1', true);
      await _esperar();
      expect(t.enCurso, isNull);
    });

    test('lo visto en la web (en el perfil) no sale en la app', () async {
      await conSesion(vistos: ['studio.v3']);
      t.declararListo('studio.v3', true);
      await _esperar();
      expect(t.enCurso, isNull);
      t.declararListo('daily.v2', true);
      await _esperar();
      expect(t.enCurso, 'daily.v2');
    });

    test('saltar cuenta como visto', () async {
      await conSesion();
      t.declararListo('daily.v2', true);
      await _esperar();
      t.saltar();
      await _esperar();
      expect(t.enCurso, isNull);
      expect(s.marcadas(), ['daily.v2']);
    });

    test('si la pantalla deja de estar lista antes de arrancar, no arranca', () async {
      await conSesion();
      t.declararListo('daily.v2', true);
      t.declararListo('daily.v2', false);
      await _esperar();
      expect(t.enCurso, isNull);
    });

    test('espera a que se cierre la celebración', () async {
      await conSesion(celebrando: true);
      t.declararListo('studio.v3', true);
      await _esperar();
      expect(t.enCurso, isNull);
      t.sincronizar(usuario: 'u1', perfil: null, celebrando: false);
      await _esperar();
      expect(t.enCurso, 'studio.v3');
    });

    test('apagados no salen, y el interruptor se recuerda en el dispositivo', () async {
      await conSesion();
      await t.setActivos(false);
      t.declararListo('studio.v3', true);
      await _esperar();
      expect(t.enCurso, isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(Tutoriales.claveActivos), isFalse);

      final otro = Tutoriales(s.api());
      addTearDown(otro.dispose);
      await _esperar();
      expect(otro.activos, isFalse);
    });

    test('apagarlos con uno abierto lo cierra sin marcarlo', () async {
      await conSesion();
      t.declararListo('studio.v3', true);
      await _esperar();
      await t.setActivos(false);
      expect(t.enCurso, isNull);
      expect(s.marcadas(), isEmpty);
    });

    test('si el POST falla, la caché local evita que se repita (también tras reabrir la app)', () async {
      s.fallarCon = 500;
      await conSesion();
      t.declararListo('daily.v2', true);
      await _esperar();
      t.saltar();
      await _esperar();

      final reabierta = Tutoriales(s.api());
      addTearDown(reabierta.dispose);
      reabierta.sincronizar(usuario: 'u1', perfil: _perfil(), celebrando: false);
      await _esperar();
      reabierta.declararListo('daily.v2', true);
      await _esperar();
      expect(reabierta.enCurso, isNull);
    });

    test('la caché es de cada cuenta', () async {
      await conSesion();
      t.declararListo('daily.v2', true);
      await _esperar();
      t.saltar();
      await _esperar();
      t.sincronizar(usuario: 'u2', perfil: const UserProfile(id: 'u2'), celebrando: false);
      await _esperar();
      t.declararListo('daily.v2', true);
      await _esperar();
      expect(t.enCurso, 'daily.v2');
    });

    test('volver a verlos: borra en el servidor y aquí, y el perfil viejo no los resucita', () async {
      final viejo = _perfil(vistos: ['daily.v2', 'studio.v3']);
      t.sincronizar(usuario: 'u1', perfil: viejo, celebrando: false);
      await _esperar();
      await t.setActivos(false);
      await t.reiniciar();
      expect(s.pedidas.last.method, 'DELETE');
      expect(t.activos, isTrue);
      expect(t.vistos, isEmpty);

      // El ProxyProvider vuelve a pasar el MISMO perfil (aún sin refrescar): no cuenta.
      t.sincronizar(usuario: 'u1', perfil: viejo, celebrando: false);
      await _esperar();
      expect(t.vistos, isEmpty);
      t.declararListo('studio.v3', true);
      await _esperar();
      expect(t.enCurso, 'studio.v3');
    });

    test('si el servidor no puede reiniciar, lanza y no toca nada', () async {
      t.sincronizar(usuario: 'u1', perfil: _perfil(vistos: ['daily.v2']), celebrando: false);
      await _esperar();
      s.fallarCon = 500;
      await expectLater(t.reiniciar(), throwsA(isA<TutorialesException>()));
      expect(t.vistos, {'daily.v2'});
    });

    test('al cerrar sesión se corta el tutorial abierto', () async {
      await conSesion();
      t.declararListo('daily.v2', true);
      await _esperar();
      t.sincronizar(usuario: null, perfil: null, celebrando: false);
      expect(t.enCurso, isNull);
    });
  });
}
