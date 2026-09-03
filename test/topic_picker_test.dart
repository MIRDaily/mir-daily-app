// Paso 2 del creador de simulacros: el selector de temas.
//
// Regresión de la F5 (modales adaptativos): en tablet la hoja sale como
// `Dialog`, y un `DraggableScrollableSheet` ahí dentro recibía altura
// infinita ("BoxConstraints forces an infinite height"), así que el selector
// no llegaba a pintarse en NINGUNA asignatura.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:mirdaily_app/core/models/models.dart';
import 'package:mirdaily_app/core/services/api_service.dart';
import 'package:mirdaily_app/core/services/auth_service.dart';
import 'package:mirdaily_app/core/theme/app_theme.dart';
import 'package:mirdaily_app/features/simulacro/simulacro_screen.dart';

class _FakeApi extends ApiService {
  _FakeApi() : super(AuthService());

  @override
  Future<List<SimSubject>> getSimulacroSubjects() async => const [
        SimSubject(id: 1, name: 'Cardiología'),
        SimSubject(id: 2, name: 'Miscelánea'),
      ];

  @override
  Future<List<SimTopic>> getSimulacroTopics(List<int> subjectIds) async => const [
        SimTopic(id: 10, name: 'Arritmias', subjectId: 1),
        SimTopic(id: 20, name: 'Geriatría', subjectId: 2),
      ];
}

// El creador tiene ilustraciones que se animan en bucle, así que
// `pumpAndSettle` no termina nunca: se bombea a mano.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

Future<void> _openPicker(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    Provider<ApiService>.value(
      value: _FakeApi(),
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: const SimulacroScreen(),
      ),
    ),
  );
  await _settle(tester);

  // Atajo "Todas": marca las asignaturas y dispara la carga de temas.
  await tester.tap(find.text('Todas'));
  await _settle(tester);

  // En móvil el botón del paso 2 cae por debajo del pliegue.
  await tester.ensureVisible(find.text('Elegir temas concretos'));
  await _settle(tester);
  await tester.tap(find.text('Elegir temas concretos'));
  await _settle(tester);
}

void main() {
  // 430x932 y no 390x844: con el font de pruebas (más ancho que el real) la
  // cabecera de "Modo de corrección" desborda 17px a 390 y el test se cae por
  // un aviso que en el dispositivo no existe.
  testWidgets('móvil: el selector de temas lista los temas', (tester) async {
    await _openPicker(tester, const Size(430, 932));

    expect(find.text('Elegir temas'), findsOneWidget);
    expect(find.text('Arritmias'), findsOneWidget);
    expect(find.text('Geriatría'), findsOneWidget);
  });

  testWidgets('tablet: el selector de temas lista los temas', (tester) async {
    await _openPicker(tester, const Size(1280, 800));

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('Elegir temas'), findsOneWidget);
    expect(find.text('Arritmias'), findsOneWidget);
    expect(find.text('Geriatría'), findsOneWidget);
  });
}
