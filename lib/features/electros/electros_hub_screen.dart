import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/models/ecg_core.dart';
import '../../core/models/ecg_patrones.dart';
import '../../core/responsive/breakpoints.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/sticker/sticker.dart';
import '../../shared/sticker/textures.dart';
import 'electro_web_view.dart';
import 'explorador/ecg_lienzos.dart';
import 'explorador/explorador_ecg_screen.dart';

/// Menú de Electros dentro de Studio. Arriba, un monitor vivo que va cambiando de ritmo (es lo que
/// se aprende aquí, a la vista desde el primer segundo). Debajo, el camino en dos pasos:
///  1. APRENDE — la Academia (ruta guiada, web embebida).
///  2. PRACTICA — el Explorador de 12 derivaciones (nativo), con acceso directo al modo examen.
/// Al terminar la ruta, la Academia también lleva al Explorador.
class ElectrosHubScreen extends StatelessWidget {
  const ElectrosHubScreen({super.key});

  static const Color _rosa = Color(0xFFD4978C);
  static const Color _verde = Color(0xFF6E8E6B);

  void _openExplorador(BuildContext context, {bool examen = false}) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ExploradorEcgScreen(empezarEnExamen: examen),
    ));
  }

  void _openAcademia(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ElectroWebView(
        title: 'Academia ECG',
        assetPrefix: 'assets/electros/academia',
        onOpenSimulador: () => _openExplorador(context),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final dosColumnas = context.usesTwoPane;
    final academia = _TarjetaPaso(
      numero: 1,
      etiqueta: 'APRENDE',
      color: _rosa,
      icono: Icons.school_rounded,
      titulo: 'Academia ECG',
      texto: 'De la chispa eléctrica del corazón a los algoritmos diagnósticos, paso a paso y con '
          'animaciones que se tocan.',
      datos: const ['9 módulos', 'Compás y eje interactivos', 'Algoritmos MIR'],
      onTap: () => _openAcademia(context),
      acciones: [
        StickerButton(
          label: 'Empezar la ruta',
          icon: Icons.arrow_forward_rounded,
          color: _rosa,
          expand: true,
          onPressed: () => _openAcademia(context),
        ),
      ],
    );
    final explorador = _TarjetaPaso(
      numero: 2,
      etiqueta: 'PRACTICA',
      color: _verde,
      icono: Icons.monitor_heart_rounded,
      titulo: 'Explorador de 12 derivaciones',
      texto: 'Monitor en tiempo real y ECG completo de los diagnósticos clave del MIR, con su ficha '
          'clínica y perla.',
      datos: ['${patronesEcg.length} diagnósticos', '12 derivaciones', 'Examen de 10 ECG'],
      onTap: () => _openExplorador(context),
      acciones: [
        StickerButton(
          label: 'Explorar',
          icon: Icons.travel_explore_rounded,
          color: _verde,
          expand: true,
          onPressed: () => _openExplorador(context),
        ),
        GhostButton(
          label: 'Ponte a prueba',
          icon: Icons.quiz_rounded,
          expand: true,
          onPressed: () => _openExplorador(context, examen: true),
        ),
      ],
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Electros')),
      body: SafeArea(
        top: false,
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(context.bodyGutter, 8, context.bodyGutter, 40),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 980),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Electrocardiografía',
                      style: TextStyle(
                        color: kInk,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Primero entiende de dónde sale cada onda; luego entrena el ojo con trazos reales.',
                      style: TextStyle(color: kMuted, fontSize: 13.5, height: 1.4),
                    ),
                    const SizedBox(height: 16),
                    const _MonitorPortada(),
                    const SizedBox(height: 22),
                    if (dosColumnas)
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: academia),
                            const SizedBox(width: 20),
                            Expanded(child: explorador),
                          ],
                        ),
                      )
                    else ...[
                      academia,
                      const SizedBox(height: 18),
                      explorador,
                    ],
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

/* ════════════════════════════════════════════════════════════════════════
   Monitor de portada
═══════════════════════════════════════════════════════════════════════════ */

/// Un monitor que barre la derivación II y cambia de ritmo cada pocos segundos, con su nombre y la
/// FC. Sin sonido: aquí solo se mira. Tocarlo pasa al siguiente ritmo.
class _MonitorPortada extends StatefulWidget {
  const _MonitorPortada();

  @override
  State<_MonitorPortada> createState() => _MonitorPortadaState();
}

class _MonitorPortadaState extends State<_MonitorPortada> {
  /// Una muestra variada y reconocible: lo normal, lo rápido, lo lento y lo que hay que ver ya.
  static const List<String> _ritmos = ['sinus', 'afib', 'stemi_inf', 'aflutter', 'avb3', 'vtach'];
  static const Duration _cadaCuanto = Duration(seconds: 8);

  int _i = 0;
  Timer? _timer;
  final ValueNotifier<int> _latidos = ValueNotifier(0);

  PatronEcg get _patron => patronesEcg.firstWhere((p) => p.id == _ritmos[_i]);

  @override
  void initState() {
    super.initState();
    _programar();
  }

  void _programar() {
    _timer?.cancel();
    _timer = Timer.periodic(_cadaCuanto, (_) => _siguiente());
  }

  void _siguiente() {
    if (!mounted) return;
    setState(() => _i = (_i + 1) % _ritmos.length);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _latidos.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = _patron;
    final color = switch (p.gravedad) {
      GravedadEcg.normal => const Color(0xFF6E8E6B),
      GravedadEcg.warn => const Color(0xFFC8963E),
      GravedadEcg.crit => const Color(0xFFC0564B),
    };
    return Semantics(
      button: true,
      label: 'Monitor de ejemplo: ${p.nombre}. Toca para ver otro ritmo.',
      child: StickerCard(
        radius: 22,
        clipBehavior: Clip.antiAlias,
        onTap: () {
          _siguiente();
          _programar();
        },
        child: SizedBox(
          height: context.usesTwoPane ? 170 : 132,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ExcludeSemantics(
                child: MonitorEcg(
                  sintesis: sintesisDe(p),
                  derivacion: 'II',
                  alLatir: () => _latidos.value++,
                ),
              ),
              Positioned(
                left: 12,
                top: 10,
                right: 12,
                child: Row(
                  children: [
                    Flexible(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        child: _Pastilla(
                          key: ValueKey(p.id),
                          color: color,
                          texto: p.nombre,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _Fc(fc: p.fc, latidos: _latidos),
                  ],
                ),
              ),
              const Positioned(
                left: 12,
                bottom: 8,
                child: Text(
                  'II · 25 mm/s',
                  style: TextStyle(color: kMuted, fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pastilla extends StatelessWidget {
  final Color color;
  final String texto;

  const _Pastilla({super.key, required this.color, required this.texto});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: kInk, width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                texto,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: kInk, fontSize: 12, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// La FC del monitor, con un corazón que late con cada QRS.
class _Fc extends StatelessWidget {
  final int fc;
  final ValueNotifier<int> latidos;

  const _Fc({required this.fc, required this.latidos});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 3, 10, 3),
      decoration: BoxDecoration(
        color: kInk,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ValueListenableBuilder<int>(
            valueListenable: latidos,
            builder: (_, n, __) => TweenAnimationBuilder<double>(
              key: ValueKey(n),
              tween: Tween(begin: 1.35, end: 1),
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOut,
              builder: (_, s, child) => Transform.scale(scale: s, child: child),
              child: const Icon(Icons.favorite_rounded, size: 14, color: Color(0xFFE8A598)),
            ),
          ),
          const SizedBox(width: 5),
          Text(
            fc > 0 ? '$fc' : '—',
            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900),
          ),
          const SizedBox(width: 3),
          const Text('lpm', style: TextStyle(color: Color(0xB3FFFFFF), fontSize: 10, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/* ════════════════════════════════════════════════════════════════════════
   Tarjetas de los dos pasos
═══════════════════════════════════════════════════════════════════════════ */

class _TarjetaPaso extends StatelessWidget {
  final int numero;
  final String etiqueta;
  final Color color;
  final IconData icono;
  final String titulo;
  final String texto;
  final List<String> datos;
  final VoidCallback onTap;
  final List<Widget> acciones;

  const _TarjetaPaso({
    required this.numero,
    required this.etiqueta,
    required this.color,
    required this.icono,
    required this.titulo,
    required this.texto,
    required this.datos,
    required this.onTap,
    required this.acciones,
  });

  @override
  Widget build(BuildContext context) {
    return StickerCard(
      radius: 24,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      // El papel milimetrado del ECG, teñido del color del paso.
      texture: graphPaper(tint: color, step: 12),
      onTap: onTap,
      pressDelay: const Duration(milliseconds: 90),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 54,
                height: 54,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: kInk, width: 2),
                  boxShadow: inkShadow(3),
                ),
                child: Icon(icono, color: Colors.white, size: 28),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: tinted(color, 0.18),
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: kInk, width: 1.5),
                ),
                child: Text(
                  '$numero · $etiqueta',
                  style: const TextStyle(color: kInk, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            titulo,
            style: const TextStyle(color: kInk, fontSize: 20, fontWeight: FontWeight.w900, height: 1.15, letterSpacing: -0.3),
          ),
          const SizedBox(height: 6),
          Text(texto, style: const TextStyle(color: kMuted, fontSize: 13.5, height: 1.45)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final d in datos)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: kHairline, width: 1.5),
                  ),
                  child: Text(d, style: const TextStyle(color: kInk, fontSize: 11.5, fontWeight: FontWeight.w700)),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (context.usesTwoPane) const Spacer(),
          for (var i = 0; i < acciones.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            acciones[i],
          ],
        ],
      ),
    );
  }
}
