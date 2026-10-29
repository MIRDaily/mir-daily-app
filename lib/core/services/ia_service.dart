// Cliente de los endpoints de IA (mapas, flashcards y resúmenes activos).
//
// El permiso (rol admin, interruptor y cupos) lo valida SIEMPRE el backend;
// aquí solo se hace la llamada y se devuelve lo que responda. Reutiliza el token
// de sesión de la app (se le pasa `ApiService.validToken`), como hace Versus.

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/ia.dart';
import 'ia_indice.dart';
import 'ia_stream.dart';

/// Área de IA: cada una tiene su propio router bajo /api/admin.
enum IaArea {
  mapas('/api/admin/mapas-ia'),
  flashcards('/api/admin/flashcards-ia'),
  resumenes('/api/admin/resumenes-ia');

  const IaArea(this.base);
  final String base;
}

/// Mensaje para un streaming que se corta antes del resultado final.
const String mensajeCortadoIa =
    'Se cortó la conexión con el servidor antes de terminar. No se ha guardado nada: vuelve a intentarlo.';

class IaService {
  final Future<String> Function() _token;
  final String _baseUrl;
  final http.Client _client;

  IaService({
    required Future<String> Function() token,
    required String baseUrl,
    http.Client? client,
  })  : _token = token,
        _baseUrl = baseUrl,
        _client = client ?? http.Client();

  Future<String> _tokenSeguro() async {
    final t = await _token();
    if (t.isEmpty) {
      throw const IaException('Inicia sesión para usar la IA', status: 401);
    }
    return t;
  }

  /// `null` si la función no está disponible para este usuario (no admin, apagada…).
  Future<Map<String, dynamic>?> estado(IaArea area) async {
    try {
      final req = await _peticion('GET', '${area.base}/estado');
      final res = await _client
          .send(req)
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 20));
      final cuerpo = _json(res.body);
      if (res.statusCode < 200 || res.statusCode >= 300) return null;
      return cuerpo?['disponible'] == true ? cuerpo : null;
    } catch (_) {
      return null;
    }
  }

  /// Índice de un documento largo: solo viaja el principio de cada sección.
  Future<List<TemaIndice>> indice(
    IaArea area, {
    required String titulo,
    required List<Seccion> secciones,
  }) async {
    final cuerpo = await post(area, path: '/indice', cuerpo: {
      'titulo': titulo,
      'secciones': resumenParaIndice(secciones),
    });
    return sanitizeTemas(cuerpo['temas'], secciones.length);
  }

  /// Llama a un endpoint de IA. Con `onEvento`, lee la respuesta en streaming
  /// (NDJSON) y devuelve los datos del evento «fin»; sin él, lee el JSON normal.
  Future<Map<String, dynamic>> post(
    IaArea area, {
    String path = '',
    required Map<String, dynamic> cuerpo,
    void Function(EventoIa)? onEvento,
  }) async {
    final req = await _peticion('POST', '${area.base}$path', body: jsonEncode(cuerpo));

    if (onEvento == null) {
      req.headers['Accept'] = 'application/json';
      final res = await _client.send(req).then(http.Response.fromStream);
      return _cuerpoOError(res.statusCode, res.body);
    }

    req.headers['Accept'] = 'application/x-ndjson';
    final res = await _client.send(req);
    return _leerStreaming(res, onEvento);
  }

  Future<http.Request> _peticion(String method, String path, {String? body}) async {
    final token = await _tokenSeguro();
    final req = http.Request(method, Uri.parse('$_baseUrl$path'))
      ..headers['Authorization'] = 'Bearer $token'
      ..headers['Content-Type'] = 'application/json';
    if (body != null) req.body = body;
    return req;
  }

  Map<String, dynamic> _cuerpoOError(int status, String body) {
    final cuerpo = _json(body);
    if (status < 200 || status >= 300) {
      final error = cuerpo?['error'];
      final codigo = cuerpo?['codigo'] ?? cuerpo?['motivo'];
      throw IaException(
        error is String ? error : 'No se pudo completar la operación',
        status: status,
        codigo: codigo is String ? codigo : '',
        datos: cuerpo,
      );
    }
    return cuerpo ?? <String, dynamic>{};
  }

  Future<Map<String, dynamic>> _leerStreaming(
    http.StreamedResponse res,
    void Function(EventoIa) onEvento,
  ) async {
    final tipo = (res.headers['content-type'] ?? '').toLowerCase();
    if (!tipo.contains('application/x-ndjson')) {
      // Servidor antiguo, o un error antes de empezar (cupo, petición no válida):
      // se lee como el JSON de siempre.
      final cuerpo = await res.stream.bytesToString();
      return _cuerpoOError(res.statusCode, cuerpo);
    }

    Map<String, dynamic>? finDatos;
    IaException? fallo;
    final lector = LectorLineas((linea) {
      if (finDatos != null || fallo != null) return;
      final e = leerEvento(linea);
      if (e == null) return;
      if (e is EventoFin) {
        finDatos = e.datos;
      } else if (e is EventoError) {
        fallo = IaException(e.error, status: e.status, codigo: e.codigo, datos: e.datos);
      } else {
        onEvento(e);
      }
    });

    try {
      await for (final trozo in res.stream.transform(utf8.decoder)) {
        lector.push(trozo);
      }
      lector.fin();
    } catch (_) {
      throw const IaException(mensajeCortadoIa, codigo: 'cortado');
    }

    if (fallo != null) throw fallo!;
    if (finDatos == null) {
      throw const IaException(mensajeCortadoIa, codigo: 'cortado');
    }
    return finDatos!;
  }

  Map<String, dynamic>? _json(String body) {
    try {
      final j = jsonDecode(body);
      if (j is Map<String, dynamic>) return j;
      if (j is Map) return Map<String, dynamic>.from(j);
      return null;
    } catch (_) {
      return null;
    }
  }
}
