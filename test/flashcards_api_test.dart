// Cliente de flashcards (ApiService): que cada llamada vaya a la ruta de la web con su cuerpo.
//
// El fallo que corrige la tanda 2: la app registraba el repaso en la ruta de los mazos
// (`/decks/:id/log`, sí/no), que planifica con la escalera de tres intervalos fijos, mientras la web
// usa `/flashcard-decks/:id/log` con el grado de FSRS. Repasar la misma tarjeta en cada sitio la
// dejaba con fechas distintas.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mirdaily_app/core/models/models.dart';
import 'package:mirdaily_app/core/services/api_service.dart';
import 'package:mirdaily_app/core/services/auth_service.dart';

class _Espia {
  final List<http.Request> enviadas = [];
  final http.Response Function(http.Request req) responder;

  _Espia([http.Response Function(http.Request req)? r]) : responder = r ?? ((_) => http.Response('{}', 200));

  late final http.Client client = MockClient((req) async {
    enviadas.add(req);
    return responder(req);
  });

  Map<String, dynamic> get cuerpo => jsonDecode(enviadas.last.body) as Map<String, dynamic>;
}

ApiService _api(_Espia espia) => ApiService(AuthService(), client: espia.client)
  ..session = AuthSession(
    accessToken: 'token-de-prueba',
    refreshToken: 'r',
    expiresAt: DateTime.now().add(const Duration(hours: 1)),
    userId: 'u1',
  );

http.Response _json(Object o, [int status = 200]) =>
    http.Response(jsonEncode(o), status, headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  test('el repaso va a la ruta de flashcards con el grado y el tiempo, no a la de mazos', () async {
    final espia = _Espia();
    await _api(espia).logFlashcard(deckId: 'd1', deckItemId: 7, grade: 3, sessionId: 's1', timeSpent: 12);
    final req = espia.enviadas.single;
    expect((req.method, req.url.path), ('POST', '/api/studio/flashcard-decks/d1/log'));
    expect(espia.cuerpo, {'deckItemId': 7, 'grade': 3, 'sessionId': 's1', 'timeSpent': 12});
  });

  test('la sesión se abre con sus ajustes (escalera por defecto)', () async {
    final espia = _Espia((_) => _json({'sessionId': 'abc'}));
    final id = await _api(espia).startFlashcardSession('d1', 40, opciones: {'ladder': false, 'onlyStatus': 'failed', 'cardLimit': 20});
    expect(id, 'abc');
    expect(espia.enviadas.single.url.path, '/api/studio/decks/d1/start-session');
    expect(espia.cuerpo, {'limit': 40, 'ladder': false, 'onlyStatus': 'failed', 'cardLimit': 20});
    await _api(espia).startFlashcardSession('d1', 20);
    expect(espia.cuerpo, {'limit': 20, 'ladder': true});
  });

  test('la siguiente tarjeta trae nivel, tema, origen y los cuatro intervalos', () async {
    final espia = _Espia((_) => _json({
          'item': {
            'id': 55,
            'flashcard': {
              'id': 'f9',
              'front': 'Gota: cristales',
              'back': 'Urato monosódico, birrefringencia negativa',
              'topic': 'Gota',
              'level': 2,
              'source': {'name': 'Tema 05.pdf', 'page': 12, 'unit': 'pagina', 'snippet': 'Los cristales…'},
            },
            'preview': {
              '1': {'scheduledDays': 0, 'due': '2026-10-29T10:01:00.000Z'},
              '2': {'scheduledDays': 0, 'due': '2026-10-29T10:06:00.000Z'},
              '3': {'scheduledDays': 0, 'due': '2026-10-29T10:10:00.000Z'},
              '4': {'scheduledDays': 8, 'due': '2026-11-06T10:00:00.000Z'},
            },
          },
        }));
    final r = await _api(espia).getNextFlashcard('d1', 's 1');
    expect(espia.enviadas.single.url.query, 'sessionId=s+1');
    expect(r.kind, FlashNextKind.card);
    expect((r.card!.itemId, r.card!.level, r.card!.tema), (55, 2, 'Gota'));
    expect(r.card!.source!.lugar, 'Tema 05.pdf · pág. 12');
    expect(r.preview.keys.toList(), [1, 2, 3, 4]);
    expect(r.preview[4]!.scheduledDays, 8);
  });

  test('deshacer: el estado restaurado, o null si no hay nada (409)', () async {
    var conflicto = false;
    final espia = _Espia((_) => conflicto
        ? _json({'error': 'No hay ningún repaso que deshacer en esta sesión', 'reason': 'nada-que-deshacer'}, 409)
        : _json({
            'ok': true,
            'deckItemId': 55,
            'preview': {
              '3': {'scheduledDays': 2, 'due': '2026-10-31T10:00:00.000Z'},
            },
          }));
    final api = _api(espia);
    final r = await api.undoFlashcardReview('d1', 's1');
    expect(espia.enviadas.single.url.path, '/api/studio/flashcard-decks/d1/undo');
    expect(espia.cuerpo, {'sessionId': 's1'});
    expect((r!.deckItemId, r.preview[3]!.scheduledDays), (55, 2));
    conflicto = true;
    expect(await api.undoFlashcardReview('d1', 's1'), isNull);
  });

  test('editar solo manda el nivel si cambia (y null lo quita)', () async {
    final espia = _Espia();
    final api = _api(espia);
    await api.updateFlashcard(flashcardId: 'f1', front: 'A', back: 'B');
    expect(espia.cuerpo, {'front': 'A', 'back': 'B'});
    await api.updateFlashcard(flashcardId: 'f1', front: 'A', back: 'B', setLevel: true, level: null);
    expect(espia.cuerpo, {'front': 'A', 'back': 'B', 'level': null});
    await api.createFlashcard(deckId: 'd1', front: 'A', back: 'B', topic: ' Gota ', level: 3);
    expect(espia.cuerpo, {'front': 'A', 'back': 'B', 'topic': 'Gota', 'level': 3});
  });

  test('mover, copiar y borrar en bloque', () async {
    final espia = _Espia((req) => _json(switch (req.url.path) {
          '/api/studio/flashcard-cards/move' => {'moved': 2, 'alreadyThere': 1},
          '/api/studio/flashcard-cards/copy' => {'copied': 3, 'alreadyThere': 0},
          _ => {'deleted': 4},
        }));
    final api = _api(espia);
    final m = await api.moveFlashcards([1, 2, 3], 'd2');
    expect(espia.cuerpo, {'itemIds': [1, 2, 3], 'targetDeckId': 'd2'});
    expect((m.done, m.alreadyThere), (2, 1));
    final c = await api.copyFlashcards([1, 2, 3], 'd2');
    expect(c.done, 3);
    expect(await api.bulkDeleteFlashcards([1, 2, 3, 4]), 4);
    expect(espia.enviadas.last.url.path, '/api/studio/flashcard-cards/bulk-delete');
  });

  test('grupos con sus cubos; previsión, estado y escalera', () async {
    final espia = _Espia((req) => _json(switch (req.url.path) {
          '/api/studio/flashcard-decks' => {
              'decks': [
                {
                  'id': 'd1',
                  'name': 'Reumatología',
                  'totalCards': 10,
                  'dueCards': 6,
                  'dueReviewCards': 4,
                  'summary': {'new': 2, 'failed': 1, 'learning': 4, 'mastered': 3},
                  'folder_subject_id': 3080,
                },
              ],
            },
          '/api/studio/flashcards/forecast' => {
              'overdue': 3,
              'days': [
                {'date': '2026-10-29', 'count': 5},
                {'date': '2026-10-30', 'count': 0},
              ],
            },
          '/api/studio/flashcards/stats' => {
              'maturity': {'new': 2, 'learning': 4, 'young': 3, 'mature': 1},
              'retention': {'reviews': 10, 'passed': 8, 'rate': 0.8, 'matureReviews': 0, 'matureRate': null},
            },
          _ => {
              'topics': [
                {
                  'topic': 'Gota',
                  'levels': [
                    {'level': 1, 'total': 4, 'mastered': 1, 'unlocked': true},
                    {'level': 2, 'total': 3, 'lowerTotal': 4, 'lowerMastered': 1, 'needed': 4, 'unlocked': false},
                  ],
                },
              ],
            },
        }));
    final api = _api(espia);
    final d = (await api.getFlashDecks()).single;
    expect((d.summary.nuevas, d.summary.failed, d.repasos, d.dominio, d.folderSubjectId), (2, 1, 3, 30, 3080));
    final f = await api.getFlashcardForecast();
    expect(espia.enviadas.last.url.query, 'days=30');
    expect((f.overdue, f.total, f.days.length), (3, 5, 2));
    final s = await api.getFlashcardStats();
    expect((s.total, s.rate, s.matureRate), (10, 0.8, null));
    final e = await api.getFlashcardLadder('d1');
    expect(espia.enviadas.last.url.path, '/api/studio/flashcard-decks/d1/ladder');
    expect(e.topics.single.levels.last.unlocked, isFalse);
  });
}
