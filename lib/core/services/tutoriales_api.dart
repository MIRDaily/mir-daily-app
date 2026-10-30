// Lo visto de los tutoriales, en la cuenta: POST y DELETE /api/profile/tutorials.
// Puerto de la web: src/lib/tutorials/storage.ts (marcarVisto y reiniciarTutoriales).
//
// La lista se LEE con el perfil (GET /api/profile → `tutorials_seen`); aquí solo se escribe. El
// servidor valida la clave («pantalla.vN») y es idempotente: marcar dos veces no hace nada.

import 'dart:convert';

import 'package:http/http.dart' as http;

class TutorialesException implements Exception {
  final String message;
  final int? status;
  const TutorialesException(this.message, {this.status});
  @override
  String toString() => message;
}

class TutorialesApi {
  final Future<String> Function() _token;
  final String _baseUrl;
  final http.Client _client;

  TutorialesApi({
    required Future<String> Function() token,
    required String baseUrl,
    http.Client? client,
  })  : _token = token,
        _baseUrl = baseUrl,
        _client = client ?? http.Client();

  Future<Map<String, dynamic>> _pedir(String metodo, {Map<String, dynamic>? cuerpo, required String mensaje}) async {
    final token = await _token();
    if (token.isEmpty) throw const TutorialesException('No hay sesión activa', status: 401);
    final req = http.Request(metodo, Uri.parse('$_baseUrl/api/profile/tutorials'))
      ..headers['Authorization'] = 'Bearer $token'
      ..headers['Content-Type'] = 'application/json';
    if (cuerpo != null) req.body = jsonEncode(cuerpo);
    final http.Response res;
    try {
      res = await _client.send(req).then(http.Response.fromStream).timeout(const Duration(seconds: 20));
    } catch (_) {
      throw const TutorialesException('No se pudo conectar con el servidor');
    }
    Map<String, dynamic>? j;
    try {
      final d = jsonDecode(res.body);
      if (d is Map) j = Map<String, dynamic>.from(d);
    } catch (_) {}
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw TutorialesException(j?['error'] is String ? j!['error'] as String : mensaje, status: res.statusCode);
    }
    return j ?? <String, dynamic>{};
  }

  /// Marca un tutorial como visto. Devuelve la lista que queda en el servidor (vacía si al servidor
  /// le falta la migración: responde `pendingMigration` y no guarda nada, sin error).
  Future<List<String>> marcar(String clave) async {
    final r = await _pedir('POST', cuerpo: {'key': clave}, mensaje: 'No se pudo guardar el tutorial');
    final l = r['tutorials_seen'];
    return l is List ? l.whereType<String>().toList() : const [];
  }

  /// Los olvida todos, en todos los dispositivos (el «volver a verlos» del Perfil).
  Future<void> reiniciar() => _pedir('DELETE', mensaje: 'No se pudieron reiniciar los tutoriales');
}
