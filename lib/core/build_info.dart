import 'package:package_info_plus/package_info_plus.dart';

/// Identifica el build que se está ejecutando, para pruebas.
///
/// El `versionName` de Android lleva un sufijo con el hash de git y la fecha
/// (ver `android/app/build.gradle.kts`, se aplica a debug y release). De ahí
/// [label] se queda solo con el hash (8 caracteres) — es lo único que
/// distingue un build de otro mientras no publiquemos: la versión y el build
/// number no cambian en desarrollo. Se puede además pasar
/// `--dart-define=BUILD_LABEL=F3` y [label] lo antepone.
class BuildInfo {
  BuildInfo._();

  static const String _override =
      String.fromEnvironment('BUILD_LABEL', defaultValue: '');

  /// Los builds de Play se compilan con `--dart-define=HIDE_BUILD_TAG=true`.
  static const bool _hidden = bool.fromEnvironment('HIDE_BUILD_TAG');

  /// El sufijo de versionName tiene forma "-<sha 8 hex>-<fecha>".
  static final RegExp _shaPattern = RegExp(r'-([0-9a-f]{8})-');

  static String _label = _override.isEmpty ? '…' : _override;

  /// Texto corto para mostrar en la esquina de desarrollo.
  static String get label => _label;

  /// Hoy todos los builds son de prueba: el sello se ve siempre (debug y
  /// release), salvo que se pase `--dart-define=HIDE_BUILD_TAG=true`.
  static bool get visible => !_hidden;

  static Future<void> load() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final sha = _shaPattern.firstMatch(info.version)?.group(1) ?? info.version;
      _label = _override.isEmpty ? sha : '$_override · $sha';
    } catch (_) {
      _label = _override.isEmpty ? 'v?' : _override;
    }
  }
}
