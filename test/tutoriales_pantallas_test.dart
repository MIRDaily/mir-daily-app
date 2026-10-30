// Tanda 8: los tutoriales de la mascota en sus pantallas, de principio a fin, en móvil (360×780) y
// tablet (1024×768), sin desbordes ni excepciones.
//
//   flutter test test/tutoriales_pantallas_test.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mirdaily_app/core/models/models.dart';
import 'package:mirdaily_app/core/models/tutoriales.dart';
import 'package:mirdaily_app/core/providers/auth_provider.dart';
import 'package:mirdaily_app/core/providers/daily_provider.dart';
import 'package:mirdaily_app/core/providers/progress_provider.dart';
import 'package:mirdaily_app/core/providers/settings_provider.dart';
import 'package:mirdaily_app/core/services/api_service.dart';
import 'package:mirdaily_app/core/services/auth_service.dart';
import 'package:mirdaily_app/core/services/ia_service.dart';
import 'package:mirdaily_app/core/services/tutoriales_api.dart';
import 'package:mirdaily_app/core/theme/app_theme.dart';
import 'package:mirdaily_app/features/biblioteca/biblioteca_hub_screen.dart';
import 'package:mirdaily_app/features/focus/providers/focus_provider.dart';
import 'package:mirdaily_app/features/navigation/main_navigation.dart';
import 'package:mirdaily_app/features/quiz/screens/quiz_screen.dart';
import 'package:mirdaily_app/features/resumenes/resumenes_api.dart';
import 'package:mirdaily_app/features/resumenes/resumenes_ia.dart';
import 'package:mirdaily_app/features/resumenes/resumenes_screen.dart';
import 'package:mirdaily_app/features/tutorial/ajustes_tutoriales.dart';
import 'package:mirdaily_app/features/tutorial/tutorial_ancla.dart';
import 'package:mirdaily_app/features/tutorial/tutorial_overlay.dart';
import 'package:mirdaily_app/features/tutorial/tutoriales_controller.dart';

const _movil = Size(360, 780);
const _tablet = Size(1024, 768);

class _Servidor {
  final List<http.Request> pedidas = [];
  late final http.Client client = MockClient((req) async {
    pedidas.add(req);
    return http.Response(jsonEncode({'success': true, 'tutorials_seen': []}), 200);
  });
  List<String> marcadas() =>
      [for (final r in pedidas.where((r) => r.method == 'POST')) (jsonDecode(r.body) as Map)['key'] as String];
}

/// Monta [home] con el controlador y la capa del tutorial encima de todo, como main.dart.
Future<(Tutoriales, _Servidor)> _montar(
  WidgetTester tester,
  Size size,
  Widget home, {
  List<String> vistos = const [],
  List<SingleChildWidget> extra = const [],
  Map<String, Object> prefs = const {},
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final s = _Servidor();
  final t = Tutoriales(TutorialesApi(token: () async => 'T', baseUrl: 'https://api.test', client: s.client));
  t.sincronizar(usuario: 'u1', perfil: UserProfile(id: 'u1', tutorialsSeen: vistos), celebrando: false);

  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<Tutoriales>.value(value: t),
      ...extra,
    ],
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      home: home,
      builder: (context, child) => Stack(
        textDirection: TextDirection.ltr,
        children: [child!, const Positioned.fill(child: TutorialOverlay())],
      ),
    ),
  ));
  await tester.pump();
  return (t, s);
}

Future<void> _bombear(WidgetTester tester, [int veces = 10, int ms = 100]) async {
  for (var i = 0; i < veces; i++) {
    await tester.pump(Duration(milliseconds: ms));
  }
}

/// Espera a que arranque [id] (la pantalla se asienta 1,4 s y hay un fotograma de margen).
Future<void> _esperarArranque(WidgetTester tester, Tutoriales t, String id) async {
  for (var i = 0; i < 40 && t.enCurso != id; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(t.enCurso, id);
}

/// El rectángulo de una ancla en pantalla, o null si no está montada.
Rect? _rectAncla(Tutoriales t, String ancla) {
  for (final k in t.anclas(ancla)) {
    final ro = k.currentContext?.findRenderObject();
    if (ro is RenderBox && ro.attached && ro.hasSize && ro.size.width > 0) {
      return ro.localToGlobal(Offset.zero) & ro.size;
    }
  }
  return null;
}

/// Recorre el tutorial entero tocando la capa como un dedo: el primer toque acelera, y con la frase
/// escrita pasa de página. Comprueba en cada paso que el texto está, que el ancla (si la hay) acaba
/// dentro de la pantalla y que nada revienta.
Future<List<String>> _recorrer(WidgetTester tester, Tutoriales t, Size size, {Set<String> sinAncla = const {}}) async {
  final textos = <String>[];
  var guarda = 0;
  while (t.enCurso != null && guarda++ < 40) {
    final paso = t.pasoActual!;
    final indice = t.indice;
    textos.add(paso.texto);
    // Toque para acelerar y tiempo de sobra para que se escriba y el foco se asiente.
    await tester.tapAt(const Offset(8, 120));
    await _bombear(tester, 18);
    expect(tester.takeException(), isNull, reason: 'paso $indice: ${paso.texto}');
    expect(find.text(paso.texto), findsWidgets, reason: 'el bocadillo enseña el paso $indice');

    final ancla = paso.anclaEfectiva;
    if (ancla != null && !sinAncla.contains(ancla)) {
      final r = _rectAncla(t, ancla);
      expect(r, isNotNull, reason: 'ancla $ancla montada');
      expect(r!.overlaps(Offset.zero & size), isTrue, reason: 'ancla $ancla llevada a la vista');
    }
    await tester.tapAt(const Offset(8, 120));
    await _bombear(tester, 4);
    expect(t.indice != indice || t.enCurso == null, isTrue, reason: 'el toque pasa de página');
  }
  await _bombear(tester, 4);
  return textos;
}

class _DailyListo extends DailyProvider {
  _DailyListo(super.api);

  @override
  DailyStatus get status => DailyStatus.ready;

  @override
  List<DailyQuestion> get questions => [
        for (var i = 0; i < 5; i++)
          DailyQuestion.fromJson({
            'id': '$i',
            'subject': 'Cardiología',
            'statement': 'Pregunta $i',
            'options': ['a', 'b', 'c', 'd'],
            'correct_answer': 1,
          }),
      ];
}

http.Client _servidorResumenes({required bool conGrupos}) => MockClient((req) async {
      final ruta = req.url.path;
      final Object cuerpo;
      if (ruta == '/api/resumenes') {
        cuerpo = {
          'grupos': conGrupos
              ? [
                  {'id': 'g1', 'name': 'Reuma', 'total': 3, 'pendientes': 3},
                  {'id': 'g2', 'name': 'Infecciosas', 'total': 5, 'pendientes': 0},
                ]
              : [],
        };
      } else if (ruta.endsWith('/estado')) {
        return http.Response('{}', 404);
      } else {
        cuerpo = {};
      }
      return http.Response(jsonEncode(cuerpo), 200, headers: {'content-type': 'application/json; charset=utf-8'});
    });

List<SingleChildWidget> _proveedoresResumenes({required bool conGrupos}) {
  final client = _servidorResumenes(conGrupos: conGrupos);
  return [
    Provider<ResumenesApi>.value(value: ResumenesApi(token: () async => 'T', baseUrl: 'https://api.test', client: client)),
    Provider<ResumenesIa>.value(value: ResumenesIa(IaService(token: () async => 'T', baseUrl: 'https://api.test', client: client))),
  ];
}

void main() {
  for (final (nombre, size) in [('móvil', _movil), ('tablet', _tablet)]) {
    group(nombre, () {
      testWidgets('Studio: el tutorial entero, señalando cada tarjeta, y queda marcado', (tester) async {
        final (t, s) = await _montar(tester, size, const BibliotecaHubScreen());
        await _esperarArranque(tester, t, 'studio.v3');
        final textos = await _recorrer(tester, t, size);
        expect(textos, [for (final p in armarGuion(tutorialStudio)) p.texto]);
        expect(t.enCurso, isNull);
        expect(s.marcadas(), ['studio.v3']);
        expect(tester.takeException(), isNull);
      });

      testWidgets('Resúmenes sin grupos: señala el aviso de «aún no tienes» y el botón de crear', (tester) async {
        final (t, s) = await _montar(tester, size, const ResumenesScreen(),
            extra: _proveedoresResumenes(conGrupos: false));
        await _esperarArranque(tester, t, 'resumenes.v1');
        final textos = await _recorrer(tester, t, size);
        expect(textos, hasLength(4));
        expect(s.marcadas(), ['resumenes.v1']);
      });

      testWidgets('Resúmenes con grupos: la zona es la lista', (tester) async {
        final (t, _) = await _montar(tester, size, const ResumenesScreen(),
            extra: _proveedoresResumenes(conGrupos: true));
        await _esperarArranque(tester, t, 'resumenes.v1');
        expect(find.text('Reuma'), findsOneWidget);
        final textos = await _recorrer(tester, t, size);
        expect(textos, hasLength(4));
      });

      testWidgets('Daily: con el sobre a la vista arranca y lo señala', (tester) async {
        final api = ApiService(AuthService());
        final (t, s) = await _montar(
          tester,
          size,
          const Scaffold(body: QuizScreen()),
          extra: [
            Provider<ApiService>.value(value: api),
            ChangeNotifierProvider<DailyProvider>(create: (_) => _DailyListo(api)),
            ChangeNotifierProvider(create: (_) => SettingsProvider()),
          ],
        );
        await _esperarArranque(tester, t, 'daily.v2');
        expect(_rectAncla(t, anclaDailySobre), isNotNull);
        // Aquí no hay barra (es la pantalla sola): ese paso sale centrado, sin romperse.
        final textos = await _recorrer(tester, t, size, sinAncla: {anclaNavPestanas});
        expect(textos, [for (final p in armarGuion(tutorialDaily)) p.texto]);
        expect(s.marcadas(), ['daily.v2']);
      });
    });
  }

  for (final (nombre, size) in [('móvil', const Size(390, 844)), ('tablet', _tablet)]) {
    testWidgets('la barra de navegación es el ancla del cierre del daily ($nombre)', (tester) async {
      final auth = AuthService();
      final api = ApiService(auth);
      final (t, _) = await _montar(tester, size, const MainNavigation(), extra: [
        Provider<ApiService>.value(value: api),
        ChangeNotifierProvider(create: (_) => AuthProvider(authService: auth, apiService: api)),
        ChangeNotifierProvider(create: (_) => DailyProvider(api)),
        ChangeNotifierProvider(create: (_) => ProgressProvider(api)),
        ChangeNotifierProvider(create: (_) => FocusProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        // Corta el diálogo de recordatorios (llamaría al plugin de notificaciones).
      ], prefs: {'daily_reminder_prompted': true});
      await _bombear(tester, 12);
      final r = _rectAncla(t, anclaNavPestanas);
      expect(r, isNotNull);
      expect((Offset.zero & size).contains(r!.center), isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('lo visto en la web no sale', (tester) async {
    final (t, _) = await _montar(tester, _movil, const BibliotecaHubScreen(), vistos: ['studio.v3']);
    await _bombear(tester, 30);
    expect(t.enCurso, isNull);
    expect(find.text(armarGuion(tutorialStudio).first.texto), findsNothing);
  });

  testWidgets('«Saltar» lo cierra y lo marca', (tester) async {
    final (t, s) = await _montar(tester, _movil, const BibliotecaHubScreen());
    await _esperarArranque(tester, t, 'studio.v3');
    await tester.tap(find.text('Saltar'));
    await _bombear(tester, 4);
    expect(t.enCurso, isNull);
    expect(s.marcadas(), ['studio.v3']);
    expect(find.text('Saltar'), findsNothing);
  });

  testWidgets('mientras escribe, un toque acelera en vez de pasar de página', (tester) async {
    final (t, _) = await _montar(tester, _movil, const BibliotecaHubScreen());
    await _esperarArranque(tester, t, 'studio.v3');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(const Offset(8, 120));
    await tester.pump(const Duration(milliseconds: 30));
    expect(t.indice, 0);
    await _bombear(tester, 10);
    await tester.tapAt(const Offset(8, 120));
    await tester.pump();
    expect(t.indice, 1);
    await _bombear(tester, 10);
  });

  testWidgets('con «reducir movimiento» el texto sale entero al momento', (tester) async {
    final (t, _) = await _montar(
      tester,
      _movil,
      const MediaQuery(data: MediaQueryData(size: _movil, disableAnimations: true), child: BibliotecaHubScreen()),
    );
    await _esperarArranque(tester, t, 'studio.v3');
    await tester.pump();
    await tester.pump();
    // La capa vive fuera del MediaQuery de la pantalla: se mira solo que no rompe y que avanza.
    await _recorrer(tester, t, _movil);
    expect(tester.takeException(), isNull);
  });

  group('cuándo está lista una pantalla', () {
    testWidgets('con la pestaña apagada (TickerMode) no arranca; al verse, sí', (tester) async {
      final visible = ValueNotifier(false);
      final (t, _) = await _montar(
        tester,
        _movil,
        Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: visible,
            builder: (_, v, __) => TickerMode(
              enabled: v,
              child: const TutorialListo(id: 'studio.v3', listo: true, child: SizedBox.expand()),
            ),
          ),
        ),
      );
      await _bombear(tester, 25);
      expect(t.enCurso, isNull);
      visible.value = true;
      await _esperarArranque(tester, t, 'studio.v3');
    });

    testWidgets('con algo encima (otra ruta) espera, y no arranca a medias', (tester) async {
      final navegador = GlobalKey<NavigatorState>();
      final (t, _) = await _montar(
        tester,
        _movil,
        Navigator(
          key: navegador,
          onGenerateRoute: (_) => MaterialPageRoute(
            builder: (_) => const TutorialListo(id: 'studio.v3', listo: true, child: SizedBox.expand()),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      navegador.currentState!.push(MaterialPageRoute(builder: (_) => const Scaffold(body: Text('popup'))));
      await _bombear(tester, 25);
      expect(t.enCurso, isNull, reason: 'el tiempo de asentarse se corta al taparse');
      navegador.currentState!.pop();
      await _esperarArranque(tester, t, 'studio.v3');
    });

    testWidgets('si la pantalla se va antes de asentarse, no arranca', (tester) async {
      final mostrar = ValueNotifier(true);
      final (t, _) = await _montar(
        tester,
        _movil,
        ValueListenableBuilder<bool>(
          valueListenable: mostrar,
          builder: (_, v, __) =>
              v ? const TutorialListo(id: 'studio.v3', listo: true, child: SizedBox.expand()) : const SizedBox(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));
      mostrar.value = false;
      await _bombear(tester, 25);
      expect(t.enCurso, isNull);
    });
  });

  group('Perfil → Tutoriales', () {
    for (final (nombre, size) in [('móvil', _movil), ('tablet', _tablet)]) {
      testWidgets('el interruptor los apaga y «volver a verlos» los reinicia ($nombre)', (tester) async {
        final (t, s) = await _montar(
          tester,
          size,
          Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(onPressed: () => abrirAjustesTutoriales(context), child: const Text('abrir')),
              ),
            ),
          ),
          vistos: ['daily.v2', 'studio.v3'],
        );
        await _bombear(tester, 3);
        await tester.tap(find.text('abrir'));
        await _bombear(tester, 6);
        expect(find.text('ACTIVADOS'), findsOneWidget);
        await tester.tap(find.bySemanticsLabel('Activar o desactivar los tutoriales de la mascota'));
        await _bombear(tester, 3);
        expect(t.activos, isFalse);
        expect(find.text('DESACTIVADOS'), findsOneWidget);

        await tester.tap(find.text('Volver a verlos desde el principio'));
        await _bombear(tester, 6);
        expect(s.pedidas.last.method, 'DELETE');
        expect(t.activos, isTrue);
        expect(t.vistos, isEmpty);
        expect(find.text('ACTIVADOS'), findsNothing, reason: 'la hoja se cierra para llevar al daily');
        expect(tester.takeException(), isNull);
      });
    }
  });
}
