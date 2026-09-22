// Arrancar la app sin conexión NO puede echarte de tu cuenta (causa A6).
//
//   flutter test test/sesion_sin_conexion_test.dart
//
// `bootstrap` metía por el mismo `catch` dos cosas muy distintas: que el
// servidor conteste que la sesión no vale, y que no haya servidor al que
// preguntar. Lo segundo pasa cada vez que se abre la app en el metro, y te
// mandaba a la pantalla de login. Cuando además la referencia de logros era una
// clave global que se borraba al salir, ese viaje se llevaba por delante todo
// lo que estuviera pendiente de celebrar.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mirdaily_app/core/providers/auth_provider.dart';
import 'package:mirdaily_app/core/services/api_service.dart';
import 'package:mirdaily_app/core/services/auth_service.dart';

AuthSession _caducada() => AuthSession(
      accessToken: 'viejo',
      refreshToken: 'r',
      expiresAt: DateTime.now().subtract(const Duration(hours: 1)),
      userId: 'u1',
    );

/// Un AuthService que no sale a la red: decide en el acto qué pasa al renovar.
class _AuthFalso extends AuthService {
  final Object? alRenovar;
  final AuthSession? guardada;
  bool limpiada = false;

  _AuthFalso({this.alRenovar, this.guardada});

  @override
  Future<AuthSession?> loadSession() async => guardada;

  @override
  Future<AuthSession> refresh(AuthSession session) async {
    if (alRenovar != null) throw alRenovar!;
    return AuthSession(
      accessToken: 'nuevo',
      refreshToken: 'r2',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
      userId: session.userId,
    );
  }

  @override
  Future<void> clearSession() async => limpiada = true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('sin red, la sesión se mantiene (modo sin conexión)', () async {
    final auth = _AuthFalso(
      guardada: _caducada(),
      // Lo que lanza `http.post` cuando no hay a quién preguntar.
      alRenovar: TimeoutException('sin red'),
    );
    final api = ApiService(auth);
    final p = AuthProvider(authService: auth, apiService: api);

    await p.bootstrap();

    expect(p.status, AuthStatus.authenticated,
        reason: 'abrir la app en el metro no puede cerrarte la sesión');
    expect(p.sinConexion, isTrue);
    expect(api.session, isNotNull,
        reason: 'el token guardado sigue ahí: se reintentará al haber red');
    expect(p.userId, 'u1');
    expect(auth.limpiada, isFalse, reason: 'no se borra nada del disco');
  });

  test('credenciales rechazadas de verdad: ahí sí se cierra', () async {
    final auth = _AuthFalso(
      guardada: _caducada(),
      // Esto es lo que lanza `AuthService.refresh` ante un 4xx de Supabase, y
      // solo después de haber borrado ya la sesión del disco.
      alRenovar: const AuthException('Tu sesión ha caducado.'),
    );
    final api = ApiService(auth);
    final p = AuthProvider(authService: auth, apiService: api);

    await p.bootstrap();

    expect(p.status, AuthStatus.unauthenticated);
    expect(api.session, isNull);
    expect(p.userId, isNull);
    expect(p.error, isNotNull, reason: 'y se le dice por qué');
  });

  test('con red y token válido, nada de esto se nota', () async {
    final auth = _AuthFalso(guardada: _caducada());
    final api = ApiService(auth);
    final p = AuthProvider(authService: auth, apiService: api);

    await p.bootstrap();

    expect(p.status, AuthStatus.authenticated);
    expect(p.sinConexion, isFalse);
    expect(api.session?.accessToken, 'nuevo');
  });

  test('sin sesión guardada se va al login, como siempre', () async {
    final auth = _AuthFalso();
    final api = ApiService(auth);
    final p = AuthProvider(authService: auth, apiService: api);

    await p.bootstrap();

    expect(p.status, AuthStatus.unauthenticated);
    expect(p.userId, isNull);
  });
}
