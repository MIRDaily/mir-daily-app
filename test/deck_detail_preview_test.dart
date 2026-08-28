// Muestrario de la pantalla de un mazo, con un ApiService de mentira: portada,
// los cuatro contadores, el desglose por asignaturas, el buscador, los tres
// interruptores de vista y la lista de preguntas.
//
//   flutter test test/deck_detail_preview_test.dart --update-goldens
//
// Deja las imágenes en test/goldens/deck_detail*.png.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:mirdaily_app/core/models/models.dart';
import 'package:mirdaily_app/core/services/api_service.dart';
import 'package:mirdaily_app/core/services/auth_service.dart';
import 'package:mirdaily_app/core/theme/app_theme.dart';
import 'package:mirdaily_app/features/decks/deck_detail_screen.dart';

/// Devuelve datos fijos en vez de salir a la red. Los mismos que tiene el mazo
/// de prueba en producción, para que la hoja de contactos se parezca a lo que
/// se ve en el móvil.
class _FakeApi extends ApiService {
  _FakeApi() : super(AuthService());

  static DeckCard _card(int i, String subject, int year) => DeckCard(
        itemId: 'item-$i',
        questionId: 'q-$i',
        statement:
            'Pregunta $i vinculada a la imagen n.º 3. En este contexto clínico, '
            '¿cuál de las siguientes actitudes le parece más adecuada?',
        options: const [
          'Solicitar una TC abdominal urgente.',
          'Iniciar antibioterapia empírica y reevaluar.',
          'Derivar a consulta externa en un mes.',
          'Alta con analgesia y control por su médico.',
        ],
        correctAnswer: 2,
        explanation:
            'La actitud correcta es la 2: el cuadro sugiere una infección con '
            'criterios de gravedad, de modo que la antibioterapia empírica no '
            'debe demorarse a la espera de pruebas de imagen.',
        subject: subject,
        year: year,
      );

  @override
  Future<DeckItemsPage> getDeckItems(
    String deckId, {
    int page = 1,
    String query = '',
  }) async =>
      DeckItemsPage(
        items: [
          _card(1, 'Digestivo y Cirugía General', 2024),
          _card(2, 'Hematología', 2025),
          _card(3, 'Traumatología', 2021),
        ],
        total: 50,
        page: 1,
        totalPages: 2,
      );

  @override
  Future<DeckSummary> getDeckSummary(String deckId) async =>
      const DeckSummary(newCount: 31, failed: 12, learning: 5, mastered: 2);

  @override
  Future<List<DeckSubject>> getDeckSubjects(String deckId) async => const [
        DeckSubject(subjectId: 4, subject: 'Traumatología', count: 22),
        DeckSubject(
            subjectId: 3, subject: 'Digestivo y Cirugía General', count: 16),
        DeckSubject(subjectId: 9, subject: 'Hematología', count: 12),
      ];
}

const _deck = Deck(
  id: 'demo',
  name: 'madre mia',
  systemGenerated: false,
  autoType: 'none',
  accuracy: 0.72,
  totalReviews: 40,
  visualState: 'clean',
  description: 'Lo que voy fallando en las simulaciones largas.',
  bannerGradient: 'blueMist',
  totalItems: 50,
);

Future<void> _pumpScreen(WidgetTester tester) async {
  await tester.pumpWidget(
    Provider<ApiService>.value(
      value: _FakeApi(),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: const DeckDetailScreen(deck: _deck),
      ),
    ),
  );
  // La portada va a la deriva en bucle: `pumpAndSettle` no terminaría.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1200));
}

void main() {
  testWidgets('pantalla de un mazo', (tester) async {
    tester.view.physicalSize = const Size(420, 1500);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await _pumpScreen(tester);

    // Los cuatro contadores tienen que caber sin desbordarse: eso lo vigila el
    // propio framework, que lanza una excepción de layout si no caben.
    expect(tester.takeException(), isNull);
    expect(find.text('PREGUNTAS (50)'), findsOneWidget);
    expect(find.text('Traumatología'), findsWidgets);

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/deck_detail.png'),
    );
  });

  testWidgets('hoja de estudiar', (tester) async {
    tester.view.physicalSize = const Size(420, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await _pumpScreen(tester);
    await tester.tap(find.text('Estudiar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Empezar a estudiar'), findsOneWidget);
    // El desplegable viejo repetía "Todas (2)" tres veces en un mazo de 2
    // cartas. Ahora hay un contador de 1 al máximo, con atajos distintos.
    expect(find.text('Todas (50)'), findsOneWidget);
    expect(find.text('de 50'), findsNothing); // arranca en el máximo
    expect(find.text('todas las del mazo'), findsOneWidget);

    // Los cuatro estados se pueden elegir en modo Normal.
    expect(tester.widget<Opacity>(find.ancestor(
      of: find.text('Falladas (12)'),
      matching: find.byType(Opacity),
    ).last).opacity, 1.0);

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/deck_detail_study.png'),
    );
  });

  testWidgets('buscador con coincidencias resaltadas', (tester) async {
    tester.view.physicalSize = const Size(420, 1100);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await _pumpScreen(tester);
    await tester.enterText(find.byType(TextField), 'clínico');
    // El buscador espera 350 ms antes de disparar la peticion.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();

    // Despliega las preguntas. Se busca por icono: la etiqueta aparece dos
    // veces (una copia invisible reserva el ancho de la palabra mas larga).
    await tester.tap(find.byIcon(Icons.unfold_more_rounded));
    await tester.pump(const Duration(milliseconds: 300));

    // El interruptor cambia de estado de verdad: pasa a ofrecer "contraer"
    // Y su pastilla se pinta activa (fondo de tinta), no solo el icono.
    expect(find.byIcon(Icons.unfold_less_rounded), findsOneWidget);
    expect(find.byIcon(Icons.unfold_more_rounded), findsNothing);
    final pastilla = tester.widget<AnimatedContainer>(
      find.ancestor(
        of: find.byIcon(Icons.unfold_less_rounded),
        matching: find.byType(AnimatedContainer),
      ).first,
    );
    expect(
      (pastilla.decoration! as BoxDecoration).color,
      const Color(0xFF2C3E50),
    );

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/deck_detail_search.png'),
    );
  });

  testWidgets('en Smart no se puede elegir estado', (tester) async {
    tester.view.physicalSize = const Size(420, 1300);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await _pumpScreen(tester);
    await tester.tap(find.text('Estudiar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Se elige un estado en modo Normal y luego se pasa a Smart.
    await tester.tap(find.text('Falladas (12)'));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.text('Smart Review'));
    await tester.pump(const Duration(milliseconds: 250));

    // El bloque entero queda apagado...
    final apagado = tester.widget<Opacity>(find.ancestor(
      of: find.text('Falladas (12)'),
      matching: find.byType(Opacity),
    ).last);
    expect(apagado.opacity, lessThan(1.0));

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/deck_detail_study_smart.png'),
    );

    // ...y el estado que estaba elegido se descarta, porque el servidor
    // ignora p_status cuando p_mode = 'smart'.
    await tester.tap(find.text('Empezar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  });
}
