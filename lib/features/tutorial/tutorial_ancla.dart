// Las dos únicas piezas que toca una pantalla para tener tutorial (como en la web, donde basta con
// `useTutorialReady` y los `data-tutorial`):
//  - `TutorialAncla`: marca un elemento que la mascota puede iluminar. Varios con el mismo nombre se
//    iluminan juntos (el rectángulo que los engloba).
//  - `TutorialListo`: dice «esta pantalla ya puede enseñar su tutorial».
// Sin el controlador en el árbol (tests de otras pantallas) no hacen nada.

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'tutoriales_controller.dart';

class TutorialAncla extends StatefulWidget {
  final String nombre;
  final Widget child;

  const TutorialAncla({super.key, required this.nombre, required this.child});

  @override
  State<TutorialAncla> createState() => _TutorialAnclaState();
}

class _TutorialAnclaState extends State<TutorialAncla> {
  final GlobalKey _key = GlobalKey();
  Tutoriales? _ctrl;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ctrl = context.read<Tutoriales?>();
    if (identical(ctrl, _ctrl)) return;
    _ctrl?.quitarAncla(widget.nombre, _key);
    _ctrl = ctrl?..registrarAncla(widget.nombre, _key);
  }

  @override
  void didUpdateWidget(TutorialAncla oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.nombre != widget.nombre) {
      _ctrl?.quitarAncla(oldWidget.nombre, _key);
      _ctrl?.registrarAncla(widget.nombre, _key);
    }
  }

  @override
  void dispose() {
    _ctrl?.quitarAncla(widget.nombre, _key);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => KeyedSubtree(key: _key, child: widget.child);
}

/// Declara lista la pantalla cuando [listo] es cierto Y además:
///  - su pestaña es la que se ve (en el PageView de la barra, las vecinas están montadas pero con los
///    tickers apagados: `TickerMode`);
///  - su ruta es la de arriba (con un popup, una hoja o un diálogo encima, espera);
///  - han pasado [asentar] así: las tarjetas entran con su animación, y medir antes perseguiría a un
///    elemento que todavía se está colocando (en la web, los 1400 ms de `hubAsentado`).
class TutorialListo extends StatefulWidget {
  final String id;
  final bool listo;
  final Duration asentar;
  final Widget child;

  const TutorialListo({
    super.key,
    required this.id,
    required this.listo,
    this.asentar = const Duration(milliseconds: 1400),
    required this.child,
  });

  @override
  State<TutorialListo> createState() => _TutorialListoState();
}

class _TutorialListoState extends State<TutorialListo> {
  Tutoriales? _ctrl;
  Timer? _espera;
  bool _declarado = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ctrl = context.read<Tutoriales?>();
    _evaluar();
  }

  @override
  void didUpdateWidget(TutorialListo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id && _declarado) _declarar(false, id: oldWidget.id);
    _evaluar();
  }

  void _evaluar() {
    final aLaVista = TickerMode.valuesOf(context).enabled && (ModalRoute.of(context)?.isCurrent ?? true);
    final quiere = widget.listo && aLaVista && _ctrl != null;
    if (quiere) {
      if (_declarado || _espera != null) return;
      _espera = Timer(widget.asentar, () {
        _espera = null;
        if (mounted) _declarar(true);
      });
    } else {
      _espera?.cancel();
      _espera = null;
      if (_declarado) _declarar(false);
    }
  }

  void _declarar(bool valor, {String? id}) {
    _declarado = valor;
    _ctrl?.declararListo(id ?? widget.id, valor);
  }

  @override
  void dispose() {
    _espera?.cancel();
    if (_declarado) _ctrl?.declararListo(widget.id, false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
