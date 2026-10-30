// Los mapas mentales del usuario: la tabla `public.mind_maps`, directa por PostgREST con la sesión
// del usuario, como la web (src/lib/mapas/api.ts). RLS deja a cada uno solo lo suyo.
//
// - La lista NO baja los documentos (la web sí, hasta la tanda 6 de Studio): solo título,
//   asignatura, fecha, fijado y carpeta. Sin miniatura por ahora.
// - Guardar es «sin pisar»: solo se escribe si `updated_at` sigue siendo el que se leyó (lo pone un
//   disparador en cada guardado). Si la web guardó entre medias, no se escribe nada y se avisa con
//   [MapaCambiadoException]. Es el bloqueo optimista que la tanda 6 de Studio llevará a la web.

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/mapas.dart';

class MapasException implements Exception {
  final String message;
  final int? status;
  const MapasException(this.message, {this.status});
  @override
  String toString() => message;
}

/// El mapa cambió en otro sitio (la web, otro móvil) desde que se abrió aquí.
class MapaCambiadoException extends MapasException {
  const MapaCambiadoException() : super('Este mapa ha cambiado en otro sitio desde que lo abriste.');
}

class ResumenMapa {
  final String id;
  final String titulo;
  final String? asignatura;
  final DateTime actualizado;
  final bool fijado;

  const ResumenMapa({
    required this.id,
    required this.titulo,
    required this.asignatura,
    required this.actualizado,
    required this.fijado,
  });

  /// El de ejemplo que se reparte a todos (sql/2026-10-mapa-ejemplo-para-todos.sql) lleva esta
  /// asignatura reservada.
  bool get ejemplo => asignatura == 'ejemplo-temporal';

  factory ResumenMapa.fromJson(Map<String, dynamic> j) => ResumenMapa(
        id: j['id'] as String,
        titulo: (j['title'] as String?)?.trim().isNotEmpty == true ? j['title'] as String : 'Mapa sin título',
        asignatura: j['subject'] as String?,
        actualizado: DateTime.tryParse('${j['updated_at']}')?.toLocal() ?? DateTime.fromMillisecondsSinceEpoch(0),
        fijado: j['pinned'] == true,
      );
}

class MapaGuardado {
  final String id;
  final String titulo;
  final String? asignatura;

  /// Tal cual lo devuelve la BD: es la marca con la que se guarda «sin pisar».
  final String actualizadoEn;
  final DocMapa doc;

  const MapaGuardado({
    required this.id,
    required this.titulo,
    required this.asignatura,
    required this.actualizadoEn,
    required this.doc,
  });
}

class MapasApi {
  final Future<String> Function() _token;
  final String _supabaseUrl;
  final String _anonKey;
  final http.Client _client;

  MapasApi({
    required Future<String> Function() token,
    required String supabaseUrl,
    required String anonKey,
    http.Client? client,
  })  : _token = token,
        _supabaseUrl = supabaseUrl,
        _anonKey = anonKey,
        _client = client ?? http.Client();

  Future<(int, Object?)> _pedir(String metodo, String query, {Object? cuerpo, bool devolver = false}) async {
    final token = await _token();
    if (token.isEmpty) throw const MapasException('No hay sesión activa', status: 401);
    final req = http.Request(metodo, Uri.parse('$_supabaseUrl/rest/v1/mind_maps?$query'))
      ..headers['apikey'] = _anonKey
      ..headers['Authorization'] = 'Bearer $token'
      ..headers['Accept'] = 'application/json'
      ..headers['Content-Type'] = 'application/json';
    if (devolver) req.headers['Prefer'] = 'return=representation';
    if (cuerpo != null) req.body = jsonEncode(cuerpo);
    final http.Response res;
    try {
      res = await _client.send(req).then(http.Response.fromStream).timeout(const Duration(seconds: 25));
    } catch (_) {
      throw const MapasException('No se pudo conectar con el servidor');
    }
    Object? j;
    try {
      j = jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {}
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final msg = j is Map && j['message'] is String ? j['message'] as String : 'Error del servidor (${res.statusCode})';
      throw MapasException(msg, status: res.statusCode);
    }
    return (res.statusCode, j);
  }

  /// Los mapas sin borrar, el más reciente primero. Si a la BD le falta la columna `pinned`, se
  /// pide sin ella (como la web).
  Future<List<ResumenMapa>> lista() async {
    const base = 'deleted_at=is.null&order=updated_at.desc';
    Object? j;
    try {
      (_, j) = await _pedir('GET', 'select=id,title,subject,updated_at,pinned&$base');
    } on MapasException catch (e) {
      if (!e.message.contains('pinned')) rethrow;
      (_, j) = await _pedir('GET', 'select=id,title,subject,updated_at&$base');
    }
    final filas = j is List ? j : const [];
    final mapas = [for (final f in filas) if (f is Map) ResumenMapa.fromJson(Map<String, dynamic>.from(f))];
    // Fijados arriba, como en la web; dentro de cada grupo, por fecha.
    mapas.sort((a, b) => a.fijado == b.fijado ? b.actualizado.compareTo(a.actualizado) : (a.fijado ? -1 : 1));
    return mapas;
  }

  /// Un mapa con su documento, o null si no existe o está en la papelera.
  Future<MapaGuardado?> abrir(String id) async {
    final (_, j) = await _pedir(
      'GET',
      'select=id,title,subject,updated_at,doc&id=eq.${Uri.encodeQueryComponent(id)}&deleted_at=is.null',
    );
    final f = j is List && j.isNotEmpty && j.first is Map ? Map<String, dynamic>.from(j.first as Map) : null;
    if (f == null) return null;
    return MapaGuardado(
      id: f['id'] as String,
      titulo: (f['title'] as String?) ?? 'Mapa sin título',
      asignatura: f['subject'] as String?,
      actualizadoEn: '${f['updated_at']}',
      doc: DocMapa.desde(f['doc']),
    );
  }

  /// Guarda título y/o documento «sin pisar». Devuelve la marca nueva (`updated_at`). Con
  /// [forzar], escribe aunque haya cambiado (el usuario eligió quedarse con lo de la app).
  Future<String> guardar(
    String id, {
    required String actualizadoEn,
    String? titulo,
    DocMapa? doc,
    bool forzar = false,
  }) async {
    final cambios = <String, dynamic>{
      if (titulo != null) 'title': titulo.trim().isEmpty ? 'Mapa sin título' : titulo.trim().substring(0, titulo.trim().length.clamp(0, 200)),
      if (doc != null) 'doc': doc.json,
    };
    if (cambios.isEmpty) return actualizadoEn;
    final filtro = 'id=eq.${Uri.encodeQueryComponent(id)}'
        '${forzar ? '' : '&updated_at=eq.${Uri.encodeQueryComponent(actualizadoEn)}'}';
    final (_, j) = await _pedir('PATCH', '$filtro&select=updated_at', cuerpo: cambios, devolver: true);
    if (j is! List || j.isEmpty) {
      if (forzar) throw const MapasException('El mapa ya no existe (¿lo borraste en la web?)');
      throw const MapaCambiadoException();
    }
    return '${(j.first as Map)['updated_at']}';
  }
}
