import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mirdaily_app/core/models/resumen.dart';
import 'package:mirdaily_app/features/resumenes/resumenes_grupo.dart';

void main() {
  test('resolveColorResumen: coral por defecto y el color pedido', () {
    expect(resolveColorResumen(null).key, 'coral');
    expect(resolveColorResumen('sage').key, 'sage');
    expect(resolveColorResumen('inexistente').key, 'coral');
  });

  test('iconoGrupoResumen: por defecto para claves desconocidas', () {
    expect(iconoGrupoResumen(null), Icons.menu_book_rounded);
    expect(iconoGrupoResumen('menu_book'), Icons.menu_book_rounded);
    expect(iconoGrupoResumen('inventado'), Icons.menu_book_rounded);
    expect(iconoGrupoResumen('bloodtype'), Icons.bloodtype_rounded);
  });

  test('cuentaEstadoResumen lee cada cuenta', () {
    const r = ResumenEstados(nuevo: 1, failed: 2, learning: 3, mastered: 4);
    expect(cuentaEstadoResumen(r, EstadoParrafoSrs.new_), 1);
    expect(cuentaEstadoResumen(r, EstadoParrafoSrs.failed), 2);
    expect(cuentaEstadoResumen(r, EstadoParrafoSrs.learning), 3);
    expect(cuentaEstadoResumen(r, EstadoParrafoSrs.mastered), 4);
  });
}
