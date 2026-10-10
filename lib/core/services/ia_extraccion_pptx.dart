// Texto de un PowerPoint (.pptx): una sección por diapositiva, con su título y
// sus notas. Un .pptx es un ZIP con XML; se lee el orden real de diapositivas y
// solo el texto (nunca imágenes ni vídeo).
//
// Puerto de la web: src/lib/mapas/ia/extract/pptx.ts.

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../models/ia.dart';
import 'ia_extraccion.dart'
    show avisoImagenes, factorLecturaIa, limpiarTexto, tituloDeArchivo, tituloDePortada;

const int _maxEntradas = 4000;
const int _maxXmlBytes = 8000000;

// Marcadores que no son contenido: número de diapositiva, pie y fecha.
const Set<String> _phIgnorados = {'sldNum', 'ftr', 'dt', 'hdr'};
const Set<String> _phTitulo = {'title', 'ctrTitle'};

Future<Extraido> extraerPptx({
  required Uint8List bytes,
  required String nombre,
  required int maxChars,
}) async {
  Archive zip;
  try {
    zip = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    throw const ExtractException('No se pudo leer la presentación. Comprueba que es un .pptx válido.');
  }
  if (zip.files.length > _maxEntradas) {
    throw const ExtractException('La presentación tiene demasiados elementos.');
  }

  // Orden real de las diapositivas: presentation.xml + sus relaciones.
  final pres = _leerXml(zip, 'ppt/presentation.xml');
  final relPres = _relaciones(_leerXml(zip, 'ppt/_rels/presentation.xml.rels'));
  var rutas = <String>[];
  if (pres != null) {
    for (final s in pres.descendants.whereType<XmlElement>().where((e) => e.name.local == 'sldId')) {
      final destino = relPres[_atributo(s, 'id')];
      if (destino != null && destino.isNotEmpty) {
        rutas.add(_resolver('ppt/presentation.xml', destino));
      }
    }
  }
  if (rutas.isEmpty) {
    rutas = zip.files
        .where((f) => RegExp(r'^ppt/slides/slide\d+\.xml$').hasMatch(f.name))
        .map((f) => f.name)
        .toList()
      ..sort((a, b) => _numeroSlide(a).compareTo(_numeroSlide(b)));
  }
  if (rutas.isEmpty) throw const ExtractException('La presentación no tiene diapositivas.');

  final secciones = <Seccion>[];
  var tituloPortada = '';
  final tope = (maxChars * factorLecturaIa).round();
  var acumulado = 0;
  var truncado = false;

  for (var indice = 0; indice < rutas.length; indice++) {
    final ruta = rutas[indice];
    final doc = _leerXml(zip, ruta);
    if (doc == null) continue;

    var titulo = '';
    final cuerpo = <String>[];

    for (final sp in doc.descendants.whereType<XmlElement>().where((e) => e.name.local == 'sp')) {
      final ph = _primerElemento(sp, 'ph');
      final tipo = ph != null ? _atributo(ph, 'type') : '';
      if (_phIgnorados.contains(tipo)) continue;
      final lineas = _parrafos(sp);
      if (lineas.isEmpty) continue;
      if (_phTitulo.contains(tipo) && titulo.isEmpty) {
        titulo = lineas.join(' ');
      } else {
        cuerpo.addAll(lineas);
      }
    }

    // Tablas (a:tbl): una línea por fila, celdas separadas por " | ".
    for (final fila in doc.descendants.whereType<XmlElement>().where((e) => e.name.local == 'tr')) {
      final celdas = fila.descendants
          .whereType<XmlElement>()
          .where((e) => e.name.local == 'tc')
          .map((c) => _parrafos(c).join(' '))
          .toList();
      if (celdas.any((c) => c.isNotEmpty)) cuerpo.add(celdas.join(' | '));
    }

    // Notas del orador: en clases y seminarios suelen llevar la explicación.
    final relSlide = _relaciones(
      _leerXml(zip, ruta.replaceFirstMapped(RegExp(r'([^/]+)\.xml$'), (m) => '_rels/${m.group(1)}.xml.rels')),
    );
    for (final destino in relSlide.values) {
      if (!destino.contains('notesSlide')) continue;
      final notas = _leerXml(zip, _resolver(ruta, destino));
      if (notas == null) continue;
      final lineas = <String>[];
      for (final sp in notas.descendants.whereType<XmlElement>().where((e) => e.name.local == 'sp')) {
        final ph = _primerElemento(sp, 'ph');
        final tipo = ph != null ? _atributo(ph, 'type') : '';
        if (tipo == 'body') lineas.addAll(_parrafos(sp));
      }
      if (lineas.isNotEmpty) cuerpo.add('Notas: ${lineas.join(' ')}');
    }

    if (ruta == rutas[0]) tituloPortada = titulo;
    final texto = limpiarTexto(cuerpo.join('\n'));
    if (titulo.isEmpty && texto.length < 10) continue;

    final tituloRec = titulo.length > 100 ? titulo.substring(0, 100) : titulo;
    secciones.add(Seccion(
      titulo: tituloRec.isEmpty ? null : tituloRec,
      texto: texto.isEmpty ? titulo : texto,
      pagina: indice + 1,
    ));
    acumulado += texto.length + titulo.length;
    if (acumulado > tope && ruta != rutas.last) {
      truncado = true;
      break;
    }
  }

  final total = secciones.fold(0, (s, x) => s + x.texto.length + (x.titulo?.length ?? 0));
  if (total < 50) {
    throw const ExtractException('La presentación no tiene texto suficiente (¿son solo imágenes?).');
  }

  final avisos = <String>[];
  if (truncado) avisos.add('La presentación es muy larga: solo se han leído las primeras diapositivas.');
  final imagenes = zip.files.where((f) => RegExp(r'^ppt/media/image', caseSensitive: false).hasMatch(f.name)).length;
  final aviso = avisoImagenes(imagenes);
  if (aviso != null) avisos.add(aviso);

  final titulo = tituloDePortada(tituloPortada);
  return Extraido(
    titulo: titulo.isNotEmpty ? titulo : tituloDeArchivo(nombre),
    secciones: secciones,
    paginas: rutas.length,
    tablas: 0,
    unidad: 'diapositiva',
    caracteres: total,
    avisos: avisos,
    truncado: truncado,
  );
}

/// Párrafos (a:p) de un contenedor, uniendo sus fragmentos de texto (a:t).
List<String> _parrafos(XmlElement raiz) {
  final out = <String>[];
  for (final p in raiz.descendants.whereType<XmlElement>().where((e) => e.name.local == 'p')) {
    final buf = StringBuffer();
    for (final t in p.descendants.whereType<XmlElement>().where((e) => e.name.local == 't')) {
      buf.write(t.innerText);
    }
    final limpio = limpiarTexto(buf.toString());
    if (limpio.isNotEmpty) out.add(limpio);
  }
  return out;
}

Map<String, String> _relaciones(XmlDocument? doc) {
  final mapa = <String, String>{};
  if (doc == null) return mapa;
  for (final r in doc.descendants.whereType<XmlElement>()) {
    if (r.name.local == 'Relationship') {
      final id = _atributo(r, 'Id');
      final destino = _atributo(r, 'Target');
      if (id.isNotEmpty && destino.isNotEmpty) mapa[id] = destino;
    }
  }
  return mapa;
}

/// Ruta absoluta dentro del zip de un destino relativo (`../slides/slide1.xml`).
String _resolver(String base, String destino) {
  if (destino.startsWith('/')) return destino.substring(1);
  final partes = base.split('/')..removeLast();
  for (final seg in destino.split('/')) {
    if (seg == '..') {
      if (partes.isNotEmpty) partes.removeLast();
    } else if (seg != '.') {
      partes.add(seg);
    }
  }
  return partes.join('/');
}

XmlDocument? _leerXml(Archive zip, String ruta) {
  final l = zip.files.where((f) => f.name == ruta).toList();
  if (l.isEmpty) return null;
  if (l.first.content.length > _maxXmlBytes) return null;
  try {
    return XmlDocument.parse(utf8.decode(l.first.content));
  } catch (_) {
    return null;
  }
}

XmlElement? _primerElemento(XmlNode raiz, String local) {
  for (final e in raiz.descendants.whereType<XmlElement>()) {
    if (e.name.local == local) return e;
  }
  return null;
}

String _atributo(XmlElement e, String local) {
  for (final a in e.attributes) {
    if (a.name.local == local) return a.value;
  }
  return '';
}

int _numeroSlide(String ruta) {
  final m = RegExp(r'\d+').firstMatch(ruta);
  return m != null ? int.parse(m.group(0)!) : 0;
}
