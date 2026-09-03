// Las pestañas que no se ven no animan.
//
//   flutter test test/ticker_mode_tabs_test.dart
//
// Existe por una fuga medida en la Tab S8: la app repintaba a ~128 fotogramas
// por segundo con la pantalla QUIETA, en cualquier pestaña. El `PageView`
// mantiene vivas las páginas vecinas para que el deslizamiento sea fluido, y
// eso dejaba corriendo sus animaciones en bucle sin que nadie las mirase —los
// cuatro dibujos del hub de Studio, el brillo del carné del perfil, el
// medallón de Premium—. `MainNavigation` las silencia con `TickerMode`.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mirdaily_app/core/providers/auth_provider.dart';
import 'package:mirdaily_app/core/providers/daily_provider.dart';
import 'package:mirdaily_app/core/providers/settings_provider.dart';
import 'package:mirdaily_app/core/services/api_service.dart';
import 'package:mirdaily_app/core/services/auth_service.dart';
import 'package:mirdaily_app/core/theme/app_theme.dart';
import 'package:mirdaily_app/features/focus/providers/focus_provider.dart';
import 'package:mirdaily_app/features/navigation/main_navigation.dart';

/// `TickerMode.of` resuelto en el contexto de cada pantalla del PageView.
///
/// Se busca por la clave de la pantalla y se mira hacia arriba: es justo lo
/// que hace un `AnimationController` con `vsync: this` para saber si su ticker
/// va silenciado.
bool tickingOf(WidgetTester tester, String key) {
  final ctx = tester.element(find.byKey(ValueKey(key), skipOffstage: false));
  return TickerMode.of(ctx);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'daily_reminder_prompted': true});
  });

  Future<void> pumpNavigation(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

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
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const MainNavigation(),
        ),
      ),
    );
    // Sin pumpAndSettle: hay animaciones en bucle y el árbol no queda quieto.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('en reposo solo anima la pestaña a la vista', (tester) async {
    await pumpNavigation(tester);

    expect(tickingOf(tester, 'quiz'), isTrue, reason: 'la pestaña abierta');

    // Solo las VECINAS se construyen (el PageView cachea una página a cada
    // lado). Desde el daily son Versus y Premium; Studio, a dos de distancia,
    // ni existe todavía —por eso sus cuatro dibujos solo gastaban al estar en
    // Versus, no siempre—.
    expect(find.byKey(const ValueKey('biblioteca'), skipOffstage: false),
        findsNothing,
        reason: 'Studio esta a dos pestañas: no se construye');

    expect(tickingOf(tester, 'versus'), isFalse, reason: 'vecina, no se ve');
    expect(tickingOf(tester, 'premium'), isFalse, reason: 'vecina, no se ve');
  });

  testWidgets('al deslizar, la pestaña que entra ya anima', (tester) async {
    await pumpNavigation(tester);
    expect(tickingOf(tester, 'versus'), isFalse);

    // Arrastre a medias hacia Versus, sin soltar: no debe entrar congelada.
    final gesture = await tester.startGesture(const Offset(100, 300));
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(120, 0));
    await tester.pump();

    expect(tickingOf(tester, 'versus'), isTrue,
        reason: 'la que entra anima durante el gesto');

    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
  });
}
