// Mapas mentales en la app: leer, pintar y la edición simple (texto, ramas y mover).
// Puerto de la web: src/lib/mapas (types.ts, graph.ts, layout.ts, labelHtml.ts, table.ts) y del
// editor (components/mapas/proto: addNode, deleteNode, childSlot y el trazado de AnimatedEdge).
//
// REGLA DE ORO: el documento se edita SOBRE SU JSON ORIGINAL. La app solo toca lo que sabe tocar
// (posición, texto, nodos y aristas nuevos o borrados) y todo lo demás —estilos, tablas, IA,
// ajustes del mapa, campos que la web añada mañana— se guarda exactamente como estaba. Así un
// mapa retocado en la app se sigue viendo igual en la web.
//
// Formatos (los dos que guarda la web):
//  - Grafo (versión 2): lo que guarda el editor. Nodos con posición y estilo, aristas.
//  - Árbol (versión 1): lo que sale de la IA o de importar, hasta que se abre en el editor de la
//    web (que lo convierte y lo guarda como grafo). Aquí se ordena igual que allí y se puede ver,
//    pero NO se edita: guardarlo sería convertirlo con tamaños aproximados.

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/painting.dart';

/* ════════════════════════════════════════════════════════════════════════
   Categorías (types.ts)
═══════════════════════════════════════════════════════════════════════════ */

class CategoriaMapa {
  final String id;
  final String nombre;
  final Color color;
  const CategoriaMapa(this.id, this.nombre, this.color);
}

const Map<String, CategoriaMapa> categoriasMapa = {
  'general': CategoriaMapa('general', 'General', Color(0xFF7D8A96)),
  'definicion': CategoriaMapa('definicion', 'Definición', Color(0xFF6E9BC5)),
  'etiologia': CategoriaMapa('etiologia', 'Etiología', Color(0xFF9B86BD)),
  'clinica': CategoriaMapa('clinica', 'Clínica', Color(0xFFE8A598)),
  'diagnostico': CategoriaMapa('diagnostico', 'Diagnóstico', Color(0xFFD9A441)),
  'tratamiento': CategoriaMapa('tratamiento', 'Tratamiento', Color(0xFF8BA888)),
  'perla': CategoriaMapa('perla', 'Perla MIR', Color(0xFFD4667A)),
};

String _hex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/* ════════════════════════════════════════════════════════════════════════
   Colores CSS y estilo de nodo (graph.ts)
═══════════════════════════════════════════════════════════════════════════ */

const Map<String, Color> _colorNombre = {
  'white': Color(0xFFFFFFFF),
  'black': Color(0xFF000000),
  'red': Color(0xFFFF0000),
  'transparent': Color(0x00000000),
};

/// Un color de CSS (`#RGB`, `#RGBA`, `#RRGGBB`, `#RRGGBBAA`, `rgb()`, `rgba()` o un nombre básico).
Color? colorCss(Object? valor) {
  if (valor is! String) return null;
  final v = valor.trim().toLowerCase();
  if (v.startsWith('#')) {
    var h = v.substring(1);
    if (h.length == 3 || h.length == 4) h = h.split('').map((c) => '$c$c').join();
    if (h.length == 6) h = '${h}ff';
    if (h.length != 8 || !RegExp(r'^[0-9a-f]{8}$').hasMatch(h)) return null;
    final rgba = int.parse(h, radix: 16);
    return Color(((rgba & 0xFF) << 24) | (rgba >> 8));
  }
  final m = RegExp(r'^rgba?\(\s*([\d.]+)\s*,\s*([\d.]+)\s*,\s*([\d.]+)\s*(?:,\s*([\d.]+)\s*)?\)$').firstMatch(v);
  if (m != null) {
    int c(String s) => double.parse(s).round().clamp(0, 255);
    final a = m.group(4) == null ? 1.0 : double.parse(m.group(4)!).clamp(0.0, 1.0);
    return Color.fromARGB((a * 255).round(), c(m.group(1)!), c(m.group(2)!), c(m.group(3)!));
  }
  return _colorNombre[v];
}

enum FormaNodo { rectangulo, pastilla, circulo, rombo, rotulo }

FormaNodo _forma(Object? v) => switch (v) {
      'pill' => FormaNodo.pastilla,
      'circle' => FormaNodo.circulo,
      'diamond' => FormaNodo.rombo,
      'label' => FormaNodo.rotulo,
      _ => FormaNodo.rectangulo,
    };

class EstiloNodo {
  final Color relleno;
  final Color borde;
  final double grosorBorde;
  final Color brillo;
  final FormaNodo forma;
  final Color texto;
  final double tamanoLetra;
  final TextAlign alineacion;

  const EstiloNodo({
    required this.relleno,
    required this.borde,
    required this.grosorBorde,
    required this.brillo,
    required this.forma,
    required this.texto,
    required this.tamanoLetra,
    required this.alineacion,
  });

  /// `DEFAULT_GRAPH_STYLE` de la web, con lo que traiga el JSON por encima (acotado igual).
  factory EstiloNodo.desde(Object? raw) {
    final r = raw is Map ? raw : const {};
    double acotado(Object? v, double min, double max, double d) =>
        v is num && v.isFinite ? v.toDouble().clamp(min, max) : d;
    return EstiloNodo(
      relleno: colorCss(r['color']) ?? const Color(0xFFFFFFFF),
      borde: colorCss(r['borderColor']) ?? const Color(0xFFEDE6DE),
      grosorBorde: acotado(r['borderWidth'], 0, 12, 1),
      brillo: colorCss(r['glowColor']) ?? const Color(0xFFE8A598),
      forma: _forma(r['shape']),
      texto: colorCss(r['textColor']) ?? const Color(0xFF2A2420),
      tamanoLetra: acotado(r['fontSize'], 8, 72, 14),
      alineacion: switch (r['textAlign']) {
        'left' => TextAlign.left,
        'right' => TextAlign.right,
        _ => TextAlign.center,
      },
    );
  }
}

/// Estilo de serie según el nivel en el árbol y la categoría (`styleForNode` de graph.ts), como
/// JSON listo para guardar.
Map<String, dynamic> estiloDeSerie(int nivel, String categoria, String texto) {
  final cat = (categoriasMapa[categoria] ?? categoriasMapa['general']!).color;
  final base = <String, dynamic>{
    'color': '#FFFFFF',
    'borderColor': '#EDE6DE',
    'borderWidth': 1,
    'glowColor': '#E8A598',
    'glowIntensity': 0,
    'shape': 'rectangle',
    'textColor': '#2A2420',
    'fontSize': 14,
    'fontFamily': 'Lexend',
    'textAlign': 'center',
  };
  if (nivel == 0) {
    final acento = categoria == 'general' ? '#E8A598' : _hex(cat);
    return {
      ...base,
      'shape': texto.length <= 16 ? 'circle' : 'pill',
      'color': acento,
      'borderWidth': 0,
      'glowColor': acento,
      'textColor': '#FFFFFF',
    };
  }
  if (nivel == 1) {
    return {
      ...base,
      'shape': 'pill',
      'color': _hex(cat),
      'borderWidth': 0,
      'glowColor': _hex(cat),
      'textColor': '#FFFFFF',
    };
  }
  return {
    ...base,
    'borderColor': _hex(cat),
    'borderWidth': 2,
    'glowColor': _hex(cat),
  };
}

/* ════════════════════════════════════════════════════════════════════════
   Texto de los nodos: HTML saneado (labelHtml.ts) → trozos con formato
═══════════════════════════════════════════════════════════════════════════ */

/// Un trozo de texto con su formato. Un salto de línea es un trozo con `texto == '\n'`.
class TrozoTexto {
  final String texto;
  final bool negrita;
  final bool cursiva;
  final bool subrayado;
  final bool tachado;
  final Color? color;
  final Color? fondo;
  final double? escala;

  const TrozoTexto(
    this.texto, {
    this.negrita = false,
    this.cursiva = false,
    this.subrayado = false,
    this.tachado = false,
    this.color,
    this.fondo,
    this.escala,
  });
}

const _entidades = {'amp': '&', 'lt': '<', 'gt': '>', 'quot': '"', 'apos': "'", 'nbsp': ' '};

String _decodificar(String s) => s.replaceAllMapped(RegExp(r'&(#x?[0-9a-fA-F]+|[a-zA-Z]+);'), (m) {
      final e = m.group(1)!;
      if (e.startsWith('#')) {
        final code = e[1] == 'x' || e[1] == 'X' ? int.tryParse(e.substring(2), radix: 16) : int.tryParse(e.substring(1));
        return code != null && code > 0 && code <= 0x10FFFF ? String.fromCharCode(code) : '';
      }
      return _entidades[e.toLowerCase()] ?? m.group(0)!;
    });

class _Fmt {
  bool b = false, i = false, u = false, s = false;
  Color? color, fondo;
  double? escala;
  _Fmt copia() => _Fmt()
    ..b = b
    ..i = i
    ..u = u
    ..s = s
    ..color = color
    ..fondo = fondo
    ..escala = escala;
}

final _token = RegExp(r'<!--[\s\S]*?(?:-->|$)|<(\/?)([a-zA-Z][a-zA-Z0-9:-]*)((?:"[^"]*"|' "'[^']*'" r"|[^'" r'">])*)>|<|[^<]+');

/// El HTML de un nodo (ya saneado por la web, pero se lee con la misma lista blanca) en trozos.
List<TrozoTexto> trozosDeLabel(String html) {
  final out = <TrozoTexto>[];
  final pila = <(String, _Fmt)>[];
  var fmt = _Fmt();
  var hayTexto = false;

  void salto() {
    out.add(const TrozoTexto('\n'));
  }

  for (final m in _token.allMatches(html)) {
    final t = m.group(0)!;
    final nombre = m.group(2)?.toLowerCase();
    if (nombre == null) {
      if (t.startsWith('<!--')) continue;
      final texto = _decodificar(t);
      if (texto.isEmpty) continue;
      out.add(TrozoTexto(texto,
          negrita: fmt.b, cursiva: fmt.i, subrayado: fmt.u, tachado: fmt.s, color: fmt.color, fondo: fmt.fondo, escala: fmt.escala));
      hayTexto = true;
      continue;
    }
    final cierre = m.group(1) == '/';
    if (nombre == 'br') {
      if (!cierre) salto();
      continue;
    }
    final bloque = const {'div', 'p', 'li', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'tr', 'blockquote', 'pre'}.contains(nombre);
    if (cierre) {
      final at = pila.lastIndexWhere((e) => e.$1 == nombre);
      if (at < 0) continue;
      fmt = pila[at].$2;
      pila.removeRange(at, pila.length);
      continue;
    }
    // Un bloque empieza en línea nueva (el contentEditable de la web mete <div> por línea).
    if (bloque && hayTexto && (out.isEmpty || out.last.texto != '\n')) salto();
    pila.add((nombre, fmt));
    fmt = fmt.copia();
    switch (nombre) {
      case 'b' || 'strong':
        fmt.b = true;
      case 'i' || 'em':
        fmt.i = true;
      case 'u':
        fmt.u = true;
      case 's' || 'strike' || 'del':
        fmt.s = true;
    }
    final style = RegExp(r'''style\s*=\s*(?:"([^"]*)"|'([^']*)')''').firstMatch(m.group(3) ?? '');
    if (style != null) {
      for (final decl in _decodificar(style.group(1) ?? style.group(2) ?? '').split(';')) {
        final i = decl.indexOf(':');
        if (i < 0) continue;
        final prop = decl.substring(0, i).trim().toLowerCase();
        final valor = decl.substring(i + 1).trim().toLowerCase();
        switch (prop) {
          case 'font-weight':
            fmt.b = valor == 'bold' || (int.tryParse(valor) ?? 400) >= 600;
          case 'font-style':
            fmt.i = valor == 'italic';
          case 'text-decoration' || 'text-decoration-line':
            fmt.u = valor.contains('underline');
            fmt.s = valor.contains('line-through');
          case 'color':
            fmt.color = colorCss(valor) ?? fmt.color;
          case 'background-color':
            fmt.fondo = colorCss(valor) ?? fmt.fondo;
          case 'font-size':
            final em = RegExp(r'^([\d.]+)(em|%)$').firstMatch(valor);
            if (em != null) {
              final n = double.parse(em.group(1)!);
              fmt.escala = em.group(2) == '%' ? n / 100 : n;
            }
        }
      }
    }
  }
  while (out.isNotEmpty && out.last.texto == '\n') {
    out.removeLast();
  }
  return out;
}

/// El texto del nodo sin formato (saltos de línea incluidos).
String textoDeLabel(String html) => trozosDeLabel(html).map((t) => t.texto).join();

/// Si el texto lleva formato que se perdería al editarlo en la app (negrita, colores…).
bool labelTieneFormato(String html) => trozosDeLabel(html)
    .any((t) => t.negrita || t.cursiva || t.subrayado || t.tachado || t.color != null || t.fondo != null || t.escala != null);

/// Texto escrito en la app → HTML del nodo (escapado; las líneas, con `<br>`).
String labelDeTexto(String texto) => const LineSplitter()
    .convert(texto.trim())
    .map((l) => l.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;'))
    .join('<br>');

/* ════════════════════════════════════════════════════════════════════════
   Árbol (versión 1) → grafo, para VER los mapas que la web aún no ha convertido
═══════════════════════════════════════════════════════════════════════════ */

String _escapar(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

/// `tableToLabel` de table.ts: título en negrita y filas con `|`.
String labelDeTabla(Object? tabla) {
  if (tabla is! Map) return '';
  final titulo = tabla['title'] is String ? tabla['title'] as String : '';
  List<String> fila(Object? f) => f is List ? f.map((c) => '$c'.replaceAll('\n', ' ')).toList() : const [];
  final filas = [fila(tabla['columns']), for (final r in (tabla['rows'] is List ? tabla['rows'] as List : const [])) fila(r)];
  return [
    if (titulo.isNotEmpty) '<b>${_escapar(titulo)}</b>',
    for (final f in filas) _escapar(f.join(' | ')),
  ].join('<br>');
}

/// Tamaño estimado de una caja de árbol (`estimateSize` de layout.ts, sin medición real).
({double w, double h}) _tamanoEstimado(String texto, bool raiz) {
  const charW = 7.6, padX = 40.0, lineH = 20.0, padY = 22.0, minW = 110.0, maxW = 270.0, minH = 46.0;
  final lineas = (texto.isEmpty ? ' ' : texto).split('\n');
  double medir(String l) => l.length * (raiz ? charW + 1 : charW);
  final natural = lineas.map(medir).fold<double>(1, math.max);
  final w = math.min(maxW, math.max(minW, (natural + padX + 2).ceilToDouble()));
  final maxTexto = w - padX;
  var filas = 0;
  for (final l in lineas) {
    var f = 1;
    var cur = 0.0;
    for (final palabra in l.split(' ')) {
      final ww = medir(palabra);
      if (ww > maxTexto) {
        final piezas = (ww / maxTexto).ceil();
        f += cur > 0 ? piezas : piezas - 1;
        cur = ww - (piezas - 1) * maxTexto;
      } else if (cur == 0) {
        cur = ww;
      } else if (cur + medir(' ') + ww <= maxTexto + 1e-6) {
        cur += medir(' ') + ww;
      } else {
        f++;
        cur = ww;
      }
    }
    filas += f;
  }
  return (w: w, h: math.max(minH, filas * lineH + padY));
}

/// `treeToGraph` de graph.ts (con `computeLayout` de layout.ts): árbol horizontal, en abanico a
/// ambos lados de la raíz desde 8 bloques. Sin la colocación de ramas plegadas: aquí se ven
/// desplegadas.
Map<String, dynamic> grafoDesdeArbol(Map<String, dynamic> arbol) {
  final crudos = arbol['nodes'] is List ? arbol['nodes'] as List : const [];
  final nodos = <Map<String, dynamic>>[];
  final vistos = <String>{};
  for (final n in crudos) {
    if (n is! Map || n['id'] is! String || vistos.contains(n['id'])) continue;
    vistos.add(n['id'] as String);
    nodos.add(Map<String, dynamic>.from(n));
  }
  if (nodos.isEmpty) return {'version': 2, 'nodes': [], 'edges': []};
  final hijos = <String?, List<Map<String, dynamic>>>{};
  for (final n in nodos) {
    final p = n['parentId'] is String && vistos.contains(n['parentId']) ? n['parentId'] as String : null;
    n['parentId'] = p;
    hijos.putIfAbsent(p, () => []).add(n);
  }
  final raiz = hijos[null]!.first;
  String textoDe(Map<String, dynamic> n) =>
      n['table'] != null ? textoDeLabel(labelDeTabla(n['table'])) : textoDeLabel('${n['text'] ?? ''}');

  const gapX = 110.0, gapY = 18.0, depthGaps = [60.0, 22.0];
  final tam = <String, ({double w, double h})>{};
  final span = <String, double>{};
  final prof = <String, int>{};
  double hueco(Map<String, dynamic> padre) => gapY + ((prof[padre['id']] ?? 0) < depthGaps.length ? depthGaps[prof[padre['id']]!] : 0);
  List<Map<String, dynamic>> visibles(Map<String, dynamic> n) => hijos[n['id']] ?? const [];
  double spanHijos(Map<String, dynamic> n) {
    final g = hueco(n);
    var acc = 0.0;
    final hs = visibles(n);
    for (var i = 0; i < hs.length; i++) {
      acc += span[hs[i]['id']]! + (i > 0 ? g : 0);
    }
    return acc;
  }

  void medir(Map<String, dynamic> n, int d) {
    prof[n['id']] = d;
    tam[n['id']] = _tamanoEstimado(textoDe(n), d == 0);
    for (final c in visibles(n)) {
      medir(c, d + 1);
    }
    span[n['id']] = math.max(tam[n['id']]!.h, spanHijos(n));
  }

  medir(raiz, 0);
  final cajas = <String, Rect>{};
  void colocar(Map<String, dynamic> n, double borde, double arriba, int dir) {
    final t = tam[n['id']]!;
    final s = span[n['id']]!;
    final x = dir == 1 ? borde : borde - t.w;
    cajas[n['id']] = Rect.fromLTWH(x, arriba + (s - t.h) / 2, t.w, t.h);
    final g = hueco(n);
    var cursor = arriba + (s - spanHijos(n)) / 2;
    for (final c in visibles(n)) {
      colocar(c, dir == 1 ? x + t.w + gapX : x - gapX, cursor, dir);
      cursor += span[c['id']]! + g;
    }
  }

  final bloques = visibles(raiz);
  if (bloques.length >= 8) {
    final g = hueco(raiz);
    final total = bloques.fold<double>(0, (a, c) => a + span[c['id']]!) + g * (bloques.length - 1);
    var acumulado = 0.0, corte = 1, mejor = double.infinity;
    for (var k = 1; k < bloques.length; k++) {
      acumulado += span[bloques[k - 1]['id']]! + (k > 1 ? g : 0);
      final diff = (acumulado - (total - acumulado - g)).abs();
      if (diff < mejor) {
        mejor = diff;
        corte = k;
      }
    }
    final lados = [(bloques.sublist(0, corte), 1), (bloques.sublist(corte), -1)];
    double alto(List<Map<String, dynamic>> l) =>
        l.isEmpty ? 0 : l.fold<double>(0, (a, c) => a + span[c['id']]!) + g * (l.length - 1);
    final altos = lados.map((l) => alto(l.$1)).toList();
    final rt = tam[raiz['id']]!;
    final h = [...altos, rt.h].reduce(math.max);
    cajas[raiz['id']] = Rect.fromLTWH(0, (h - rt.h) / 2, rt.w, rt.h);
    for (var i = 0; i < 2; i++) {
      var cursor = (h - altos[i]) / 2;
      for (final c in lados[i].$1) {
        colocar(c, lados[i].$2 == 1 ? rt.w + gapX : -gapX, cursor, lados[i].$2);
        cursor += span[c['id']]! + g;
      }
    }
  } else {
    colocar(raiz, 0, 0, 1);
  }

  int nivel(Map<String, dynamic> n) {
    var l = 0;
    var p = n['parentId'] as String?;
    while (p != null && l < 1000) {
      l++;
      p = nodos.firstWhere((x) => x['id'] == p)['parentId'] as String?;
    }
    return l;
  }

  final gNodos = <Map<String, dynamic>>[];
  final gAristas = <Map<String, dynamic>>[];
  for (final n in nodos) {
    final id = n['id'] as String;
    final cat = categoriasMapa.containsKey(n['category']) ? n['category'] as String : 'general';
    final tabla = n['table'];
    final label = tabla != null ? labelDeTabla(tabla) : '${n['text'] ?? ''}';
    final estilo = estiloDeSerie(tabla != null ? 2 : nivel(n), cat, textoDeLabel(label));
    final caja = cajas[id] ?? Rect.zero;
    gNodos.add({
      'id': id,
      'type': 'mindmap',
      'position': {'x': caja.left, 'y': caja.top},
      if (estilo['shape'] == 'circle') 'width': 116,
      if (estilo['shape'] == 'circle') 'height': 116,
      'data': {
        'label': label,
        'style': estilo,
        if (n['parentId'] != null) 'parentId': n['parentId'],
        'category': cat,
        if (tabla != null) 'table': tabla,
        if (n['ia'] != null) 'ia': n['ia'],
      },
    });
    if (n['parentId'] != null) {
      gAristas.add({
        'id': 'e-${n['parentId']}-$id',
        'source': n['parentId'],
        'target': id,
        'sourceHandle': 'right',
        'targetHandle': 'left',
        'type': 'animated',
        'data': {'variant': 'solid', 'color': _hex(categoriasMapa[cat]!.color), 'strokeWidth': 1.8},
      });
    }
  }
  return {'version': 2, 'nodes': gNodos, 'edges': gAristas};
}

/* ════════════════════════════════════════════════════════════════════════
   El documento
═══════════════════════════════════════════════════════════════════════════ */

/// Lo que se pinta de un nodo. Se recalcula del JSON tras cada cambio.
class NodoMapa {
  final String id;
  final Offset posicion;
  final double? ancho;
  final double? alto;
  final String label;
  final EstiloNodo estilo;
  final String? padre;
  final String categoria;
  final bool plegado;
  final bool esTabla;

  const NodoMapa({
    required this.id,
    required this.posicion,
    required this.ancho,
    required this.alto,
    required this.label,
    required this.estilo,
    required this.padre,
    required this.categoria,
    required this.plegado,
    required this.esTabla,
  });

  /// Se puede cambiar su texto en la app (una tabla se edita en la web).
  bool get textoEditable => !esTabla;
}

class AristaMapa {
  final String id;
  final String origen;
  final String destino;
  final Color color;
  final double grosor;
  final String variante; // solid | dashed | dotted
  const AristaMapa(this.id, this.origen, this.destino, this.color, this.grosor, this.variante);
}

class DocMapa {
  /// El JSON tal cual (versión 2). Las ediciones lo cambian en su sitio.
  final Map<String, dynamic> json;

  /// Venía en formato árbol: se ve, pero no se edita (ver la cabecera).
  final bool desdeArbol;

  DocMapa._(this.json, this.desdeArbol);

  /// Lee el `doc` de la BD. Se copia entero (nada se comparte con el original).
  factory DocMapa.desde(Object? raw) {
    final copia = raw is Map ? jsonDecode(jsonEncode(raw)) as Map<String, dynamic> : <String, dynamic>{};
    if (copia['version'] == 2) {
      copia['nodes'] = (copia['nodes'] is List ? copia['nodes'] as List : const []).whereType<Map>().toList();
      copia['edges'] = (copia['edges'] is List ? copia['edges'] as List : const []).whereType<Map>().toList();
      return DocMapa._(copia, false);
    }
    return DocMapa._(grafoDesdeArbol(copia), true);
  }

  bool get editable => !desdeArbol;

  List<Map> get _nodos => json['nodes'] as List<Map>;
  List<Map> get _aristas => json['edges'] as List<Map>;

  Map? _nodo(String id) {
    for (final n in _nodos) {
      if (n['id'] == id) return n;
    }
    return null;
  }

  List<NodoMapa> get nodos => [
        for (final n in _nodos)
          if (n['id'] is String)
            () {
              final d = n['data'] is Map ? n['data'] as Map : const {};
              final p = n['position'] is Map ? n['position'] as Map : const {};
              double? dim(Object? v) => v is num && v.isFinite && v >= 20 ? v.toDouble() : null;
              return NodoMapa(
                id: n['id'] as String,
                posicion: Offset(
                  p['x'] is num ? (p['x'] as num).toDouble() : 0,
                  p['y'] is num ? (p['y'] as num).toDouble() : 0,
                ),
                ancho: dim(n['width']),
                alto: dim(n['height']),
                label: d['table'] != null ? labelDeTabla(d['table']) : (d['label'] is String ? d['label'] as String : ''),
                estilo: EstiloNodo.desde(d['style']),
                padre: d['parentId'] is String ? d['parentId'] as String : null,
                categoria: categoriasMapa.containsKey(d['category']) ? d['category'] as String : 'general',
                plegado: d['collapsed'] == true,
                esTabla: d['table'] != null,
              );
            }(),
      ];

  List<AristaMapa> get aristas {
    final ids = {for (final n in _nodos) n['id']};
    return [
      for (final e in _aristas)
        if (ids.contains(e['source']) && ids.contains(e['target']) && e['source'] != e['target'])
          () {
            final d = e['data'] is Map ? e['data'] as Map : const {};
            return AristaMapa(
              '${e['id'] ?? 'e-${e['source']}-${e['target']}'}',
              e['source'] as String,
              e['target'] as String,
              colorCss(d['color']) ?? const Color(0xFF585B70),
              d['strokeWidth'] is num ? (d['strokeWidth'] as num).toDouble().clamp(0.5, 12.0) : 1.5,
              d['variant'] is String ? d['variant'] as String : 'solid',
            );
          }(),
    ];
  }

  /// Padre de cada nodo: `data.parentId` o, si no lo tiene, el origen de la primera arista que le
  /// llega (como `autoLayoutGraph`). Sin ciclos.
  Map<String, String?> get padres {
    final ids = {for (final n in _nodos) n['id'] as String};
    final entrante = <String, String>{};
    for (final e in _aristas) {
      final s = e['source'], t = e['target'];
      if (s is String && t is String && ids.contains(s) && s != t) entrante.putIfAbsent(t, () => s);
    }
    final out = <String, String?>{};
    for (final n in nodos) {
      final p = n.padre != null && ids.contains(n.padre) && n.padre != n.id ? n.padre : entrante[n.id];
      out[n.id] = p;
    }
    for (final id in out.keys.toList()) {
      final camino = <String>{};
      String? cur = id;
      while (cur != null) {
        if (!camino.add(cur)) {
          out[id] = null;
          break;
        }
        cur = out[cur];
      }
    }
    return out;
  }

  /// Todos los descendientes de [id] (sin él).
  Set<String> descendientes(String id) {
    final hijos = <String, List<String>>{};
    padres.forEach((n, p) {
      if (p != null) hijos.putIfAbsent(p, () => []).add(n);
    });
    final out = <String>{};
    void bajar(String n) {
      for (final h in hijos[n] ?? const <String>[]) {
        if (out.add(h)) bajar(h);
      }
    }

    bajar(id);
    return out;
  }

  /// Nivel en el árbol (0 = raíz).
  int nivel(String id) {
    final p = padres;
    var l = 0;
    for (var cur = p[id]; cur != null && l < 5000; cur = p[cur]) {
      l++;
    }
    return l;
  }

  /* ── Ediciones (solo en grafos) ────────────────────────────────────────── */

  void _exigirEditable() {
    if (!editable) throw StateError('Este mapa no se puede editar en la app');
  }

  /// Cambia el texto del nodo. Devuelve false si no se puede (tabla) o no cambia.
  bool cambiarTexto(String id, String texto) {
    _exigirEditable();
    final n = _nodo(id);
    if (n == null) return false;
    final d = (n['data'] ??= <String, dynamic>{}) as Map;
    if (d['table'] != null) return false;
    final nuevo = labelDeTexto(texto);
    if (nuevo.isEmpty || nuevo == d['label']) return false;
    d['label'] = nuevo;
    return true;
  }

  /// Mueve [id] y toda su rama (como el arrastre de rama del editor de la web).
  void moverRama(String id, Offset delta) {
    _exigirEditable();
    final ids = {id, ...descendientes(id)};
    for (final n in _nodos) {
      if (!ids.contains(n['id'])) continue;
      final p = n['position'] is Map ? n['position'] as Map : <String, dynamic>{};
      double r(num v) => (v * 10).round() / 10;
      n['position'] = {
        'x': r(((p['x'] as num?) ?? 0) + delta.dx),
        'y': r(((p['y'] as num?) ?? 0) + delta.dy),
      };
    }
  }

  /// Añade un hijo a [padreId] y devuelve su id. Va hacia fuera (el lado contrario al abuelo), en
  /// la columna de sus hermanos y debajo del último (`childSlot` del editor). [tamano] da el tamaño
  /// pintado de cada nodo; [azar] es para los tests.
  String anadirHijo(String padreId, {required Size Function(String id) tamano, math.Random? azar}) {
    _exigirEditable();
    final padre = nodos.firstWhere((n) => n.id == padreId);
    final ps = padres;
    final abuelo = ps[padreId] == null ? null : nodos.where((n) => n.id == ps[padreId]).firstOrNull;
    final lado = abuelo != null && abuelo.posicion.dx > padre.posicion.dx ? -1 : 1;
    final hermanos = nodos
        .where((n) => ps[n.id] == padreId && (n.posicion.dx - padre.posicion.dx).sign == lado)
        .toList();
    final pw = tamano(padreId).width;
    final Offset pos;
    if (hermanos.isEmpty) {
      pos = lado > 0 ? Offset(padre.posicion.dx + pw + 90, padre.posicion.dy) : Offset(padre.posicion.dx - 90 - 160, padre.posicion.dy);
    } else {
      final ultimo = hermanos.reduce((a, b) =>
          b.posicion.dy + tamano(b.id).height > a.posicion.dy + tamano(a.id).height ? b : a);
      final x = lado > 0
          ? hermanos.map((n) => n.posicion.dx).reduce(math.min)
          : hermanos.map((n) => n.posicion.dx + tamano(n.id).width).reduce(math.max) - 160;
      pos = Offset(x, ultimo.posicion.dy + tamano(ultimo.id).height + 16);
    }
    final r = azar ?? math.Random();
    const abc = '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
    String id;
    do {
      id = List.generate(10, (_) => abc[r.nextInt(abc.length)]).join();
    } while (_nodo(id) != null);
    final nivelHijo = nivel(padreId) + 1;
    final categoria = padre.categoria;
    _nodos.add(<String, dynamic>{
      'id': id,
      'type': 'mindmap',
      'position': {'x': pos.dx, 'y': pos.dy},
      'data': {
        'label': 'Nueva idea',
        'style': estiloDeSerie(nivelHijo, categoria, 'Nueva idea'),
        'parentId': padreId,
        'category': categoria,
      },
    });
    _aristas.add(<String, dynamic>{
      'id': 'e-$padreId-$id',
      'source': padreId,
      'target': id,
      'sourceHandle': null,
      'targetHandle': null,
      'type': 'animated',
      'data': {'color': _hex(categoriasMapa[categoria]!.color), 'strokeWidth': 1.8},
    });
    // Añadir a una rama plegada la despliega: si no, el hijo nacería oculto.
    final dp = _nodo(padreId)!['data'];
    if (dp is Map && dp['collapsed'] == true) dp.remove('collapsed');
    return id;
  }

  /// Borra [id] con toda su rama y sus aristas. Devuelve cuántos nodos se fueron. La raíz no.
  int borrarRama(String id) {
    _exigirEditable();
    if (padres[id] == null) return 0;
    final fuera = {id, ...descendientes(id)};
    _nodos.removeWhere((n) => fuera.contains(n['id']));
    _aristas.removeWhere((e) => fuera.contains(e['source']) || fuera.contains(e['target']));
    return fuera.length;
  }

  /// Para buscar dentro (texto plano de todos los nodos, en minúsculas y sin tildes).
  String get textoBusqueda => normalizarBusquedaMapa(nodos.map((n) => textoDeLabel(n.label)).join(' '));
}

String normalizarBusquedaMapa(String s) {
  const tildes = {'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ü': 'u', 'ñ': 'n'};
  return s.toLowerCase().split('').map((c) => tildes[c] ?? c).join();
}

/* ════════════════════════════════════════════════════════════════════════
   Trazado de las líneas (AnimatedEdge.tsx, sin el desvío de obstáculos)
═══════════════════════════════════════════════════════════════════════════ */

enum LadoNodo { derecha, izquierda, arriba, abajo }

/// Por dónde sale y entra la línea según dónde están los dos nodos ahora (`pickSides`).
(LadoNodo, LadoNodo) ladosDeConexion(Rect s, Rect t) {
  if (t.left >= s.right) return (LadoNodo.derecha, LadoNodo.izquierda);
  if (t.right <= s.left) return (LadoNodo.izquierda, LadoNodo.derecha);
  return t.center.dy >= s.center.dy ? (LadoNodo.abajo, LadoNodo.arriba) : (LadoNodo.arriba, LadoNodo.abajo);
}

Offset anclaDe(Rect r, LadoNodo lado) => switch (lado) {
      LadoNodo.derecha => Offset(r.right, r.center.dy),
      LadoNodo.izquierda => Offset(r.left, r.center.dy),
      LadoNodo.abajo => Offset(r.center.dx, r.bottom),
      LadoNodo.arriba => Offset(r.center.dx, r.top),
    };

Offset _control(Offset p, LadoNodo lado, double brazo) => switch (lado) {
      LadoNodo.derecha => p + Offset(brazo, 0),
      LadoNodo.izquierda => p - Offset(brazo, 0),
      LadoNodo.abajo => p + Offset(0, brazo),
      LadoNodo.arriba => p - Offset(0, brazo),
    };

double _brazo(Offset a, Offset b, LadoNodo lado) {
  final dist = (b - a).distance;
  final eje = lado == LadoNodo.izquierda || lado == LadoNodo.derecha ? (b.dx - a.dx).abs() : (b.dy - a.dy).abs();
  return [dist * 0.42, eje * 0.55 + 20, 220.0].reduce(math.min);
}

/// La curva de una línea entre dos cajas: inicio, dos puntos de control y fin.
(Offset, Offset, Offset, Offset) curvaEntre(Rect origen, Rect destino) {
  final (ls, lt) = ladosDeConexion(origen, destino);
  final s = anclaDe(origen, ls);
  final t = anclaDe(destino, lt);
  return (s, _control(s, ls, _brazo(s, t, ls)), _control(t, lt, _brazo(t, s, lt)), t);
}
