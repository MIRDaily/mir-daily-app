// Los fallos del incidente de las subidas de nivel en cascada (21/09/2026).
//
//   flutter test test/niveles_regresion_test.dart
//
// Cada test de aquí reproduce UNA de las causas del informe. Están escritos
// antes de la corrección y a propósito: si alguno vuelve a pasar en rojo sin
// que nadie lo haya tocado, es que la corrección se ha caído por el camino.
//
//   A1  el permiso de celebrar no caducaba: concedido sin nada que enseñar,
//       se quedaba abierto para siempre y lo soltaba todo al entrar al perfil.
//   A2  cada recarga añadía su propio "Nivel N" a la cola.
//   A4  un 200 con el estado de un usuario recién nacido se guardaba como
//       referencia, y a la siguiente lectura buena se celebraba el salto entero.
//   A7  una respuesta tardía escribía los datos del usuario anterior.
//   A8  los desafíos se recordaban solo por código, sin periodo.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:mirdaily_app/core/models/logros.dart';
import 'package:mirdaily_app/core/models/progress.dart';
import 'package:mirdaily_app/core/providers/progress_provider.dart';
import 'package:mirdaily_app/core/services/api_service.dart';
import 'package:mirdaily_app/core/services/auth_service.dart';
import 'package:mirdaily_app/core/theme/levels.dart';

/// Devuelve lo que se le diga, y deja contar cuántas veces se lo han pedido.
class _Espia {
  final List<Uri> pedidas = [];
  Map<String, dynamic> respuesta;

  /// Retraso artificial, para poder colar un cambio de cuenta a media carga.
  Duration retraso = Duration.zero;

  _Espia(this.respuesta);

  late final http.Client client = MockClient((req) async {
    pedidas.add(req.url);
    if (retraso > Duration.zero) await Future<void>.delayed(retraso);
    return http.Response(jsonEncode(respuesta), 200,
        headers: {'content-type': 'application/json'});
  });
}

/// Referencia y cola en memoria, una por usuario, como el disco de verdad.
class _StoreFalso implements LogrosStore {
  final Map<String, Referencia> referencias = {};
  final Map<String, List<Logro>> colas = {};

  @override
  Future<Referencia?> leerReferencia(String usuario) async =>
      referencias[usuario];

  @override
  Future<void> guardarReferencia(String usuario, Referencia ref) async =>
      referencias[usuario] = ref;

  @override
  Future<List<Logro>> leerPendientes(String usuario) async =>
      colas[usuario] ?? const [];

  @override
  Future<void> guardarPendientes(String usuario, List<Logro> logros) async =>
      colas[usuario] = [...logros];

  @override
  Future<void> limpiar(String usuario) async {
    referencias.remove(usuario);
    colas.remove(usuario);
  }

  @override
  Future<void> purgarSinDuenno() async {}
}

Map<String, dynamic> _cuerpo({
  int level = 1,
  int xpTotal = 0,
  int racha = 0,
  List<Map<String, dynamic>> daily = const [],
}) =>
    {
      'progress': {
        'level': level,
        'maxLevel': 100,
        'xpTotal': xpTotal,
        'xpIntoLevel': xpTotal - xpParaNivel(level),
        'xpForNext': costeNivel(level),
        'currentStreak': racha,
        'longestStreak': racha,
        'streakFreezes': 0,
        'streakMultiplier': 1.0,
        'lastActiveDay': '2026-09-21',
        'xpToday': 0,
        'xpTodayTotal': 0,
        'dailyCap': 300,
      },
      'daily': daily,
      'weekly': const <Map<String, dynamic>>[],
    };

/// El cuerpo que devolvía el servidor cuando `tryRpc` se tragaba el error: un
/// 200 con el estado de alguien que acaba de registrarse.
Map<String, dynamic> get _fallback => _cuerpo();

Map<String, dynamic> _desafio(String code, String periodo,
        {bool hecho = true}) =>
    {
      'code': code,
      'scope': 'daily',
      'metric': 'daily_complete',
      'title': 'Haz el Daily',
      'description': '',
      'progress': hecho ? 1 : 0,
      'target': 1,
      'xpReward': 30,
      'completed': hecho,
      'sortOrder': 1,
      'meta': null,
      'periodKey': periodo,
    };

ApiService _api(_Espia espia) {
  final api = ApiService(AuthService(), client: espia.client);
  api.session = AuthSession(
    accessToken: 'token-de-prueba',
    refreshToken: 'r',
    expiresAt: DateTime.now().add(const Duration(hours: 1)),
    userId: 'u1',
  );
  return api;
}

Referencia _ref(int nivel, int xpTotal,
        {int racha = 0, List<String> hechos = const []}) =>
    Referencia(nivel: nivel, xpTotal: xpTotal, racha: racha, hechos: hechos);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // -----------------------------------------------------------------------
  // A1 . El permiso caduca si al concederlo no habia nada que ensenar
  // -----------------------------------------------------------------------
  test('A1 · permiso concedido en vacío no se queda abierto para siempre',
      () async {
    final espia = _Espia(_cuerpo(level: 12, xpTotal: xpParaNivel(12) + 90));
    final store = _StoreFalso()..referencias['u1'] = _ref(11, xpParaNivel(11));
    final p = ProgressProvider(
      _api(espia),
      store: store,
      ventanaPermiso: const Duration(milliseconds: 40),
    );
    addTearDown(p.dispose);
    p.setUsuario('u1');
    await Future<void>.delayed(const Duration(milliseconds: 20));

    // Sale de la pantalla de resultados sin haber conseguido nada: el permiso
    // se concede igual, porque `dispose` no sabe si hay algo.
    p.descartarLogros([for (final l in p.logros) l.id]);
    p.permitirCelebracion();
    expect(p.celebracionLista, isFalse, reason: 'la cola está vacía');

    // Pasa la rendija sin que llegue nada. El permiso tiene que cerrarse solo.
    await Future<void>.delayed(const Duration(milliseconds: 90));

    // Y AHORA el usuario entra al perfil, que recarga. Entre medias ha subido.
    store.referencias['u1'] = _ref(11, xpParaNivel(11));
    await p.refresh();

    expect(p.logros, hasLength(1), reason: 'el logro sí se detecta…');
    expect(p.celebracionLista, isFalse,
        reason: '…pero no puede saltarle encima: nadie ha dado permiso ahora');
  });

  test('A1 · si el logro llega DENTRO de la rendija, sí se celebra', () async {
    // La rendija existe justo para esto: el permiso se concede al salir de los
    // resultados y la recarga que disparó esa misma pantalla llega un instante
    // después. Cerrar el grifo del todo se comería la celebración legítima.
    final espia = _Espia(_cuerpo(level: 12, xpTotal: xpParaNivel(12) + 90))
      ..retraso = const Duration(milliseconds: 30);
    final store = _StoreFalso()..referencias['u1'] = _ref(11, xpParaNivel(11));
    final p = ProgressProvider(
      _api(espia),
      store: store,
      ventanaPermiso: const Duration(seconds: 5),
    );
    addTearDown(p.dispose);
    p.setUsuario('u1');

    final carga = p.refresh();
    p.permitirCelebracion();
    await carga;

    expect(p.celebracionLista, isTrue);
  });

  // -----------------------------------------------------------------------
  // A2 . Varias recargas no apilan varias subidas de nivel
  // -----------------------------------------------------------------------
  test('A2 · dos recargas que suben de nivel dan UN aviso, no dos', () async {
    final espia = _Espia(_cuerpo(level: 11, xpTotal: xpParaNivel(11) + 10));
    final store = _StoreFalso()..referencias['u1'] = _ref(10, xpParaNivel(10));
    final p = ProgressProvider(_api(espia), store: store);
    addTearDown(p.dispose);
    p.setUsuario('u1');

    await p.refresh();
    // El usuario sigue estudiando en la web y vuelve a la app: otra recarga.
    espia.respuesta = _cuerpo(level: 12, xpTotal: xpParaNivel(12) + 90);
    await p.refresh();

    expect(p.logros, hasLength(1),
        reason: 'no son dos logros: es UNA subida de 10 a 12');
    final l = p.logros.single;
    expect(l.nivel, 12);
    expect(l.xpAntes, xpParaNivel(10),
        reason: 'la barra arranca donde arrancó el tramo, no a mitad');
    expect(l.xpDespues, xpParaNivel(12) + 90);
  });

  test('A2 · fusionarSaltos respeta el id del primero y no toca los desafíos',
      () {
    final cola = [
      Logro(
          id: 'a',
          tipo: TipoLogro.nivel,
          nivel: 11,
          xpAntes: xpParaNivel(10),
          xpDespues: xpParaNivel(11)),
      const Logro(id: 'd1', tipo: TipoLogro.desafio, titulo: 'Haz el Daily'),
      Logro(
          id: 'b',
          tipo: TipoLogro.rango,
          nivel: 12,
          rango: 'Graduado',
          xpAntes: xpParaNivel(11),
          xpDespues: xpParaNivel(12)),
    ];

    final out = fusionarSaltos(cola);

    expect(out, hasLength(2));
    expect(out.first.id, 'a',
        reason: 'si la tarjeta ya está en pantalla, cambiar el id la remonta');
    expect(out.first.tipo, TipoLogro.rango,
        reason: 'si alguno de los peldaños cruzó rango, el tramo cruzó rango');
    expect(out.first.nivel, 12);
    expect(out.last.tipo, TipoLogro.desafio);
  });

  // -----------------------------------------------------------------------
  // A4 . Una foto anomala no se toma por buena
  // -----------------------------------------------------------------------
  test('A4 · el fallback del servidor no pisa la referencia', () async {
    final espia = _Espia(_fallback);
    final store = _StoreFalso()
      ..referencias['u1'] = _ref(12, xpParaNivel(12) + 90);
    final p = ProgressProvider(_api(espia), store: store);
    addTearDown(p.dispose);
    p.setUsuario('u1');

    await p.refresh();

    expect(store.referencias['u1']!.nivel, 12,
        reason: 'guardar nivel 1 aquí es lo que provocaba el incidente');
    expect(p.data, isNull, reason: 'tampoco se pinta: es mentira');
    expect(p.error, isNotNull);
    expect(p.logros, isEmpty);

    // Y cuando el servidor se recupera, NO hay nada que celebrar: el usuario
    // seguía en el nivel 12 todo el rato.
    espia.respuesta = _cuerpo(level: 12, xpTotal: xpParaNivel(12) + 90);
    await p.refresh();

    expect(p.logros, isEmpty);
    expect(p.data?.progress.level, 12);
  });

  test('A4 · un cuerpo vacío (2xx que no era JSON) tampoco cuenta', () {
    final vacio = ProgressSnapshot.fromJson(const {});
    expect(vacio.progress.level, 1, reason: 'así es como lo parsea el modelo');
    expect(fotoAnomala(_ref(12, 3918), vacio), isTrue);
  });

  test('A4 · perder la lista de desafíos también es anómalo', () {
    final sinDesafios =
        ProgressSnapshot.fromJson(_cuerpo(level: 12, xpTotal: 3918));
    expect(
      fotoAnomala(
          _ref(12, 3918, hechos: const ['daily_done|2026-09-21']), sinDesafios),
      isTrue,
      reason: 'tenía desafíos hechos y ahora no llega ni la lista',
    );
  });

  test('A4 · un usuario nuevo de verdad NO es anómalo', () {
    // Nivel 1 y cero XP es el estado real de quien acaba de registrarse. Sin
    // referencia previa no hay nada con qué compararlo y no se puede rechazar.
    expect(fotoAnomala(null, ProgressSnapshot.fromJson(_fallback)), isFalse);
    expect(
        fotoAnomala(_ref(1, 0), ProgressSnapshot.fromJson(_fallback)), isFalse);
  });

  // -----------------------------------------------------------------------
  // A7 . Una respuesta tardia no escribe en la cuenta que entro despues
  // -----------------------------------------------------------------------
  test('A7 · cambiar de cuenta a media carga descarta la respuesta vieja',
      () async {
    final espia = _Espia(_cuerpo(level: 12, xpTotal: xpParaNivel(12) + 90))
      ..retraso = const Duration(milliseconds: 60);
    final store = _StoreFalso()..referencias['u1'] = _ref(11, xpParaNivel(11));
    final p = ProgressProvider(_api(espia), store: store);
    addTearDown(p.dispose);

    p.setUsuario('u1');
    final tardia = p.refresh();

    // A mitad de vuelo, el usuario cierra sesión y entra otro.
    p.setUsuario('u2');
    await tardia;
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(store.referencias['u2'], isNull,
        reason: 'los datos de u1 no pueden aterrizar en la cuenta de u2');
    expect(store.referencias['u1']!.nivel, 11,
        reason: 'ni avanzar la de u1, que ya no está mirando');
    expect(p.logros, isEmpty);
  });

  test('A7 · la cola y la referencia van por usuario', () async {
    final espia = _Espia(_cuerpo(level: 3, xpTotal: xpParaNivel(3)));
    final store = _StoreFalso()
      ..colas['u1'] = [
        const Logro(id: 'de-u1', tipo: TipoLogro.desafio, titulo: 'Suyo')
      ];
    final p = ProgressProvider(_api(espia), store: store);
    addTearDown(p.dispose);

    p.setUsuario('u1');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(p.logros.map((l) => l.id), contains('de-u1'));

    p.setUsuario('u2');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(p.logros, isEmpty, reason: 'lo pendiente de u1 no se le enseña a u2');
  });

  // -----------------------------------------------------------------------
  // A8 . Los desafios se recuerdan por codigo Y periodo
  // -----------------------------------------------------------------------
  test('A8 · el mismo desafío de otro día se vuelve a celebrar', () {
    final ayer = _ref(12, 3918, hechos: const ['daily_done|2026-09-20']);
    final hoy = ProgressSnapshot.fromJson(_cuerpo(
      level: 12,
      xpTotal: 3918,
      daily: [_desafio('daily_done', '2026-09-21')],
    ));

    final logros = detectarLogros(ayer, hoy);

    expect(logros, hasLength(1),
        reason: 'hacer el Daily hoy es un logro de hoy, no el de ayer');
    expect(logros.single.tipo, TipoLogro.desafio);
  });

  test('A8 · el mismo desafío del MISMO día no se repite', () {
    final ref = _ref(12, 3918, hechos: const ['daily_done|2026-09-21']);
    final mismo = ProgressSnapshot.fromJson(_cuerpo(
      level: 12,
      xpTotal: 3918,
      daily: [_desafio('daily_done', '2026-09-21')],
    ));

    expect(detectarLogros(ref, mismo), isEmpty);
  });
}
