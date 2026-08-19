// Que cada llamada salga con SU verbo y su cuerpo.
//
//   flutter test test/api_verbs_test.dart
//
// Existe por un fallo real: `_request` solo contemplaba POST y DELETE, y todo
// lo demás caía en GET por descarte. Las tres llamadas PATCH —guardar los
// datos del perfil, renombrar un grupo de flashcards y editar una tarjeta— se
// enviaban como GET y sin cuerpo, así que no hacían nada. Y no fallaba de
// forma ruidosa: simplemente no guardaba.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:mirdaily_app/core/services/api_service.dart';
import 'package:mirdaily_app/core/services/auth_service.dart';

/// Apunta lo que se envió y responde siempre que sí.
class _Espia {
  final List<http.Request> enviadas = [];

  late final http.Client client = MockClient((req) async {
    enviadas.add(req);
    return http.Response('{}', 200);
  });
}

ApiService _api(_Espia espia) {
  // La sesión vive en el propio ApiService; sin ella `_validToken` aborta
  // antes de llegar a la red y no se enviaría nada.
  return ApiService(AuthService(), client: espia.client)
    ..session = AuthSession(
      accessToken: 'token-de-prueba',
      refreshToken: 'r',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
      userId: 'u1',
    );
}

void main() {
  test('guardar los datos del perfil sale como PATCH y con cuerpo', () async {
    final espia = _Espia();
    await _api(espia).updateAcademicProfile(bio: 'Hola');

    expect(espia.enviadas, hasLength(1));
    final req = espia.enviadas.single;
    expect(req.method, 'PATCH', reason: 'el verbo no puede degradarse a GET');
    expect(req.url.path, '/api/profile/academic');
    expect(jsonDecode(req.body), {'bio': 'Hola'});
  });

  test('editar una tarjeta sale como PATCH y con cuerpo', () async {
    final espia = _Espia();
    await _api(espia)
        .updateFlashcard(flashcardId: 'f1', front: 'A', back: 'B');

    final req = espia.enviadas.single;
    expect(req.method, 'PATCH');
    expect(jsonDecode(req.body), {'front': 'A', 'back': 'B'});
  });

  test('renombrar un grupo de flashcards sale como PATCH', () async {
    final espia = _Espia();
    await _api(espia).updateFlashDeck('d1', name: 'Cardio');

    expect(espia.enviadas.single.method, 'PATCH');
  });

  test('los otros verbos siguen siendo los suyos', () async {
    final espia = _Espia();
    final api = _api(espia);

    await api.getFlashDecks(); // GET
    await api.createFlashDeck('Nuevo'); // POST
    await api.deleteFlashcard(deckId: 'd1', itemId: 7); // DELETE

    expect(espia.enviadas.map((r) => r.method).toList(),
        ['GET', 'POST', 'DELETE']);
    // El GET no lleva cuerpo.
    expect(espia.enviadas.first.body, isEmpty);
  });
}
