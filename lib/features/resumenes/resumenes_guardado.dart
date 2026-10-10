// Guardar la vista previa de los resúmenes con IA (lo puro): qué párrafos se
// guardan de verdad, el literal por documento (tope del 30 %) y las tandas para
// el servidor (por documento, de 40 en 40). Puerto de src/lib/resumenes/guardado.ts.

import '../../core/models/resumen.dart';
import '../../core/models/resumen_ia.dart';
import 'resumenes_api.dart';

const int tandaGuardado = 40;

/// ¿Se guarda? Marcado y, si se parece a uno del grupo, con «Incluir igual».
bool seGuarda(ParrafoBorrador p, Parecido? parecido) => p.incluir && (parecido == null || p.incluirParecido);

/// Caracteres de «texto original» por documento entre los que se guardan.
Map<String, int> literalPorDocumento(List<ParrafoBorrador> lista, ModoResumen modo, Map<String, Parecido?> parecidos) {
  final out = <String, int>{};
  if (modo != ModoResumen.literal) return out;
  for (final p in lista) {
    if (p.doc != null && seGuarda(p, parecidos[p.key])) {
      out[p.doc!] = (out[p.doc!] ?? 0) + p.texto.length;
    }
  }
  return out;
}

/// Un documento que se pasaría del tope en el grupo.
class ExcesoLiteral {
  final String hash;
  final int usado;
  final int tope;
  final int nuevos;
  final int sobran;

  const ExcesoLiteral({required this.hash, required this.usado, required this.tope, required this.nuevos, required this.sobran});
}

List<ExcesoLiteral> excesosLiteral(Map<String, int> nuevos, List<UsoLiteral> usos) {
  final out = <ExcesoLiteral>[];
  for (final u in usos) {
    final n = nuevos[u.hash] ?? 0;
    if (n > 0 && u.usado + n > u.tope) {
      out.add(ExcesoLiteral(hash: u.hash, usado: u.usado, tope: u.tope, nuevos: n, sobran: u.usado + n - u.tope));
    }
  }
  return out;
}

/// Los que se guardan → tandas por documento (en orden), con su fuente y los
/// índices (dentro de la tanda) de los que van aunque se parezcan a uno del grupo.
List<TandaIA> tandasDeGuardado(
  List<ParrafoBorrador> lista,
  ParrafoNuevo Function(ParrafoBorrador) aNuevo,
  List<FuenteFirmada> fuentes,
  Map<String, Parecido?> parecidos,
) {
  final porDoc = <String, List<ParrafoBorrador>>{};
  for (final p in lista) {
    if (!seGuarda(p, parecidos[p.key])) continue;
    final k = (p.doc != null && fuentes.any((f) => f.hash == p.doc)) ? p.doc! : '';
    (porDoc[k] ??= []).add(p);
  }

  final tandas = <TandaIA>[];
  for (final e in porDoc.entries) {
    FuenteFirmada? fuente;
    for (final f in fuentes) {
      if (f.hash == e.key) {
        fuente = f;
        break;
      }
    }
    final ps = e.value;
    for (var k = 0; k < ps.length; k += tandaGuardado) {
      final fin = (k + tandaGuardado) < ps.length ? k + tandaGuardado : ps.length;
      final trozo = ps.sublist(k, fin);
      final incluirParecidos = <int>[];
      for (var j = 0; j < trozo.length; j++) {
        if (trozo[j].incluirParecido && parecidos[trozo[j].key] != null) incluirParecidos.add(j);
      }
      tandas.add(TandaIA(fuente: fuente, parrafos: trozo.map(aNuevo).toList(), incluirParecidos: incluirParecidos));
    }
  }
  return tandas;
}
