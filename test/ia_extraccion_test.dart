import 'dart:io' show File;
import 'dart:typed_data';

import 'package:flutter/material.dart' show Rect;
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'package:mirdaily_app/core/models/ia.dart';
import 'package:mirdaily_app/core/services/ia_extraccion.dart';

/// Genera un PDF en memoria con una página por texto (para el test de ida y vuelta).
/// Usa una fuente TrueType embebida: el extractor lee el texto por el mapa ToUnicode,
/// igual que hará con los PDF reales (los fuentes estándar no llevan ToUnicode).
Uint8List _pdf(String titulo, List<String> textos) {
  final ttf = File('assets/fonts/lexend/Lexend-Regular.ttf').readAsBytesSync();
  final doc = PdfDocument();
  doc.documentInformation.title = titulo;
  final font = PdfTrueTypeFont(ttf, 12);
  for (final t in textos) {
    final page = doc.pages.add();
    page.graphics.drawString(
      t,
      font,
      bounds: const Rect.fromLTWH(20, 20, 400, 200),
    );
  }
  final bytes = doc.saveSync();
  doc.dispose();
  return Uint8List.fromList(bytes);
}

void main() {
  group('mensajeFormato', () {
    test('ppt, doc y key dan instrucciones de conversión', () {
      expect(mensajeFormato('tema.ppt'), contains('PowerPoint antiguo'));
      expect(mensajeFormato('tema.doc'), contains('Word antiguo'));
      expect(mensajeFormato('notas.key'), contains('Keynote'));
    });

    test('extensión desconocida da el mensaje genérico', () {
      expect(mensajeFormato('archivo.xyz'), contains('Formato no admitido'));
    });
  });

  group('tituloDeArchivo', () {
    test('quita extensión, prefijo numérico y sufijo (n)', () {
      expect(tituloDeArchivo('01_Tema_2_(3).pdf'), 'Tema 2');
    });

    test('sin título devuelve el nombre por defecto', () {
      expect(tituloDeArchivo(''), 'Mapa mental');
    });
  });

  group('limpiarTexto', () {
    test('quita caracteres invisibles', () {
      expect(limpiarTexto('A\u200B\u200BB'), 'AB');
    });

    test('normaliza espacios y tabuladores', () {
      expect(limpiarTexto('  hola\t mundo  '), 'hola mundo');
    });

    test('normaliza los saltos de línea', () {
      expect(limpiarTexto('una\r\nlinea'), 'una\nlinea');
    });
  });

  group('quitarRepetidas', () {
    test('quita una cabecera que aparece en la mayoría de páginas', () {
      final paginas = [
        'CABECERA\nLa anemia ferropénica es frecuente',
        'CABECERA\nEl lupus eritematoso sistémico',
        'CABECERA\nLa insuficiencia cardiaca crónica',
        'CABECERA\nLa diabetes mellitus tipo dos',
        'CABECERA\nLa hipertensión arterial esencial',
      ];
      final limpias = quitarRepetidas(paginas);
      expect(limpias.every((p) => !p.contains('CABECERA')), isTrue);
      expect(limpias[0], 'La anemia ferropénica es frecuente');
    });
  });

  group('extraerPdf', () {
    test('extrae una sección por página y el título de los metadatos', () async {
      final bytes = _pdf('Mi documento', [
        'La anemia ferropénica es la causa más frecuente de anemia en el mundo',
        'El lupus eritematoso sistémico es una enfermedad autoinmune crónica',
      ]);
      final e = await extraerPdf(bytes: bytes, nombre: 'apuntes.pdf', maxChars: 100000);
      expect(e.titulo, 'Mi documento');
      expect(e.paginas, 2);
      expect(e.secciones.length, 2);
      expect(e.secciones[0].pagina, 1);
      expect(e.secciones[1].pagina, 2);
      expect(e.secciones[0].texto, contains('anemia ferropénica'));
    });

    test('un PDF sin texto se detecta como escaneado', () async {
      final bytes = _pdf('Vacio', ['']);
      await expectLater(
        extraerPdf(bytes: bytes, nombre: 'escaneado.pdf', maxChars: 100000),
        throwsA(isA<ExtractException>().having((e) => e.message, 'message', contains('escaneado'))),
      );
    });
  });

  group('extraerDocumento', () {
    test('archivo vacío lanza su error', () async {
      await expectLater(
        extraerDocumento(bytes: Uint8List(0), nombre: 'x.pdf', maxChars: 1000),
        throwsA(isA<ExtractException>().having((e) => e.message, 'message', 'El archivo está vacío.')),
      );
    });

    test('extensión no admitida da el mensaje de formato', () async {
      await expectLater(
        extraerDocumento(bytes: Uint8List.fromList([1, 2, 3]), nombre: 'x.odt', maxChars: 1000),
        throwsA(isA<ExtractException>().having((e) => e.message, 'message', contains('LibreOffice'))),
      );
    });
  });
}
