import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';

/// Sesión de Supabase (la misma que usa la web).
class AuthSession {
  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
  final String userId;
  final String? email;

  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.userId,
    this.email,
  });

  bool get isExpired =>
      DateTime.now().isAfter(expiresAt.subtract(const Duration(seconds: 60)));

  Map<String, dynamic> toJson() => {
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'expiresAt': expiresAt.millisecondsSinceEpoch,
        'userId': userId,
        'email': email,
      };

  factory AuthSession.fromJson(Map<String, dynamic> json) => AuthSession(
        accessToken: json['accessToken'] as String,
        refreshToken: json['refreshToken'] as String,
        expiresAt:
            DateTime.fromMillisecondsSinceEpoch(json['expiresAt'] as int),
        userId: json['userId'] as String,
        email: json['email'] as String?,
      );

  factory AuthSession.fromSupabase(Map<String, dynamic> data) {
    final user = (data['user'] ?? {}) as Map<String, dynamic>;
    final expiresIn = ((data['expires_in'] ?? 3600) as num).round();
    return AuthSession(
      accessToken: data['access_token'] as String,
      refreshToken: data['refresh_token'] as String,
      expiresAt: DateTime.now().add(Duration(seconds: expiresIn)),
      userId: user['id'].toString(),
      email: user['email'] as String?,
    );
  }
}

class AuthException implements Exception {
  final String message;
  const AuthException(this.message);
  @override
  String toString() => message;
}

/// Autenticación contra Supabase Auth (REST), sin SDK:
/// el access_token resultante se envía como `Authorization: Bearer`
/// al backend de Railway, igual que hace el frontend web.
class AuthService {
  static const _storageKey = 'mirdaily_session_v1';

  Uri _authUri(String path, [Map<String, String>? query]) =>
      Uri.parse('${AppConfig.supabaseUrl}/auth/v1/$path')
          .replace(queryParameters: query);

  Map<String, String> get _headers => {
        'apikey': AppConfig.supabaseAnonKey,
        'Content-Type': 'application/json',
      };

  Future<AuthSession> signInWithPassword({
    required String email,
    required String password,
  }) async {
    final res = await http
        .post(
          _authUri('token', {'grant_type': 'password'}),
          headers: _headers,
          body: jsonEncode({'email': email.trim(), 'password': password}),
        )
        .timeout(const Duration(seconds: 20));

    final body = jsonDecode(res.body) as Map<String, dynamic>;

    if (res.statusCode != 200) {
      throw AuthException(_friendlyError(body));
    }

    final session = AuthSession.fromSupabase(body);
    await persistSession(session);
    return session;
  }

  /// Registro con email y contraseña (como RegisterCard en la web).
  /// Devuelve la sesión si el proyecto no exige confirmar email, o null
  /// si hay que confirmar el correo antes de entrar.
  Future<AuthSession?> signUp({
    required String email,
    required String password,
  }) async {
    final res = await http
        .post(
          _authUri('signup'),
          headers: _headers,
          body: jsonEncode({'email': email.trim(), 'password': password}),
        )
        .timeout(const Duration(seconds: 20));

    final body = jsonDecode(res.body) as Map<String, dynamic>;

    if (res.statusCode != 200) {
      throw AuthException(_friendlyError(body));
    }

    if (body['access_token'] != null) {
      final session = AuthSession.fromSupabase(body);
      await persistSession(session);
      return session;
    }
    return null; // pendiente de confirmación por email
  }

  /// Email de recuperación de contraseña.
  Future<void> recoverPassword(String email) async {
    final res = await http
        .post(
          _authUri('recover'),
          headers: _headers,
          body: jsonEncode({'email': email.trim()}),
        )
        .timeout(const Duration(seconds: 20));

    if (res.statusCode != 200) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      throw AuthException(_friendlyError(body));
    }
  }

  /// Deep link al que Supabase devuelve los tokens tras el OAuth.
  /// Debe estar en la allowlist del panel de Supabase
  /// (Authentication → URL Configuration → Redirect URLs).
  static const oauthRedirect = 'com.mirdaily.app://auth-callback';

  /// URL del flujo OAuth (se abre en el navegador del sistema).
  Uri oauthAuthorizeUrl(String provider) {
    return Uri.parse(
      '${AppConfig.supabaseUrl}/auth/v1/authorize'
      '?provider=$provider'
      '&redirect_to=${Uri.encodeComponent(oauthRedirect)}',
    );
  }

  /// Parsea el deep link de vuelta del OAuth
  /// (com.mirdaily.app://auth-callback#access_token=...&refresh_token=...).
  Future<AuthSession?> sessionFromOAuthCallback(Uri uri) async {
    final fragment = uri.fragment;
    if (fragment.isEmpty) return null;

    final params = Uri.splitQueryString(fragment);
    final accessToken = params['access_token'];
    final refreshToken = params['refresh_token'];
    if (accessToken == null || refreshToken == null) {
      final desc = params['error_description'];
      if (desc != null) {
        throw AuthException(Uri.decodeComponent(desc.replaceAll('+', ' ')));
      }
      return null;
    }

    final expiresIn = int.tryParse(params['expires_in'] ?? '') ?? 3600;

    // El user id va dentro del JWT (claim sub).
    final userId = _jwtClaim(accessToken, 'sub') ?? '';
    final email = _jwtClaim(accessToken, 'email');

    final session = AuthSession(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresAt: DateTime.now().add(Duration(seconds: expiresIn)),
      userId: userId,
      email: email,
    );
    await persistSession(session);
    return session;
  }

  String? _jwtClaim(String jwt, String claim) {
    try {
      final parts = jwt.split('.');
      if (parts.length != 3) return null;
      final payload = utf8.decode(
        base64Url.decode(base64Url.normalize(parts[1])),
      );
      final map = jsonDecode(payload) as Map<String, dynamic>;
      return map[claim]?.toString();
    } catch (_) {
      return null;
    }
  }

  Future<AuthSession> refresh(AuthSession session) async {
    final res = await http
        .post(
          _authUri('token', {'grant_type': 'refresh_token'}),
          headers: _headers,
          body: jsonEncode({'refresh_token': session.refreshToken}),
        )
        .timeout(const Duration(seconds: 20));

    final body = jsonDecode(res.body) as Map<String, dynamic>;

    if (res.statusCode != 200) {
      await clearSession();
      throw const AuthException(
          'Tu sesión ha caducado. Vuelve a iniciar sesión.');
    }

    final refreshed = AuthSession.fromSupabase(body);
    await persistSession(refreshed);
    return refreshed;
  }

  Future<void> persistSession(AuthSession session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(session.toJson()));
  }

  Future<AuthSession?> loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null) return null;
    try {
      return AuthSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      await prefs.remove(_storageKey);
      return null;
    }
  }

  Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }

  // ==========================
  // RECORDAR CREDENCIALES (opción "Recordar mis datos" del login)
  // ==========================
  static const _rememberKey = 'mirdaily_remember_v1';

  Future<void> saveRememberedCredentials(
      String email, String password) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _rememberKey,
      jsonEncode({'email': email.trim(), 'password': password}),
    );
  }

  /// Devuelve {'email','password'} si el usuario marcó "Recordar mis datos".
  Future<Map<String, String>?> loadRememberedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_rememberKey);
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return {
        'email': (map['email'] ?? '') as String,
        'password': (map['password'] ?? '') as String,
      };
    } catch (_) {
      await prefs.remove(_rememberKey);
      return null;
    }
  }

  Future<void> clearRememberedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_rememberKey);
  }

  String _friendlyError(Map<String, dynamic> body) {
    final code = (body['error_code'] ?? body['code'] ?? '').toString();
    final msg = (body['error_description'] ?? body['msg'] ?? body['message'])
        ?.toString();

    switch (code) {
      case 'invalid_credentials':
        return 'Email o contraseña incorrectos.';
      case 'email_not_confirmed':
        return 'Confirma tu email antes de entrar.';
      case 'over_request_rate_limit':
      case 'over_email_send_rate_limit':
        return 'Demasiados intentos. Espera un momento.';
      case 'user_already_exists':
      case 'email_exists':
        return 'Ya existe una cuenta con ese email.';
      case 'weak_password':
        return 'La contraseña es demasiado débil (mínimo 6 caracteres).';
      case 'validation_failed':
        return 'Revisa el email introducido.';
    }
    if (msg != null && msg.toLowerCase().contains('invalid login')) {
      return 'Email o contraseña incorrectos.';
    }
    return msg ?? 'No se pudo iniciar sesión. Inténtalo de nuevo.';
  }
}
