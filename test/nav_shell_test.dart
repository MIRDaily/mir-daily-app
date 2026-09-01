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
import 'package:mirdaily_app/features/navigation/main_navigation.dart';
import 'package:mirdaily_app/features/navigation/widgets/nav_rail.dart';

/// El shell de navegación cambia de forma con el tamaño de ventana:
/// barra inferior en móvil / tablet vertical, raíl lateral en tablet
/// horizontal. Los mismos 5 destinos en los dos casos.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'daily_reminder_prompted': true});
  });

  Future<void> pump(WidgetTester tester, Size size) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size;
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
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('móvil: barra inferior, sin raíl', (tester) async {
    await pump(tester, const Size(390, 844));
    expect(find.byType(NavRail), findsNothing);
    expect(find.byType(BottomAppBar), findsNothing); // es una barra custom
    // Los 5 destinos, como etiquetas, están presentes en la barra.
    for (final label in ['Studio', 'Versus', 'Quiz', 'Premium', 'Perfil']) {
      expect(find.text(label), findsWidgets, reason: label);
    }
  });

  testWidgets('tablet horizontal: raíl lateral en vez de barra', (tester) async {
    await pump(tester, const Size(1280, 800));
    expect(find.byType(NavRail), findsOneWidget);
    for (final label in ['Studio', 'Versus', 'Quiz', 'Premium', 'Perfil']) {
      expect(find.text(label), findsWidgets, reason: label);
    }
    // El raíl ocupa TODO el alto (no un cuadrado a media altura) y es
    // estrecho.
    final size = tester.getSize(find.byType(NavRail));
    expect(size.height, 800);
    expect(size.width, lessThan(90));
  });

  testWidgets('tablet vertical: barra inferior, sin raíl', (tester) async {
    await pump(tester, const Size(834, 1194));
    expect(find.byType(NavRail), findsNothing);
  });

  testWidgets('rotar de vertical a horizontal: el raíl aparece a todo el alto',
      (tester) async {
    await pump(tester, const Size(834, 1194));
    expect(find.byType(NavRail), findsNothing);

    tester.view.physicalSize = const Size(1194, 834);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(NavRail), findsOneWidget);
    expect(tester.getSize(find.byType(NavRail)).height, 834,
        reason: 'raíl a todo el alto, no un cuadrado');
  });

  testWidgets('tocar un destino del raíl cambia de pestaña', (tester) async {
    await pump(tester, const Size(1280, 800));
    // Deja que termine la animación de entrada del raíl antes de tocar.
    await tester.pump(const Duration(milliseconds: 900));
    await tester.tap(find.descendant(
      of: find.byType(NavRail),
      matching: find.text('Perfil'),
    ));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    // No explota y el raíl sigue ahí.
    expect(find.byType(NavRail), findsOneWidget);
    // La pestaña visible es Perfil, no el Quiz.
    expect(find.byKey(const ValueKey('profile')), findsOneWidget);
    expect(find.byKey(const ValueKey('quiz')), findsNothing);
  });

  testWidgets('al rotar, la pestaña abierta sigue visible (no se queda '
      'en blanco)', (tester) async {
    await pump(tester, const Size(1280, 800));
    await tester.pump(const Duration(milliseconds: 900));
    await tester.tap(find.descendant(
      of: find.byType(NavRail),
      matching: find.text('Perfil'),
    ));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(const ValueKey('profile')), findsOneWidget);

    // Rotar a vertical: cambia el ancho del área de páginas.
    tester.view.physicalSize = const Size(800, 1280);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Vuelve la barra inferior y Perfil SIGUE siendo la pestaña visible.
    expect(find.byType(NavRail), findsNothing);
    expect(find.byKey(const ValueKey('profile')), findsOneWidget);
    expect(find.byKey(const ValueKey('quiz')), findsNothing);
  });
}
