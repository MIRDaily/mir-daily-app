// Con el daily ya hecho, la pestaña "Sobre" enseña "¡Daily completado!" al
// momento. Antes había una espera forzada de 10 s con el goo ("Guardando tu
// resultado…") aunque no hubiera nada que guardar.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:mirdaily_app/core/models/models.dart';
import 'package:mirdaily_app/core/providers/daily_provider.dart';
import 'package:mirdaily_app/core/providers/settings_provider.dart';
import 'package:mirdaily_app/core/services/api_service.dart';
import 'package:mirdaily_app/core/services/auth_service.dart';
import 'package:mirdaily_app/core/theme/app_theme.dart';
import 'package:mirdaily_app/features/quiz/screens/quiz_screen.dart';

class _CompletedDaily extends DailyProvider {
  _CompletedDaily(super.api);

  @override
  DailyStatus get status => DailyStatus.completed;
}

void main() {
  testWidgets('el daily completado enseña "¡Daily completado!" sin espera',
      (tester) async {
    final api = ApiService(AuthService());

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ApiService>.value(value: api),
          ChangeNotifierProvider<DailyProvider>(
              create: (_) => _CompletedDaily(api)),
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          home: const Scaffold(body: QuizScreen()),
        ),
      ),
    );
    await tester.pump();

    // Al momento: la pantalla de completado, sin el loader del goo.
    expect(find.text('¡Daily completado!'), findsOneWidget);
    expect(find.text('Guardando tu resultado...'), findsNothing);

    // Y sigue igual tras dejar correr el reloj (no aparece ninguna espera).
    await tester.pump(const Duration(seconds: 12));
    expect(find.text('¡Daily completado!'), findsOneWidget);
    expect(find.text('Guardando tu resultado...'), findsNothing);
  });
}
