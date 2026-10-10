// Cliente de "Resúmenes activos" (/api/resumenes): grupos, párrafos y estudio.
// Todo lo que llega se sanea (los huecos, con las mismas reglas que el servidor).
// Como las flashcards, no cuenta para las estadísticas del MIR.
//
// Puerto de la web: src/lib/resumenes/api.ts.

import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../../core/models/resumen.dart';
import 'resumenes_huecos.dart';

class ResumenesApiError implements Exception {
  final String message;
  final int? status;
  final int? caben;
  final bool? limite;
  final bool? literal;

  const ResumenesApiError(this.message, {this.status, this.caben, this.limite, this.literal});

  @override
  String toString() => message;
}

int _num(dynamic v) => v is num && v.isFinite ? v.toInt() : 0;

EstadoParrafoSrs? _estadoDe(String s) {
  switch (s) {
    case 'new':
      return EstadoParrafoSrs.new_;
    case 'failed':
      return EstadoParrafoSrs.failed;
    case 'learning':
      return EstadoParrafoSrs.learning;
    case 'mastered':
      return EstadoParrafoSrs.mastered;
  }
  return null;
}

GrupoResumen? sanearGrupo(dynamic raw) {
  if (raw is! Map) return null;
  final id = raw['id'];
  final name = raw['name'];
  if (id is! String || name is! String) return null;
  final r = raw['resumen'] is Map ? raw['resumen'] as Map : const {};
  return GrupoResumen(
    id: id,
    name: name.length > 80 ? name.substring(0, 80) : name,
    description: raw['description'] is String ? raw['description'] as String : null,
    color: raw['color'] is String ? raw['color'] as String : null,
    icon: raw['icon'] is String ? raw['icon'] as String : null,
    createdAt: raw['created_at'] is String ? raw['created_at'] as String : null,
    total: _num(raw['total']),
    pendientes: _num(raw['pendientes']),
    resumen: ResumenEstados(
      nuevo: _num(r['new']),
      failed: _num(r['failed']),
      learning: _num(r['learning']),
      mastered: _num(r['mastered']),
    ),
  );
}

Parrafo? sanearParrafo(dynamic raw) {
  if (raw is! Map) return null;
  final id = raw['id'];
  final texto = raw['texto'];
  if (id is! String || texto is! String) return null;

  final o = raw['origen'] is Map ? raw['origen'] as Map : null;
  final statusRaw = raw['status'];
  EstadoParrafoSrs? status;
  if (statusRaw is String) status = _estadoDe(statusRaw);

  return Parrafo(
    itemId: _num(raw['itemId']),
    id: id,
    tema: raw['tema'] is String && (raw['tema'] as String).trim().isNotEmpty ? raw['tema'] as String : null,
    modo: raw['modo'] == 'literal' ? ModoResumen.literal : ModoResumen.resumen,
    texto: texto,
    huecos: sanearHuecos(raw['huecos'], texto),
    aiGenerated: raw['aiGenerated'] == true,
    origen: o != null
        ? OrigenGuardado(
            name: o['name'] is String ? o['name'] as String : null,
            page: o['page'] is int ? o['page'] as int : null,
            unit: o['unit'] == 'diapositiva'
                ? 'diapositiva'
                : o['unit'] == 'pagina'
                    ? 'pagina'
                    : null,
            fragmento: sanearFragmento(o['fragmento']),
          )
        : null,
    status: status,
    due: raw['due'] is bool ? raw['due'] as bool : null,
    nextDueAt: raw['nextDueAt'] is String ? raw['nextDueAt'] as String : null,
    huecosFallados: sanearFallados(raw['huecosFallados']),
    fallos: raw['fallos'] is num && (raw['fallos'] as num) > 0 ? (raw['fallos'] as num).floor() : 0,
  );
}

class SiguienteResumen {
  final SiguienteTipoResumen tipo;
  final Parrafo? parrafo;
  const SiguienteResumen._(this.tipo, [this.parrafo]);

  const SiguienteResumen.parrafo(Parrafo p) : this._(SiguienteTipoResumen.parrafo, p);
  const SiguienteResumen.fin() : this._(SiguienteTipoResumen.fin);
  const SiguienteResumen.caducada() : this._(SiguienteTipoResumen.caducada);
  const SiguienteResumen.limite() : this._(SiguienteTipoResumen.limite);
}

enum SiguienteTipoResumen { parrafo, fin, caducada, limite }

class ParrafoFallado {
  final Parrafo parrafo;
  final List<int> huecosFalladosSesion;
  const ParrafoFallado(this.parrafo, this.huecosFalladosSesion);
}

class ResumenesApi {
  final Future<String> Function() _token;
  final String _baseUrl;
  final http.Client _client;

  ResumenesApi({
    required Future<String> Function() token,
    required String baseUrl,
    http.Client? client,
  })  : _token = token,
        _baseUrl = baseUrl,
        _client = client ?? http.Client();

  Future<Map<String, dynamic>> _pedir(
    String ruta, {
    String method = 'GET',
    Map<String, dynamic>? cuerpo,
    String mensaje = 'No se pudo completar la operación',
  }) async {
    final token = await _token();
    if (token.isEmpty) throw const ResumenesApiError('Inicia sesión');

    final req = http.Request(method, Uri.parse('$_baseUrl/api/resumenes$ruta'))
      ..headers['Authorization'] = 'Bearer $token'
      ..headers['Content-Type'] = 'application/json';
    if (cuerpo != null) req.body = jsonEncode(cuerpo);

    final res = await _client
        .send(req)
        .then(http.Response.fromStream)
        .timeout(const Duration(seconds: 25));

    Map<String, dynamic> json;
    try {
      json = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      json = const {};
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ResumenesApiError(
        json['error'] is String ? json['error'] as String : mensaje,
        status: res.statusCode,
        caben: json['caben'] is num ? (json['caben'] as num).toInt() : null,
        limite: json['limite'] == true,
        literal: json['literal'] == true,
      );
    }
    return json;
  }

  Future<List<GrupoResumen>> listarGrupos() async {
    final r = await _pedir('', mensaje: 'No se pudieron cargar los grupos');
    final grupos = r['grupos'] is List ? r['grupos'] as List : const [];
    return grupos.map(sanearGrupo).whereType<GrupoResumen>().toList();
  }

  Future<GrupoResumen> crearGrupo(String name, {String? color, String? icon}) async {
    final r = await _pedir(
      '',
      method: 'POST',
      cuerpo: {'name': name, if (color != null) 'color': color, if (icon != null) 'icon': icon},
      mensaje: 'No se pudo crear el grupo',
    );
    final g = sanearGrupo(r['grupo']);
    if (g == null) throw const ResumenesApiError('Respuesta no válida');
    return g;
  }

  Future<void> editarGrupo(String id, {String? name, String? color, String? icon}) async {
    await _pedir(
      '/$id',
      method: 'PATCH',
      cuerpo: {if (name != null) 'name': name, if (color != null) 'color': color, if (icon != null) 'icon': icon},
      mensaje: 'No se pudo guardar el grupo',
    );
  }

  Future<void> borrarGrupo(String id) async {
    await _pedir('/$id', method: 'DELETE', mensaje: 'No se pudo borrar el grupo');
  }

  Future<({GrupoResumen grupo, List<Parrafo> parrafos, int max})> cargarGrupo(String id) async {
    final r = await _pedir('/$id', mensaje: 'No se pudo cargar el grupo');
    final grupo = sanearGrupo({...(r['grupo'] is Map ? r['grupo'] as Map : const {}), 'total': 0, 'pendientes': 0});
    if (grupo == null) throw const ResumenesApiError('Grupo no encontrado');
    final parrafos = (r['parrafos'] is List ? r['parrafos'] as List : const [])
        .map(sanearParrafo)
        .whereType<Parrafo>()
        .toList();
    return (grupo: grupo, parrafos: parrafos, max: _num(r['max']) == 0 ? 300 : _num(r['max']));
  }

  Future<({int creados, int duplicados})> anadirParrafos(
    String id,
    List<ParrafoNuevo> lista, {
    bool aiGenerated = false,
    void Function(int)? onProgreso,
  }) async {
    var creados = 0;
    var duplicados = 0;
    for (var k = 0; k < lista.length; k += 40) {
      final lote = lista.sublist(k, math.min(k + 40, lista.length));
      final r = await _pedir(
        '/$id/parrafos',
        method: 'POST',
        cuerpo: {'parrafos': lote.map((p) => p.toJson()).toList(), 'aiGenerated': aiGenerated},
        mensaje: 'No se pudieron guardar los párrafos',
      );
      creados += _num(r['creados']);
      duplicados += _num(r['duplicados']);
      onProgreso?.call(math.min(lista.length, k + 40));
    }
    return (creados: creados, duplicados: duplicados);
  }

  Future<Parrafo> editarParrafo(String pid, {String? texto, List<Hueco>? huecos, String? tema}) async {
    final r = await _pedir(
      '/parrafos/$pid',
      method: 'PATCH',
      cuerpo: {
        if (texto != null) 'texto': texto,
        if (huecos != null) 'huecos': huecos.map((h) => h.toJson()).toList(),
        if (tema != null) 'tema': tema,
      },
      mensaje: 'No se pudo guardar el párrafo',
    );
    final p = sanearParrafo(r['parrafo']);
    if (p == null) throw const ResumenesApiError('Respuesta no válida');
    return p;
  }

  Future<void> quitarParrafo(String id, int itemId) async {
    await _pedir('/$id/parrafos/$itemId', method: 'DELETE', mensaje: 'No se pudo borrar el párrafo');
  }

  Future<String> empezarSesion(String id, AjustesEstudio ajustes, {int limit = 200}) async {
    final body = <String, dynamic>{'limit': limit, ...ajustes.toJson()};
    if (ajustes.levels != null && (ajustes.levels!.isEmpty || ajustes.levels!.length >= 4)) {
      body.remove('levels');
    }
    final r = await _pedir('/$id/sesion', method: 'POST', cuerpo: body, mensaje: 'No se pudo empezar la sesión');
    final sid = r['sessionId'];
    if (sid is! String) throw const ResumenesApiError('Respuesta no válida');
    return sid;
  }

  Future<SiguienteResumen> siguiente(String id, String sessionId) async {
    final r = await _pedir('/$id/siguiente?sessionId=${Uri.encodeQueryComponent(sessionId)}',
        mensaje: 'No se pudo cargar el siguiente párrafo');
    final p = sanearParrafo(r['parrafo']);
    if (p != null) return SiguienteResumen.parrafo(p);
    if (r['expired'] == true) return const SiguienteResumen.caducada();
    if (r['limitReached'] == true) return const SiguienteResumen.limite();
    return const SiguienteResumen.fin();
  }

  Future<({int grade, int sugerida})> registrarRepaso(
    String id, {
    required String sessionId,
    required int deckItemId,
    required List<({int i, int f, bool sabia})> huecos,
    int? grade,
    int? timeSpent,
  }) async {
    final r = await _pedir(
      '/$id/repaso',
      method: 'POST',
      cuerpo: {
        'sessionId': sessionId,
        'deckItemId': deckItemId,
        'huecos': huecos.map((h) => {'i': h.i, 'f': h.f, 'sabia': h.sabia}).toList(),
        if (grade != null) 'grade': grade,
        if (timeSpent != null) 'timeSpent': timeSpent,
      },
      mensaje: 'No se pudo registrar el repaso',
    );
    int n(dynamic v) => (v == 1 || v == 2 || v == 3 || v == 4) ? v as int : 3;
    return (grade: n(r['grade'] ?? grade), sugerida: n(r['sugerida']));
  }

  Future<({int deckItemId, Parrafo? parrafo})> deshacerRepaso(String id, String sessionId) async {
    final r = await _pedir('/$id/deshacer', method: 'POST', cuerpo: {'sessionId': sessionId},
        mensaje: 'No se pudo deshacer el repaso');
    return (deckItemId: _num(r['deckItemId']), parrafo: sanearParrafo(r['parrafo']));
  }

  Future<List<ParrafoFallado>> terminarSesion(String id, String sessionId) async {
    try {
      final r = await _pedir('/$id/fin', method: 'POST', cuerpo: {'sessionId': sessionId});
      final raw = r['fallados'] is List ? r['fallados'] as List : const [];
      final out = <ParrafoFallado>[];
      for (final x in raw) {
        final p = sanearParrafo(x);
        if (p == null) continue;
        var enSesion = const <int>[];
        if (x is Map && x['huecosFalladosSesion'] is List) {
          enSesion = (x['huecosFalladosSesion'] as List)
              .whereType<int>()
              .where((k) => k >= 0 && k < p.huecos.length)
              .toSet()
              .toList()
            ..sort();
        }
        out.add(ParrafoFallado(p, enSesion));
      }
      return out;
    } catch (_) {
      return const [];
    }
  }
}
