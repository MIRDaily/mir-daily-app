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
  static const _kBgMusic = 'settings.bg_music';
  static const _kBgMusicVolume = 'settings.bg_music_volume';

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

  /// Si suena la música de fondo mientras se navega por la app.
  bool _backgroundMusic = true;
  bool get backgroundMusic => _backgroundMusic;

  /// Volumen de la música de fondo, 0..1.
  ///
  /// Por defecto bastante bajo: acompaña mientras se ojea la app, no compite
  /// con nada. A 1 sigue estando por debajo de una app de música.
  double _backgroundMusicVolume = 0.35;
  double get backgroundMusicVolume => _backgroundMusicVolume;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();

    final musica = prefs.getBool(_kIntroMusic);
    if (musica != null && musica != _introMusic) {
      _introMusic = musica;
      notifyListeners();
    }

    final fondo = prefs.getBool(_kBgMusic);
    final volumen = prefs.getDouble(_kBgMusicVolume);
    if (fondo != null && fondo != _backgroundMusic) {
      _backgroundMusic = fondo;
      notifyListeners();
    }
    if (volumen != null && volumen != _backgroundMusicVolume) {
      _backgroundMusicVolume = volumen.clamp(0.0, 1.0);
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

  Future<void> setBackgroundMusic(bool on) async {
    if (on == _backgroundMusic) return;
    _backgroundMusic = on;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kBgMusic, on);
  }

  /// Guarda el volumen de la música de fondo. Avisa en cada cambio para que el
  /// deslizador se oiga mientras se mueve, pero solo escribe a disco el valor
  /// que quede: mover el dedo son decenas de cambios por segundo.
  Future<void> setBackgroundMusicVolume(double v, {bool persist = true}) async {
    final nuevo = v.clamp(0.0, 1.0);
    if (nuevo == _backgroundMusicVolume) return;
    _backgroundMusicVolume = nuevo;
    notifyListeners();
    if (!persist) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kBgMusicVolume, nuevo);
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
