// Tanda 5: mazos y Panel al día con la web.
//   - Papelera de preguntas del mazo (GET .../items/trash, POST .../items/:id/restore) y quitar con
//     «Deshacer»; acierto por asignatura (GET .../subject-performance); colocar a mano (POST /decks/reorder).
//   - Progreso mensual (GET /analytics/monthly-progress) en Studio y la más fallada de la semana
//     (GET /stats/most-failed-week) en el Panel.
//   - Nombre visible (POST /profile/display-name) en el editor de perfil.
// La lógica copia la de la web: TrashTimer.tsx, buildProgressCard de studio/page.tsx y la tarjeta del
// dashboard; la regla del nombre es DISPLAY_REGEX del backend.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mirdaily_app/core/models/mazos_extra.dart';
import 'package:mirdaily_app/core/models/models.dart';
import 'package:mirdaily_app/core/models/progreso_semana.dart';
import 'package:mirdaily_app/core/services/api_service.dart';
import 'package:mirdaily_app/core/services/auth_service.dart';
import 'package:mirdaily_app/core/theme/app_theme.dart';
import 'package:mirdaily_app/features/biblioteca/widgets/progreso_mensual.dart';
import 'package:mirdaily_app/features/decks/deck_detail_screen.dart';
import 'package:mirdaily_app/features/decks/deck_items_trash_screen.dart';
import 'package:mirdaily_app/features/decks/widgets/deck_reorder_sheet.dart';
import 'package:mirdaily_app/features/premium/widgets/mas_fallada_section.dart';
import 'package:mirdaily_app/features/profile/widgets/profile_editor_sheet.dart';
import 'package:provider/provider.dart';

final _tamanos = [('móvil', const Size(360, 780)), ('tablet', const Size(1024, 768))];

void _tam(WidgetTester tester, Size s) {
  tester.view.physicalSize = s;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

const _mazo = Deck(
  id: 'd1',
  name: 'Reuma',
  systemGenerated: false,
  autoType: 'none',
  accuracy: 0.5,
  totalReviews: 3,
  visualState: 'clean',
  totalItems: 2,
);

DeckCard _carta(String id, String enunciado) => DeckCard(
      itemId: id,
      questionId: '9$id',
      statement: enunciado,
      options: const ['A', 'B', 'C', 'D'],
      correctAnswer: 1,
      subject: 'Reumatología',
    );

/// Un ApiService sin red que apunta lo que se le pide.
class _ApiFalsa extends ApiService {
  _ApiFalsa() : super(AuthService());

  final List<String> llamadas = [];
  List<DeckItemTrashEntry> papelera = [];
  List<DeckCard> cartas = [_carta('1', 'Primera pregunta del mazo'), _carta('2', 'Segunda pregunta del mazo')];
  MasFallada? masFallada;
  ProgresoMensual? progreso;
  Object? fallarNombre;

  @override
  Future<DeckItemsPage> getDeckItems(String deckId, {int page = 1, String query = ''}) async =>
      DeckItemsPage(items: [...cartas], total: cartas.length, page: 1, totalPages: 1);

  @override
  Future<DeckSummary> getDeckSummary(String deckId) async =>
      const DeckSummary(newCount: 1, failed: 1, learning: 0, mastered: 0);

  @override
  Future<List<DeckSubject>> getDeckSubjects(String deckId) async =>
      const [DeckSubject(subjectId: 1, subject: 'Reumatología', count: 2)];

  @override
  Future<List<SubjectPerformance>> getDeckSubjectPerformance(String deckId) async => const [
        SubjectPerformance(subject: 'Reumatología', accuracy: 75, total: 4),
        SubjectPerformance(subject: 'Cardiología y Cirugía Cardiovascular', accuracy: 20, total: 5),
      ];

  @override
  Future<List<DeckItemTrashEntry>> getDeckItemsTrash(String deckId) async {
    llamadas.add('papelera');
    return [...papelera];
  }

  @override
  Future<void> removeDeckItem(String deckId, String itemId) async {
    llamadas.add('quitar $itemId');
    cartas.removeWhere((c) => c.itemId == itemId);
  }

  @override
  Future<void> restoreDeckItem(String deckId, String itemId) async {
    llamadas.add('restaurar $itemId');
    papelera.removeWhere((e) => e.id == itemId);
  }

  @override
  Future<MasFallada?> getMostFailedWeek() async => masFallada;

  @override
  Future<ProgresoMensual> getMonthlyProgress() async => progreso ?? (throw Exception('sin datos'));

  @override
  Future<List<University>> getUniversities() async => [];

  @override
  Future<List<MirSpecialty>> getMirSpecialties() async => [];

  @override
  Future<void> updateDisplayName(String displayName) async {
    llamadas.add('nombre $displayName');
    if (fallarNombre != null) throw fallarNombre!;
  }

  @override
  Future<void> updateAcademicProfile({
    Object? mainGoal = const Object(),
    Object? medicalYear = const Object(),
    Object? mirSpecialtyId = const Object(),
    Object? universityId = const Object(),
    Object? customUniversity = const Object(),
    Object? profilePublic = const Object(),
    Object? bio = const Object(),
    Object? galleryStyle = const Object(),
  }) async {
    llamadas.add('academico');
  }
}

/// Para pantallas con animaciones que no acaban (la portada del mazo): `pumpAndSettle` no volvería nunca.
Future<void> _asentar(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Widget _app(ApiService api, Widget home) => Provider<ApiService>.value(
      value: api,
      child: MaterialApp(theme: AppTheme.lightTheme, home: home),
    );

void main() {
  group('lógica', () {
    final ahora = DateTime(2026, 10, 29, 12);

    test('caducidad de la papelera como el TrashTimer de la web', () {
      expect(textoCaducidad(null), 'Expiración no disponible');
      expect(textoCaducidad(ahora.add(const Duration(hours: 23, minutes: 4, seconds: 10)), ahora: ahora), 'Expira en 23h 5m');
      expect(textoCaducidad(ahora.add(const Duration(seconds: 20)), ahora: ahora), 'Expira en 0h 1m');
      expect(textoCaducidad(ahora.subtract(const Duration(minutes: 1)), ahora: ahora), 'Expirada');
    });

    test('la papelera se lee del servidor y va de la más reciente a la más antigua', () {
      final l = ordenarPapelera([
        DeckItemTrashEntry.fromJson({'id': 1, 'question_id': 40, 'deleted_at': '2026-10-28T10:00:00Z', 'purge_at': '2026-10-29T10:00:00Z', 'questions': {'statement': 'Vieja', 'subject': 'Neurología'}}),
        DeckItemTrashEntry.fromJson({'id': 2, 'deleted_at': null, 'questions': null}),
        DeckItemTrashEntry.fromJson({'id': 3, 'deleted_at': '2026-10-29T09:00:00Z', 'questions': {'statement': 'Nueva', 'subject': ''}}),
      ]);
      expect(l.map((e) => e.id), ['3', '1', '2']);
      expect(l[1].subject, 'Neurología');
      expect(l[0].subject, isNull);
      expect(l[2].statement, 'Pregunta sin enunciado');
    });

    test('acierto por asignatura y mover en la lista', () {
      final p = SubjectPerformance.fromJson({'subject': 'Reuma', 'accuracy': 133, 'total': 4});
      expect(p.accuracy, 100);
      expect(moverEnLista(['a', 'b', 'c', 'd'], 0, 3), ['b', 'c', 'a', 'd']);
      expect(moverEnLista(['a', 'b', 'c', 'd'], 3, 0), ['d', 'a', 'b', 'c']);
      expect(moverEnLista(['a', 'b', 'c'], 1, 3), ['a', 'c', 'b']);
    });

    test('números en español como Intl es-ES', () {
      expect(numeroEs(0), '0');
      expect(numeroEs(1234), '1234');
      expect(numeroEs(12345), '12.345');
      expect(numeroEs(1234567), '1.234.567');
      expect(numeroEs(12.5), '12,5');
      expect(numeroEs(-3.2), '-3,2');
      expect(numeroEs(9.96), '10');
    });

    test('la tarjeta de progreso mensual', () {
      var t = textoProgresoMensual(ProgresoMensual.fromJson({
        'month': {'questions': 120},
        'previousMonth': {'questions': 0},
        'year': {'questions': 1500},
        'trendPct': null,
      }));
      expect(t.valor, '+120');
      expect(t.insignia, isNull);
      expect(t.detalle, '1500 preguntas repasadas en el último año');
      t = textoProgresoMensual(const ProgresoMensual(mes: 60, mesAnterior: 50, anio: 1, tendencia: 20));
      expect(t.insignia, '↑ +20%');
      expect(t.signo, 1);
      expect(t.detalle, '1 pregunta repasada en el último año');
      t = textoProgresoMensual(const ProgresoMensual(mes: 0, mesAnterior: 8, anio: 30, tendencia: -100));
      expect(t.valor, '0');
      expect(t.insignia, '↓ -100%');
      expect(t.signo, -1);
      expect(textoProgresoMensual(const ProgresoMensual(mes: 5, mesAnterior: 5, anio: 5, tendencia: 0)).insignia, '→ 0%');
    });

    test('la más fallada: sin datos, índices 1-based y la frase de cada caso', () {
      expect(MasFallada.fromJson({'message': 'No data available for last completed week'}), isNull);
      final base = {
        'weekStart': '2026-10-19',
        'questionId': 4265,
        'wrongPercentage': 71.43,
        'totalResponses': 14,
        'statement': 'Enunciado',
        'options': ['Uno', 'Dos', 'Tres', 'Cuatro'],
        'correctAnswer': 2,
        'answeredAt': '2026-10-21T09:30:00Z',
      };
      final mal = MasFallada.fromJson({...base, 'yourLastAnswer': 4, 'youWereCorrect': false})!;
      expect(mal.correctIndex, 1);
      expect(mal.tuRespuesta, 3);
      expect(mal.respondidaMal, isTrue);
      expect(textoMasFallada(mal), startsWith('La fallaste cuando la hiciste el 21/10/2026. No fuiste el único: el 71.4%'));
      final bien = MasFallada.fromJson({...base, 'yourLastAnswer': 2, 'youWereCorrect': true})!;
      expect(textoMasFallada(bien), contains('Estás por encima del 71.4% de usuarios.'));
      final nunca = MasFallada.fromJson({...base, 'yourLastAnswer': null})!;
      expect(nunca.nuncaRespondida, isTrue);
      expect(textoMasFallada(nunca), startsWith('Ese día no hiciste el Daily.'));
      expect(fechaCorta('2026-10-19'), '19/10/2026');
      expect(fechaCorta(null), isNull);
    });

    test('nombre visible: la regla del backend', () {
      expect(nombreVisibleValido('Ana'), isTrue);
      expect(nombreVisibleValido('  Ana Pérez  '), isFalse); // sin tildes, como DISPLAY_REGEX
      expect(nombreVisibleValido('Ana Perez 2'), isTrue);
      expect(nombreVisibleValido('A'), isFalse);
      expect(nombreVisibleValido('Diecisiete letras'), isFalse);
      expect(nombreVisibleValido('ana_88'), isFalse);
    });
  });

  test('ApiService: rutas, verbos y cuerpos de la tanda', () async {
    final enviadas = <String>[];
    final api = ApiService(
      AuthService(),
      client: MockClient((req) async {
        enviadas.add('${req.method} ${req.url.path} ${req.body}');
        final p = req.url.path;
        if (p.endsWith('/items/trash')) {
          return http.Response(jsonEncode({'trash': [
            {'id': 7, 'deleted_at': '2026-10-29T10:00:00Z', 'purge_at': '2026-10-30T10:00:00Z', 'questions': {'statement': 'X'}},
          ]}), 200);
        }
        if (p.endsWith('/subject-performance')) {
          return http.Response(jsonEncode({'subjects': [{'subject': 'Reuma', 'accuracy': 50, 'total': 2}]}), 200);
        }
        if (p.endsWith('/monthly-progress')) {
          return http.Response(jsonEncode({'month': {'questions': 3}, 'previousMonth': {'questions': 1}, 'year': {'questions': 9}, 'trendPct': 200}), 200);
        }
        if (p.endsWith('/most-failed-week')) return http.Response(jsonEncode({'message': 'No data available'}), 200);
        if (p.endsWith('/display-name')) {
          return http.Response(jsonEncode({'error': 'El nombre visible debe tener entre 2 y 16 caracteres (letras, números y espacios).'}), 400);
        }
        return http.Response('{"ok":true}', 200);
      }),
    )..session = AuthSession(
        accessToken: 't',
        refreshToken: 'r',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
        userId: 'u1',
      );

    expect((await api.getDeckItemsTrash('d1')).single.id, '7');
    await api.restoreDeckItem('d1', '7');
    await api.reorderDecks(['b', 'a']);
    expect((await api.getDeckSubjectPerformance('d1')).single.accuracy, 50);
    expect((await api.getMonthlyProgress()).tendencia, 200);
    expect(await api.getMostFailedWeek(), isNull);
    await expectLater(api.updateDisplayName(' Ana '),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('entre 2 y 16'))));
    expect(enviadas, [
      'GET /api/studio/decks/d1/items/trash ',
      'POST /api/studio/decks/d1/items/7/restore {}',
      'POST /api/studio/decks/reorder {"orderedDeckIds":["b","a"]}',
      'GET /api/studio/decks/d1/subject-performance ',
      'GET /api/analytics/monthly-progress ',
      'GET /api/stats/most-failed-week ',
      'POST /api/profile/display-name {"displayName":"Ana"}',
    ]);
  });

  for (final (nombre, tam) in _tamanos) {
    group('en $nombre', () {
      testWidgets('papelera del mazo: lista, caducidad y restaurar', (tester) async {
        _tam(tester, tam);
        final api = _ApiFalsa()
          ..papelera = [
            DeckItemTrashEntry(
              id: '5',
              statement: 'Varón de 60 años con dolor torácico opresivo irradiado a la mandíbula de dos horas de evolución',
              subject: 'Cardiología y Cirugía Cardiovascular',
              deletedAt: DateTime.now().subtract(const Duration(hours: 1)),
              purgeAt: DateTime.now().add(const Duration(hours: 23)),
            ),
          ];
        await tester.pumpWidget(_app(api, const DeckItemsTrashScreen(deck: _mazo)));
        await tester.pumpAndSettle();
        expect(find.textContaining('1 pregunta eliminada'), findsOneWidget);
        expect(find.textContaining('Expira en 2'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.tap(find.text('Restaurar'));
        await tester.pumpAndSettle();
        expect(api.llamadas, contains('restaurar 5'));
        expect(find.text('No hay preguntas en la papelera.'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('detalle del mazo: acierto por asignatura, quitar con confirmación y deshacer', (tester) async {
        _tam(tester, tam);
        final api = _ApiFalsa();
        await tester.pumpWidget(_app(api, const DeckDetailScreen(deck: _mazo)));
        await _asentar(tester);
        expect(find.text('ACIERTO POR ASIGNATURA'), findsOneWidget);
        expect(find.text('75%'), findsOneWidget);
        expect(find.text('20%'), findsOneWidget);
        // La lista es perezosa: el botón de la papelera solo existe cuando se acerca a la vista.
        await tester.scrollUntilVisible(find.byKey(const ValueKey('papelera-del-mazo')), 200, scrollable: find.byType(Scrollable).first);
        expect(find.descendant(of: find.byKey(const ValueKey('papelera-del-mazo')), matching: find.text('0')), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.scrollUntilVisible(find.byTooltip('Quitar del mazo').first, 200, scrollable: find.byType(Scrollable).first);
        // Un poco más, para que no quede debajo del botón flotante «Estudiar».
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -160));
        await _asentar(tester);
        await tester.tap(find.byTooltip('Quitar del mazo').first);
        await _asentar(tester);
        expect(find.text('¿Eliminar esta pregunta del mazo?'), findsOneWidget);
        await tester.tap(find.text('Eliminar'));
        await _asentar(tester);
        expect(api.llamadas, contains('quitar 1'));
        expect(find.text('Primera pregunta del mazo'), findsNothing);
        expect(find.descendant(of: find.byKey(const ValueKey('papelera-del-mazo')), matching: find.text('1')), findsOneWidget);

        await tester.tap(find.text('Deshacer'));
        await _asentar(tester);
        expect(api.llamadas, contains('restaurar 1'));
        expect(find.text('Primera pregunta del mazo'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('colocar a mano: arrastrar por el asa y guardar el orden', (tester) async {
        _tam(tester, tam);
        List<String>? resultado;
        final mazos = [
          for (final n in ['Uno', 'Dos', 'Tres'])
            Deck(id: n.toLowerCase(), name: n, systemGenerated: false, autoType: 'none', accuracy: 0, totalReviews: 0, visualState: 'clean', totalItems: 1),
        ];
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () async => resultado = await showDeckReorderSheet(context, mazos),
                  child: const Text('abrir'),
                ),
              ),
            ),
          ),
        ));
        await tester.tap(find.text('abrir'));
        await tester.pumpAndSettle();
        expect(find.text('Colocar a mano'), findsOneWidget);
        expect(tester.takeException(), isNull);

        // Sin cambios, «Guardar orden» no hace nada.
        await tester.tap(find.text('Guardar orden'));
        await tester.pumpAndSettle();
        expect(find.text('Colocar a mano'), findsOneWidget);

        final asa = find.byIcon(Icons.drag_handle_rounded).first;
        final g = await tester.startGesture(tester.getCenter(asa));
        await tester.pump(const Duration(milliseconds: 50)); // el asa arrastra sin pulsación larga
        for (var i = 0; i < 10; i++) {
          await g.moveBy(const Offset(0, 14));
          await tester.pump(const Duration(milliseconds: 16));
        }
        await g.up();
        await tester.pumpAndSettle();

        await tester.tap(find.text('Guardar orden'));
        await tester.pumpAndSettle();
        expect(resultado, isNotNull);
        expect(resultado!.first, 'dos');
        expect(resultado!.toSet(), {'uno', 'dos', 'tres'});
      });

      testWidgets('la más fallada: elegir sin guardar, ver respuesta y la explicación', (tester) async {
        _tam(tester, tam);
        final api = _ApiFalsa()
          ..masFallada = MasFallada.fromJson({
            'weekStart': '2026-10-19',
            'questionId': 1,
            'wrongPercentage': 71.43,
            'totalResponses': 14,
            'statement': 'Mujer de 34 años con artralgias y eritema malar. ¿Qué anticuerpo es más específico?',
            'options': ['Antinucleares', 'Anti-ADN de doble cadena', 'Anti-Ro', 'Factor reumatoide'],
            'correctAnswer': 2,
            'explanation': 'Los anti-ADNdc son los más específicos del lupus.',
            'yourLastAnswer': 1,
            'youWereCorrect': false,
            'answeredAt': '2026-10-21T09:30:00Z',
            'isPlaceholder': true,
          });
        await tester.pumpWidget(_app(api, const Scaffold(body: SingleChildScrollView(padding: EdgeInsets.all(20), child: MasFalladaSubsection()))));
        await tester.pumpAndSettle();
        expect(find.text('Semana\n19/10/2026'), findsOneWidget);
        expect(find.textContaining('Datos de ejemplo'), findsOneWidget);
        expect(find.text('¿La volverías a acertar hoy?'), findsOneWidget);
        expect(find.text('Correcta'), findsNothing);
        expect(tester.takeException(), isNull);

        await tester.tap(find.text('Anti-Ro'));
        await tester.pump();
        await tester.ensureVisible(find.text('Ver respuesta'));
        await tester.tap(find.text('Ver respuesta'));
        await tester.pumpAndSettle();
        expect(find.text('Correcta'), findsOneWidget);
        expect(find.text('Tu respuesta'), findsOneWidget);
        expect(find.textContaining('La fallaste cuando la hiciste el 21/10/2026'), findsOneWidget);
        expect(find.text('Claves para no fallarla'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('progreso mensual en Studio, y nada si no hay datos', (tester) async {
        _tam(tester, tam);
        final api = _ApiFalsa()..progreso = const ProgresoMensual(mes: 1240, mesAnterior: 1000, anio: 15320, tendencia: 24);
        await tester.pumpWidget(_app(api, const Scaffold(body: Padding(padding: EdgeInsets.all(20), child: ProgresoMensualCard()))));
        await tester.pumpAndSettle();
        expect(find.text('+1240'), findsOneWidget);
        expect(find.text('↑ +24%'), findsOneWidget);
        expect(find.text('15.320 preguntas repasadas en el último año'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(_app(_ApiFalsa(), const Scaffold(body: ProgresoMensualCard())));
        await tester.pumpAndSettle();
        expect(find.text('PROGRESO MENSUAL'), findsNothing);
      });

      testWidgets('nombre visible: se valida antes de mandar y se guarda aparte', (tester) async {
        _tam(tester, tam);
        final api = _ApiFalsa();
        await tester.pumpWidget(_app(
          api,
          Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () => showProfileEditor(
                    context,
                    const UserProfile(id: 'u1', displayName: 'Alejandro', username: 'alejandro'),
                  ),
                  child: const Text('editar'),
                ),
              ),
            ),
          ),
        ));
        await tester.tap(find.text('editar'));
        await tester.pumpAndSettle();
        expect(find.text('NOMBRE VISIBLE'), findsOneWidget);
        expect(find.text('Alejandro'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.enterText(find.widgetWithText(TextField, 'Alejandro'), 'Álex');
        await tester.tap(find.text('Guardar cambios'));
        await tester.pumpAndSettle();
        expect(find.text('Entre 2 y 16 caracteres: letras, números y espacios.'), findsOneWidget);
        expect(api.llamadas, isEmpty);

        await tester.enterText(find.widgetWithText(TextField, 'Álex'), 'Alex 2');
        await tester.tap(find.text('Guardar cambios'));
        await tester.pumpAndSettle();
        expect(api.llamadas, ['nombre Alex 2', 'academico']);
        expect(find.text('Tus datos'), findsNothing); // se cierra al guardar
      });
    });
  }
}
