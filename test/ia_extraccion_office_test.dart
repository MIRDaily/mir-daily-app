import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mirdaily_app/core/services/ia_extraccion_docx.dart';
import 'package:mirdaily_app/core/services/ia_extraccion_pptx.dart';

/// Construye un ZIP en memoria con las entradas dadas (para los tests).
Uint8List _zip(Map<String, String> entradas) {
  final zip = Archive();
  entradas.forEach((nombre, contenido) {
    final bytes = utf8.encode(contenido);
    zip.addFile(ArchiveFile(nombre, bytes.length, bytes));
  });
  return Uint8List.fromList(ZipEncoder().encode(zip));
}

/// Diapositiva mínima: una lista de (tipo de marcador, texto).
String _slide(List<(String, String)> items) {
  final buf = StringBuffer();
  var id = 1;
  for (final (tipo, texto) in items) {
    buf.write('<p:sp><p:nvSpPr><p:cNvPr id="$id" name="x"/><p:nvPr><p:ph type="$tipo"/></p:nvPr></p:nvSpPr>'
        '<p:txBody><a:p><a:r><a:t>$texto</a:t></a:r></a:p></p:txBody></p:sp>');
    id++;
  }
  return '<p:sld xmlns:p="p" xmlns:a="a"><p:cSld><p:spTree>$buf</p:spTree></p:cSld></p:sld>';
}

void main() {
  group('extraerDocx', () {
    test('agrupa en secciones por títulos y junta las celdas de tabla con |', () async {
      final docx = _zip({
        'word/document.xml': '''
          <w:document xmlns:w="w"><w:body>
            <w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr><w:r><w:t>Introducción</w:t></w:r></w:p>
            <w:p><w:r><w:t>La anemia ferropénica es la causa más frecuente de anemia en el mundo</w:t></w:r></w:p>
            <w:tbl><w:tr><w:tc><w:p><w:r><w:t>Hierro</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>Ferritina</w:t></w:r></w:p></w:tc></w:tr></w:tbl>
            <w:p><w:pPr><w:pStyle w:val="Heading2"/></w:pPr><w:r><w:t>Diagnóstico</w:t></w:r></w:p>
            <w:p><w:r><w:t>La ferritina baja confirma el diagnóstico</w:t></w:r></w:p>
          </w:body></w:document>''',
      });

      final e = await extraerDocx(bytes: docx, nombre: 'tema.docx', maxChars: 100000);
      expect(e.secciones.length, 2);
      expect(e.secciones[0].titulo, 'Introducción');
      expect(e.secciones[0].texto, contains('La anemia ferropénica'));
      expect(e.secciones[0].texto, contains('Hierro | Ferritina'));
      expect(e.secciones[1].titulo, 'Diagnóstico');
      expect(e.secciones[1].texto, contains('La ferritina baja'));
    });
  });

  group('extraerPptx', () {
    test('una sección por diapositiva, con título y notas', () async {
      final pptx = _zip({
        'ppt/presentation.xml': '''
          <p:presentation xmlns:p="p" xmlns:r="r">
            <p:sldIdLst><p:sldId id="256" r:id="rId2"/><p:sldId id="257" r:id="rId1"/></p:sldIdLst>
          </p:presentation>''',
        'ppt/_rels/presentation.xml.rels': '''
          <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
            <Relationship Id="rId1" Type="x" Target="slides/slide2.xml"/>
            <Relationship Id="rId2" Type="x" Target="slides/slide1.xml"/>
          </Relationships>''',
        'ppt/slides/slide1.xml': _slide([
          ('title', 'Mi presentación'),
          ('body', 'La anemia ferropénica es la causa más frecuente de anemia'),
        ]),
        'ppt/slides/slide2.xml': _slide([
          ('body', 'El lupus eritematoso sistémico es una enfermedad autoinmune'),
        ]),
      });

      final e = await extraerPptx(bytes: pptx, nombre: 'clase.pptx', maxChars: 100000);
      expect(e.titulo, 'Mi presentación');
      expect(e.paginas, 2);
      expect(e.unidad, 'diapositiva');
      expect(e.secciones.length, 2);
      expect(e.secciones[0].titulo, 'Mi presentación');
      expect(e.secciones[0].pagina, 1);
      expect(e.secciones[1].texto, contains('lupus eritematoso'));
    });
  });
}
