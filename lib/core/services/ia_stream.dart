// Parseo del canal de streaming de la IA (NDJSON). El servidor manda una línea
// JSON por evento: fases, ramas provisionales mientras el modelo escribe y, al
// final, el resultado validado. Todo lo que llega es entrada no fiable: cada
// evento se reduce a sus campos conocidos y los eventos desconocidos se ignoran.
//
// Puerto directo de la web: src/lib/mapas/ia/stream.ts.

import 'dart:convert';

import '../models/ia.dart';

/// Tope de texto de una línea provisional (igual que la web).
const int maxTextoIa = 300;
const int maxNivelIa = 8;
const int maxParteIa = 10000;
const int maxTemaIa = 1000;

/// Corta en líneas lo que va llegando: los trozos de red parten las líneas por
/// cualquier sitio.
class LectorLineas {
  final void Function(String) _onLinea;
  String _buf = '';

  LectorLineas(this._onLinea);

  void push(String trozo) {
    _buf += trozo;
    var i = _buf.indexOf('\n');
    while (i >= 0) {
      _onLinea(_buf.substring(0, i));
      _buf = _buf.substring(i + 1);
      i = _buf.indexOf('\n');
    }
  }

  void fin() {
    if (_buf.trim().isNotEmpty) _onLinea(_buf);
    _buf = '';
  }
}

int? _entero(Object? v, int min, int max) =>
    v is int && v >= min && v <= max ? v : null;

String _recorta(String s, int max) => s.length > max ? s.substring(0, max) : s;

FaseIa? _faseDe(Object? v) {
  if (v is! String) return null;
  for (final f in FaseIa.values) {
    if (f.name == v) return f;
  }
  return null;
}

EstadoTema? _estadoDe(Object? v) {
  if (v is! String) return null;
  for (final e in EstadoTema.values) {
    if (e.name == v) return e;
  }
  return null;
}

/// Una línea del servidor → evento conocido, o null si se ignora.
EventoIa? leerEvento(String linea) {
  if (linea.trim().isEmpty) return null;

  Object? j;
  try {
    j = jsonDecode(linea);
  } catch (_) {
    return null;
  }
  if (j is! Map) return null;
  final r = j;

  switch (r['tipo']) {
    case 'fase':
      final f = _faseDe(r['fase']);
      return f == null ? null : EventoFase(f);

    case 'rama':
      final parte = _entero(r['parte'], 0, maxParteIa);
      final d = _entero(r['d'], 1, maxNivelIa);
      final t = r['t'];
      if (parte == null || d == null || t is! String || t.trim().isEmpty) {
        return null;
      }
      return EventoRama(
        parte: parte,
        tema: _entero(r['tema'], 0, maxTemaIa),
        d: d,
        t: _recorta(t.trim(), maxTextoIa),
      );

    case 'reinicio':
      final parte = _entero(r['parte'], 0, maxParteIa);
      if (parte == null) return null;
      return EventoReinicio(parte: parte, tema: _entero(r['tema'], 0, maxTemaIa));

    case 'temas':
      final raw = r['temas'];
      if (raw is! List) return null;
      final temas = raw.take(maxTemaIa).map((t) {
        if (t is! Map) return const TemaRef(titulo: '', chars: 0);
        final titulo = t['titulo'];
        return TemaRef(
          titulo: titulo is String ? _recorta(titulo, 160) : '',
          chars: _entero(t['chars'], 0, 10000000) ?? 0,
        );
      }).toList();
      return EventoTemas(temas);

    case 'tema':
      final i = _entero(r['i'], 0, maxTemaIa);
      final estado = _estadoDe(r['estado']);
      if (i == null || estado == null) return null;
      return EventoTema(i: i, estado: estado, nodos: _entero(r['nodos'], 0, 100000));

    case 'latido':
      return const EventoLatido();

    case 'fin':
      return EventoFin(Map<String, dynamic>.from(r)..remove('tipo'));

    case 'error':
      final e = r['error'];
      final c = r['codigo'];
      return EventoError(
        error: e is String ? _recorta(e, 300) : 'No se pudo generar el mapa',
        codigo: c is String ? _recorta(c, 40) : '',
        status: _entero(r['status'], 0, 599) ?? 0,
        datos: Map<String, dynamic>.from(r)..remove('tipo'),
      );

    case 'reserva':
      final id = _entero(r['usageId'], 1, 4503599627370496);
      if (id == null) return null;
      final c = r['creditos'];
      return EventoReserva(
        usageId: id,
        cobrados: c is Map ? _entero(c['cobrados'], 0, 1 << 30) : null,
        saldo: c is Map ? _entero(c['saldo'], 0, 1 << 30) : null,
      );

    default:
      return null;
  }
}

/// Lo que acumula el diálogo: las líneas provisionales, con los reinicios ya
/// aplicados.
List<LineaProvisional> aplicarEvento(List<LineaProvisional> lineas, EventoIa e) {
  if (e is EventoRama) {
    return [
      ...lineas,
      LineaProvisional(parte: e.parte, tema: e.tema, d: e.d, t: e.t),
    ];
  }
  if (e is EventoReinicio) {
    return lineas.where((l) => l.parte != e.parte || l.tema != e.tema).toList();
  }
  return lineas;
}

/// Líneas «nivel | texto» → árbol, como lo reconstruye el servidor: un nodo
/// cuelga del último de nivel inferior y un nivel nunca salta más de uno. Las
/// partes (documento troceado) van una detrás de otra, en su orden.
List<RamaProvisional> arbolProvisional(List<LineaProvisional> lineas) {
  final raices = <RamaProvisional>[];
  final partes = lineas.map((l) => l.parte).toSet().toList()..sort();
  var k = 0;

  for (final parte in partes) {
    final pila = <RamaProvisional>[];
    for (final l in lineas) {
      if (l.parte != parte) continue;
      final d = l.d < pila.length + 1 ? l.d : pila.length + 1;
      final nodo = RamaProvisional(key: '$parte-${k++}', t: l.t, hijos: []);

      if (d == 1) {
        raices.add(nodo);
      } else {
        pila[d - 2].hijos.add(nodo);
      }
      pila.length = d - 1;
      pila.add(nodo);
    }
  }
  return raices;
}

/// Documento largo: un bloque por tema (con su título) y debajo su borrador.
/// Solo los temas que ya tienen ramas, en el orden del documento.
List<RamaProvisional> arbolLibro(List<LineaProvisional> lineas, List<String> titulos) {
  final temas = lineas.map((l) => l.tema ?? 0).toSet().toList()..sort();
  return temas.map((i) {
    final hijos = arbolProvisional(
      lineas.where((l) => (l.tema ?? 0) == i).toList(),
    )
        .map((n) => RamaProvisional(key: '$i-${n.key}', t: n.t, hijos: n.hijos))
        .toList();
    final titulo = i < titulos.length && titulos[i].isNotEmpty
        ? titulos[i]
        : 'Tema ${i + 1}';
    return RamaProvisional(key: 'tema-$i', t: titulo, hijos: hijos);
  }).toList();
}
