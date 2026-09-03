import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:provider/provider.dart';

import 'package:mirdaily_app/core/providers/auth_provider.dart';
import 'package:mirdaily_app/core/providers/daily_provider.dart';
import 'package:mirdaily_app/core/providers/settings_provider.dart';
import 'package:mirdaily_app/core/services/api_service.dart';
import 'package:mirdaily_app/core/services/app_warmup.dart';
import 'package:mirdaily_app/core/services/auth_service.dart';
import 'package:mirdaily_app/features/splash/loading_screen.dart';

/// La salida de la pantalla de carga: las células se precipitan y barren el
/// fondo antes de dar paso a la app. Lo que no puede fallar es que acabe
/// cediendo el paso: si onContinue no llegara a llamarse, el usuario se
/// quedaría encerrado en la carga.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  /// El viewport por defecto de los tests (800x600) es ancho y bajo, y esta
  /// pantalla es vertical: con el logo a 500 px de ancho la columna no cabe y
  /// desborda. Se usa una pantalla de móvil real (360x780 dp).
  void usePhoneScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  // Sin sesión, las tareas del warmup fallan solas; con los plazos en corto la
  // pantalla llega a "Continuar" en unos pocos pumps.
  AppWarmup buildWarmup() {
    final auth = AuthService();
    final api = ApiService(auth);
    return AppWarmup(
      auth: AuthProvider(authService: auth, apiService: api),
      daily: DailyProvider(api),
      minimumDuration: const Duration(milliseconds: 10),
      timeout: const Duration(milliseconds: 50),
    );
  }

  testWidgets('la cascada cede el paso solo cuando termina de barrer el fondo',
      (tester) async {
    usePhoneScreen(tester);
    var continued = 0;
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => SettingsProvider(),
        child: MaterialApp(
          home: LoadingScreen(
            warmup: buildWarmup(),
            onContinue: () => continued++,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 600));

    await tester.tap(find.text('Continuar'));
    await tester.pump();
    expect(continued, 0, reason: 'la app no puede entrar antes de la cascada');

    // A media caída las células ya llevan velocidad extra y no se reponen.
    await tester.pump(const Duration(milliseconds: 400));
    final mid = tester.widget<ParticlesBackground>(
      find.byType(ParticlesBackground),
    );
    expect(mid.fallBoost, greaterThan(0));
    expect(mid.animate, isTrue);
    expect(continued, 0);

    // Y al acabar entra la app, con el fondo ya parado.
    await tester.pump(const Duration(milliseconds: 600));
    expect(continued, 1);
    final end = tester.widget<ParticlesBackground>(
      find.byType(ParticlesBackground),
    );
    expect(end.animate, isFalse, reason: 'el fondo debe quedar congelado');

    // El fundido de la música dura más que la salida y sigue vivo después de
    // que la pantalla se destruya (a propósito: si se cortara aquí, "Continuar"
    // sonaría a tijeretazo). Se le deja acabar o el test se queja del timer.
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('con las animaciones del sistema desactivadas la cascada no '
      'retrasa la entrada', (tester) async {
    usePhoneScreen(tester);
    // Quien desactiva las animaciones (accesibilidad, o unas Opciones de
    // desarrollador con la escala en off) no quiere esperar a que caigan las
    // células: Flutter recorta la duración al 5% y la salida es un corte.
    // OJO al probar la cascada a mano: con este ajuste puesto no se ve, porque
    // los 850 ms se quedan en ~42.
    tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(
      tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue,
    );

    var continued = 0;
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => SettingsProvider(),
        child: MaterialApp(
          home: LoadingScreen(
            warmup: buildWarmup(),
            onContinue: () => continued++,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 600));

    await tester.tap(find.text('Continuar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    expect(continued, 1);

    // Dejar acabar el fundido de la música, que sobrevive a la pantalla.
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('pulsar Continuar dos veces no dispara dos entradas',
      (tester) async {
    usePhoneScreen(tester);
    var continued = 0;
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => SettingsProvider(),
        child: MaterialApp(
          home: LoadingScreen(
            warmup: buildWarmup(),
            onContinue: () => continued++,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 600));

    // El botón sigue en pantalla mientras la cascada corre, así que se puede
    // volver a pulsar.
    await tester.tap(find.text('Continuar'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Continuar'), warnIfMissed: false);
    await tester.pump(const Duration(seconds: 1));

    expect(continued, 1);

    // Dejar acabar el fundido de la música, que sobrevive a la pantalla.
    await tester.pump(const Duration(seconds: 6));
  });
}
