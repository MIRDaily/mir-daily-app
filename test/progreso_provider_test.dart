// El provider del progreso: cuándo pide, cuándo celebra y cuándo no.
//
//   flutter test test/progreso_provider_test.dart
//
// Las tres reglas que no puede saltarse:
//
//   · SIN SESIÓN NO PIDE NADA. En la web ese descuido era un 401 en cada
//     visita a la portada.
//   · Ninguna celebración sale sin permiso explícito, y el permiso solo se
//     concede al TERMINAR una actividad. Nunca durante una pregunta.
//   · Un logro solo se descarta cuando se ha enseñado de verdad; si no, se
//     guarda y sigue ahí al volver a abrir la app.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:mirdaily_app/core/models/logros.dart';
import 'package:mirdaily_app/core/providers/progress_provider.dart';
import 'package:mirdaily_app/core/services/api_service.dart';
import 'package:mirdaily_app/core/services/auth_service.dart';
import 'package:mirdaily_app/core/theme/levels.dart';

/// Cuenta las peticiones y devuelve el progreso que se le pida.
class _Espia {
  final List<Uri> pedidas = [];
  Map<String, dynamic> respuesta;

  _Espia(this.respuesta);

  late final http.Client client = MockClient((req) async {
    pedidas.add(req.url);
    return http.Response(jsonEncode(respuesta), 200,
        headers: {'content-type': 'application/json'});
  });
}

/// Referencia y cola en memoria, para no depender del disco del aparato.
class _StoreFalso implements LogrosStore {
  Referencia? referencia;
  List<Logro> pendientes = [];
  bool limpiado = false;

  @override
  Future<Referencia?> leerReferencia() async => referencia;

  @override
  Future<void> guardarReferencia(Referencia ref) async => referencia = ref;

  @override
  Future<List<Logro>> leerPendientes() async => pendientes;

  @override
  Future<void> guardarPendientes(List<Logro> logros) async =>
      pendientes = [...logros];

  @override
  Future<void> limpiar() async {
    referencia = null;
    pendientes = [];
    limpiado = true;
  }
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
        'lastActiveDay': '2026-09-08',
        'xpToday': 0,
        'xpTodayTotal': 0,
        'dailyCap': 300,
      },
      'daily': daily,
      'weekly': const [],
    };

ApiService _api(_Espia espia, {bool conSesion = true}) {
  final api = ApiService(AuthService(), client: espia.client);
  if (conSesion) {
    api.session = AuthSession(
      accessToken: 'token-de-prueba',
      refreshToken: 'r',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
      userId: 'u1',
    );
  }
  return api;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('sin sesión no se llama a /api/progress', () async {
    final espia = _Espia(_cuerpo());
    final p = ProgressProvider(_api(espia), store: _StoreFalso());

    // Nadie ha dicho que haya sesión: ni al construirlo ni al pedir refresco.
    await p.refresh();
    expect(espia.pedidas, isEmpty);

    p.setAutenticado(false);
    await p.refresh();
    expect(espia.pedidas, isEmpty);

    p.dispose();
  });

  test('con sesión pide una vez y guarda el snapshot', () async {
    final espia = _Espia(_cuerpo(level: 5, xpTotal: 3000, racha: 3));
    final p = ProgressProvider(_api(espia), store: _StoreFalso());

    p.setAutenticado(true);
    await p.refresh();

    expect(espia.pedidas.single.path, '/api/progress');
    expect(p.progress?.level, 5);
    expect(p.progress?.currentStreak, 3);
    expect(p.error, isNull);
    p.dispose();
  });

  test('la primera vez que se ve a un usuario no se celebra nada', () async {
    // Sin referencia previa solo se toma la foto: si no, entrar por primera
    // vez dispararía un aluvión de avisos por cosas ya conseguidas.
    final espia = _Espia(_cuerpo(level: 12, xpTotal: 4000, racha: 30));
    final store = _StoreFalso();
    final p = ProgressProvider(_api(espia), store: store);

    p.setAutenticado(true);
    await p.refresh();

    expect(p.logros, isEmpty);
    expect(store.referencia?.nivel, 12, reason: 'pero sí queda la foto');
    p.dispose();
  });

  test('subir de nivel NO se enseña hasta que hay permiso', () async {
    final espia = _Espia(_cuerpo(level: 12, xpTotal: xpParaNivel(12) + 90));
    final store = _StoreFalso()
      ..referencia = Referencia(
        nivel: 11,
        xpTotal: xpParaNivel(11) + 30,
        racha: 0,
        hechos: const [],
      );
    final p = ProgressProvider(_api(espia), store: store);

    p.setAutenticado(true);
    await p.refresh();

    expect(p.logros, hasLength(1), reason: 'el logro está detectado…');
    expect(p.celebracionLista, isFalse, reason: '…pero no se puede enseñar');

    // Aquí termina la actividad.
    p.permitirCelebracion();
    expect(p.celebracionLista, isTrue);

    // Y solo al enseñarlo de verdad se descarta.
    expect(store.pendientes, hasLength(1));
    p.descartarLogros([p.logros.single.id]);
    expect(p.logros, isEmpty);
    expect(store.pendientes, isEmpty);
    expect(p.celebracionLista, isFalse,
        reason: 'el permiso vale para una tanda, no para siempre');
    p.dispose();
  });

  test('un logro pendiente de otra sesión vuelve a la cola al arrancar',
      () async {
    final espia = _Espia(_cuerpo());
    final store = _StoreFalso()
      ..pendientes = [
        const Logro(
          id: 'viejo',
          tipo: TipoLogro.nivel,
          nivel: 7,
          xpAntes: 1500,
          xpDespues: 1900,
        ),
      ];

    final p = ProgressProvider(_api(espia), store: store);
    // La lectura del disco es asíncrona: se le da un turno al bucle.
    await Future<void>.delayed(Duration.zero);

    expect(p.logros.map((l) => l.id), ['viejo'],
        reason: 'cerrar la app con un logro pendiente no puede perderlo');
    p.dispose();
  });

  test('cerrar sesión tira el estado y la referencia', () async {
    final espia = _Espia(_cuerpo(level: 9, xpTotal: 2600));
    final store = _StoreFalso();
    final p = ProgressProvider(_api(espia), store: store);

    p.setAutenticado(true);
    await p.refresh();
    expect(p.progress, isNotNull);

    p.setAutenticado(false);
    // El cambio se aplaza a un microtask (lo llama el proxy durante el build):
    // se le da un turno al bucle.
    await Future<void>.delayed(Duration.zero);

    expect(p.progress, isNull);
    expect(p.logros, isEmpty);
    expect(store.limpiado, isTrue,
        reason: 'la referencia es de un usuario: no puede pasar a la cuenta '
            'siguiente y celebrarle cosas que no ha conseguido');
    p.dispose();
  });

  test('las metas simuladas son de mentira pero coherentes con la curva',
      () async {
    // El simulador de desarrollo no puede inventarse tramos imposibles: la
    // barra los recorre de verdad, así que un xpAntes/xpDespues que no cuadre
    // con la curva se vería como un salto a un sitio que no existe.
    final espia = _Espia(_cuerpo());
    final store = _StoreFalso();
    final p = ProgressProvider(_api(espia), store: store);

    p.simularLogro(SimulacionLogro.rango);

    final l = p.logros.single;
    expect(l.tipo, TipoLogro.rango);
    expect(nivelParaXp(l.xpAntes), 18);
    expect(nivelParaXp(l.xpDespues), 20,
        reason: 'dos peldaños encadenados, para ver el salto doble');
    expect(p.celebracionLista, isTrue,
        reason: 'quien pulsa el botón ya está diciendo "enséñamelo ahora"');

    // Y NO se persisten: son de mentira, no deben reaparecer mañana.
    expect(store.pendientes, isEmpty);
    expect(espia.pedidas, isEmpty, reason: 'ni una llamada al servidor');

    p.simularLogro(SimulacionLogro.todo);
    expect(p.logros.map((e) => e.id).toSet(), hasLength(p.logros.length),
        reason: 'identidad propia: sin ella el aviso cambia de texto sin '
            'animar');

    p.dispose();
  });

  test('dos refrescos a la vez no detectan el logro dos veces', () async {
    final espia = _Espia(_cuerpo(level: 4, xpTotal: xpParaNivel(4)));
    final store = _StoreFalso()
      ..referencia = Referencia(
        nivel: 3,
        xpTotal: xpParaNivel(3),
        racha: 0,
        hechos: const [],
      );
    final p = ProgressProvider(_api(espia), store: store);

    p.setAutenticado(true);
    // Volver del segundo plano justo al terminar un daily.
    await Future.wait([p.refresh(), p.refresh()]);

    expect(p.logros, hasLength(1));
    p.dispose();
  });
}
