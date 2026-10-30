// Renovar la sesión en un 401 y reintentar (pendiente desde la tanda 4 del plan de la app).
//
//   flutter test test/renovar_sesion_test.dart
//
// - ClienteConSesion: un 401 pide token nuevo y repite la MISMA petición una vez.
// - ApiService: varias peticiones a la vez con el token caducado renuevan UNA vez (Supabase rota el
//   refresh token: gastarlo dos veces podía cerrar la sesión).
// - Si Supabase dice que no, se avisa para volver al login.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mirdaily_app/core/providers/auth_provider.dart';
import 'package:mirdaily_app/core/services/api_service.dart';
import 'package:mirdaily_app/core/services/auth_service.dart';
import 'package:mirdaily_app/core/services/cliente_con_sesion.dart';

AuthSession _sesion(String token, {bool caducada = false}) => AuthSession(
      accessToken: token,
      refreshToken: 'r-$token',
      expiresAt: DateTime.now().add(Duration(hours: caducada ? -1 : 1)),
      userId: 'u1',
    );

/// Un AuthService sin red: cuenta las renovaciones y tarda un poco, para que se solapen.
class _AuthFalso extends AuthService {
  int renovaciones = 0;
  Object? error;
  AuthSession? guardada;

  @override
  Future<AuthSession> refresh(AuthSession session) async {
    renovaciones++;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    if (error != null) throw error!;
    return _sesion('nuevo$renovaciones');
  }

  @override
  Future<void> clearSession() async {}

  @override
  Future<AuthSession?> loadSession() async => guardada;
}

/// Un backend que solo acepta [valido] y apunta lo que le llega.
class _Backend {
  String valido;
  final List<http.Request> pedidas = [];

  _Backend(this.valido);

  Future<http.Response> responder(http.Request r) async {
    pedidas.add(r);
    if (r.headers['Authorization'] != 'Bearer $valido') {
      return http.Response(jsonEncode({'error': 'Invalid token'}), 401);
    }
    return http.Response(jsonEncode({'ok': true, 'eco': r.body}), 200);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('ClienteConSesion', () {
    test('un 401 renueva y repite la misma petición, con su cuerpo y cabeceras', () async {
      final b = _Backend('nuevo');
      final rechazados = <String>[];
      final c = ClienteConSesion(MockClient(b.responder), renovar: (t) async {
        rechazados.add(t);
        return 'nuevo';
      });
      final res = await c.post(
        Uri.parse('https://api.test/api/x'),
        headers: {'Authorization': 'Bearer viejo', 'Content-Type': 'application/json'},
        body: jsonEncode({'a': 1}),
      );
      expect(res.statusCode, 200);
      expect(rechazados, ['viejo']);
      expect(b.pedidas, hasLength(2));
      expect(b.pedidas.last.method, 'POST');
      expect(b.pedidas.last.body, '{"a":1}');
      expect(b.pedidas.last.headers['Content-Type'], startsWith('application/json'));
    });

    test('sin 401 no se toca nada', () async {
      final b = _Backend('bueno');
      var llamadas = 0;
      final c = ClienteConSesion(MockClient(b.responder), renovar: (_) async {
        llamadas++;
        return 'x';
      });
      final res = await c.get(Uri.parse('https://api.test/a'), headers: {'Authorization': 'Bearer bueno'});
      expect(res.statusCode, 200);
      expect(llamadas, 0);
    });

    test('si no hay token nuevo, llega el 401 original con su cuerpo', () async {
      final b = _Backend('otro');
      final c = ClienteConSesion(MockClient(b.responder), renovar: (_) async => null);
      final res = await c.get(Uri.parse('https://api.test/a'), headers: {'Authorization': 'Bearer viejo'});
      expect(res.statusCode, 401);
      expect(jsonDecode(res.body), {'error': 'Invalid token'});
      expect(b.pedidas, hasLength(1));
    });

    test('un solo reintento: si el token nuevo también falla, se entrega ese 401', () async {
      final b = _Backend('ninguno');
      final c = ClienteConSesion(MockClient(b.responder), renovar: (_) async => 'nuevo');
      final res = await c.get(Uri.parse('https://api.test/a'), headers: {'Authorization': 'Bearer viejo'});
      expect(res.statusCode, 401);
      expect(b.pedidas, hasLength(2));
    });

    test('sin cabecera de sesión no se reintenta', () async {
      final b = _Backend('x');
      var llamadas = 0;
      final c = ClienteConSesion(MockClient(b.responder), renovar: (_) async {
        llamadas++;
        return 'y';
      });
      expect((await c.get(Uri.parse('https://api.test/a'))).statusCode, 401);
      expect(llamadas, 0);
    });
  });

  group('ApiService', () {
    test('cinco peticiones a la vez con el token caducado: una sola renovación', () async {
      final auth = _AuthFalso();
      final b = _Backend('nuevo1');
      final api = ApiService(auth, client: MockClient(b.responder))..session = _sesion('viejo', caducada: true);
      final tokens = await Future.wait([for (var i = 0; i < 5; i++) api.validToken()]);
      expect(tokens.toSet(), {'nuevo1'});
      expect(auth.renovaciones, 1);
    });

    test('un 401 con el token aún «vigente» renueva y la llamada sale bien', () async {
      final auth = _AuthFalso();
      final b = _Backend('nuevo1');
      final api = ApiService(auth, client: MockClient(b.responder))..session = _sesion('revocado');
      final perfil = await api.clienteConSesion.get(
        Uri.parse('https://api.test/api/profile'),
        headers: {'Authorization': 'Bearer ${await api.validToken()}'},
      );
      expect(perfil.statusCode, 200);
      expect(auth.renovaciones, 1);
      expect(api.session!.accessToken, 'nuevo1');
    });

    test('varios 401 a la vez: renueva una vez y todos reintentan con el mismo token', () async {
      final auth = _AuthFalso();
      final b = _Backend('nuevo1');
      final api = ApiService(auth, client: MockClient(b.responder))..session = _sesion('revocado');
      final res = await Future.wait([
        for (var i = 0; i < 4; i++)
          api.clienteConSesion.get(Uri.parse('https://api.test/$i'), headers: {'Authorization': 'Bearer revocado'}),
      ]);
      expect(res.map((r) => r.statusCode).toSet(), {200});
      expect(auth.renovaciones, 1);
    });

    test('si otra petición ya renovó, se reintenta con el token actual sin renovar', () async {
      final auth = _AuthFalso();
      final api = ApiService(auth)..session = _sesion('actual');
      expect(await api.tokenTrasRechazo('viejo'), 'actual');
      expect(auth.renovaciones, 0);
    });

    test('Supabase rechaza el refresh token: sesión fuera y aviso para volver al login', () async {
      final auth = _AuthFalso()..error = const AuthException('Tu sesión ha caducado. Vuelve a iniciar sesión.');
      final api = ApiService(auth)..session = _sesion('viejo');
      String? aviso;
      api.alPerderSesion = (m) => aviso = m;
      expect(await api.tokenTrasRechazo('viejo'), isNull);
      expect(api.session, isNull);
      expect(aviso, contains('caducado'));
    });

    test('un fallo pasajero al renovar (sin red, 5xx) NO cierra la sesión', () async {
      final auth = _AuthFalso()..error = Exception('No se pudo renovar la sesión (503)');
      final api = ApiService(auth)..session = _sesion('viejo');
      var avisos = 0;
      api.alPerderSesion = (_) => avisos++;
      expect(await api.tokenTrasRechazo('viejo'), isNull);
      expect(api.session?.accessToken, 'viejo');
      expect(avisos, 0);
      // Y al volver la red, se puede renovar otra vez.
      auth.error = null;
      expect(await api.tokenTrasRechazo('viejo'), startsWith('nuevo'));
    });
  });

  test('AuthProvider vuelve al login cuando la sesión muere en mitad del uso', () async {
    final auth = _AuthFalso()..guardada = _sesion('vigente');
    final api = ApiService(auth, client: MockClient((_) async => http.Response('{}', 200)));
    final p = AuthProvider(authService: auth, apiService: api);
    await p.bootstrap();
    expect(p.status, AuthStatus.authenticated);

    auth.error = const AuthException('Tu sesión ha caducado. Vuelve a iniciar sesión.');
    expect(await api.tokenTrasRechazo('vigente'), isNull);
    expect(p.status, AuthStatus.unauthenticated);
    expect(p.error, contains('caducado'));
  });
}
