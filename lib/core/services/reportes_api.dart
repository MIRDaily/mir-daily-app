// Reportes de contenido: POST /api/reports y GET /api/reports/mine.
// Puerto de la web: src/lib/reports/api.ts.
//
// El servidor valida todo (categorías, límite de 20 al día con su 429, foto de la pregunta, duplicados:
// si ya tenías uno abierto de ese tipo lo actualiza y responde `updated: true`). Aquí solo se manda y se
// enseña su mensaje, que ya viene en castellano.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/reportes.dart';

class ReporteException implements Exception {
  final String message;
  final int? status;
  const ReporteException(this.message, {this.status});
  @override
  String toString() => message;
}

class ReportesApi {
  final Future<String> Function() _token;
  final String _baseUrl;
  final http.Client _client;

  ReportesApi({
    required Future<String> Function() token,
    required String baseUrl,
    http.Client? client,
  })  : _token = token,
        _baseUrl = baseUrl,
        _client = client ?? http.Client();

  Future<Map<String, dynamic>> _pedir(String ruta, {Map<String, dynamic>? cuerpo, required String mensaje}) async {
    final token = await _token();
    if (token.isEmpty) throw const ReporteException('Inicia sesión para reportar', status: 401);
    final req = http.Request(cuerpo == null ? 'GET' : 'POST', Uri.parse('$_baseUrl/api/reports$ruta'))
      ..headers['Authorization'] = 'Bearer $token'
      ..headers['Content-Type'] = 'application/json';
    if (cuerpo != null) req.body = jsonEncode(cuerpo);
    final http.Response res;
    try {
      res = await _client.send(req).then(http.Response.fromStream).timeout(const Duration(seconds: 20));
    } catch (_) {
      throw const ReporteException('No se pudo conectar con el servidor');
    }
    Map<String, dynamic>? j;
    try {
      final d = jsonDecode(res.body);
      if (d is Map) j = Map<String, dynamic>.from(d);
    } catch (_) {}
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ReporteException(j?['error'] is String ? j!['error'] as String : mensaje, status: res.statusCode);
    }
    return j ?? <String, dynamic>{};
  }

  /// Manda el reporte. Devuelve true si corrigió uno tuyo que seguía abierto.
  Future<bool> enviar({
    required int questionId,
    required ContextoReporte contexto,
    required String categoria,
    String? subcategoria,
    int? sugerida,
    String mensaje = '',
    String? appVersion,
    String? userAgent,
  }) async {
    final r = await _pedir(
      '',
      cuerpo: cuerpoReporte(
        questionId: questionId,
        contexto: contexto,
        categoria: categoria,
        subcategoria: subcategoria,
        sugerida: sugerida,
        mensaje: mensaje,
        appVersion: appVersion,
        userAgent: userAgent,
      ),
      mensaje: 'No se pudo enviar el reporte',
    );
    Reportadas.instancia.marcar(claveContenido(questionId));
    return r['updated'] == true;
  }

  /// Tus reportes abiertos de esa pregunta (el más reciente primero).
  Future<List<MiReporte>> mios(int questionId) async {
    final r = await _pedir(
      '/mine?contentKey=${Uri.encodeQueryComponent(claveContenido(questionId))}',
      mensaje: 'No se pudieron leer tus reportes',
    );
    final l = r['reports'];
    return l is List ? l.whereType<Map>().map((m) => MiReporte.fromJson(Map<String, dynamic>.from(m))).toList() : const [];
  }
}

/// Qué preguntas se han reportado en esta sesión de la app, para pintar la bandera rellena sin
/// preguntar al servidor por cada una (como el `Set` de la web, que dura lo que la pestaña).
class Reportadas extends ChangeNotifier {
  Reportadas._();
  static final Reportadas instancia = Reportadas._();

  final Set<String> _claves = {};

  bool contiene(String clave) => _claves.contains(clave);

  void marcar(String clave) {
    if (_claves.add(clave)) notifyListeners();
  }

  /// Al cambiar de cuenta, lo reportado por la anterior no cuenta.
  void olvidar() {
    if (_claves.isEmpty) return;
    _claves.clear();
    notifyListeners();
  }
}
