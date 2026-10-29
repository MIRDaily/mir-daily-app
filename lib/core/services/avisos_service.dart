// Bandeja de avisos del servidor: GET /api/notifications, /unread-count, POST /:id/read y /read-all.
// Puerto de la web: src/service/api/notifications.js + NotificationsProvider (el contador compartido).
//
// El servidor genera los avisos del daily al pedirle la lista o el contador (motor «lazy»), así que
// basta con preguntar al abrir la app, al volver a ella y al abrir la bandeja.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/avisos.dart';

class AvisosException implements Exception {
  final String message;
  final int? status;
  const AvisosException(this.message, {this.status});
  @override
  String toString() => message;
}

/// `all` o `unread`: los dos filtros que enseña la página de la web.
enum FiltroAvisos {
  todos('all'),
  noLeidos('unread');

  final String valor;
  const FiltroAvisos(this.valor);
}

class AvisosApi {
  final Future<String> Function() _token;
  final String _baseUrl;
  final http.Client _client;

  AvisosApi({
    required Future<String> Function() token,
    required String baseUrl,
    http.Client? client,
  })  : _token = token,
        _baseUrl = baseUrl,
        _client = client ?? http.Client();

  Future<Map<String, dynamic>> _pedir(String ruta, {Map<String, dynamic>? cuerpo, required String mensaje}) async {
    final token = await _token();
    if (token.isEmpty) throw const AvisosException('No hay sesión activa', status: 401);
    final req = http.Request(cuerpo == null ? 'GET' : 'POST', Uri.parse('$_baseUrl/api/notifications$ruta'))
      ..headers['Authorization'] = 'Bearer $token'
      ..headers['Content-Type'] = 'application/json';
    if (cuerpo != null) req.body = jsonEncode(cuerpo);
    final http.Response res;
    try {
      res = await _client.send(req).then(http.Response.fromStream).timeout(const Duration(seconds: 20));
    } catch (_) {
      throw const AvisosException('No se pudo conectar con el servidor');
    }
    Map<String, dynamic>? j;
    try {
      final d = jsonDecode(res.body);
      if (d is Map) j = Map<String, dynamic>.from(d);
    } catch (_) {}
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw AvisosException(j?['error'] is String ? j!['error'] as String : mensaje, status: res.statusCode);
    }
    return j ?? <String, dynamic>{};
  }

  /// La lista (la más reciente primero) y el total de no leídas, que el servidor manda aparte.
  Future<({List<Aviso> avisos, int noLeidas})> lista({FiltroAvisos filtro = FiltroAvisos.todos, int limite = 20}) async {
    final r = await _pedir('?filter=${filtro.valor}&limit=$limite', mensaje: 'No se pudieron cargar las notificaciones');
    final items = r['items'];
    return (
      avisos: items is List
          ? items.whereType<Map>().map((m) => Aviso.fromJson(Map<String, dynamic>.from(m))).toList()
          : <Aviso>[],
      noLeidas: r['unreadCount'] is num ? (r['unreadCount'] as num).toInt() : 0,
    );
  }

  Future<int> noLeidas() async {
    final r = await _pedir('/unread-count', mensaje: 'No se pudo leer el contador');
    return r['unreadCount'] is num ? (r['unreadCount'] as num).toInt() : 0;
  }

  Future<void> marcarLeido(String id) =>
      _pedir('/${Uri.encodeComponent(id)}/read', cuerpo: const {}, mensaje: 'No se pudo marcar como leída');

  Future<void> marcarTodos({FiltroAvisos filtro = FiltroAvisos.todos}) =>
      _pedir('/read-all', cuerpo: {'filter': filtro.valor}, mensaje: 'No se pudieron marcar como leídas');
}

/// El contador de no leídas, compartido por la navegación y el Perfil. Por cuenta: al cambiar de
/// usuario vuelve a cero y se pide de nuevo.
class Avisos extends ChangeNotifier {
  final AvisosApi api;

  Avisos(this.api);

  int noLeidas = 0;
  String? _usuario;
  String? get usuario => _usuario;
  Future<void>? _enCurso;

  /// Pide el contador al servidor. Un fallo de red deja el que hubiera.
  Future<void> refrescar() {
    if (_usuario == null) return Future.value();
    final usuario = _usuario;
    return _enCurso ??= () async {
      try {
        final n = await api.noLeidas();
        if (usuario == _usuario) poner(n);
      } catch (_) {
      } finally {
        _enCurso = null;
      }
    }();
  }

  void poner(int n) {
    final v = n < 0 ? 0 : n;
    if (v == noLeidas) return;
    noLeidas = v;
    notifyListeners();
  }

  void restarUno() => poner(noLeidas - 1);

  void setUsuario(String? usuario) {
    if (usuario == _usuario) return;
    _usuario = usuario;
    noLeidas = 0;
    // Llega desde el `update` de un ProxyProvider (en pleno build): se avisa después.
    scheduleMicrotask(() {
      notifyListeners();
      if (usuario != null) refrescar();
    });
  }
}
