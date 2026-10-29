// Mazos al día con la web (tanda 5): papelera de preguntas de un mazo, acierto por asignatura y
// orden a mano. Puerto de src/lib/studio/trash.ts, components/studio/TrashTimer.tsx y del
// `handleDragEnd` de src/app/decks/page.tsx.

/// Una pregunta quitada de un mazo, recuperable hasta [purgeAt] (24 h). GET .../items/trash.
class DeckItemTrashEntry {
  final String id;
  final String? questionId;
  final String statement;
  final String? subject;
  final DateTime? deletedAt;
  final DateTime? purgeAt;

  const DeckItemTrashEntry({
    required this.id,
    this.questionId,
    required this.statement,
    this.subject,
    this.deletedAt,
    this.purgeAt,
  });

  factory DeckItemTrashEntry.fromJson(Map<String, dynamic> j) {
    final q = j['questions'] is Map ? Map<String, dynamic>.from(j['questions'] as Map) : const <String, dynamic>{};
    final subject = q['subject'];
    return DeckItemTrashEntry(
      id: '${j['id'] ?? ''}',
      questionId: j['question_id']?.toString(),
      statement: '${q['statement'] ?? 'Pregunta sin enunciado'}',
      subject: subject is String && subject.trim().isNotEmpty ? subject : null,
      deletedAt: DateTime.tryParse('${j['deleted_at'] ?? ''}'),
      purgeAt: DateTime.tryParse('${j['purge_at'] ?? ''}'),
    );
  }
}

/// La más reciente arriba, y las que no traen fecha al final (como `sortByDeletedAtDesc`).
List<DeckItemTrashEntry> ordenarPapelera(List<DeckItemTrashEntry> l) {
  final r = [...l];
  r.sort((a, b) {
    final x = a.deletedAt, y = b.deletedAt;
    if (x == null && y == null) return 0;
    if (x == null) return 1;
    if (y == null) return -1;
    return y.compareTo(x);
  });
  return r;
}

/// «Expira en 23h 5m», «Expira en <1m» o «Expirada», como el TrashTimer de la web.
String textoCaducidad(DateTime? purgeAt, {DateTime? ahora}) {
  if (purgeAt == null) return 'Expiración no disponible';
  final queda = purgeAt.difference(ahora ?? DateTime.now());
  if (queda.inMilliseconds <= 0) return 'Expirada';
  final minutos = (queda.inMilliseconds / 60000).ceil();
  if (minutos <= 0) return 'Expira en <1m';
  return 'Expira en ${minutos ~/ 60}h ${minutos % 60}m';
}

/// Acierto (último intento de cada pregunta) por asignatura. GET .../subject-performance.
class SubjectPerformance {
  final String subject;

  /// 0-100, ya redondeado por el servidor.
  final int accuracy;
  final int total;

  const SubjectPerformance({required this.subject, required this.accuracy, required this.total});

  factory SubjectPerformance.fromJson(Map<String, dynamic> j) => SubjectPerformance(
        subject: '${j['subject'] ?? ''}',
        accuracy: j['accuracy'] is num ? (j['accuracy'] as num).round().clamp(0, 100) : 0,
        total: j['total'] is num ? (j['total'] as num).round() : 0,
      );
}

/// Mueve un elemento como `ReorderableListView` (el índice nuevo cuenta con el hueco del que sale).
List<T> moverEnLista<T>(List<T> lista, int desde, int hasta) {
  final r = [...lista];
  if (desde < 0 || desde >= r.length) return r;
  var destino = hasta > desde ? hasta - 1 : hasta;
  destino = destino.clamp(0, r.length - 1);
  final x = r.removeAt(desde);
  r.insert(destino, x);
  return r;
}
