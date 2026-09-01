import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  NavBarStyle _navBarStyle = NavBarStyle.classic;
  NavBarStyle get navBarStyle => _navBarStyle;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_kNavBarStyle) == 'floating') {
      _navBarStyle = NavBarStyle.floating;
      notifyListeners();
    }
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
