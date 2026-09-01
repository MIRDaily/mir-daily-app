import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mirdaily_app/core/build_info.dart';
import 'package:mirdaily_app/main.dart';

void main() {
  testWidgets('BuildTag pinta el sello en debug y no interfiere', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Center(child: Text('contenido'))),
      // sin builder: lo aplicamos a mano
    ));

    await tester.pumpWidget(MaterialApp(
      home: const Scaffold(body: Center(child: Text('contenido'))),
      builder: (context, child) => BuildTag(child: child ?? const SizedBox()),
    ));

    // El contenido sigue ahí y encima hay un sello, envuelto en IgnorePointer
    // para no capturar toques.
    expect(find.text('contenido'), findsOneWidget);
    expect(find.byType(BuildTag), findsOneWidget);
    final tagText = find.text(BuildInfo.label);
    expect(tagText, findsOneWidget);
    expect(
      find.ancestor(of: tagText, matching: find.byType(IgnorePointer)),
      findsOneWidget,
    );
  });

  test('BuildInfo.visible es true en debug', () {
    expect(BuildInfo.visible, isTrue);
  });

  test('el patron del sha extrae solo el hash del versionName', () {
    final pattern = RegExp(r'-([0-9a-f]{8})-');
    expect(pattern.firstMatch('1.0.0-63c98b7c-0901.1730')?.group(1),
        '63c98b7c');
    expect(pattern.firstMatch('1.0.0')?.group(1), isNull);
  });
}
