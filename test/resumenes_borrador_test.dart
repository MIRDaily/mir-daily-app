import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:mirdaily_app/core/models/resumen.dart';
import 'package:mirdaily_app/core/models/resumen_ia.dart';
import 'package:mirdaily_app/features/resumenes/resumenes_borrador.dart';

ParrafoBorrador _parrafo() => const ParrafoBorrador(
      key: 'k',
      tema: 'General',
      texto: 'La anemia ferropénica es frecuente',
      huecos: [Hueco(3, 9, 2)],
      incluir: true,
    );

void main() {
  test('sha256Hex devuelve 64 hex y es determinista', () {
    final h = sha256Hex([1, 2, 3]);
    expect(h.length, 64);
    expect(h, sha256Hex([1, 2, 3]));
  });

  test('claveBorradorResumen junta usuario y documento', () {
    expect(claveBorradorResumen('u', 'd'), 'u:d');
    expect(claveBorradorResumen('u'), 'u:documento');
  });

  test('caducadoBorrador', () {
    const b = BorradorResumen(
      clave: 'u:d', usuario: 'u', documento: 'd', titulo: 't', nombreGrupo: 'g',
      modo: ModoResumen.resumen, fuentes: const [], lista: const [], fallidos: const [],
      creado: 0, actualizado: 0, caduca: 1000,
    );
    expect(caducadoBorrador(b, DateTime.fromMillisecondsSinceEpoch(999)), isFalse);
    expect(caducadoBorrador(b, DateTime.fromMillisecondsSinceEpoch(1000)), isTrue);
  });

  test('borradorToJson y sanearBorradorResumen van y vuelven', () {
    final b = BorradorResumen(
      clave: 'u:${'a' * 64}',
      usuario: 'u',
      documento: 'a' * 64,
      titulo: 'Título',
      nombreGrupo: 'Grupo',
      modo: ModoResumen.literal,
      fuentes: [FuenteFirmada(hash: 'a' * 64, caracteres: 100, firma: 'b' * 64)],
      lista: [_parrafo()],
      fallidos: const [],
      creado: 1, actualizado: 2, caduca: 3,
    );
    final back = sanearBorradorResumen(jsonDecode(jsonEncode(borradorToJson(b))));
    expect(back, isNotNull);
    expect(back!.titulo, 'Título');
    expect(back.modo, ModoResumen.literal);
    expect(back.lista.single.texto, 'La anemia ferropénica es frecuente');
    expect(back.fuentes.single.caracteres, 100);
  });

  test('ordenarBorradoresResumen descarta caducados y ordena por actualizado', () {
    final d1 = 'a' * 64;
    final d2 = 'b' * 64;
    final d3 = 'c' * 64;
    BorradorResumen b(String documento, int actualizado, int caduca) => BorradorResumen(
          clave: 'u:$documento', usuario: 'u', documento: documento, titulo: 't', nombreGrupo: 'g',
          modo: ModoResumen.resumen, fuentes: const [], lista: [_parrafo()], fallidos: const [],
          creado: 0, actualizado: actualizado, caduca: caduca,
        );
    final ahora = DateTime.fromMillisecondsSinceEpoch(5000);
    final r = ordenarBorradoresResumen([
      borradorToJson(b(d1, 100, 10000)),
      borradorToJson(b(d2, 200, 1000)), // caducado
      borradorToJson(b(d3, 300, 10000)),
    ], 'u', ahora);
    expect(r.sobran, ['u:$d2']);
    expect(r.vivos.map((b) => b.documento), [d3, d1]);
  });
}
