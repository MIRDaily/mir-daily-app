// Carpetas del material: el árbol del catálogo (GET /api/carpetas/arbol), mover mapas o grupos
// (PATCH /api/carpetas) y la sugerencia de carpeta a partir de los textos de un documento.
// Puerto de la web: src/lib/carpetas/api.ts y src/lib/carpetas/sugerir.ts. El servidor valida dueño,
// asignatura y tema; aquí solo se pide, se sugiere y se pinta.
//
// La sugerencia no usa IA ni red: cada texto vota por el tema que más se le parece (si se parece lo
// bastante) y por su asignatura. Con votos claros por un tema → ese tema; si solo destaca la
// asignatura → su «General»; si no → «Sin clasificar».

import 'dart:convert';

import 'package:http/http.dart' as http;

class TemaCatalogo {
  final int id;
  final String nombre;
  const TemaCatalogo({required this.id, required this.nombre});
}

class AsignaturaCatalogo {
  final int id;
  final String nombre;
  final String nombreCorto;
  final String? sigla;
  final List<TemaCatalogo> temas;

  const AsignaturaCatalogo({required this.id, required this.nombre, required this.nombreCorto, this.sigla, this.temas = const []});

  static AsignaturaCatalogo? fromJson(Object? raw) {
    if (raw is! Map || raw['id'] is! int || raw['nombre'] is! String) return null;
    final temas = raw['temas'];
    return AsignaturaCatalogo(
      id: raw['id'] as int,
      nombre: raw['nombre'] as String,
      nombreCorto: raw['nombreCorto'] is String ? raw['nombreCorto'] as String : raw['nombre'] as String,
      sigla: raw['sigla'] is String ? raw['sigla'] as String : null,
      temas: temas is List
          ? [
              for (final t in temas)
                if (t is Map && t['id'] is int && t['nombre'] is String) TemaCatalogo(id: t['id'] as int, nombre: t['nombre'] as String),
            ]
          : const [],
    );
  }
}

/// Dónde va: asignatura y tema; `subjectId` null = «Sin clasificar», `topicId` null = «General».
class Carpeta {
  final int? subjectId;
  final int? topicId;
  const Carpeta({this.subjectId, this.topicId});

  static const sinClasificar = Carpeta();

  @override
  bool operator ==(Object other) => other is Carpeta && other.subjectId == subjectId && other.topicId == topicId;

  @override
  int get hashCode => Object.hash(subjectId, topicId);
}

class TextoPonderado {
  final String texto;
  final double peso;
  const TextoPonderado(this.texto, this.peso);
}

class Sugerencia {
  /// Lo que se preselecciona (sin clasificar si no hay nada claro).
  final Carpeta carpeta;
  final String confianza; // alta | media | baja
  /// Otras opciones razonables, de la más a la menos parecida (sin repetir la elegida).
  final List<Carpeta> candidatas;
  const Sugerencia(this.carpeta, this.confianza, this.candidatas);
}

const _stop = {
  'a', 'al', 'con', 'de', 'del', 'e', 'el', 'en', 'la', 'las', 'lo', 'los', 'o', 'para', 'por', 'su', 'sus',
  'u', 'un', 'una', 'y', 'otra', 'otras', 'otro', 'otros', 'tema',
};

// Dart no trae normalize('NFD'): las letras con diacrítico del español y vecinas, a mano. La web
// quita también la tilde de la ñ (NFD la separa), así que aquí ñ → n igual.
const _sinTilde = {
  'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a', 'ã': 'a', 'å': 'a',
  'é': 'e', 'è': 'e', 'ë': 'e', 'ê': 'e',
  'í': 'i', 'ì': 'i', 'ï': 'i', 'î': 'i',
  'ó': 'o', 'ò': 'o', 'ö': 'o', 'ô': 'o', 'õ': 'o',
  'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u',
  'ñ': 'n', 'ç': 'c', 'ý': 'y', 'ÿ': 'y',
};
final _combinantes = RegExp('[̀-ͯ]');
final _noPalabra = RegExp(r'[^a-z0-9ñ]+');

String normalizarCarpeta(String texto) {
  final b = StringBuffer();
  for (final c in texto.toLowerCase().replaceAll(_combinantes, '').split('')) {
    b.write(_sinTilde[c] ?? c);
  }
  return b.toString().replaceAll(_noPalabra, ' ').trim();
}

String _raiz(String p) {
  if (p.length > 5 && p.endsWith('es') && !RegExp(r'[aeiou]es$').hasMatch(p)) return p.substring(0, p.length - 2);
  if (p.length > 4 && p.endsWith('s')) return p.substring(0, p.length - 1);
  return p;
}

List<String> _palabras(String texto) =>
    normalizarCarpeta(texto).split(' ').where((p) => p.isNotEmpty && !_stop.contains(p)).map(_raiz).toSet().toList();

Set<String> _trigramas(String texto) {
  final t = ' ${_palabras(texto).join(' ')} ';
  return {for (var i = 0; i < t.length - 2; i++) t.substring(i, i + 3)};
}

double _dice(Set<String> a, Set<String> b) {
  if (a.isEmpty || b.isEmpty) return 0;
  final comun = a.where(b.contains).length;
  return (2 * comun) / (a.length + b.length);
}

/// Parecido de 0 a 1 entre dos nombres (palabras + trigramas; contener entero al otro suma con techo).
double parecidoCarpeta(String a, String b) {
  if (normalizarCarpeta(a) == normalizarCarpeta(b)) return 1;
  final pa = _palabras(a).toSet();
  final pb = _palabras(b).toSet();
  final porPalabras = _dice(pa, pb);
  final porLetras = _dice(_trigramas(a), _trigramas(b));
  final comun = pa.where(pb.contains).length;
  final menor = pa.length < pb.length ? pa.length : pb.length;
  final contenido = menor > 0 && comun == menor ? 0.75 : 0.0;
  final a1 = 0.6 * porPalabras + 0.4 * porLetras;
  final a2 = contenido * (porLetras > 0.8 ? porLetras : 0.8);
  return a1 > a2 ? a1 : a2;
}

const _votaTema = 0.45;
const _votaAsignatura = 0.6;
const _mayoria = 0.4;
const _minimo = 0.5;

Sugerencia sugerirCarpeta(List<AsignaturaCatalogo> arbol, List<TextoPonderado> textos) {
  final validos = textos.where((t) => t.peso > 0 && normalizarCarpeta(t.texto).length > 1);
  var total = 0.0;
  // Mapas con orden de inserción: el desempate es el mismo que en la web.
  final votosTema = <int, ({int subjectId, double votos})>{};
  final votosAsig = <int, double>{};
  final temas = [for (final a in arbol) for (final t in a.temas) (id: t.id, nombre: t.nombre, subjectId: a.id)];

  for (final tp in validos) {
    ({int id, int subjectId, double p})? mejor;
    for (final t in temas) {
      final p = parecidoCarpeta(tp.texto, t.nombre);
      if (mejor == null || p > mejor.p) mejor = (id: t.id, subjectId: t.subjectId, p: p);
    }
    var vota = false;
    if (mejor != null && mejor.p >= _votaTema) {
      vota = true;
      final v = votosTema[mejor.id];
      votosTema[mejor.id] = (subjectId: mejor.subjectId, votos: (v?.votos ?? 0) + tp.peso * mejor.p);
      votosAsig[mejor.subjectId] = (votosAsig[mejor.subjectId] ?? 0) + tp.peso * mejor.p;
    }
    for (final a in arbol) {
      final p1 = parecidoCarpeta(tp.texto, a.nombre);
      final p2 = parecidoCarpeta(tp.texto, a.nombreCorto);
      final p = p1 > p2 ? p1 : p2;
      if (p >= _votaAsignatura) {
        vota = true;
        votosAsig[a.id] = (votosAsig[a.id] ?? 0) + tp.peso * p;
      }
    }
    if (vota) total += tp.peso;
  }

  // sort de Dart no es estable: se ordena por votos y, a igualdad, por orden de llegada (como JS).
  List<T> estable<T>(List<T> l, double Function(T) votos) {
    final idx = [for (var i = 0; i < l.length; i++) i];
    idx.sort((x, y) {
      final c = votos(l[y]).compareTo(votos(l[x]));
      return c != 0 ? c : x.compareTo(y);
    });
    return [for (final i in idx) l[i]];
  }

  final rankingTemas = estable(votosTema.entries.toList(), (e) => e.value.votos);
  final rankingAsig = estable(votosAsig.entries.toList(), (e) => e.value);
  final temaTop = rankingTemas.isEmpty ? null : rankingTemas.first;
  final asigTop = rankingAsig.isEmpty ? null : rankingAsig.first;
  final umbral = _minimo > _mayoria * total ? _minimo : _mayoria * total;

  var carpeta = Carpeta.sinClasificar;
  var confianza = 'baja';
  if (temaTop != null && temaTop.value.votos >= umbral && (asigTop == null || asigTop.key == temaTop.value.subjectId)) {
    carpeta = Carpeta(subjectId: temaTop.value.subjectId, topicId: temaTop.key);
    confianza = 'alta';
  } else if (asigTop != null && asigTop.value >= umbral) {
    carpeta = Carpeta(subjectId: asigTop.key);
    confianza = 'media';
  }

  final candidatas = <Carpeta>[];
  void meter(Carpeta c) {
    if (c != carpeta && !candidatas.contains(c)) candidatas.add(c);
  }

  final temasOrdenados = carpeta.subjectId == null
      ? rankingTemas
      : [
          ...rankingTemas.where((e) => e.value.subjectId == carpeta.subjectId),
          ...rankingTemas.where((e) => e.value.subjectId != carpeta.subjectId),
        ];
  for (final e in temasOrdenados) {
    meter(Carpeta(subjectId: e.value.subjectId, topicId: e.key));
  }
  for (final e in rankingAsig) {
    meter(Carpeta(subjectId: e.key));
  }
  return Sugerencia(carpeta, confianza, candidatas.take(3).toList());
}

/// «Reumatología › Lupus eritematoso sistémico», «Reumatología › General» o «Sin clasificar».
String nombreCarpeta(List<AsignaturaCatalogo>? arbol, Carpeta c, {bool corto = false}) {
  if (c.subjectId == null) return 'Sin clasificar';
  final a = arbol?.where((x) => x.id == c.subjectId).firstOrNull;
  if (a == null) return 'Carpeta';
  final asig = corto ? a.nombreCorto : a.nombre;
  if (c.topicId == null) return '$asig › General';
  final t = a.temas.where((x) => x.id == c.topicId).firstOrNull;
  return t != null ? '$asig › ${t.nombre}' : '$asig › General';
}

/// Los textos de un documento con sus pesos: el título pesa 3; las demás listas, 2 en total cada una.
List<TextoPonderado> textosDocumento(String titulo, [List<List<String?>> listas = const []]) {
  final out = [TextoPonderado(titulo, 3)];
  for (final lista in listas) {
    final limpias = lista.whereType<String>().where((x) => x.trim().length > 1).toList();
    for (final t in limpias) {
      out.add(TextoPonderado(t, 2 / limpias.length));
    }
  }
  return out;
}

class CarpetasApi {
  final Future<String> Function() _token;
  final String _baseUrl;
  final http.Client _client;

  CarpetasApi({
    required Future<String> Function() token,
    required String baseUrl,
    http.Client? client,
  })  : _token = token,
        _baseUrl = baseUrl,
        _client = client ?? http.Client();

  // El catálogo es igual para todos y cambia muy poco: un pedido por sesión de la app, compartido.
  List<AsignaturaCatalogo>? _arbol;
  Future<List<AsignaturaCatalogo>>? _enCurso;

  Future<dynamic> _pedir(String ruta, {String method = 'GET', Map<String, dynamic>? cuerpo}) async {
    final token = await _token();
    if (token.isEmpty) throw Exception('Inicia sesión');
    final req = http.Request(method, Uri.parse('$_baseUrl/api/carpetas$ruta'))
      ..headers['Authorization'] = 'Bearer $token'
      ..headers['Content-Type'] = 'application/json';
    if (cuerpo != null) req.body = jsonEncode(cuerpo);
    final res = await _client.send(req).then(http.Response.fromStream).timeout(const Duration(seconds: 20));
    dynamic j;
    try {
      j = jsonDecode(res.body);
    } catch (_) {}
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception(j is Map && j['error'] is String ? j['error'] : 'No se pudo completar la operación');
    }
    return j;
  }

  /// El catálogo para elegir carpeta. Si falla, se puede volver a pedir.
  Future<List<AsignaturaCatalogo>> arbol() {
    if (_arbol != null) return Future.value(_arbol);
    return _enCurso ??= () async {
      try {
        final r = await _pedir('/arbol');
        final l = r is Map && r['asignaturas'] is List ? r['asignaturas'] as List : const [];
        return _arbol = l.map(AsignaturaCatalogo.fromJson).whereType<AsignaturaCatalogo>().toList();
      } finally {
        _enCurso = null;
      }
    }();
  }

  /// Mueve mapas o grupos a una carpeta. `origen` 'sugerencia' si se aceptó la propuesta sin cambiarla.
  Future<int> mover(String tipo, List<String> ids, Carpeta carpeta, {String origen = 'usuario'}) async {
    final r = await _pedir('', method: 'PATCH', cuerpo: {
      'tipo': tipo,
      'ids': ids,
      'subjectId': carpeta.subjectId,
      'topicId': carpeta.topicId,
      'origen': origen,
    });
    return r is Map && r['movidos'] is int ? r['movidos'] as int : 0;
  }
}
