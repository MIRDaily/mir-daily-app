// Tanda 6: «Simulacro a tu medida» (POST /api/simulacro/smart), con el lanzador de la web: la tarjeta
// destacada de Studio → hoja con «Qué entra» y el modo → el «Antes de empezar» de siempre → el runner
// con EXACTAMENTE las preguntas que se enseñaron. Casos de SmartSimulacroModal.tsx y de la ruta /smart.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mirdaily_app/core/models/models.dart';
import 'package:mirdaily_app/core/models/progress.dart';
import 'package:mirdaily_app/core/models/simulacro_a_medida.dart';
import 'package:mirdaily_app/core/providers/progress_provider.dart';
import 'package:mirdaily_app/core/providers/saved_questions_provider.dart';
import 'package:mirdaily_app/core/services/api_service.dart';
import 'package:mirdaily_app/core/services/auth_service.dart';
import 'package:mirdaily_app/core/theme/app_theme.dart';
import 'package:mirdaily_app/features/biblioteca/widgets/a_medida_card.dart';
import 'package:mirdaily_app/features/simulacro/simulacro_a_medida_sheet.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _tamanos = [('móvil', const Size(360, 780)), ('tablet', const Size(1024, 768))];

Future<void> _asentar(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void _tam(WidgetTester tester, Size s) {
  tester.view.physicalSize = s;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Map<String, dynamic> _pregunta(int id) => {
      'id': id,
      'statement': 'Enunciado de la pregunta $id del simulacro a medida',
      'subject': 'Reumatología',
      'topic': 'Lupus',
      'has_image': false,
      'image_url': null,
      'options': ['Opción A', 'Opción B', 'Opción C', 'Opción D'],
    };

Map<String, dynamic> _planJson({String coverage = 'mixed', int n = 30}) => {
      'questions': [for (var i = 1; i <= n; i++) _pregunta(1000 + i)],
      'composition': [
        {'subjectName': 'Reumatología', 'count': 18},
        {'subjectName': 'Cardiología y Cirugía Cardiovascular', 'count': 12},
      ],
      'coverage': coverage,
    };

/// Un ApiService sin red: la tanda que se le diga, o un fallo.
class _ApiFalsa extends ApiService {
  _ApiFalsa(this.respuesta) : super(AuthService());
  Object respuesta; // PlanAMedida o una excepción
  int pedidas = 0;

  @override
  Future<PlanAMedida> getSimulacroAMedida({int count = 30}) async {
    pedidas++;
    final r = respuesta;
    if (r is PlanAMedida) return r;
    throw r;
  }
}

Widget _lanzador(ApiService api) => MultiProvider(
      providers: [
        Provider<ApiService>.value(value: api),
        ChangeNotifierProvider(create: (_) => SavedQuestionsProvider()),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(onPressed: () => abrirSimulacroAMedida(context), child: const Text('abrir')),
            ),
          ),
        ),
      ),
    );

Challenge _desafio(Map<String, dynamic>? meta, {String metric = 'weak_topic_questions'}) => Challenge.fromJson({
      'code': 'weak_topic',
      'scope': 'daily',
      'metric': metric,
      'title': 'Tu punto débil',
      'description': '',
      'progress': 0,
      'target': 5,
      'xpReward': 20,
      'completed': false,
      'sortOrder': 3,
      'meta': meta,
    });

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('lógica', () {
    test('el plan: cobertura, desglose y cuándo no hay datos', () {
      final p = PlanAMedida.fromJson(_planJson());
      expect(p.questions.length, 30);
      expect(p.questions.first.id, 1001);
      expect(p.coverage, CoberturaAMedida.mixed);
      expect(p.composition.first, (subjectName: 'Reumatología', count: 18));
      expect(p.insuficiente, isFalse);
      expect(PlanAMedida.fromJson(_planJson(coverage: 'topics')).coverage, CoberturaAMedida.topics);
      expect(PlanAMedida.fromJson({'questions': [], 'composition': [], 'coverage': 'insufficient'}).insuficiente, isTrue);
      // Sin preguntas tampoco se ofrece empezar, aunque diga otra cosa.
      expect(PlanAMedida.fromJson({'questions': [], 'coverage': 'topics'}).insuficiente, isTrue);
    });

    test('el punto débil sale del desafío personalizado del día', () {
      expect(puntoDebilDe(const []), isNull);
      expect(puntoDebilDe([_desafio({'topic_name': 'Lupus'}, metric: 'daily_done')]), isNull);
      expect(puntoDebilDe([_desafio({'subject_name': 'Reumatología'})]), isNull);
      final p = puntoDebilDe([_desafio({'topic_name': 'Lupus', 'subject_name': 'Reumatología', 'accuracy': 0.31})])!;
      expect(p.tema, 'Lupus');
      expect(p.precision, 0.31);
      expect(descripcionAMedida(p),
          'Una sesión de 30 preguntas centrada en Lupus, de Reumatología, que es donde peor vas ahora mismo.');
      expect(descripcionAMedida(null),
          'Cuando tengamos datos de tus fallos, te propondremos aquí una sesión centrada en ellos.');
    });
  });

  test('ApiService: POST /api/simulacro/smart con count 30', () async {
    late http.Request enviada;
    final api = ApiService(
      AuthService(),
      client: MockClient((req) async {
        enviada = req;
        return http.Response(jsonEncode(_planJson(coverage: 'topics', n: 2)), 200);
      }),
    )..session = AuthSession(
        accessToken: 't',
        refreshToken: 'r',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
        userId: 'u1',
      );
    final plan = await api.getSimulacroAMedida();
    expect(enviada.method, 'POST');
    expect(enviada.url.path, '/api/simulacro/smart');
    expect(jsonDecode(enviada.body), {'count': 30});
    expect(plan.questions.length, 2);
  });

  for (final (nombre, tam) in _tamanos) {
    group('en $nombre', () {
      testWidgets('qué entra, modo y empezar: el runner juega la misma tanda', (tester) async {
        _tam(tester, tam);
        final api = _ApiFalsa(PlanAMedida.fromJson(_planJson()));
        await tester.pumpWidget(_lanzador(api));
        await tester.tap(find.text('abrir'));
        await tester.pumpAndSettle();

        expect(find.text('30 preguntas centradas en donde peor vas ahora mismo.'), findsOneWidget);
        expect(find.text('Completado con asignaturas flojas'), findsOneWidget);
        expect(find.text('Cardiología y Cirugía Cardiovascular'), findsOneWidget);
        expect(find.text('18'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.tap(find.text('Corrección inmediata'));
        await tester.pump();
        await tester.tap(find.text('Empezar'));
        // El «Antes de empezar» y el runner animan sin parar: pumpAndSettle no volvería.
        await _asentar(tester);

        // El mismo «Antes de empezar» que el creador normal.
        expect(find.text('Antes de empezar'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Clásico'));
        await _asentar(tester);

        expect(find.text('Simulacro a tu medida'), findsOneWidget); // título de la pantalla
        expect(find.text('Inmediata'), findsOneWidget); // el modo elegido
        expect(find.text('1 de 30'), findsOneWidget);
        expect(find.textContaining('pregunta 1001', findRichText: true), findsWidgets);
        expect(api.pedidas, 1, reason: 'no se vuelve a sortear al empezar');
        expect(tester.takeException(), isNull);
      });

      testWidgets('sin datos suficientes: el aviso y el camino al creador normal', (tester) async {
        _tam(tester, tam);
        await tester.pumpWidget(_lanzador(
          _ApiFalsa(PlanAMedida.fromJson({'questions': [], 'composition': [], 'coverage': 'insufficient'})),
        ));
        await tester.tap(find.text('abrir'));
        await tester.pumpAndSettle();
        expect(find.text('Todavía no te conocemos lo suficiente'), findsOneWidget);
        expect(find.text('Crear un simulacro normal'), findsOneWidget);
        expect(find.text('Empezar'), findsNothing);
        expect(tester.takeException(), isNull);
      });

      testWidgets('si falla, el mensaje del servidor y «Reintentar»', (tester) async {
        _tam(tester, tam);
        final api = _ApiFalsa(const ApiException(500, 'No se pudo generar tu simulacro a medida'));
        await tester.pumpWidget(_lanzador(api));
        await tester.tap(find.text('abrir'));
        await tester.pumpAndSettle();
        expect(find.text('No se pudo generar tu simulacro a medida'), findsOneWidget);
        expect(find.text('Ir al creador normal'), findsOneWidget);

        api.respuesta = PlanAMedida.fromJson(_planJson(coverage: 'topics'));
        await tester.tap(find.text('Reintentar'));
        await tester.pumpAndSettle();
        expect(api.pedidas, 2);
        expect(find.text('Empezar'), findsOneWidget);
        expect(find.text('Completado con asignaturas flojas'), findsNothing);
        expect(tester.takeException(), isNull);
      });

      testWidgets('la tarjeta de Studio: apagada sin punto débil, encendida con él', (tester) async {
        _tam(tester, tam);
        await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Padding(padding: EdgeInsets.all(20), child: AMedidaCard()))));
        expect(find.textContaining('Cuando tengamos datos de tus fallos'), findsOneWidget);
        expect(find.text('Generar sesión personalizada'), findsNothing);
        expect(tester.takeException(), isNull);

        final api = ApiService(
          AuthService(),
          client: MockClient((_) async => http.Response(
                jsonEncode({
                  'progress': {'level': 3, 'xpTotal': 100, 'xpIntoLevel': 10, 'xpForNext': 100},
                  'daily': [
                    {
                      'code': 'weak_topic', 'scope': 'daily', 'metric': 'weak_topic_questions', 'title': 'Tu punto débil',
                      'description': '', 'progress': 0, 'target': 5, 'xpReward': 20, 'completed': false, 'sortOrder': 1,
                      'meta': {'topic_name': 'Lupus', 'subject_name': 'Reumatología', 'accuracy': 0.3},
                    },
                  ],
                  'weekly': const [],
                }),
                200,
                headers: {'content-type': 'application/json'},
              )),
        )..session = AuthSession(
            accessToken: 't',
            refreshToken: 'r',
            expiresAt: DateTime.now().add(const Duration(hours: 1)),
            userId: 'u1',
          );
        final progreso = ProgressProvider(api);
        addTearDown(progreso.dispose);
        await tester.pumpWidget(ChangeNotifierProvider<ProgressProvider>.value(
          value: progreso,
          child: const MaterialApp(home: Scaffold(body: Padding(padding: EdgeInsets.all(20), child: AMedidaCard()))),
        ));
        await tester.runAsync(() async {
          progreso.setUsuario('u1');
          await progreso.refresh();
        });
        await tester.pump();
        expect(find.textContaining('centrada en Lupus, de Reumatología'), findsOneWidget);
        expect(find.text('Generar sesión personalizada'), findsOneWidget);
        expect(find.text('RECOMENDADO'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });
  }

  test('la pregunta del runner es la misma que la del plan (SimQuestion.fromJson)', () {
    final q = SimQuestion.fromJson(_pregunta(7));
    expect(q.id, 7);
    expect(q.options.length, 4);
  });
}
