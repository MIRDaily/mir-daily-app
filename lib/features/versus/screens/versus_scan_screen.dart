import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/services/haptics_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/sticker/sticker.dart';
import '../services/versus_links.dart';

/// Escáner del QR de una sala. Devuelve el PIN con `Navigator.pop`, o null si
/// se cierra sin escanear nada.
///
/// Acepta tanto el enlace del QR (`com.mirdaily.app://versus/PIN`) como el que
/// se comparte por WhatsApp (`https://mirdaily.com/versus/PIN`) y como un PIN
/// suelto, por si alguien genera el código a mano.
class VersusScanScreen extends StatefulWidget {
  const VersusScanScreen({super.key});

  @override
  State<VersusScanScreen> createState() => _VersusScanScreenState();
}

class _VersusScanScreenState extends State<VersusScanScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
  );

  /// Ya se ha aceptado un código. La cámara sigue emitiendo unos frames más
  /// después de cerrar, y sin esto se harían varios `pop`.
  bool _done = false;

  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;

    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue?.trim();
      if (raw == null || raw.isEmpty) continue;

      final pin = _pinFrom(raw);
      if (pin == null) continue;

      _done = true;
      HapticsService.medium();
      Navigator.of(context).pop(pin);
      return;
    }
  }

  /// Un QR de sala, o un PIN a secas.
  String? _pinFrom(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri != null && uri.hasScheme) {
      final fromLink = VersusLinks.pinFrom(uri);
      if (fromLink != null) return fromLink;
    }

    final bare = raw.toUpperCase();
    return RegExp(r'^[A-Z0-9]{6}$').hasMatch(bare) ? bare : null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Escanear sala'),
        actions: [
          IconButton(
            tooltip: 'Linterna',
            icon: const Icon(Icons.flashlight_on_rounded),
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) {
              // El caso normal aquí es el permiso denegado. Decirlo, porque una
              // pantalla negra sin más parece que la app está rota.
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.no_photography_rounded,
                          color: Colors.white54, size: 48),
                      const SizedBox(height: 16),
                      const Text(
                        'No se puede abrir la cámara',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Revisa el permiso de cámara en los ajustes del '
                        'sistema. También puedes teclear el código a mano.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),

          // Marco de puntería: sin él no se sabe dónde poner el código.
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                // Doble trazo: coral por dentro y tinta por fuera, para que el
                // marco se lea igual sobre una pared clara que sobre una
                // oscura, que es lo que tiene apuntar con la cámara.
                border: Border.all(color: AppColors.primary, width: 3),
                borderRadius: BorderRadius.circular(24),
                boxShadow: const [
                  BoxShadow(color: kInk, blurRadius: 0, spreadRadius: 2),
                ],
              ),
            ),
          ),

          Positioned(
            left: 24,
            right: 24,
            bottom: 48,
            child: Text(
              'Apunta al QR de la sala',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
