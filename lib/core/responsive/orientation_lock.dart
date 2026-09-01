import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'breakpoints.dart';

/// Política de orientación de la app:
///
/// - **Móvil** (lado corto < 600 dp): bloqueado a vertical. La app está
///   diseñada en una columna y no hay versión apaisada de móvil.
/// - **Tablet** (lado corto >= 600 dp): las 4 orientaciones. El uso principal
///   es horizontal, pero vertical también vale.
///
/// Se llama una vez al arrancar (`lib/main.dart`) y de nuevo al salir del modo
/// focus (que fija sus propias orientaciones mientras está activo).
class OrientationLock {
  const OrientationLock._();

  static const List<DeviceOrientation> _portraitOnly = [
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ];

  static const List<DeviceOrientation> _all = [
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ];

  /// `true` si el dispositivo es una tablet, según el lado corto de la
  /// pantalla física en píxeles lógicos.
  static bool get isTablet {
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final size = view.physicalSize / view.devicePixelRatio;
    return size.shortestSide >= kMediumMinWidth;
  }

  /// Aplica el bloqueo que corresponde al dispositivo. Sin `await` obligatorio:
  /// no debe retrasar el primer frame.
  static Future<void> apply() {
    return SystemChrome.setPreferredOrientations(
      isTablet ? _all : _portraitOnly,
    );
  }
}

/// Igual que [OrientationLock.isTablet] pero calculado desde una vista
/// concreta (para tests que inyectan tamaño).
bool isTabletView(ui.FlutterView view) {
  final size = view.physicalSize / view.devicePixelRatio;
  return size.shortestSide >= kMediumMinWidth;
}
