// El orden de la galería. Es lógica pura, así que se comprueba sin pintar
// nada: qué acaba primero con cada criterio, y las dos reglas que no son
// obvias (el mazo de fallos siempre arriba, y "sin datos" no es "lo peor").
import 'package:flutter_test/flutter_test.dart';

import 'package:mirdaily_app/core/models/models.dart';
import 'package:mirdaily_app/features/decks/widgets/deck_sort.dart';

Deck _deck(
  String name, {
  bool auto = false,
  double accuracy = 0,
  int reviews = 0,
  String created = '2026-01-01',
}) =>
    Deck(
      id: name,
      name: name,
      systemGenerated: auto,
      autoType: auto ? 'failed_global' : 'none',
      accuracy: accuracy,
      totalReviews: reviews,
      visualState: 'clean',
      createdAt: DateTime.parse(created),
    );

List<String> _nombres(List<Deck> d) => d.map((x) => x.name).toList();

void main() {
  final fallos = _deck('Fallos', auto: true, reviews: 999);
  // 30 repasos: por encima del umbral de 25, así que su dominio SÍ cuenta.
  final viejo = _deck('Viejo', created: '2025-01-01', reviews: 30,
      accuracy: 0.9);
  final medio = _deck('Medio', created: '2026-03-01', reviews: 80,
      accuracy: 0.3);
  final nuevo = _deck('Nuevo', created: '2026-08-01', reviews: 40,
      accuracy: 0.6);
  // Menos de 25 repasos: su dominio es desconocido, no un 0 %.
  final sinDatos = _deck('Sin datos', created: '2026-05-01', reviews: 3);

  final todos = [fallos, viejo, medio, nuevo, sinDatos];

  test('manual respeta el orden que llega del servidor', () {
    expect(_nombres(sortDecks(todos, DeckSort.manual)), _nombres(todos));
  });

  test('el mazo automático de fallos va primero en todos los criterios', () {
    for (final sort in DeckSort.values) {
      expect(sortDecks(todos, sort).first.name, 'Fallos',
          reason: 'con ${sort.label}');
    }
  });

  test('más recientes y más antiguos son opuestos', () {
    expect(_nombres(sortDecks(todos, DeckSort.recent)),
        ['Fallos', 'Nuevo', 'Sin datos', 'Medio', 'Viejo']);
    expect(_nombres(sortDecks(todos, DeckSort.oldest)),
        ['Fallos', 'Viejo', 'Medio', 'Sin datos', 'Nuevo']);
  });

  test('más repasados ordena por número de repasos', () {
    expect(_nombres(sortDecks(todos, DeckSort.mostStudied)),
        ['Fallos', 'Medio', 'Nuevo', 'Viejo', 'Sin datos']);
  });

  test('menos dominados manda los que no tienen dato al final', () {
    // Medio (30 %) antes que Nuevo (60 %) antes que Viejo (90 %), y el que no
    // tiene suficientes repasos NO encabeza la lista con un 0 % inventado.
    expect(_nombres(sortDecks(todos, DeckSort.leastMastered)),
        ['Fallos', 'Medio', 'Nuevo', 'Viejo', 'Sin datos']);
  });

  test('alfabético ignora mayúsculas', () {
    final decks = [_deck('zeta'), _deck('Alfa'), _deck('beta')];
    expect(_nombres(sortDecks(decks, DeckSort.alphabetical)),
        ['Alfa', 'beta', 'zeta']);
  });

  test('ordenar no modifica la lista original', () {
    final original = _nombres(todos);
    sortDecks(todos, DeckSort.alphabetical);
    expect(_nombres(todos), original);
  });

  test('un id desconocido cae en el orden por defecto', () {
    expect(deckSortFromId('lo-que-sea'), DeckSort.manual);
    expect(deckSortFromId(null), DeckSort.manual);
    expect(deckSortFromId('recent'), DeckSort.recent);
  });
}
