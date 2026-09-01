import 'package:package_info_plus/package_info_plus.dart';

/// Identifica el build que se está ejecutando, para pruebas.
///
/// El `versionName` de Android lleva un sufijo con el hash de git y la fecha
/// (ver `android/app/build.gradle.kts`, se aplica a debug y release), así que
/// [label] queda p. ej. `1.0.0-ab12cd34-0901.1620 (1)`. Se puede además pasar
/// `--dart-define=BUILD_LABEL=F3` y [label] lo antepone.
class BuildInfo {
  BuildInfo._();

  static const String _override =
      String.fromEnvironment('BUILD_LABEL', defaultValue: '');

  /// Los builds de Play se compilan con `--dart-define=HIDE_BUILD_TAG=true`.
  static const bool _hidden = bool.fromEnvironment('HIDE_BUILD_TAG');

  static String _label = _override.isEmpty ? '…' : _override;

  /// Texto corto para mostrar en la esquina de desarrollo.
  static String get label => _label;

  /// Hoy todos los builds son de prueba: el sello se ve siempre (debug y
  /// release), salvo que se pase `--dart-define=HIDE_BUILD_TAG=true`.
  static bool get visible => !_hidden;

  static Future<void> load() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final base = '${info.version} (${info.buildNumber})';
      _label = _override.isEmpty ? base : '$_override · $base';
    } catch (_) {
      _label = _override.isEmpty ? 'v?' : _override;
    }
  }
}
