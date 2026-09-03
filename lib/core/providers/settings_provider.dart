import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../responsive/orientation_lock.dart';

/// Estilo de la barra de navegación inferior.
enum NavBarStyle {
  /// La de siempre: pegada al borde, de lado a lado.
  classic,

  /// Un "bocadillo" flotante, despegado del borde y con las esquinas
  /// redondeadas (estilo Apple Music). El contenido pasa por detrás.
  floating,
}

/// Ajustes de la app que son puras preferencias de visualización (viven en
/// el dispositivo, no en el servidor).
class SettingsProvider extends ChangeNotifier {
  SettingsProvider() {
    _load();
  }

  static const _kNavBarStyle = 'settings.nav_bar_style';
  static const _kIntroMusic = 'settings.intro_music';

  /// Por defecto: flotante en tablet, clásica en móvil. Solo cuenta si el
  /// usuario no ha elegido nada todavía.
  late NavBarStyle _navBarStyle =
      OrientationLock.isTablet ? NavBarStyle.floating : NavBarStyle.classic;
  NavBarStyle get navBarStyle => _navBarStyle;

  /// Si suena la musiquilla de la pantalla de carga.
  ///
  /// Encendida de fábrica, pero es lo primero que va a querer apagar quien
  /// estudie en una biblioteca. Se puede quitar y volver a poner desde la
  /// propia pantalla de carga o desde Perfil > Preferencias, y se recuerda.
  bool _introMusic = true;
  bool get introMusic => _introMusic;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();

    final musica = prefs.getBool(_kIntroMusic);
    if (musica != null && musica != _introMusic) {
      _introMusic = musica;
      notifyListeners();
    }

    final saved = prefs.getString(_kNavBarStyle);
    if (saved == null) return; // se queda con el valor por defecto
    final wanted =
        saved == 'floating' ? NavBarStyle.floating : NavBarStyle.classic;
    if (wanted != _navBarStyle) {
      _navBarStyle = wanted;
      notifyListeners();
    }
  }

  Future<void> setIntroMusic(bool on) async {
    if (on == _introMusic) return;
    _introMusic = on;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kIntroMusic, on);
  }

  Future<void> setNavBarStyle(NavBarStyle style) async {
    if (style == _navBarStyle) return;
    _navBarStyle = style;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kNavBarStyle,
      style == NavBarStyle.floating ? 'floating' : 'classic',
    );
  }
}
