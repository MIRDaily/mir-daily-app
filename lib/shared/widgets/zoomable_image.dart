import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Imagen de pregunta: se muestra inline y, al tocarla, se abre a pantalla
/// completa con zoom (pellizco) y desplazamiento. Se usa en todas las
/// pantallas donde aparecen imágenes de preguntas.
class ZoomableImage extends StatelessWidget {
  final String url;
  final BoxFit fit;
  final BorderRadius borderRadius;

  /// Si true, la imagen llena el espacio disponible (parent acotado, p. ej.
  /// la página de imagen del carrusel). Si false, se dimensiona al contenido
  /// (contextos con scroll).
  final bool expand;

  const ZoomableImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
    this.expand = false,
  });

  @override
  Widget build(BuildContext context) {
    Widget image = Image.network(
      url,
      fit: fit,
      width: expand ? null : double.infinity,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Container(
          height: expand ? double.infinity : 160,
          width: double.infinity,
          color: AppColors.surfaceVariant,
          alignment: Alignment.center,
          child: const SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(
                color: AppColors.primary, strokeWidth: 2.4),
          ),
        );
      },
      errorBuilder: (_, _, _) => const SizedBox.shrink(),
    );

    if (expand) image = SizedBox.expand(child: image);

    return GestureDetector(
      onTap: () => showFullscreenImage(context, url),
      child: Stack(
        children: [
          ClipRRect(borderRadius: borderRadius, child: image),
          Positioned(
            right: 8,
            bottom: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(99),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.zoom_in_rounded, color: Colors.white, size: 15),
                  SizedBox(width: 4),
                  Text('Ampliar',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Abre cualquier imagen a pantalla completa con zoom.
void showFullscreenImage(BuildContext context, String url) {
  Navigator.of(context).push(
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, _, _) => _FullscreenImage(url: url),
      transitionsBuilder: (_, anim, _, child) =>
          FadeTransition(opacity: anim, child: child),
    ),
  );
}

class _FullscreenImage extends StatelessWidget {
  final String url;
  const _FullscreenImage({required this.url});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 5,
                child: Center(
                  child: Image.network(
                    url,
                    fit: BoxFit.contain,
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      );
                    },
                    errorBuilder: (_, _, _) => const Center(
                      child: Text('No se pudo cargar la imagen',
                          style: TextStyle(color: Colors.white70)),
                    ),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded,
                      color: Colors.white, size: 28),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.15),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
