import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Identifica el build que se está ejecutando, para pruebas de desarrollo.
///
/// - En **debug**, el `versionName` de Android lleva un sufijo con el hash de
///   git y la fecha (ver `android/app/build.gradle.kts`), así que
///   [label] queda p. ej. `1.0.0-ab12cd34-0901.1620 (1)`.
/// - En un build de prueba `release` se puede pasar
///   `--dart-define=BUILD_LABEL=F3` y [label] lo antepone.
class BuildInfo {
  BuildInfo._();

  static const String _override =
      String.fromEnvironment('BUILD_LABEL', defaultValue: '');

  static String _label = _override.isEmpty ? '…' : _override;

  /// Texto corto para mostrar en la esquina de desarrollo.
  static String get label => _label;

  /// Se muestra siempre el sello en builds debug; en release solo si se pasó
  /// `BUILD_LABEL`.
  static bool get visible => kDebugMode || _override.isNotEmpty;

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
