import 'package:flutter_test/flutter_test.dart';

import 'package:mirdaily_app/core/models/resumen.dart';
import 'package:mirdaily_app/features/resumenes/resumenes_filtro.dart';

Parrafo _p(
  int itemId, {
  String? tema,
  String texto = 'La anemia ferropénica es frecuente',
  List<Hueco>? huecos,
  EstadoParrafoSrs? status,
  bool? due,
  String? nextDueAt,
  List<int>? huecosFallados,
  int fallos = 0,
}) =>
    Parrafo(
      itemId: itemId,
      id: 'p$itemId',
      tema: tema,
      modo: ModoResumen.resumen,
      texto: texto,
      huecos: huecos ?? const [],
      aiGenerated: false,
      status: status,
      due: due,
      nextDueAt: nextDueAt,
      huecosFallados: huecosFallados,
      fallos: fallos,
    );

void main() {
  test('normalizarResumen quita tildes y mayúsculas', () {
    expect(normalizarResumen('  La Anemia  Ferropénica  '), 'la anemia ferropenica');
  });

  test('terminosDe separa y quita repetidos', () {
    expect(terminosDe('anemia anemia'), ['anemia']);
  });

  test('coincide busca en texto, tema o solo en los huecos', () {
    final p = _p(1, tema: 'Cardio', texto: 'La anemia ferropénica es frecuente', huecos: const [Hueco(3, 9, 2)]);
    expect(coincide(p, ['anemia']), isTrue);
    expect(coincide(p, ['cardio']), isTrue);
    expect(coincide(p, ['anemia'], soloHuecos: true), isTrue); // «anemia» está en el hueco
    expect(coincide(p, ['ferropenica'], soloHuecos: true), isFalse); // «ferropénica» no es hueco
    expect(coincide(p, ['lupus']), isFalse);
  });

  test('filtrarParrafos filtra por estado, nivel, pendiente y fallados', () {
    final ps = [
      _p(1, huecos: const [Hueco(3, 9, 2)], status: EstadoParrafoSrs.failed),
      _p(2, huecos: const [Hueco(3, 9, 4)], status: EstadoParrafoSrs.new_),
      _p(3, due: true, status: EstadoParrafoSrs.learning),
      _p(4, huecosFallados: [0]),
    ];
    expect(filtrarParrafos(ps, const FiltrosGrupo(estados: [EstadoParrafoSrs.failed])).map((p) => p.itemId), [1]);
    expect(filtrarParrafos(ps, const FiltrosGrupo(niveles: [4])).map((p) => p.itemId), [2]);
    expect(filtrarParrafos(ps, const FiltrosGrupo(tocaRepasar: true)).map((p) => p.itemId), [3]);
    expect(filtrarParrafos(ps, const FiltrosGrupo(conFallados: true)).map((p) => p.itemId), [4]);
  });

  test('agruparPorTema conserva el orden de primera aparición', () {
    final ps = [_p(1, tema: 'A'), _p(2, tema: 'B'), _p(3, tema: 'A')];
    final grupos = agruparPorTema(ps);
    expect(grupos.map((g) => g.$1), ['A', 'B']);
    expect(grupos[0].$2.length, 2);
  });

  test('ordenarParrafos por fallados pone los más fallados primero', () {
    final ps = [_p(1, fallos: 1), _p(2, fallos: 5), _p(3, fallos: 2)];
    final ordenados = ordenarParrafos(ps, OrdenGrupo.fallados);
    expect(ordenados.map((p) => p.itemId), [2, 3, 1]);
  });

  test('cuandoVence distingue hoy, mañana y días', () {
    final ahora = DateTime.utc(2026, 10, 11);
    expect(cuandoVence(_p(1, nextDueAt: '2026-10-11T10:00:00Z'), ahora), 'Vence hoy');
    expect(cuandoVence(_p(2, nextDueAt: '2026-10-12T10:00:00Z'), ahora), 'Vence mañana');
    expect(cuandoVence(_p(3, nextDueAt: '2026-10-16T10:00:00Z'), ahora), 'Vence en 5 días');
    expect(cuandoVence(_p(4, status: EstadoParrafoSrs.new_), ahora), isNull);
  });

  test('cuandoVuelve distingue ya, mañana, días y fecha', () {
    final ahora = DateTime.utc(2026, 10, 11, 12);
    expect(cuandoVuelve('2026-10-11T08:00:00Z', ahora), 'ya');
    expect(cuandoVuelve('2026-10-11T20:00:00Z', ahora), 'hoy');
    expect(cuandoVuelve('2026-10-12T10:00:00Z', ahora), 'mañana');
    expect(cuandoVuelve('2026-10-15T10:00:00Z', ahora), 'en 4 días');
    expect(cuandoVuelve('2026-12-03T10:00:00Z', ahora), 'el 3 dic.');
    expect(cuandoVuelve(null, ahora), 'pendiente');
  });
}
