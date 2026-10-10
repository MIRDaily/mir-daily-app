// Ayudas del índice de un documento largo (libro tema a tema). El servidor saca
// el índice con una llamada barata a partir del PRINCIPIO de cada sección, no
// del documento entero. Puro y testeable.
//
// Puerto de la web: src/lib/mapas/ia/libro.ts (resumenParaIndice + sanitizeTemas).

import '../models/ia.dart';

/// Caracteres del principio de cada sección que viajan para sacar el índice.
const int inicioIndice = 400;

const int _maxTemasIndice = 200;
const int _maxCharsTema = 10000000;
const int _maxPagina = 100000;

/// Lo que se manda a POST /indice: el principio de cada sección, su tamaño y su página.
List<Map<String, dynamic>> resumenParaIndice(List<Seccion> secciones) {
  return secciones.map((s) {
    final inicio = '${s.titulo != null ? '${s.titulo}\n' : ''}${s.texto}';
    return {
      'inicio': inicio.length > inicioIndice ? inicio.substring(0, inicioIndice) : inicio,
      'chars': s.texto.length + (s.titulo?.length ?? 0),
      if (s.pagina != null) 'pagina': s.pagina,
    };
  }).toList();
}

int? _entero(Object? v, int max) => v is int && v >= 0 && v <= max ? v : null;

String _texto(Object? v, int max) {
  if (v is! String) return '';
  final limpio = v.replaceAll(RegExp(r'\s+'), ' ').trim();
  return limpio.length > max ? limpio.substring(0, max) : limpio;
}

/// Respuesta no fiable del servidor → temas válidos (en orden, dentro de rango,
/// sin solaparse).
List<TemaIndice> sanitizeTemas(Object? raw, int n) {
  if (raw is! List) return const [];
  final out = <TemaIndice>[];
  var fin = -1;

  for (final r in raw.take(_maxTemasIndice)) {
    if (r is! Map) continue;
    final desde = _entero(r['desde'], n - 1);
    final hasta = _entero(r['hasta'], n - 1);
    if (desde == null || hasta == null || desde > hasta || desde <= fin) continue;
    fin = hasta;

    final apartados = <ApartadoIndice>[];
    if (r['apartados'] is List) {
      for (final a in r['apartados'] as List) {
        final m = a is Map ? a : const {};
        final titulo = _texto(m['titulo'], 120);
        final d = _entero(m['desde'], n - 1);
        if (titulo.isNotEmpty && d != null && d >= desde && d <= hasta) {
          apartados.add(ApartadoIndice(titulo: titulo, desde: d));
        }
      }
    }

    final titulo = _texto(r['titulo'], 120);
    out.add(TemaIndice(
      titulo: titulo.isNotEmpty ? titulo : 'Parte ${out.length + 1}',
      desde: desde,
      hasta: hasta,
      chars: _entero(r['chars'], _maxCharsTema) ?? 0,
      paginaDesde: _entero(r['paginaDesde'], _maxPagina),
      paginaHasta: _entero(r['paginaHasta'], _maxPagina),
      apartados: apartados,
    ));
  }
  return out;
}
