// Extracción de documentos (PDF primero) para alimentar la IA. El texto se
// extrae EN EL DISPOSITIVO: el archivo nunca se sube; al servidor solo viaja el
// texto. Puerto de la web: src/lib/mapas/ia/extract/*.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../models/ia.dart';
import 'ia_extraccion_docx.dart';
import 'ia_extraccion_pptx.dart';

const int maxArchivoBytesIa = 30000000;
const int maxOfficeBytesIa = 120000000;
const double factorLecturaIa = 1.3;

const String formatosAceptadosIa = '.pdf,.docx,.pptx';

// Quita caracteres invisibles (también los que esconden instrucciones para una
// IA) y normaliza espacios. El servidor repite esta limpieza.
final RegExp _invisibles = RegExp(
  r'[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F-\u009F\u00AD\u061C\u180E\u200B-\u200F\u202A-\u202E\u2060-\u206F\uFEFF\u{E0000}-\u{E007F}]',
  unicode: true,
);

/// Normaliza el texto de una página: invisibles fuera, espacios y saltos limpios.
String limpiarTexto(String t) {
  return t
      .replaceAll(_invisibles, '')
      .replaceAll(RegExp(r'\r\n?'), '\n')
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll(RegExp(r' ?\n ?'), '\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

String _clave(String linea) => linea
    .toLowerCase()
    .replaceAll(RegExp(r'\d+'), '#')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Cabeceras y pies repetidos en las páginas (una línea corta que aparece en al
/// menos el 40 % de las páginas) no son contenido.
List<String> quitarRepetidas(List<String> paginas) {
  if (paginas.length < 4) {
    return paginas
        .map((p) => p.replaceAll(RegExp(r'^\s*\d{1,4}\s*$', multiLine: true), '').trim())
        .toList();
  }

  final cuenta = <String, int>{};
  for (final p in paginas) {
    final vistas = p.split('\n').map(_clave).where((l) => l.isNotEmpty && l.length < 120).toSet();
    for (final l in vistas) {
      cuenta[l] = (cuenta[l] ?? 0) + 1;
    }
  }

  final umbral = math.max(3, (paginas.length * 0.4).ceil());
  return paginas.map((p) {
    return p
        .split('\n')
        .where((l) {
          final k = _clave(l);
          if (k.isEmpty) return true;
          if (RegExp(r'^#$').hasMatch(k)) return false; // número de página suelto
          return !((cuenta[k] ?? 0) >= umbral && l.length < 120);
        })
        .join('\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }).toList();
}

/// Título razonable a partir del nombre de archivo (para cuando no hay metadatos).
String tituloDeArchivo(String nombre) {
  final t = nombre
      .replaceAll(RegExp(r'\.[a-z0-9]{2,5}$', caseSensitive: false), '')
      .replaceAll(RegExp(r'_+'), ' ')
      .replaceAll(RegExp(r'^\d+[.)\s-]+\s*'), '')
      .replaceAll(RegExp(r'\s*\(\d+\)\s*$'), '')
      .trim();
  final recortado = t.length > 120 ? t.substring(0, 120) : t;
  return recortado.isNotEmpty ? recortado : 'Mapa mental';
}

const String _comoGuardar = 'Archivo → Guardar como';

const Map<String, String> _mensajesFormato = {
  'ppt': 'Es un PowerPoint antiguo (.ppt) y solo se puede leer el formato nuevo. Ábrelo en PowerPoint o LibreOffice Impress, $_comoGuardar → «Presentación de PowerPoint (.pptx)», y vuelve a elegirlo. También vale exportarlo a PDF, pero así se pierden las notas del ponente.',
  'pps': 'Es una presentación de PowerPoint antigua (.pps). Ábrela en PowerPoint o LibreOffice Impress, $_comoGuardar → «Presentación de PowerPoint (.pptx)», y vuelve a elegirla.',
  'ppsx': 'Es una presentación de PowerPoint en modo pase (.ppsx). Ábrela en PowerPoint, $_comoGuardar → «Presentación de PowerPoint (.pptx)», y vuelve a elegirla.',
  'doc': 'Es un Word antiguo (.doc) y solo se puede leer el formato nuevo. Ábrelo en Word o LibreOffice Writer, $_comoGuardar → «Documento de Word (.docx)», y vuelve a elegirlo. También vale exportarlo a PDF.',
  'rtf': 'Es un documento .rtf. Ábrelo en Word o LibreOffice Writer, $_comoGuardar → «Documento de Word (.docx)», y vuelve a elegirlo.',
  'odt': 'Es un documento de LibreOffice (.odt). En LibreOffice Writer, $_comoGuardar → «Word 2007-365 (.docx)», y vuelve a elegirlo.',
  'odp': 'Es una presentación de LibreOffice (.odp). En LibreOffice Impress, $_comoGuardar → «PowerPoint 2007-365 (.pptx)», y vuelve a elegirla.',
  'key': 'Es una presentación de Keynote. En Keynote, Archivo → Exportar a → PowerPoint (.pptx) o PDF, y vuelve a elegirla.',
  'pages': 'Es un documento de Pages. En Pages, Archivo → Exportar a → Word (.docx) o PDF, y vuelve a elegirlo.',
};

const String _genericoFormato = 'Formato no admitido. Usa un PDF con texto, un Word (.docx) o un PowerPoint (.pptx).';

/// Mensaje para un archivo que no se puede leer, según su extensión.
String mensajeFormato(String nombre) {
  final m = RegExp(r'\.([a-z0-9]+)$', caseSensitive: false).firstMatch(nombre.trim());
  final ext = m?.group(1)?.toLowerCase() ?? '';
  return _mensajesFormato[ext] ?? _genericoFormato;
}

/// Aviso para un documento con imágenes: su contenido no entra en el mapa.
String? avisoImagenes(int n) {
  if (n <= 0) return null;
  return n == 1
      ? 'Tiene 1 imagen: lo que haya dentro (tablas, esquemas, texto en la imagen) no se lee, solo el texto del documento.'
      : 'Tiene $n imágenes: lo que haya dentro (tablas, esquemas, texto en las imágenes) no se lee, solo el texto del documento.';
}

/// Título de la portada como título del mapa; en MAYÚSCULAS se pasa a frase normal.
String tituloDePortada(String t) {
  final limpio = t.replaceAll(RegExp(r'\s+'), ' ').trim();
  final recortado = limpio.length > 120 ? limpio.substring(0, 120) : limpio;
  if (recortado.length < 4) return '';
  if (recortado != recortado.toUpperCase()) return recortado;
  final minus = recortado.toLowerCase();
  return minus[0].toUpperCase() + minus.substring(1);
}

/// Lee un PDF, un Word o un PowerPoint y devuelve su texto por secciones.
Future<Extraido> extraerDocumento({
  required Uint8List bytes,
  required String nombre,
  required int maxChars,
  void Function(int hecho, int total)? onProgreso,
}) async {
  if (bytes.isEmpty) throw const ExtractException('El archivo está vacío.');

  final nombreBajo = nombre.toLowerCase();
  final esOffice = nombreBajo.endsWith('.docx') || nombreBajo.endsWith('.pptx');
  final tope = esOffice ? maxOfficeBytesIa : maxArchivoBytesIa;
  if (bytes.length > tope) {
    throw ExtractException('El archivo pesa demasiado (máximo ${(tope / 1000000).round()} MB).');
  }

  if (nombreBajo.endsWith('.pdf')) {
    return extraerPdf(bytes: bytes, nombre: nombre, maxChars: maxChars, onProgreso: onProgreso);
  }
  if (nombreBajo.endsWith('.docx')) {
    return extraerDocx(bytes: bytes, nombre: nombre, maxChars: maxChars);
  }
  if (nombreBajo.endsWith('.pptx')) {
    return extraerPptx(bytes: bytes, nombre: nombre, maxChars: maxChars);
  }
  throw ExtractException(mensajeFormato(nombre));
}

/// Texto de un PDF, una sección por página. Solo PDF con capa de texto (sin OCR).
Future<Extraido> extraerPdf({
  required Uint8List bytes,
  required String nombre,
  required int maxChars,
  void Function(int hecho, int total)? onProgreso,
}) async {
  PdfDocument doc;
  try {
    doc = PdfDocument(inputBytes: bytes);
  } catch (e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('password') || msg.contains('encrypt')) {
      throw const ExtractException('El PDF está protegido con contraseña.');
    }
    throw const ExtractException('No se pudo leer el PDF. Puede estar dañado.');
  }

  try {
    final numPaginas = doc.pages.count;
    final topeLectura = (maxChars * factorLecturaIa).round();
    final extractor = PdfTextExtractor(doc);
    final paginas = <String>[];
    var acumulado = 0;
    var truncado = false;

    for (var i = 0; i < numPaginas; i++) {
      final limpio = limpiarTexto(extractor.extractText(startPageIndex: i, endPageIndex: i));
      paginas.add(limpio);
      acumulado += limpio.length;
      onProgreso?.call(i + 1, numPaginas);
      if (acumulado > topeLectura && i < numPaginas - 1) {
        truncado = true;
        break;
      }
    }

    final conTexto = paginas.where((p) => p.length >= 40).length;
    if (paginas.isNotEmpty && conTexto / paginas.length < 0.3) {
      throw const ExtractException(
        'Este PDF parece escaneado (casi no tiene texto seleccionable). De momento solo se admiten PDF con texto.',
      );
    }

    var titulo = '';
    try {
      titulo = limpiarTexto(doc.documentInformation.title);
    } catch (_) {
      /* sin metadatos */
    }
    if (titulo.length > 120) titulo = titulo.substring(0, 120);

    final marcadores = _marcadores(doc, paginas.length);
    final limpias = quitarRepetidas(paginas);

    final secciones = <Seccion>[];
    for (var i = 0; i < limpias.length; i++) {
      if (limpias[i].length >= 10) {
        secciones.add(Seccion(texto: limpias[i], pagina: i + 1));
      }
    }

    final avisos = <String>[];
    if (truncado) avisos.add('El documento es muy largo: solo se ha leído la primera parte.');

    return Extraido(
      titulo: titulo.length >= 4 ? titulo : tituloDeArchivo(nombre),
      secciones: secciones,
      paginas: numPaginas,
      tablas: 0, // Detección de tablas: pendiente de una fase posterior.
      unidad: 'página',
      caracteres: secciones.fold(0, (s, x) => s + x.texto.length),
      avisos: avisos,
      truncado: truncado,
      marcadores: marcadores.length >= 2 ? marcadores : null,
    );
  } finally {
    doc.dispose();
  }
}

List<Marcador> _marcadores(PdfDocument doc, int maxPagina) {
  final out = <Marcador>[];

  void recorrer(PdfBookmarkBase base, int nivel) {
    for (var i = 0; i < base.count && out.length < 300; i++) {
      final bm = base[i];
      final titulo = limpiarTexto(bm.title);
      final pagina = _paginaDe(doc, bm.destination);
      if (pagina != null && titulo.isNotEmpty && pagina <= maxPagina) {
        out.add(Marcador(
          titulo: titulo.length > 120 ? titulo.substring(0, 120) : titulo,
          pagina: pagina,
          nivel: nivel,
        ));
      }
      if (nivel == 1) recorrer(bm, 2);
    }
  }

  try {
    recorrer(doc.bookmarks, 1);
  } catch (_) {
    /* sin marcadores */
  }
  return out;
}

int? _paginaDe(PdfDocument doc, PdfDestination? dest) {
  if (dest == null) return null;
  try {
    final idx = doc.pages.indexOf(dest.page);
    return idx >= 0 ? idx + 1 : null;
  } catch (_) {
    return null;
  }
}
