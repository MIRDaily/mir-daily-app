// Los dos lienzos del Explorador. Puerto de la web: src/lib/electros/render.ts y
// src/components/electros/EcgCanvases.tsx. Papel: 25 mm/s, 10 mm/mV, cuadrícula de 1 y 5 mm.
//
// - `MonitorEcg`: el monitor de cabecera, que barre una derivación en tiempo real.
//   En la web el trazo se va pintando sobre un canvas que no se borra. Aquí cada fotograma se dibuja
//   entero a partir del tiempo simulado: en cada columna, la muestra más reciente que cayó en ella,
//   con el hueco borrado justo delante del cabezal. Se ve igual y no necesita un lienzo que recuerde.
// - `DoceDerivacionesEcg`: el ECG completo en formato de impresión, 4×3 con las columnas consecutivas
//   en el tiempo, más la tira de ritmo de 10 s.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../core/models/ecg_core.dart';

const Color _papel = Color(0xFFFFF7F4);
const Color _fina = Color(0x38D4978C); // rgba(212,151,140,0.22)
const Color _gruesa = Color(0x85D4978C); // rgba(212,151,140,0.52)
const Color tintaEcg = Color(0xFF1C1512);

const double _mmPorSegundo = 25;
const double _mmPorMv = 10;

void _pintarCuadricula(Canvas canvas, Size size, double mm) {
  canvas.drawRect(Offset.zero & size, Paint()..color = _papel);
  if (mm <= 0) return;
  void lineas(double paso, Paint p) {
    final path = Path();
    for (double x = 0; x <= size.width; x += paso) {
      path
        ..moveTo(x, 0)
        ..lineTo(x, size.height);
    }
    for (double y = 0; y <= size.height; y += paso) {
      path
        ..moveTo(0, y)
        ..lineTo(size.width, y);
    }
    canvas.drawPath(path, p);
  }

  lineas(mm, Paint()
    ..color = _fina
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1);
  lineas(mm * 5, Paint()
    ..color = _gruesa
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.3);
}

Paint _trazo(double ancho, [Color color = tintaEcg]) => Paint()
  ..color = color
  ..style = PaintingStyle.stroke
  ..strokeWidth = ancho
  ..strokeJoin = StrokeJoin.round
  ..strokeCap = StrokeCap.round;

/* ════════════════════════════════════════════════════════════════════════
   Monitor de barrido
═══════════════════════════════════════════════════════════════════════════ */

class _CuadriculaPainter extends CustomPainter {
  final double mm;
  const _CuadriculaPainter(this.mm);

  @override
  void paint(Canvas canvas, Size size) => _pintarCuadricula(canvas, size, mm);

  @override
  bool shouldRepaint(_CuadriculaPainter old) => old.mm != mm;
}

/// El trazo del monitor en el instante [tSim]: lo que se ha barrido desde [tInicio] (al cambiar de
/// derivación o de patrón el trazo empieza limpio, como en la web).
class MonitorTrazoPainter extends CustomPainter {
  final Float32List buffer;
  final double tSim;
  final double tInicio;
  final double pxPorMm;

  MonitorTrazoPainter({required this.buffer, required this.tSim, required this.tInicio, this.pxPorMm = 6});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    if (w <= 0) return;
    final pxPorSegundo = _mmPorSegundo * pxPorMm;
    final borrado = pxPorMm * 3; // el borrador justo delante del cabezal
    double y(double mv) => size.height / 2 - mv * _mmPorMv * pxPorMm;

    // De la muestra más nueva (en el cabezal) hacia atrás, columna a columna, hasta el borrador.
    final columnas = (w - borrado - 1).floor();
    final path = Path();
    double? xPrevio;
    for (var d = 0; d <= columnas; d++) {
      final t = tSim - d / pxPorSegundo;
      if (t < tInicio) break;
      final x = (t * pxPorSegundo) % w;
      final punto = Offset(x, y(voltajeEn(buffer, t)));
      // Hacia atrás, al cruzar el borde izquierdo la x salta a la derecha: ahí se corta el trazo.
      if (xPrevio == null || x > xPrevio) {
        path.moveTo(punto.dx, punto.dy);
      } else {
        path.lineTo(punto.dx, punto.dy);
      }
      xPrevio = x;
    }
    canvas.drawPath(path, _trazo(1.8));
  }

  @override
  bool shouldRepaint(MonitorTrazoPainter old) =>
      old.tSim != tSim || old.tInicio != tInicio || !identical(old.buffer, buffer) || old.pxPorMm != pxPorMm;
}

/// El monitor de cabecera: barre [derivacion] de [sintesis] a [velocidad] (1 = tiempo real) mientras
/// [enMarcha]. Avisa en [alLatir] cada vez que el cabezal cruza una R.
class MonitorEcg extends StatefulWidget {
  final SintesisEcg sintesis;
  final String derivacion;
  final bool enMarcha;
  final double velocidad;
  final VoidCallback? alLatir;

  const MonitorEcg({
    super.key,
    required this.sintesis,
    required this.derivacion,
    this.enMarcha = true,
    this.velocidad = 1,
    this.alLatir,
  });

  @override
  State<MonitorEcg> createState() => _MonitorEcgState();
}

class _MonitorEcgState extends State<MonitorEcg> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_alTick);
  Duration _previo = Duration.zero;
  double _tSim = 0;
  double _tInicio = 0;
  int? _ultimoLatido;

  @override
  void initState() {
    super.initState();
    if (widget.enMarcha) _ticker.start();
  }

  @override
  void didUpdateWidget(MonitorEcg old) {
    super.didUpdateWidget(old);
    if (!identical(old.sintesis, widget.sintesis)) {
      // Patrón nuevo: el barrido empieza de cero.
      _tSim = 0;
      _tInicio = 0;
      _ultimoLatido = null;
    } else if (old.derivacion != widget.derivacion) {
      // Otra derivación: se limpia el trazo, el tiempo sigue.
      _tInicio = _tSim;
    }
    if (widget.enMarcha && !_ticker.isActive) {
      _previo = Duration.zero;
      _ticker.start();
    } else if (!widget.enMarcha && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _alTick(Duration transcurrido) {
    // Como la web: como mucho 50 ms por fotograma, para que una pausa del sistema no dé un salto.
    final dt = math.min(0.05, (transcurrido - _previo).inMicroseconds / 1e6);
    _previo = transcurrido;
    if (dt <= 0) return;
    final tPrevio = _tSim;
    setState(() => _tSim += dt * widget.velocidad);
    final k = latidoCruzado(widget.sintesis.latidos, tPrevio, _tSim, _ultimoLatido, dur: widget.sintesis.dur);
    if (k != null) {
      _ultimoLatido = k;
      widget.alLatir?.call();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final buffer = widget.sintesis.derivaciones[widget.derivacion]!;
    return Stack(
      fit: StackFit.expand,
      children: [
        const RepaintBoundary(child: CustomPaint(painter: _CuadriculaPainter(6))),
        CustomPaint(painter: MonitorTrazoPainter(buffer: buffer, tSim: _tSim, tInicio: _tInicio)),
      ],
    );
  }
}

/* ════════════════════════════════════════════════════════════════════════
   ECG de 12 derivaciones (formato impresión)
═══════════════════════════════════════════════════════════════════════════ */

const List<List<String>> _rejilla12 = [
  ['I', 'aVR', 'V1', 'V4'],
  ['II', 'aVL', 'V2', 'V5'],
  ['III', 'aVF', 'V3', 'V6'],
];

class DoceDerivacionesPainter extends CustomPainter {
  final SintesisEcg? sintesis;
  final String derivacionRitmo;

  DoceDerivacionesPainter({required this.sintesis, this.derivacionRitmo = 'II'});

  static const double _segundosPanel = 2.5;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (w <= 0 || h <= 0) return;
    const filas = 3;
    const columnas = 4;
    const pad = 8.0;
    final anchoColumna = (w - pad * 2) / columnas;
    final mm = anchoColumna / (_segundosPanel * _mmPorSegundo); // px por mm
    _pintarCuadricula(canvas, size, mm);
    final s = sintesis;
    if (s == null) return;

    const filasTotales = filas + 1;
    final altoFila = (h - pad * 2) / filasTotales;
    final pxPorMv = _mmPorMv * mm;
    final tamEtiqueta = math.max(11.0, mm * 2.4);
    final tinta = _trazo(1.6);

    void etiqueta(String texto, double x, double y) {
      final tp = TextPainter(
        text: TextSpan(
          text: texto,
          style: TextStyle(color: tintaEcg, fontSize: tamEtiqueta, fontWeight: FontWeight.w600, fontFamily: 'Lexend'),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      // fillText de canvas pinta sobre la línea base: se sube lo que mide el texto por encima de ella.
      tp.paint(canvas, Offset(x, y - tp.computeDistanceToActualBaseline(TextBaseline.alphabetic)));
    }

    void panel(String nombre, double x0, double yMid, double ancho, double segundos, double tDesde) {
      final buf = s.derivaciones[nombre]!;
      final px = math.max(2, ancho.ceil());
      final path = Path();
      for (var p = 0; p <= px; p++) {
        final t = tDesde + (p / px) * segundos;
        final x = x0 + (p / px) * ancho;
        final y = yMid - voltajeEn(buf, t, fs: s.fs, dur: s.dur) * pxPorMv;
        if (p == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, tinta);
      etiqueta(nombre, x0 + 4, yMid - altoFila * 0.32);
      // Marca de calibración (10 mm de alto = 1 mV) al inicio del panel.
      final cx = x0 + 2;
      canvas.drawPath(
        Path()
          ..moveTo(cx, yMid)
          ..lineTo(cx, yMid - pxPorMv)
          ..lineTo(cx + mm * 2, yMid - pxPorMv),
        _trazo(1.2, const Color(0x801C1512)),
      );
    }

    // 3×4 paneles: cada columna es una ventana de tiempo distinta, como el ECG real, que registra las
    // columnas en secuencia.
    for (var r = 0; r < filas; r++) {
      final yMid = pad + altoFila * (r + 0.5);
      for (var c = 0; c < columnas; c++) {
        final x0 = pad + c * anchoColumna;
        if (c > 0) {
          canvas.drawLine(
            Offset(x0, pad + altoFila * r + 4),
            Offset(x0, pad + altoFila * (r + 1) - 4),
            Paint()
              ..color = const Color(0x1F1C1512)
              ..strokeWidth = 1,
          );
        }
        panel(_rejilla12[r][c], x0 + 2, yMid, anchoColumna - 6, _segundosPanel, c * _segundosPanel);
      }
    }

    // Tira de ritmo: la fila de abajo, a todo lo ancho, los 10 s.
    final yMid = pad + altoFila * (filas + 0.5);
    final buf = s.derivaciones[derivacionRitmo]!;
    final px = math.max(2, (w - pad * 2).ceil());
    final path = Path();
    for (var p = 0; p <= px; p++) {
      final t = (p / px) * s.dur;
      final i = (t * s.fs).floor();
      final x = pad + (p / px) * (w - pad * 2);
      final y = yMid - (i < buf.length ? buf[i] : 0) * pxPorMv;
      if (p == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, tinta);
    etiqueta('$derivacionRitmo  (tira de ritmo · 10 s)', pad + 4, yMid - altoFila * 0.34);
  }

  @override
  bool shouldRepaint(DoceDerivacionesPainter old) =>
      !identical(old.sintesis, sintesis) || old.derivacionRitmo != derivacionRitmo;
}

/// El ECG de 12 derivaciones. En pantallas estrechas se dibuja a un ancho mínimo legible y se desliza
/// en horizontal: con los 360 px de un móvil, cada panel de 2,5 s se quedaba en 1,4 px por milímetro.
class DoceDerivacionesEcg extends StatelessWidget {
  final SintesisEcg sintesis;
  final String derivacionRitmo;

  static const double anchoMinimo = 640;

  const DoceDerivacionesEcg({super.key, required this.sintesis, this.derivacionRitmo = 'II'});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final ancho = math.max(c.maxWidth, anchoMinimo);
      // Proporción de la web (≈ 480 de alto a 900-1000 de ancho), con suelo para no aplastar las filas.
      final alto = (ancho * 0.5).clamp(340.0, 520.0);
      final lienzo = RepaintBoundary(
        child: SizedBox(
          width: ancho,
          height: alto,
          child: CustomPaint(painter: DoceDerivacionesPainter(sintesis: sintesis, derivacionRitmo: derivacionRitmo)),
        ),
      );
      if (ancho <= c.maxWidth) return lienzo;
      return SingleChildScrollView(scrollDirection: Axis.horizontal, child: lienzo);
    });
  }
}
