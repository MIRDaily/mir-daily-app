// Texto de un Word (.docx) con sus títulos como secciones. Un .docx es un ZIP
// con XML; aquí se lee word/document.xml y se agrupa por títulos.
//
// Puerto de la web: src/lib/mapas/ia/extract/docx.ts.

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../models/ia.dart';
import 'ia_extraccion.dart'
    show avisoImagenes, factorLecturaIa, limpiarTexto, tituloDeArchivo;

Future<Extraido> extraerDocx({
  required Uint8List bytes,
  required String nombre,
  required int maxChars,
}) async {
  Archive zip;
  try {
    zip = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    throw const ExtractException('No se pudo leer el documento Word. Comprueba que es un .docx válido.');
  }

  final entry = _entrada(zip, 'word/document.xml');
  if (entry == null) {
    throw const ExtractException('No se pudo leer el documento Word. Comprueba que es un .docx válido.');
  }

  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(utf8.decode(entry.content));
  } catch (_) {
    throw const ExtractException('No se pudo leer el documento Word. Comprueba que es un .docx válido.');
  }

  final secciones = <Seccion>[];
  String? titulo;
  var lineas = <String>[];
  var acumulado = 0;
  var truncado = false;
  final tope = (maxChars * factorLecturaIa).round();

  void cerrar() {
    final texto = limpiarTexto(lineas.join('\n'));
    if (texto.length >= 10 || (titulo != null && texto.isNotEmpty)) {
      secciones.add(Seccion(titulo: titulo, texto: texto));
    }
    lineas = [];
  }

  void recorrer(XmlElement nodo) {
    for (final hijo in nodo.childElements) {
      if (truncado) return;
      final nombre = hijo.name.local;
      final nivel = nombre == 'p' ? _nivelTitulo(hijo) : null;

      if (nivel != null) {
        cerrar();
        final t = limpiarTexto(hijo.innerText);
        titulo = t.length > 100 ? t.substring(0, 100) : t;
        if (titulo!.isEmpty) titulo = null;
      } else if (nombre == 'p') {
        final t = limpiarTexto(hijo.innerText);
        if (t.isNotEmpty) {
          lineas.add(t);
          acumulado += t.length;
        }
      } else if (nombre == 'tr') {
        // Las celdas vacías se conservan: quitarlas descuadra las columnas.
        final celdas = hijo.childElements
            .where((c) => c.name.local == 'tc')
            .map((c) => limpiarTexto(c.innerText))
            .toList();
        final fila = celdas.any((c) => c.isNotEmpty) ? celdas.join(' | ') : '';
        if (fila.isNotEmpty) {
          lineas.add(fila);
          acumulado += fila.length;
        }
      } else {
        recorrer(hijo); // tbl, sdt, etc.
      }

      if (acumulado > tope) truncado = true;
    }
  }

  final cuerpo = _elemento(doc, 'body');
  if (cuerpo != null) recorrer(cuerpo);
  cerrar();

  final total = secciones.fold(0, (s, x) => s + x.texto.length);
  if (total < 50) {
    throw const ExtractException('El documento no tiene texto suficiente.');
  }

  final avisos = <String>[];
  if (truncado) avisos.add('El documento es muy largo: solo se ha leído la primera parte.');
  final imagenes = zip.files.where((f) => f.name.startsWith('word/media/')).length;
  final aviso = avisoImagenes(imagenes);
  if (aviso != null) avisos.add(aviso);

  return Extraido(
    titulo: tituloDeArchivo(nombre),
    secciones: secciones,
    // Word no tiene páginas fijas; se estima (≈ 2.500 caracteres por página).
    paginas: math.max(1, (total / 2500).round()),
    tablas: 0,
    unidad: 'página',
    caracteres: total,
    avisos: avisos,
    truncado: truncado,
  );
}

/// Nivel de título de un párrafo (1..6), o null si no es un título.
int? _nivelTitulo(XmlElement p) {
  final val = _valorEstilo(p);
  if (val.isEmpty) return null;
  if (!RegExp(r'heading|t[íi]tulo', caseSensitive: false).hasMatch(val)) return null;
  final m = RegExp(r'\d').firstMatch(val);
  final nivel = m != null ? (int.tryParse(m.group(0)!) ?? 1) : 1;
  return nivel.clamp(1, 6);
}

String _valorEstilo(XmlElement p) {
  for (final e in p.descendants.whereType<XmlElement>()) {
    if (e.name.local == 'pStyle') return _atributo(e, 'val');
  }
  return '';
}

String _atributo(XmlElement e, String local) {
  for (final a in e.attributes) {
    if (a.name.local == local) return a.value;
  }
  return '';
}

XmlElement? _elemento(XmlNode raiz, String local) {
  for (final e in raiz.descendants.whereType<XmlElement>()) {
    if (e.name.local == local) return e;
  }
  return null;
}

ArchiveFile? _entrada(Archive zip, String ruta) {
  final l = zip.files.where((f) => f.name == ruta).toList();
  return l.isEmpty ? null : l.first;
}
