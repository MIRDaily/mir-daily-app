import 'package:flutter/material.dart';

import '../../../core/models/models.dart';

/// Criterios de orden de la galería de mazos.
///
/// La web ordena arrastrando (guarda `decks.position`); en el móvil, arrastrar
/// dentro de una lista que ya hace scroll es incómodo y frágil, así que aquí
/// se ordena eligiendo. [manual] respeta el orden que venga del servidor, que
/// es justo el que se colocó a mano en la web.
enum DeckSort {
  manual,
  recent,
  oldest,
  mostStudied,
  leastMastered,
  alphabetical,
}

extension DeckSortInfo on DeckSort {
  String get id => name;

  String get label {
    switch (this) {
      case DeckSort.manual:
        return 'Predeterminado';
      case DeckSort.recent:
        return 'Más recientes';
      case DeckSort.oldest:
        return 'Más antiguos';
      case DeckSort.mostStudied:
        return 'Más repasados';
      case DeckSort.leastMastered:
        return 'Menos dominados';
      case DeckSort.alphabetical:
        return 'Alfabético';
    }
  }

  String get hint {
    switch (this) {
      case DeckSort.manual:
        return 'El orden que colocaste en la web.';
      case DeckSort.recent:
        return 'Lo último que creaste, arriba.';
      case DeckSort.oldest:
        return 'Los de siempre, primero.';
      case DeckSort.mostStudied:
        return 'Por número de repasos.';
      case DeckSort.leastMastered:
        return 'Lo que peor llevas, primero.';
      case DeckSort.alphabetical:
        return 'Por nombre, de la A a la Z.';
    }
  }

  IconData get icon {
    switch (this) {
      case DeckSort.manual:
        return Icons.format_list_bulleted_rounded;
      case DeckSort.recent:
        return Icons.schedule_rounded;
      case DeckSort.oldest:
        return Icons.history_rounded;
      case DeckSort.mostStudied:
        return Icons.refresh_rounded;
      case DeckSort.leastMastered:
        return Icons.trending_down_rounded;
      case DeckSort.alphabetical:
        return Icons.sort_by_alpha_rounded;
    }
  }
}

DeckSort deckSortFromId(String? id) => DeckSort.values.firstWhere(
      (s) => s.name == id,
      orElse: () => DeckSort.manual,
    );

/// Ordena la galería sin tocar la lista original.
///
/// Los mazos del sistema (el automático de fallos) van SIEMPRE los primeros,
/// sea cual sea el criterio: no son mazos que el usuario haya hecho, y
/// mezclarlos con los suyos los perdería de vista. Es el mismo criterio con el
/// que ya los ordena el backend.
List<Deck> sortDecks(List<Deck> decks, DeckSort sort) {
  final system = decks.where((d) => d.isSystemDeck).toList();
  final own = decks.where((d) => !d.isSystemDeck).toList();

  int byName(Deck a, Deck b) =>
      a.name.toLowerCase().compareTo(b.name.toLowerCase());

  switch (sort) {
    case DeckSort.manual:
      // Ya viene ordenado del servidor; no se toca.
      return decks;

    case DeckSort.recent:
      own.sort((a, b) => _created(b).compareTo(_created(a)));
    case DeckSort.oldest:
      own.sort((a, b) => _created(a).compareTo(_created(b)));

    case DeckSort.mostStudied:
      own.sort((a, b) {
        final c = b.totalReviews.compareTo(a.totalReviews);
        return c != 0 ? c : byName(a, b);
      });

    case DeckSort.leastMastered:
      // Un mazo sin datos suficientes no es "el que peor llevas": es uno del
      // que no se sabe nada. Va al final en vez de encabezar la lista con un
      // 0 % que no significa nada.
      own.sort((a, b) {
        final am = a.masteryPercent;
        final bm = b.masteryPercent;
        if (am == null && bm == null) return byName(a, b);
        if (am == null) return 1;
        if (bm == null) return -1;
        final c = am.compareTo(bm);
        return c != 0 ? c : byName(a, b);
      });

    case DeckSort.alphabetical:
      own.sort(byName);
  }

  return [...system, ...own];
}

/// Fecha de creación, con un valor de respaldo para los mazos antiguos a los
/// que el backend no devuelva `created_at`: quedan al final de "más recientes"
/// en vez de romper la comparación.
DateTime _created(Deck d) => d.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
