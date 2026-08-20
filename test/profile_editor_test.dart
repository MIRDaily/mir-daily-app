// El editor de datos del perfil: que abra y se vea.
//
//   flutter test test/profile_editor_test.dart
//
// Se monta con un ApiService que no toca la red. Lo que se comprueba es que la
// hoja aparece con sus campos: "parece no funcionar" puede ser que no abra o
// que abra vacía, y desde fuera se ve igual.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:mirdaily_app/core/models/models.dart';
import 'package:mirdaily_app/core/services/api_service.dart';
import 'package:mirdaily_app/core/services/auth_service.dart';
import 'package:mirdaily_app/core/theme/app_theme.dart';
import 'package:mirdaily_app/features/profile/widgets/profile_editor_sheet.dart';

/// No llega a la red: los catálogos vuelven vacíos y al instante.
class _ApiMudo extends ApiService {
  _ApiMudo() : super(AuthService());

  @override
  Future<List<University>> getUniversities() async => [];

  @override
  Future<List<MirSpecialty>> getMirSpecialties() async => [];
}

const _perfil = UserProfile(
  id: 'u1',
  displayName: 'Alejandro',
  username: 'alejandro',
  bio: 'Opositor de segunda vuelta.',
  medicalYear: 6,
  mainGoal: 'prepare_mir',
);

void main() {
  testWidgets('el editor abre y enseña sus campos', (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: [Provider<ApiService>.value(value: _ApiMudo())],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () => showProfileEditor(context, _perfil),
                  child: const Text('Editar tus datos'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Editar tus datos'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Tus datos'), findsOneWidget,
        reason: 'la hoja tiene que abrirse');
    expect(find.text('Guardar cambios'), findsOneWidget);
    // Y tiene que venir con lo que ya hay escrito.
    expect(find.text('alejandro'), findsOneWidget);
    expect(find.text('Opositor de segunda vuelta.'), findsOneWidget);
  });

  testWidgets('la bio no admite mas de tres lineas', (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: [Provider<ApiService>.value(value: _ApiMudo())],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () => showProfileEditor(context, _perfil),
                  child: const Text('Editar'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Editar'));
    await tester.pumpAndSettle();

    // Por posicion y no por su texto: en cuanto se escribe, un finder que
    // busque el contenido anterior deja de encontrar el campo.
    final bio = find.byType(TextField).at(1);
    expect(tester.widget<TextField>(bio).controller!.text,
        'Opositor de segunda vuelta.',
        reason: 'el segundo campo es el de la bio');

    await tester.enterText(bio, 'una\ndos\ntres');
    await tester.pump();
    expect(tester.widget<TextField>(bio).controller!.text, 'una\ndos\ntres');

    // La cuarta no entra: el carne solo enseña tres.
    await tester.enterText(bio, 'una\ndos\ntres\ncuatro');
    await tester.pump();
    expect(tester.widget<TextField>(bio).controller!.text, 'una\ndos\ntres',
        reason: 'la cuarta linea tiene que rebotar');
  });
}
