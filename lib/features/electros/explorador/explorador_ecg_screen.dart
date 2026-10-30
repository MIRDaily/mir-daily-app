// El Explorador de 12 derivaciones, nativo. Puerto de la web: src/components/electros/ExploradorClient.tsx
// (/studio/electros/explorador). Sustituye al simulador antiguo, que era un HTML dentro de un WebView.
//
// Dos modos:
//  - Explorador clínico: elegir un diagnóstico y verlo en el monitor de cabecera (cualquiera de las 12
//    derivaciones, pausa, 0,5/1/2×, pitido con cada QRS), en el ECG completo 4×3 con tira de ritmo y
//    en su ficha (resumen, claves y perla MIR).
//  - Modo examen: 10 ECG al azar; se escribe el diagnóstico (con sinónimos y siglas) y se corrige.
//    Como en la web, NO cuenta para las estadísticas: esas salen solo del banco de preguntas MIR.
//
// La síntesis (10 s a 500 Hz × 12 derivaciones) se calcula una vez por patrón y se guarda.

import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../../../core/audio/audio_nativo.dart';
import '../../../core/models/ecg_core.dart';
import '../../../core/models/ecg_patrones.dart';
import '../../../core/responsive/adaptive_modal.dart';
import '../../../core/responsive/breakpoints.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/sticker/sticker.dart';
import 'ecg_lienzos.dart';

const Map<GravedadEcg, Color> colorGravedad = {
  GravedadEcg.normal: Color(0xFF8BA888),
  GravedadEcg.warn: Color(0xFFC9A24A),
  GravedadEcg.crit: Color(0xFFC4655A),
};

const Map<GravedadEcg, String> _textoGravedad = {
  GravedadEcg.normal: 'Benigno',
  GravedadEcg.warn: 'Requiere manejo',
  GravedadEcg.crit: 'Grave / urgente',
};

const Color _monitorFondo = Color(0xFF241C1A);
const List<double> _velocidades = [0.5, 1, 2];

final Map<String, SintesisEcg> _cacheSintesis = {};
SintesisEcg sintesisDe(PatronEcg p) => _cacheSintesis.putIfAbsent(p.id, () => sintetizar(p));

/// Un pitido corto con cada QRS, como el de un monitor de verdad (el mismo de la web: 880 Hz, 90 ms).
class _Pitido {
  AudioPlayer? _player;

  Future<void> sonar() async {
    if (!audioNativoDisponible) return;
    try {
      var p = _player;
      if (p == null) {
        p = _player = AudioPlayer();
        await p.setPlayerMode(PlayerMode.lowLatency);
      }
      await p.stop();
      await p.play(AssetSource('audio/pitido_monitor.wav'), volume: 1);
    } catch (_) {
      // Sin audio disponible: el monitor sigue en silencio.
    }
  }

  void dispose() {
    try {
      _player?.dispose();
    } catch (_) {}
  }
}

enum _Modo { explorador, examen }

class ExploradorEcgScreen extends StatefulWidget {
  /// Para los tests: la tanda del examen sale de este azar.
  final math.Random? azar;

  /// Abre directamente el modo examen (el acceso «Ponte a prueba» del menú de Electros).
  final bool empezarEnExamen;

  const ExploradorEcgScreen({super.key, this.azar, this.empezarEnExamen = false});

  @override
  State<ExploradorEcgScreen> createState() => _ExploradorEcgScreenState();
}

class _ExploradorEcgScreenState extends State<ExploradorEcgScreen> {
  late _Modo _modo = widget.empezarEnExamen ? _Modo.examen : _Modo.explorador;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Explorador ECG')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(context.bodyGutter, 8, context.bodyGutter, 40),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1180),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Explorador de 12 derivaciones',
                      style: TextStyle(color: kInk, fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -0.5, height: 1.15),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${patronesEcg.length} diagnósticos sintetizados en tiempo real · 25 mm/s · 10 mm/mV',
                      style: const TextStyle(color: kMuted, fontSize: 13.5, height: 1.4),
                    ),
                    const SizedBox(height: 14),
                    _SelectorModo(modo: _modo, onCambiar: (m) => setState(() => _modo = m)),
                    const SizedBox(height: 18),
                    if (_modo == _Modo.explorador) const _ModoExplorador() else _ModoExamen(azar: widget.azar),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectorModo extends StatelessWidget {
  final _Modo modo;
  final ValueChanged<_Modo> onCambiar;

  const _SelectorModo({required this.modo, required this.onCambiar});

  @override
  Widget build(BuildContext context) {
    Widget pestana(_Modo m, IconData icono, String texto) {
      final activo = modo == m;
      return Expanded(
        child: Semantics(
          selected: activo,
          button: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onCambiar(m),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: activo ? kAccent : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icono, size: 18, color: activo ? Colors.white : kMuted),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      texto,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: activo ? Colors.white : kMuted, fontWeight: FontWeight.w700, fontSize: 13.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kInk, width: 2),
        boxShadow: inkShadow(3),
      ),
      child: Row(
        children: [
          pestana(_Modo.explorador, Icons.monitor_heart_rounded, 'Explorador clínico'),
          pestana(_Modo.examen, Icons.quiz_rounded, 'Modo examen'),
        ],
      ),
    );
  }
}

/* ════════════════════════════════════════════════════════════════════════
   MODO EXPLORADOR
═══════════════════════════════════════════════════════════════════════════ */

class _ModoExplorador extends StatefulWidget {
  const _ModoExplorador();

  @override
  State<_ModoExplorador> createState() => _ModoExploradorState();
}

class _ModoExploradorState extends State<_ModoExplorador> {
  PatronEcg _patron = patronesEcg.first;
  String _derivacion = 'II';
  bool _enMarcha = true;
  double _velocidad = 1;
  // Activado de serie, como un monitor de verdad: el pitido es media gracia del explorador.
  bool _sonido = true;
  final ValueNotifier<int> _latidos = ValueNotifier(0);
  final _Pitido _pitido = _Pitido();

  void _alLatir() {
    _latidos.value++;
    if (_sonido) _pitido.sonar();
  }

  void _elegir(PatronEcg p) => setState(() => _patron = p);

  Future<void> _abrirSelector() async {
    final elegido = await showAdaptiveModal<PatronEcg>(
      context: context,
      dialogScrollable: false,
      builder: (ctx) => SizedBox(
        height: MediaQuery.sizeOf(ctx).height * 0.78,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 4),
              child: Text('Elige un diagnóstico', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 19, color: kInk)),
            ),
            const Padding(padding: EdgeInsets.fromLTRB(20, 4, 20, 8), child: LeyendaGravedad()),
            Expanded(
              child: ListaPatrones(
                activo: _patron.id,
                onElegir: (p) => Navigator.of(ctx).pop(p),
              ),
            ),
          ],
        ),
      ),
    );
    if (elegido != null && mounted) _elegir(elegido);
  }

  @override
  void dispose() {
    _latidos.dispose();
    _pitido.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sintesis = sintesisDe(_patron);
    final dosPaneles = context.usesTwoPane;

    final contenido = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!dosPaneles) ...[
          _BotonPatron(patron: _patron, onTap: _abrirSelector),
          const SizedBox(height: 14),
        ],
        _Monitor(
          patron: _patron,
          sintesis: sintesis,
          derivacion: _derivacion,
          enMarcha: _enMarcha,
          velocidad: _velocidad,
          sonido: _sonido,
          latidos: _latidos,
          alto: context.isWide ? 250 : 210,
          onDerivacion: (d) => setState(() => _derivacion = d),
          onPausa: () => setState(() => _enMarcha = !_enMarcha),
          onVelocidad: (v) => setState(() => _velocidad = v),
          onSonido: () => setState(() => _sonido = !_sonido),
          alLatir: _alLatir,
        ),
        const SizedBox(height: 16),
        _TarjetaDoce(
          titulo: 'ECG de 12 derivaciones',
          icono: Icons.grid_on_rounded,
          nota: '4×3 + tira de ritmo · 25 mm/s · 10 mm/mV',
          child: DoceDerivacionesEcg(sintesis: sintesis, derivacionRitmo: _derivacion),
        ),
        const SizedBox(height: 16),
        AnimatedSwitcher(
          duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 240),
          child: FichaPatron(key: ValueKey(_patron.id), patron: _patron),
        ),
      ],
    );

    if (!dosPaneles) return contenido;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 290,
          child: Column(
            children: [
              const LeyendaGravedad(),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: kHairline),
                ),
                clipBehavior: Clip.antiAlias,
                child: ListaPatrones(activo: _patron.id, onElegir: _elegir, enLinea: true),
              ),
            ],
          ),
        ),
        const SizedBox(width: 20),
        Expanded(child: contenido),
      ],
    );
  }
}

/// Qué significa cada color de los puntos: sin esto no dicen nada.
class LeyendaGravedad extends StatelessWidget {
  const LeyendaGravedad({super.key});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      children: [
        for (final g in GravedadEcg.values)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Punto(color: colorGravedad[g]!),
              const SizedBox(width: 5),
              Text(_textoGravedad[g]!, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: kMuted)),
            ],
          ),
      ],
    );
  }
}

class _Punto extends StatelessWidget {
  final Color color;
  final double tam;
  const _Punto({required this.color, this.tam = 8});

  @override
  Widget build(BuildContext context) =>
      Container(width: tam, height: tam, decoration: BoxDecoration(color: color, shape: BoxShape.circle));
}

class _Sigla extends StatelessWidget {
  final String texto;
  const _Sigla(this.texto);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: const Color(0xFFF2EFED), borderRadius: BorderRadius.circular(5)),
        child: Text(texto, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: kMuted)),
      );
}

/// Los diagnósticos por categoría (el raíl de la web).
class ListaPatrones extends StatelessWidget {
  final String activo;
  final ValueChanged<PatronEcg> onElegir;

  /// Sin scroll propio: en tablet va dentro de la página, que ya hace scroll (dos scrolls anidados
  /// se pelean por el dedo).
  final bool enLinea;

  const ListaPatrones({super.key, required this.activo, required this.onElegir, this.enLinea = false});

  @override
  Widget build(BuildContext context) {
    final hijos = <Widget>[];
    for (final categoria in categoriasEcg) {
      final items = patronesEcg.where((p) => p.categoria == categoria).toList();
      if (items.isEmpty) continue;
      hijos.add(Padding(
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 4),
        child: Text(
          categoria.toUpperCase(),
          style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, letterSpacing: 1, color: Color(0xFFA6AFB8)),
        ),
      ));
      for (final p in items) {
        final esActivo = p.id == activo;
        hijos.add(Material(
          color: esActivo ? const Color(0xFFFFF5F3) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => onElegir(p),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              child: Row(
                children: [
                  _Punto(color: colorGravedad[p.gravedad]!),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      p.nombre,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: esActivo ? FontWeight.w800 : FontWeight.w500,
                        color: esActivo ? kInk : kMuted,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  _Sigla(p.sigla),
                ],
              ),
            ),
          ),
        ));
      }
    }
    const padding = EdgeInsets.fromLTRB(6, 0, 6, 12);
    if (enLinea) {
      return Padding(padding: padding, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: hijos));
    }
    return ListView(padding: padding, children: hijos);
  }
}

/// En el móvil, el diagnóstico elegido; al tocarlo se abre la lista.
class _BotonPatron extends StatelessWidget {
  final PatronEcg patron;
  final VoidCallback onTap;

  const _BotonPatron({required this.patron, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return StickerCard(
      depth: 4,
      radius: 18,
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      child: Row(
        children: [
          _Punto(color: colorGravedad[patron.gravedad]!, tam: 10),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(patron.categoria.toUpperCase(),
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1, color: kMuted)),
                const SizedBox(height: 2),
                Text(patron.nombre,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: kInk)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Text('Cambiar', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.primaryDark)),
          const Icon(Icons.expand_more_rounded, color: AppColors.primaryDark),
        ],
      ),
    );
  }
}

class _Monitor extends StatelessWidget {
  final PatronEcg patron;
  final SintesisEcg sintesis;
  final String derivacion;
  final bool enMarcha;
  final double velocidad;
  final bool sonido;
  final ValueNotifier<int> latidos;
  final double alto;
  final ValueChanged<String> onDerivacion;
  final VoidCallback onPausa;
  final ValueChanged<double> onVelocidad;
  final VoidCallback onSonido;
  final VoidCallback alLatir;

  const _Monitor({
    required this.patron,
    required this.sintesis,
    required this.derivacion,
    required this.enMarcha,
    required this.velocidad,
    required this.sonido,
    required this.latidos,
    required this.alto,
    required this.onDerivacion,
    required this.onPausa,
    required this.onVelocidad,
    required this.onSonido,
    required this.alLatir,
  });

  Widget _chip(String texto, {required bool activo, required VoidCallback onTap}) => Semantics(
        button: true,
        selected: activo,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            decoration: BoxDecoration(
              color: activo ? kAccent : Colors.white.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text(
              texto,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: activo ? _monitorFondo : Colors.white.withValues(alpha: 0.75),
              ),
            ),
          ),
        ),
      );

  Widget _boton(IconData icono, String etiqueta, VoidCallback onTap, {bool activo = false}) => Semantics(
        button: true,
        label: etiqueta,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: activo ? kAccent : Colors.white.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icono, size: 20, color: activo ? _monitorFondo : Colors.white),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final reducido = MediaQuery.disableAnimationsOf(context);
    return Container(
      decoration: BoxDecoration(
        color: _monitorFondo,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kInk, width: 2),
        boxShadow: inkShadow(4),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      for (final d in ordenDerivaciones)
                        _chip(d, activo: d == derivacion, onTap: () => onDerivacion(d)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                ValueListenableBuilder<int>(
                  valueListenable: latidos,
                  builder: (_, n, __) => TweenAnimationBuilder<double>(
                    key: ValueKey(n),
                    tween: Tween(begin: reducido || n == 0 ? 1 : 1.35, end: 1),
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeOut,
                    builder: (_, e, child) => Transform.scale(scale: e, child: child),
                    child: const Icon(Icons.favorite_rounded, color: kAccent, size: 22),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  patron.fc > 0 ? '${patron.fc}' : '--',
                  style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900, height: 1),
                ),
                const Padding(
                  padding: EdgeInsets.only(left: 3, top: 9),
                  child: Text('lpm', style: TextStyle(color: Color(0x80FFFFFF), fontSize: 11, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 8),
                _boton(
                  sonido ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                  sonido ? 'Silenciar' : 'Activar sonido',
                  onSonido,
                  activo: sonido,
                ),
              ],
            ),
          ),
          SizedBox(
            height: alto,
            child: MonitorEcg(
              sintesis: sintesis,
              derivacion: derivacion,
              enMarcha: enMarcha,
              velocidad: velocidad,
              alLatir: alLatir,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _boton(enMarcha ? Icons.pause_rounded : Icons.play_arrow_rounded, enMarcha ? 'Pausa' : 'Reanudar', onPausa),
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final v in _velocidades)
                        _chip('${v == v.roundToDouble() ? v.toInt() : v}×'.replaceAll('.', ','),
                            activo: v == velocidad, onTap: () => onVelocidad(v)),
                    ],
                  ),
                ),
                for (final i in patron.intervalos)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(text: '${i.clave.toUpperCase()} '),
                        TextSpan(text: i.valor, style: const TextStyle(color: Color(0xE6FFFFFF), fontWeight: FontWeight.w800)),
                      ]),
                      style: const TextStyle(color: Color(0x80FFFFFF), fontSize: 11, fontWeight: FontWeight.w500),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TarjetaDoce extends StatelessWidget {
  final String titulo;
  final IconData icono;
  final String nota;
  final Widget child;

  const _TarjetaDoce({required this.titulo, required this.icono, required this.nota, required this.child});

  @override
  Widget build(BuildContext context) {
    final estrecho = MediaQuery.sizeOf(context).width < DoceDerivacionesEcg.anchoMinimo + 40;
    return StickerCard(
      depth: 4,
      radius: 18,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            child: Wrap(
              spacing: 8,
              runSpacing: 2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Icon(icono, size: 18, color: kAccent),
                Text(titulo, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: kInk)),
                Text(estrecho ? '$nota · desliza para ver más' : nota, style: const TextStyle(fontSize: 11, color: kMuted)),
              ],
            ),
          ),
          const Divider(height: 1, color: kHairline),
          child,
        ],
      ),
    );
  }
}

/// La ficha clínica de un diagnóstico.
class FichaPatron extends StatelessWidget {
  final PatronEcg patron;
  const FichaPatron({super.key, required this.patron});

  @override
  Widget build(BuildContext context) {
    return StickerCard(
      depth: 4,
      radius: 18,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _Punto(color: colorGravedad[patron.gravedad]!, tam: 10),
              Text(patron.nombre, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: kInk)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: kAccent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: kAccent.withValues(alpha: 0.25)),
                ),
                child: Text(patron.sigla,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFFD18D80))),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(patron.resumen, style: const TextStyle(fontSize: 14, color: kMuted, height: 1.45)),
          const SizedBox(height: 14),
          const SectionLabel('Claves en el ECG'),
          const SizedBox(height: 8),
          for (final c in patron.claves)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(padding: EdgeInsets.only(top: 7, right: 9), child: _Punto(color: kAccent, tam: 6)),
                  Expanded(child: Text(c, style: const TextStyle(fontSize: 14, color: kMuted, height: 1.4))),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF5F3),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: kAccent.withValues(alpha: 0.2)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.lightbulb_rounded, color: kAccent, size: 20),
                const SizedBox(width: 9),
                Expanded(child: Text(patron.perla, style: const TextStyle(fontSize: 14, color: kInk, height: 1.45))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/* ════════════════════════════════════════════════════════════════════════
   MODO EXAMEN
═══════════════════════════════════════════════════════════════════════════ */

class _ModoExamen extends StatefulWidget {
  final math.Random? azar;
  const _ModoExamen({this.azar});

  @override
  State<_ModoExamen> createState() => _ModoExamenState();
}

class _ModoExamenState extends State<_ModoExamen> {
  late final math.Random _azar = widget.azar ?? math.Random();
  late List<PatronEcg> _tanda = barajarExamen(patronesEcg, _azar);
  int _indice = 0;
  int _aciertos = 0;
  PatronEcg? _respuesta;
  bool _terminado = false;

  PatronEcg get _actual => _tanda[_indice];

  void _reiniciar() => setState(() {
        _tanda = barajarExamen(patronesEcg, _azar);
        _indice = 0;
        _aciertos = 0;
        _respuesta = null;
        _terminado = false;
      });

  void _responder(PatronEcg elegido) {
    if (_respuesta != null) return;
    setState(() {
      _respuesta = elegido;
      if (elegido.id == _actual.id) _aciertos++;
    });
  }

  void _siguiente() => setState(() {
        if (_indice >= largoExamenEcg - 1) {
          _terminado = true;
          return;
        }
        _indice++;
        _respuesta = null;
      });

  @override
  Widget build(BuildContext context) {
    if (_terminado) return _ResultadoExamen(aciertos: _aciertos, onRepetir: _reiniciar);
    final respuesta = _respuesta;
    final correcto = respuesta?.id == _actual.id;
    final progreso = (_indice + (respuesta != null ? 1 : 0)) / largoExamenEcg;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(end: progreso),
                  duration: const Duration(milliseconds: 350),
                  curve: kEaseOut,
                  builder: (_, v, __) => LinearProgressIndicator(
                    value: v,
                    minHeight: 6,
                    backgroundColor: kHairline,
                    color: kAccent,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text('${_indice + 1} / $largoExamenEcg',
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: kMuted)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: const Color(0xFFFFF5F3), borderRadius: BorderRadius.circular(8)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.star_rounded, size: 15, color: Color(0xFFD18D80)),
                  const SizedBox(width: 3),
                  Text('$_aciertos',
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: Color(0xFFD18D80))),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _TarjetaDoce(
          titulo: '¿Qué diagnóstico ves?',
          icono: Icons.monitor_heart_rounded,
          nota: _actual.fc > 0 ? 'FC ${_actual.fc} lpm' : 'FC —',
          child: DoceDerivacionesEcg(sintesis: sintesisDe(_actual)),
        ),
        const SizedBox(height: 14),
        if (respuesta != null)
          _Correccion(
            actual: _actual,
            respuesta: respuesta,
            correcto: correcto,
            ultimo: _indice >= largoExamenEcg - 1,
            onSiguiente: _siguiente,
          )
        else
          _BuscadorDiagnostico(key: ValueKey(_indice), onResponder: _responder),
      ],
    );
  }
}

class _BuscadorDiagnostico extends StatefulWidget {
  final ValueChanged<PatronEcg> onResponder;
  const _BuscadorDiagnostico({super.key, required this.onResponder});

  @override
  State<_BuscadorDiagnostico> createState() => _BuscadorDiagnosticoState();
}

class _BuscadorDiagnosticoState extends State<_BuscadorDiagnostico> {
  final TextEditingController _texto = TextEditingController();
  PatronEcg? _elegido;

  List<PatronEcg> get _sugerencias => _elegido != null ? const [] : buscarPatrones(_texto.text, patronesEcg);

  void _cambiar(String v) => setState(() {
        // Escribir el nombre completo a mano también vale como elección.
        _elegido = patronPorNombreExacto(v, patronesEcg);
      });

  void _escoger(PatronEcg p) {
    _texto.value = TextEditingValue(text: p.nombre, selection: TextSelection.collapsed(offset: p.nombre.length));
    setState(() => _elegido = p);
  }

  void _enviar() {
    final e = _elegido;
    if (e != null) {
      widget.onResponder(e);
      return;
    }
    final s = _sugerencias;
    if (s.length == 1) _escoger(s.first);
  }

  @override
  void dispose() {
    _texto.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sugerencias = _sugerencias;
    return StickerCard(
      depth: 4,
      radius: 18,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Escribe tu diagnóstico', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: kInk)),
          const SizedBox(height: 8),
          TextField(
            controller: _texto,
            onChanged: _cambiar,
            onSubmitted: (_) => _enviar(),
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              hintText: 'p. ej. STEMI inferior, BRD, FA…',
              prefixIcon: const Icon(Icons.edit_note_rounded, color: kAccent),
              suffixIcon: _texto.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Borrar',
                      icon: const Icon(Icons.close_rounded, color: kMuted),
                      onPressed: () => setState(() {
                        _texto.clear();
                        _elegido = null;
                      }),
                    ),
              filled: true,
              fillColor: AppColors.background,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: kHairline)),
              enabledBorder:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: kHairline)),
              focusedBorder:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: kAccent, width: 1.5)),
            ),
          ),
          if (sugerencias.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: kHairline),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (final p in sugerencias)
                    InkWell(
                      onTap: () => _escoger(p),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                        child: Row(
                          children: [
                            _Punto(color: colorGravedad[p.gravedad]!),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(p.nombre,
                                  overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, color: kInk)),
                            ),
                            const SizedBox(width: 6),
                            _Sigla(p.sigla),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          StickerButton(
            label: 'Confirmar diagnóstico',
            icon: Icons.check_rounded,
            expand: true,
            onPressed: _elegido == null ? null : _enviar,
          ),
        ],
      ),
    );
  }
}

class _Correccion extends StatelessWidget {
  final PatronEcg actual;
  final PatronEcg respuesta;
  final bool correcto;
  final bool ultimo;
  final VoidCallback onSiguiente;

  const _Correccion({
    required this.actual,
    required this.respuesta,
    required this.correcto,
    required this.ultimo,
    required this.onSiguiente,
  });

  @override
  Widget build(BuildContext context) {
    final color = correcto ? const Color(0xFF6A8A67) : AppColors.error;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: correcto ? const Color(0xFFF1F5F0) : const Color(0xFFFDF2F0),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: (correcto ? AppColors.success : AppColors.error).withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(correcto ? Icons.check_circle_rounded : Icons.cancel_rounded, color: color),
              const SizedBox(width: 6),
              Text(correcto ? '¡Correcto!' : 'Incorrecto',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: color)),
            ],
          ),
          if (!correcto) ...[
            const SizedBox(height: 6),
            Text.rich(
              TextSpan(children: [
                const TextSpan(text: 'Tu respuesta: '),
                TextSpan(text: respuesta.nombre, style: const TextStyle(fontWeight: FontWeight.w800)),
              ]),
              style: const TextStyle(fontSize: 14, color: kMuted),
            ),
          ],
          const SizedBox(height: 6),
          Text.rich(
            TextSpan(children: [
              TextSpan(text: '${actual.nombre}. ', style: const TextStyle(fontWeight: FontWeight.w800)),
              TextSpan(text: actual.perla),
            ]),
            style: const TextStyle(fontSize: 14, color: kInk, height: 1.45),
          ),
          const SizedBox(height: 14),
          StickerButton(
            label: ultimo ? 'Ver resultados' : 'Siguiente',
            icon: Icons.arrow_forward_rounded,
            onPressed: onSiguiente,
          ),
        ],
      ),
    );
  }
}

class _ResultadoExamen extends StatelessWidget {
  final int aciertos;
  final VoidCallback onRepetir;

  const _ResultadoExamen({required this.aciertos, required this.onRepetir});

  @override
  Widget build(BuildContext context) {
    final r = resultadoExamen(aciertos);
    final pct = (aciertos / largoExamenEcg * 100).round();
    final color = colorGravedad[r.tono]!;
    return StickerCard(
      depth: 5,
      radius: 22,
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
      child: Column(
        children: [
          Text(r.emoji, style: const TextStyle(fontSize: 44)),
          const SizedBox(height: 8),
          const Text('Examen completado', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: kInk)),
          const SizedBox(height: 16),
          SizedBox(
            width: 128,
            height: 128,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: pct / 100),
              duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 900),
              curve: Curves.easeOut,
              builder: (_, v, __) => CustomPaint(
                painter: _AnilloPainter(fraccion: v, color: color),
                child: Center(
                  child: Text('$pct%', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: kInk)),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Text(r.mensaje, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: kMuted, height: 1.45)),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: [
              StickerButton(label: 'Repetir examen', icon: Icons.replay_rounded, onPressed: onRepetir),
              GhostButton(label: 'Volver a Electros', onPressed: () => Navigator.of(context).maybePop()),
            ],
          ),
        ],
      ),
    );
  }
}

class _AnilloPainter extends CustomPainter {
  final double fraccion;
  final Color color;
  _AnilloPainter({required this.fraccion, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final r = rect.deflate(size.width * 0.06 + 4);
    final grosor = size.width * 0.08;
    canvas.drawArc(r, 0, math.pi * 2, false, Paint()
      ..color = const Color(0xFFEDE9E4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = grosor);
    if (fraccion <= 0) return;
    canvas.drawArc(r, -math.pi / 2, math.pi * 2 * fraccion, false, Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = grosor);
  }

  @override
  bool shouldRepaint(_AnilloPainter old) => old.fraccion != fraccion || old.color != color;
}
