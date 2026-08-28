import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../sticker/sticker.dart';

/// Imagen de pregunta: se muestra inline y, al tocarla, se abre a pantalla
/// completa con zoom (pellizco) y desplazamiento. Se usa en todas las
/// pantallas donde aparecen imágenes de preguntas.
///
/// Si la descarga falla, se ve QUE ha fallado y se puede reintentar. Antes el
/// `errorBuilder` devolvía un hueco vacío: la imagen desaparecía sin decir
/// nada, y como `Image.network` no reintenta por su cuenta, un corte de red de
/// un segundo dejaba esa pregunta sin imagen para el resto de la sesión. En el
/// simulacro en modo deslizar se notaba especialmente, porque la página
/// "IMAGEN" seguía ahí —con su cabecera y su botón de ampliar— pero vacía.
class ZoomableImage extends StatefulWidget {
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
  State<ZoomableImage> createState() => _ZoomableImageState();
}

class _ZoomableImageState extends State<ZoomableImage> {
  /// Cambia con cada reintento: se usa como `key` para forzar un `Image`
  /// nuevo, porque el que ya falló no vuelve a pedir nada por sí solo.
  int _intento = 0;
  bool _fallo = false;

  Future<void> _reintentar() async {
    // Sin desalojar la entrada de la caché, el `Image` nuevo se encontraría el
    // mismo fallo ya guardado y ni siquiera saldría a la red.
    await NetworkImage(widget.url).evict();
    if (!mounted) return;
    setState(() {
      _fallo = false;
      _intento++;
    });
  }

  @override
  void didUpdateWidget(covariant ZoomableImage old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      _fallo = false;
      _intento = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_fallo) return _errorBox();

    Widget image = Image.network(
      widget.url,
      key: ValueKey('${widget.url}#$_intento'),
      fit: widget.fit,
      width: widget.expand ? null : double.infinity,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Container(
          height: widget.expand ? double.infinity : 160,
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
      errorBuilder: (context, _, _) {
        // El estado se cambia en el siguiente fotograma: tocarlo a mitad del
        // build sería modificar el árbol mientras se construye.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_fallo) setState(() => _fallo = true);
        });
        return _errorBox();
      },
    );

    if (widget.expand) image = SizedBox.expand(child: image);

    return GestureDetector(
      onTap: () => showFullscreenImage(context, widget.url),
      child: Stack(
        children: [
          ClipRRect(borderRadius: widget.borderRadius, child: image),
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

  Widget _errorBox() {
    final box = Container(
      height: widget.expand ? null : 160,
      width: double.infinity,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: widget.borderRadius,
        border: Border.all(color: kHairline, width: 2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.image_not_supported_outlined,
              size: 30, color: AppColors.textLight),
          const SizedBox(height: 8),
          const Text(
            'No se pudo cargar la imagen',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: _reintentar,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: kInk, width: 2),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.refresh_rounded, size: 15, color: kInk),
                  SizedBox(width: 6),
                  Text(
                    'Reintentar',
                    style: TextStyle(
                      color: kInk,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    return widget.expand ? Center(child: box) : box;
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

class _FullscreenImage extends StatefulWidget {
  final String url;
  const _FullscreenImage({required this.url});

  @override
  State<_FullscreenImage> createState() => _FullscreenImageState();
}

class _FullscreenImageState extends State<_FullscreenImage> {
  int _intento = 0;

  Future<void> _reintentar() async {
    await NetworkImage(widget.url).evict();
    if (mounted) setState(() => _intento++);
  }

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
                    widget.url,
                    key: ValueKey('${widget.url}#$_intento'),
                    fit: BoxFit.contain,
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      );
                    },
                    errorBuilder: (_, _, _) => Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('No se pudo cargar la imagen',
                              style: TextStyle(color: Colors.white70)),
                          const SizedBox(height: 14),
                          TextButton.icon(
                            onPressed: _reintentar,
                            icon: const Icon(Icons.refresh_rounded,
                                color: Colors.white),
                            label: const Text('Reintentar',
                                style: TextStyle(color: Colors.white)),
                          ),
                        ],
                      ),
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
