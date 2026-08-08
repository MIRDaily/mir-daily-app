import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// El aspecto de las barras del sistema fuera del modo focus.
///
/// Vive aquí y no suelto en main.dart porque hay dos sitios que lo aplican: el
/// arranque y la salida del modo focus. Si cada uno pusiera lo suyo, bastaría
/// con entrar y salir del focus una vez para que la barra de estado volviera
/// para siempre.
class SystemUi {
  const SystemUi._();

  /// Oculta la barra de estado (reloj, batería, notificaciones) y deja la de
  /// navegación, para que la app se vea limpia sin tocar cómo se navega.
  ///
  /// Es [SystemUiMode.manual] porque es el único que permite elegir qué barra
  /// se oculta; a cambio no es "sticky": al deslizar desde el borde superior,
  /// Android la devuelve y la deja puesta. De volver a esconderla se encarga
  /// [StatusBarKeeper].
  static const List<SystemUiOverlay> _overlays = [SystemUiOverlay.bottom];

  static Future<void> apply() {
    return SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: _overlays,
    );
  }

  /// Iconos oscuros: la app siempre va en tema claro.
  static void applyStyle() {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.dark,
        systemNavigationBarDividerColor: Colors.transparent,
      ),
    );
  }
}

/// Vuelve a esconder la barra de estado cuando la app regresa a primer plano.
///
/// Hace falta porque el modo manual no se repone solo: si el usuario baja las
/// notificaciones o se va a otra app, al volver la barra se queda visible y ya
/// no se iría nunca.
class StatusBarKeeper with WidgetsBindingObserver {
  void start() => WidgetsBinding.instance.addObserver(this);
  void stop() => WidgetsBinding.instance.removeObserver(this);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    SystemUi.apply();
    SystemUi.applyStyle();
  }
}
