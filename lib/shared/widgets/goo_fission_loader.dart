import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../core/theme/app_theme.dart';

/// Loader "goo/fission" de la web (carga de mazos / sobre diario): dos blobs
/// corales que se separan y se funden con efecto gelatinoso (metaball).
///
/// El efecto goo en tiempo real no lo renderiza bien Impeller, así que se
/// reproduce un WebP animado pre-renderizado con el movimiento exacto del SVG.
/// Para evitar las rarezas del widget `Image` con WebP animado (que en algunos
/// motores solo pinta el primer fotograma), aquí se decodifican y reproducen
/// los fotogramas a mano con `instantiateImageCodec`.
class GooFissionLoader extends StatefulWidget {
  final double size;
  final String? label;
  final bool showGlow;

  const GooFissionLoader({
    super.key,
    this.size = 160,
    this.label,
    this.showGlow = true,
  });

  @override
  State<GooFissionLoader> createState() => _GooFissionLoaderState();
}

class _GooFissionLoaderState extends State<GooFissionLoader> {
  static const _asset = 'assets/images/goo_loader.webp';

  ui.Codec? _codec;
  ui.Image? _frame;
  Timer? _timer;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final data = await rootBundle.load(_asset);
      if (_disposed) return;
      _codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      _renderNextFrame();
    } catch (_) {
      // Si falla la carga, el build mostrará un fallback simple.
    }
  }

  Future<void> _renderNextFrame() async {
    final codec = _codec;
    if (_disposed || codec == null) return;
    final info = await codec.getNextFrame(); // recorre y reinicia en bucle
    if (_disposed) return;
    setState(() => _frame = info.image);
    final ms = info.duration.inMilliseconds;
    _timer = Timer(
      Duration(milliseconds: ms < 20 ? 80 : ms),
      _renderNextFrame,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: widget.size,
          height: widget.size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (widget.showGlow)
                Container(
                  width: widget.size * 0.85,
                  height: widget.size * 0.85,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.22),
                        blurRadius: 60,
                        spreadRadius: 6,
                      ),
                    ],
                  ),
                ),
              if (_frame != null)
                RawImage(
                  image: _frame,
                  width: widget.size,
                  height: widget.size,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.medium,
                )
              else
                const SizedBox(
                  width: 36,
                  height: 36,
                  child: CircularProgressIndicator(
                    color: AppColors.primary,
                    strokeWidth: 2.6,
                  ),
                ),
            ],
          ),
        ),
        if (widget.label != null) ...[
          const SizedBox(height: 16),
          Text(
            widget.label!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
              fontSize: 14.5,
            ),
          ),
        ],
      ],
    );
  }
}
