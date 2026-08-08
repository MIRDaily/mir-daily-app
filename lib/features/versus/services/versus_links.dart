import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

/// Enlaces que llevan a una sala de Versus.
///
/// Reconoce las dos formas en que puede llegar un PIN de fuera de la app:
///  - `com.mirdaily.app://versus/PIN` — la del QR, que abre la app directa.
///  - `https://mirdaily.com/versus/PIN` — la que se comparte por WhatsApp.
///
/// El PIN se guarda en un [ValueNotifier] en vez de emitirse por un stream a
/// propósito: si la app se abre DESDE el enlace estando cerrada, la pestaña de
/// Versus todavía no existe (puede haber login u onboarding por delante), y un
/// evento suelto se perdería. Guardado, espera a que alguien venga a por él.
class VersusLinks {
  VersusLinks._();

  static final VersusLinks instance = VersusLinks._();

  final ValueNotifier<String?> pendingPin = ValueNotifier(null);

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _sub;

  Future<void> start() async {
    if (_sub != null) return;

    // Con la app ya abierta.
    _sub = _appLinks.uriLinkStream.listen(_handle);

    // Y el enlace que la arrancó, si venía de estar cerrada.
    try {
      _handle(await _appLinks.getInitialLink());
    } catch (_) {
      // Sin enlace inicial no hay nada que hacer.
    }
  }

  void _handle(Uri? uri) {
    if (uri == null) return;
    final pin = pinFrom(uri);
    if (pin != null) pendingPin.value = pin;
  }

  /// Lo consume quien lo atiende, para que no se vuelva a abrir la sala al
  /// volver a la pestaña.
  void consume() => pendingPin.value = null;

  /// Saca el PIN de cualquiera de las dos formas de enlace. Devuelve null si no
  /// es un enlace de sala (p. ej. el `auth-callback` del OAuth).
  static String? pinFrom(Uri uri) {
    final segments = [
      // En el esquema propio, "versus" es el HOST y el PIN el primer segmento;
      // en el https, ambos son segmentos de la ruta.
      if (uri.host.isNotEmpty) uri.host,
      ...uri.pathSegments,
    ].where((s) => s.isNotEmpty).toList();

    final at = segments.indexOf('versus');
    if (at == -1 || at + 1 >= segments.length) return null;

    final pin = segments[at + 1].toUpperCase();
    return RegExp(r'^[A-Z0-9]{6}$').hasMatch(pin) ? pin : null;
  }
}
