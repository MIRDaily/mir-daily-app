import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mirdaily_app/core/providers/auth_provider.dart';
import 'package:mirdaily_app/core/providers/daily_provider.dart';
import 'package:mirdaily_app/core/providers/settings_provider.dart';
import 'package:mirdaily_app/core/services/api_service.dart';
import 'package:mirdaily_app/core/services/auth_service.dart';
import 'package:mirdaily_app/features/focus/providers/focus_provider.dart';
import 'package:mirdaily_app/core/theme/app_theme.dart';
import 'package:mirdaily_app/features/navigation/main_navigation.dart';
import 'package:mirdaily_app/features/quiz/game/pack_opening_game.dart';
import 'package:mirdaily_app/features/quiz/screens/quiz_screen.dart';

/// MainNavigation escucha el PageController para saber si el sobre está a la
/// vista. Ese listener corre en cada frame del scroll, así que solo puede
/// repintar cuando el dato de grano grueso cambia: si repinta siempre, recrea
/// las cinco pantallas a 120 Hz mientras el dedo se mueve.
void main() {
  setUp(() {
    // Corta el diálogo de recordatorios antes de que llame al plugin de
    // notificaciones, que en un test no existe.
    SharedPreferences.setMockInitialValues({'daily_reminder_prompted': true});
  });

  // Sin sesión, el daily falla solo y el sobre se queda en su pantalla de
  // error: nos deja el PageView montado y navegable sin tocar la red. Las
  // pestañas vecinas que el PageView monta también fallan sin ruido.
  Future<void> pumpNavigation(WidgetTester tester) async {
    // Viewport de móvil: es donde vive la barra inferior con su PageView. En
    // tablet horizontal MainNavigation usa el raíl lateral (otro test).
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final auth = AuthService();
    final api = ApiService(auth);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ApiService>.value(value: api),
          ChangeNotifierProvider(
            create: (_) => AuthProvider(authService: auth, apiService: api),
          ),
          ChangeNotifierProvider(create: (_) => DailyProvider(api)),
          ChangeNotifierProvider(create: (_) => FocusProvider()),
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ],
        child: const MaterialApp(home: MainNavigation()),
      ),
    );
    // pumpAndSettle no sirve: el indicador de "desliza para abrir" repite en
    // bucle y el árbol nunca queda quieto.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  // skipOffstage: false porque al cambiar de página el sobre no se desmonta,
  // se queda vivo fuera de pantalla (AutomaticKeepAliveClientMixin).
  QuizScreen quizWidget(WidgetTester tester) => tester.widget<QuizScreen>(
        find.byKey(const ValueKey('quiz'), skipOffstage: false),
      );

  /// Deslizamiento horizontal completo, en pasos y con pumps entre medias.
  /// tester.drag() no vale aquí: manda todos los eventos con el mismo
  /// timestamp y el PageView acaba resolviendo el gesto sin cambiar de página.
  /// Se empieza por la izquierda a propósito: el centro es la zona del sobre,
  /// donde _ZonedPageView puede bloquear el gesto.
  Future<void> swipe(WidgetTester tester, double dx) async {
    final gesture = await tester.startGesture(const Offset(100, 300));
    await gesture.moveBy(Offset(dx * 0.1, 0)); // supera el touch slop
    await tester.pump();
    await gesture.moveBy(Offset(dx * 0.9, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(seconds: 2)); // deja asentar la página
  }

  test('el sobre no pinta el fondo negro de Flame', () {
    // GameWidget mete todo en un ColoredBox con este color y, hasta que
    // onLoad() no termina, es LO ÚNICO que se ve: con el negro por defecto de
    // FlameGame la entrada al daily daba un pantallazo.
    final game = PackOpeningGame(specialties: const [], onComplete: (_) {});
    expect(game.backgroundColor(), AppColors.background);
  });

  testWidgets('deslizar sin cambiar de página no reconstruye las pantallas',
      (tester) async {
    await pumpNavigation(tester);
    final before = quizWidget(tester);

    final gesture = await tester.startGesture(const Offset(100, 300));
    await gesture.moveBy(const Offset(-40, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(-30, 0));
    await tester.pump();

    // El sobre sigue a la vista y sigue siendo la página actual, así que nada
    // de lo que MainNavigation pinta ha cambiado: debe ser el MISMO widget.
    // Otra instancia significaría que _buildScreens() volvió a correr.
    expect(
      identical(quizWidget(tester), before),
      isTrue,
      reason: 'el árbol se reconstruyó durante el scroll',
    );

    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('pasar de página deja el sobre como no visible', (tester) async {
    await pumpNavigation(tester);
    expect(quizWidget(tester).isVisible, isTrue);

    // isVisible es lo que pausa el juego Flame (QuizScreen -> setVisible).
    await swipe(tester, -500);

    expect(quizWidget(tester).isVisible, isFalse);
  });

  testWidgets('volver al sobre lo deja visible otra vez', (tester) async {
    await pumpNavigation(tester);

    await swipe(tester, -500);
    expect(quizWidget(tester).isVisible, isFalse);

    await swipe(tester, 500);
    expect(quizWidget(tester).isVisible, isTrue);
  });

  // `isVisible` no bastaba: bajaba una bandera y `update()` salía temprano,
  // pero el bucle de Flame seguía vivo y `render()` repintaba el sobre en cada
  // fotograma. Medido en una Tab S8: ~127 fotogramas por segundo estando en
  // otra pestaña, que era lo único que impedía a la app descansar. Y el
  // `TickerMode` de MainNavigation no lo arregla, porque Flame usa un `Ticker`
  // crudo. Lo que se comprueba aquí es que el MOTOR se para, no la bandera.
  test('salir del sobre para el motor de Flame, no solo la bandera', () {
    final game = PackOpeningGame(specialties: const [], onComplete: (_) {});
    expect(game.paused, isFalse, reason: 'arranca corriendo');

    game.setVisible(false);
    expect(game.paused, isTrue, reason: 'fuera de vista, motor parado');

    game.setVisible(true);
    expect(game.paused, isFalse, reason: 'al volver, motor en marcha');

    // Idempotente: QuizScreen lo llama desde initState y desde
    // didUpdateWidget, así que puede repetirse con el mismo valor.
    game.setVisible(true);
    expect(game.paused, isFalse);
    game.setVisible(false);
    game.setVisible(false);
    expect(game.paused, isTrue);
  });
}
