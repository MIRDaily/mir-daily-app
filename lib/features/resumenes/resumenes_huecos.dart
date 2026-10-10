// Lógica pura de los "Resúmenes activos": un párrafo es texto plano + huecos
// [{ i, f, n }] (el trozo texto[i, f) se tapa al estudiar; n 1-4 es su nivel).
// Las mismas reglas que valida el servidor. Sin red ni UI: se prueba con test.
//
// Puerto de la web: src/lib/resumenes/huecos.ts.

import 'dart:math' as math;

import '../../core/models/resumen.dart';

const Map<int, String> nombreNotaResumen = {1: 'Otra vez', 2: 'Difícil', 3: 'Bien', 4: 'Fácil'};

/// La nota que se propone al acabar un párrafo: todos bien = Bien; uno mal = Difícil; más = Otra vez.
int notaDeRepaso(int fallos) {
  if (fallos <= 0) return 3;
  if (fallos == 1) return 2;
  return 1;
}

/// El mismo texto, para no guardar dos veces el mismo párrafo (como el servidor).
String claveParrafo(String texto) => texto.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

int _entero(Object? v) => v is int ? v : -1;

/// Huecos que llegan de fuera (el servidor, almacenamiento local): solo los que
/// valen, ordenados, sin solaparse y como mucho 8. Nunca se confía en lo que llega.
List<Hueco> sanearHuecos(dynamic raw, String texto) {
  if (raw is! List) return const [];
  final lista = raw
      .whereType<Map>()
      .map((h) => Hueco(_entero(h['i']), _entero(h['f']), _entero(h['n'])))
      .where((h) => h.i >= 0 && h.f >= 0 && esNivelResumen(h.n))
      .toList()
    ..sort((a, b) => a.i.compareTo(b.i));

  final out = <Hueco>[];
  for (final h in lista) {
    if (h.i < 0 || h.f <= h.i || h.f > texto.length || texto.substring(h.i, h.f).trim().isEmpty) continue;
    if (out.isNotEmpty && h.i < out.last.f) continue;
    out.add(h);
    if (out.length >= maxHuecosResumen) break;
  }
  return out;
}

/// null si los huecos valen para el texto; si no, el motivo (para enseñarlo).
String? errorHuecos(String texto, List<Hueco> huecos) {
  if (huecos.isEmpty) return 'Marca al menos un hueco';
  if (huecos.length > maxHuecosResumen) return 'Como mucho $maxHuecosResumen huecos por párrafo';
  final orden = [...huecos]..sort((a, b) => a.i.compareTo(b.i));
  for (var k = 0; k < orden.length; k++) {
    final h = orden[k];
    if (!esNivelResumen(h.n)) return 'Huecos no válidos';
    if (h.i < 0 || h.f <= h.i || h.f > texto.length) return 'Un hueco se sale del texto';
    if (texto.substring(h.i, h.f).trim().isEmpty) return 'Un hueco no tiene texto';
    if (k > 0 && h.i < orden[k - 1].f) return 'Dos huecos se solapan';
  }
  return null;
}

class Segmento {
  final String t;
  final int? k;
  const Segmento(this.t, [this.k]);
}

/// Texto partido en trozos: los de fuera de los huecos y cada hueco (con su índice `k`).
List<Segmento> segmentos(String texto, List<Hueco> huecos) {
  final out = <Segmento>[];
  var pos = 0;
  for (var k = 0; k < huecos.length; k++) {
    final h = huecos[k];
    if (h.i > pos) out.add(Segmento(texto.substring(pos, h.i)));
    out.add(Segmento(texto.substring(h.i, h.f), k));
    pos = h.f;
  }
  if (pos < texto.length) out.add(Segmento(texto.substring(pos)));
  return out;
}

// Lo que no es parte de un dato en los bordes de una palabra: «(anti-TPO).» → «anti-TPO».
final RegExp _bordeIzq = RegExp("^[\\s¿¡([{«\"'\u2018\u201c]+");
final RegExp _bordeDer = RegExp("[\\s.,;:)\\]}»\"'\u2019\u201d!?]+\$");

/// Ajusta un trozo [i, f) a palabras enteras y le quita espacios y puntuación de los bordes.
({int i, int f})? ajustarSeleccion(String texto, int i, int f) {
  var a = math.max(0, math.min(i, f));
  var b = math.min(texto.length, math.max(i, f));
  // Hasta el principio y el final de la palabra (si se ha empezado o acabado a mitad).
  while (a > 0 && !RegExp(r'\s').hasMatch(texto[a - 1]) && !RegExp(r'\s').hasMatch(texto[a])) {
    a -= 1;
  }
  while (b < texto.length && !RegExp(r'\s').hasMatch(texto[b]) && b > 0 && !RegExp(r'\s').hasMatch(texto[b - 1])) {
    b += 1;
  }

  final trozo = texto.substring(a, b);
  final izq = _bordeIzq.firstMatch(trozo)?.group(0)?.length ?? 0;
  final der = _bordeDer.firstMatch(trozo.substring(izq))?.group(0)?.length ?? 0;
  a += izq;
  b -= der;
  return (b > a && texto.substring(a, b).trim().isNotEmpty) ? (i: a, f: b) : null;
}

/// La palabra en la posición `pos` (sin la puntuación de sus bordes), o null si ahí hay un espacio.
({int i, int f})? palabraEn(String texto, int pos) {
  if (pos < 0 || pos >= texto.length || RegExp(r'\s').hasMatch(texto[pos])) return null;
  return ajustarSeleccion(texto, pos, pos + 1);
}

class Cambio {
  final List<Hueco> huecos;
  final String? error;
  const Cambio(this.huecos, {this.error});
}

/// Crear un hueco sobre [i, f) (ajustado a palabras). Los huecos que toca se funden en él.
Cambio crearHueco(String texto, List<Hueco> huecos, int i, int f, int nivel) {
  final sel = ajustarSeleccion(texto, i, f);
  if (sel == null) return const Cambio([], error: 'Selecciona alguna palabra');

  final tocados = huecos.where((h) => h.i < sel.f && h.f > sel.i).toList();
  var nuevoI = sel.i;
  var nuevoF = sel.f;
  var n = nivel;
  for (final h in tocados) {
    if (h.i < nuevoI) nuevoI = h.i;
    if (h.f > nuevoF) nuevoF = h.f;
    if (h.n > n) n = h.n;
  }
  final nuevo = Hueco(nuevoI, nuevoF, n);
  final resto = huecos.where((h) => !tocados.contains(h)).toList();
  if (resto.length + 1 > maxHuecosResumen) {
    return Cambio(huecos, error: 'Como mucho $maxHuecosResumen huecos por párrafo');
  }
  final out = [...resto, nuevo]..sort((a, b) => a.i.compareTo(b.i));
  return Cambio(out);
}

/// Tocar una palabra: si está en un hueco, se quita el hueco; si no, pasa a ser un hueco.
Cambio alternarPalabra(String texto, List<Hueco> huecos, int pos, int nivel) {
  final dentro = huecos.indexWhere((h) => pos >= h.i && pos < h.f);
  if (dentro >= 0) return Cambio(quitarHueco(huecos, dentro));
  final p = palabraEn(texto, pos);
  if (p == null) return Cambio(huecos);
  return crearHueco(texto, huecos, p.i, p.f, nivel);
}

List<Hueco> quitarHueco(List<Hueco> huecos, int k) {
  final out = [...huecos]..removeAt(k);
  return out;
}

List<Hueco> cambiarNivel(List<Hueco> huecos, int k, int n) =>
    huecos.asMap().entries.map((e) => e.key == k ? e.value.copyWith(n: n) : e.value).toList();

/// Subir (+1) o bajar (-1) un nivel todos los huecos, sin salir de 1-4.
({List<Hueco> huecos, int cambiados, int enTope}) desplazarNiveles(List<Hueco> huecos, int d) {
  var cambiados = 0;
  var enTope = 0;
  final out = huecos.map((h) {
    final n = (h.n + d).clamp(1, 4);
    if (n == h.n) {
      enTope += 1;
      return h;
    }
    cambiados += 1;
    return h.copyWith(n: n);
  }).toList();
  return (huecos: cambiados > 0 ? out : huecos, cambiados: cambiados, enTope: enTope);
}

/// El texto ha cambiado: los huecos de lo que no cambia se quedan (y se mueven si hace
/// falta); los de la parte cambiada se buscan por su texto y si no, se pierden.
({List<Hueco> huecos, int perdidos}) ajustarTrasEditar(String viejo, String nuevo, List<Hueco> huecos) {
  var pre = 0;
  while (pre < viejo.length && pre < nuevo.length && viejo[pre] == nuevo[pre]) {
    pre += 1;
  }
  var suf = 0;
  while (suf < viejo.length - pre && suf < nuevo.length - pre &&
      viejo[viejo.length - 1 - suf] == nuevo[nuevo.length - 1 - suf]) {
    suf += 1;
  }

  final finViejo = viejo.length - suf;
  final delta = nuevo.length - viejo.length;
  final quedan = <Hueco>[];
  final sueltos = <Hueco>[];
  for (final h in huecos) {
    if (h.f <= pre) {
      quedan.add(h);
    } else if (h.i >= finViejo) {
      quedan.add(h.copyWith(i: h.i + delta, f: h.f + delta));
    } else {
      sueltos.add(h);
    }
  }

  var perdidos = 0;
  for (final h in sueltos) {
    final t = viejo.substring(h.i, h.f);
    final a = nuevo.indexOf(t);
    final unico = a >= 0 && nuevo.indexOf(t, a + 1) < 0;
    if (unico && !quedan.any((q) => q.i < a + t.length && q.f > a)) {
      quedan.add(Hueco(a, a + t.length, h.n));
    } else {
      perdidos += 1;
    }
  }
  quedan.sort((a, b) => a.i.compareTo(b.i));
  return (huecos: sanearHuecos(quedan.map((h) => h.toJson()).toList(), nuevo), perdidos: perdidos);
}

// ---------------------------------------------------------------------------
// Estudio
// ---------------------------------------------------------------------------

enum Respuesta { sabia, no }

class EstadoParrafo {
  final List<int> tapados;
  final Map<int, Respuesta> respuestas;
  final List<int>? orden;

  const EstadoParrafo({required this.tapados, required this.respuestas, this.orden});
}

/// Los huecos que se tapan con el filtro de niveles (los demás se ven). null = todos.
List<int> huecosTapados(List<Hueco> huecos, List<int>? niveles) {
  final out = <int>[];
  for (var k = 0; k < huecos.length; k++) {
    if (niveles == null || niveles.isEmpty || niveles.contains(huecos[k].n)) out.add(k);
  }
  return out;
}

/// Estado inicial del estudio de un párrafo: qué huecos están tapados.
EstadoParrafo empezarParrafo(List<Hueco> huecos, List<int>? niveles, [List<int>? fallados]) {
  final deNivel = huecosTapados(huecos, niveles);
  final soloFallados = fallados != null ? deNivel.where((k) => fallados.contains(k)).toList() : <int>[];
  return EstadoParrafo(
    tapados: soloFallados.isNotEmpty ? soloFallados : deNivel,
    respuestas: const {},
    orden: const [],
  );
}

/// El siguiente hueco tapado aún sin destapar (en orden de lectura), o null.
int? siguienteTapado(EstadoParrafo e) {
  for (final k in e.tapados) {
    if (!e.respuestas.containsKey(k)) return k;
  }
  return null;
}

EstadoParrafo responder(EstadoParrafo e, int k, Respuesta r) {
  if (!e.tapados.contains(k)) return e;
  return EstadoParrafo(
    tapados: e.tapados,
    respuestas: {...e.respuestas, k: r},
    orden: [...(e.orden ?? []).where((x) => x != k), k],
  );
}

EstadoParrafo cambiarRespuesta(EstadoParrafo e, int k) {
  final r = e.respuestas[k];
  if (r == null) return e;
  return EstadoParrafo(
    tapados: e.tapados,
    respuestas: {...e.respuestas, k: r == Respuesta.sabia ? Respuesta.no : Respuesta.sabia},
    orden: e.orden,
  );
}

EstadoParrafo reabrir(EstadoParrafo e, int k) {
  if (!e.respuestas.containsKey(k)) return e;
  final respuestas = {...e.respuestas}..remove(k);
  return EstadoParrafo(
    tapados: e.tapados,
    respuestas: respuestas,
    orden: (e.orden ?? []).where((x) => x != k).toList(),
  );
}

/// El último hueco contestado (para reabrirlo con Retroceso), o null.
int? ultimoRespondido(EstadoParrafo e) {
  final orden = (e.orden ?? []).where((k) => e.respuestas.containsKey(k)).toList();
  return orden.isEmpty ? null : orden.last;
}

bool terminado(EstadoParrafo e) => e.tapados.every((k) => e.respuestas.containsKey(k));

int fallos(EstadoParrafo e) => e.tapados.where((k) => e.respuestas[k] == Respuesta.no).length;

/// Lo que se manda al registrar el repaso: cada hueco tapado por su posición, y si se sabía.
List<({int i, int f, bool sabia})> resultados(EstadoParrafo e, List<Hueco> huecos) {
  final out = <({int i, int f, bool sabia})>[];
  for (final k in e.tapados) {
    if (k < huecos.length && e.respuestas.containsKey(k)) {
      out.add((i: huecos[k].i, f: huecos[k].f, sabia: e.respuestas[k] == Respuesta.sabia));
    }
  }
  return out;
}

/// Huecos fallados que llegan del servidor: posiciones válidas (0-7), sin repetir y ordenadas.
List<int>? sanearFallados(dynamic raw) {
  if (raw is! List) return null;
  final set = <int>{for (final k in raw.whereType<int>()) if (k >= 0 && k < maxHuecosResumen) k};
  final out = set.toList()..sort();
  return out;
}

/// Fragmento de origen que llega del servidor: texto (como mucho 300) o null.
String? sanearFragmento(dynamic v) {
  if (v is! String || v.trim().isEmpty) return null;
  return v.length > 300 ? v.substring(0, 300) : v;
}
