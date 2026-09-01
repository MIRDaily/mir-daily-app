// La barra de navegación tiene dos estilos elegibles: clásica (pegada al
// borde) y flotante (un bocadillo, sobre el contenido).
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

Future<void> pump(WidgetTester tester, SettingsProvider settings,
    {Size size = const Size(390, 844)}) async {
  SharedPreferences.setMockInitialValues({'daily_reminder_prompted': true});
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
        ChangeNotifierProvider<SettingsProvider>.value(value: settings),
      ],
      child: const MaterialApp(home: MainNavigation()),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  testWidgets('clásica: la barra va en el slot bottomNavigationBar',
      (tester) async {
    await pump(tester, SettingsProvider());
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    expect(scaffold.bottomNavigationBar, isNotNull);
    // Los 5 destinos están.
    for (final l in ['Studio', 'Versus', 'Quiz', 'Premium', 'Perfil']) {
      expect(find.text(l), findsWidgets, reason: l);
    }
  });

  testWidgets('flotante: sin bottomNavigationBar, la barra va sobre el '
      'contenido', (tester) async {
    final settings = SettingsProvider();
    await settings.setNavBarStyle(NavBarStyle.floating);
    await pump(tester, settings);

    // Deja terminar la animación de entrada de la barra.
    await tester.pump(const Duration(milliseconds: 1000));

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    expect(scaffold.bottomNavigationBar, isNull);
    // Los destinos siguen ahí (ahora dentro del bocadillo).
    for (final l in ['Studio', 'Versus', 'Quiz', 'Premium', 'Perfil']) {
      expect(find.text(l), findsWidgets, reason: l);
    }
    // La barra flotante no toca el borde inferior de la pantalla (hay
    // margen por debajo).
    final barBottom = tester.getRect(find.text('Perfil').first).bottom;
    expect(barBottom, lessThan(838));
  });

  testWidgets('flotante en tablet horizontal: desactiva el raíl', (tester) async {
    final settings = SettingsProvider();
    await settings.setNavBarStyle(NavBarStyle.floating);
    await pump(tester, settings, size: const Size(1280, 800));

    // Sin raíl aunque sea tablet apaisada: gana el estilo flotante.
    expect(find.byType(NavRail), findsNothing);
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold).first).bottomNavigationBar,
      isNull,
    );
    for (final l in ['Studio', 'Versus', 'Quiz', 'Premium', 'Perfil']) {
      expect(find.text(l), findsWidgets, reason: l);
    }
  });

  testWidgets('clásica en tablet horizontal: sí hay raíl', (tester) async {
    await pump(tester, SettingsProvider(), size: const Size(1280, 800));
    expect(find.byType(NavRail), findsOneWidget);
  });

  testWidgets('cambiar el ajuste en caliente cambia la barra', (tester) async {
    final settings = SettingsProvider();
    await pump(tester, settings);
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold).first).bottomNavigationBar,
      isNotNull,
    );

    await settings.setNavBarStyle(NavBarStyle.floating);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      tester.widget<Scaffold>(find.byType(Scaffold).first).bottomNavigationBar,
      isNull,
    );
  });
}
