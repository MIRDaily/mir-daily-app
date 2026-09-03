// Subrayado del enunciado: toque palabra a palabra, arrastre tras mantener
// pulsado, y que dos palabras seguidas salgan como UN bloque amarillo.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mirdaily_app/features/simulacro/widgets/highlightable_statement.dart';

const _enunciado = 'Varon de 45 anos con disnea de esfuerzo progresiva';

/// Monta el widget con el estado por fuera, como hacen los runners.
class _Host extends StatefulWidget {
  const _Host({this.inicial = const <int>{}});

  final Set<int> inicial;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late final Set<int> marcadas = {...widget.inicial};

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: HighlightableStatement(
            statement: _enunciado,
            highlighted: marcadas,
            onToggle: (i) => setState(() {
              if (!marcadas.remove(i)) marcadas.add(i);
            }),
            onPaint: (nuevo) => setState(() {
              marcadas
                ..clear()
                ..addAll(nuevo);
            }),
          ),
        ),
      ),
    );
  }
}

Set<int> _estado(WidgetTester tester) =>
    tester.state<_HostState>(find.byType(_Host)).marcadas;

/// Los trozos de texto que se pintan de amarillo, uno por bloque continuo.
///
/// El amarillo lo dibuja un `CustomPainter` por debajo del texto (para que las
/// esquinas salgan redondeadas), así que lo que se comprueba son los tramos de
/// caracteres que le llegan: un tramo = un bloque.
List<String> _tramosMarcados(WidgetTester tester) {
  final pintado = tester
      .widgetList<CustomPaint>(find.descendant(
        of: find.byType(HighlightableStatement),
        matching: find.byType(CustomPaint),
      ))
      .firstWhere((c) =>
          c.painter != null &&
          c.painter.runtimeType.toString().contains('HighlightPainter'));

  final runs = ((pintado.painter as dynamic).runs as List).cast<(int, int)>();
  return [for (final (a, b) in runs) _enunciado.substring(a, b)];
}

/// Centro de la palabra n-esima, para tocar o arrastrar encima.
Offset _centroPalabra(WidgetTester tester, int indice) {
  final render = tester.renderObject<RenderParagraph>(find.byType(RichText));
  final palabras = _enunciado.split(' ');

  var inicio = 0;
  for (var i = 0; i < indice; i++) {
    inicio += palabras[i].length + 1;
  }
  final medio = inicio + palabras[indice].length ~/ 2;

  final caja = render
      .getBoxesForSelection(TextSelection(baseOffset: medio, extentOffset: medio + 1))
      .first;
  final local = Offset((caja.left + caja.right) / 2, (caja.top + caja.bottom) / 2);
  return render.localToGlobal(local);
}

void main() {
  testWidgets('un toque marca una palabra y otro la desmarca', (tester) async {
    await tester.pumpWidget(const _Host());

    await tester.tapAt(_centroPalabra(tester, 3)); // "anos"
    await tester.pump();
    expect(_estado(tester), {3});

    await tester.tapAt(_centroPalabra(tester, 3));
    await tester.pump();
    expect(_estado(tester), isEmpty);
  });

  testWidgets('dos palabras seguidas salen como UN solo bloque amarillo',
      (tester) async {
    // "disnea de esfuerzo" son los indices 5, 6 y 7.
    await tester.pumpWidget(const _Host(inicial: {5, 6, 7}));
    await tester.pump();

    // Un unico tramo pintado, con los espacios dentro: antes eran tres
    // manchas sueltas separadas por un hueco.
    expect(_tramosMarcados(tester), ['disnea de esfuerzo']);
  });

  testWidgets('el amarillo va con las esquinas redondeadas', (tester) async {
    await tester.pumpWidget(const _Host(inicial: {5, 6, 7}));
    await tester.pump();

    final render = tester.renderObject(find
        .descendant(
          of: find.byType(HighlightableStatement),
          matching: find.byType(CustomPaint),
        )
        .first);

    // rrect y no rect: con `TextStyle.background` el engine solo sabe pintar
    // rectangulos a escuadra, y eso parecia un fallo de pintado.
    expect(render, paints..rrect());
  });

  testWidgets('palabras sueltas no se unen entre si', (tester) async {
    await tester.pumpWidget(const _Host(inicial: {0, 3}));
    await tester.pump();

    expect(_tramosMarcados(tester), ['Varon', 'anos']);
  });

  testWidgets('mantener pulsado y arrastrar marca el tramo entero',
      (tester) async {
    await tester.pumpWidget(const _Host());

    final gesto = await tester.startGesture(_centroPalabra(tester, 2));
    await tester.pump(const Duration(milliseconds: 600)); // pulsacion larga
    await gesto.moveTo(_centroPalabra(tester, 5));
    await tester.pump();
    await gesto.up();
    await tester.pump();

    expect(_estado(tester), {2, 3, 4, 5});
  });

  testWidgets('volver sobre tus pasos encoge el tramo', (tester) async {
    await tester.pumpWidget(const _Host());

    final gesto = await tester.startGesture(_centroPalabra(tester, 2));
    await tester.pump(const Duration(milliseconds: 600));
    await gesto.moveTo(_centroPalabra(tester, 6));
    await tester.pump();
    expect(_estado(tester), {2, 3, 4, 5, 6});

    // Sin soltar, hacia atras: el tramo se recorta en vez de quedarse.
    await gesto.moveTo(_centroPalabra(tester, 4));
    await tester.pump();
    await gesto.up();
    await tester.pump();

    expect(_estado(tester), {2, 3, 4});
  });

  testWidgets('empezar sobre algo ya marcado borra en vez de pintar',
      (tester) async {
    await tester.pumpWidget(const _Host(inicial: {2, 3, 4, 5, 6}));
    await tester.pump();

    // Arranca en la 3, que esta marcada: todo el arrastre borra.
    final gesto = await tester.startGesture(_centroPalabra(tester, 3));
    await tester.pump(const Duration(milliseconds: 600));
    await gesto.moveTo(_centroPalabra(tester, 5));
    await tester.pump();
    await gesto.up();
    await tester.pump();

    expect(_estado(tester), {2, 6});
  });

  // La razón de que haga falta mantener pulsado: en el modo Deslizar el
  // enunciado viaja dentro de un PageView horizontal. Un arrastre a secas
  // tiene que seguir siendo "cambiar de pregunta".
  testWidgets('un arrastre sin mantener pulsado no subraya: pasa de página',
      (tester) async {
    final marcadas = <int>{};
    final paginas = PageController();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PageView(
          controller: paginas,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: HighlightableStatement(
                statement: _enunciado,
                highlighted: marcadas,
                onToggle: (i) => marcadas.add(i),
                onPaint: (nuevo) => marcadas
                  ..clear()
                  ..addAll(nuevo),
              ),
            ),
            const Center(child: Text('siguiente pregunta')),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.fling(find.byType(RichText), const Offset(-400, 0), 1200);
    await tester.pumpAndSettle();

    expect(marcadas, isEmpty, reason: 'el arrastre no debe subrayar');
    expect(find.text('siguiente pregunta'), findsOneWidget);
  });

  testWidgets('el sentido no cambia a mitad de arrastre', (tester) async {
    // Empieza en una sin marcar y pasa por encima de marcadas: pinta todo,
    // no va alternando (que dejaria huecos).
    await tester.pumpWidget(const _Host(inicial: {4}));
    await tester.pump();

    final gesto = await tester.startGesture(_centroPalabra(tester, 2));
    await tester.pump(const Duration(milliseconds: 600));
    await gesto.moveTo(_centroPalabra(tester, 6));
    await tester.pump();
    await gesto.up();
    await tester.pump();

    expect(_estado(tester), {2, 3, 4, 5, 6});
  });
}
