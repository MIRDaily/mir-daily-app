import 'package:package_info_plus/package_info_plus.dart';

/// Identifica el build que se está ejecutando, para pruebas.
///
/// [label] tiene la forma `v6 · <sha>`:
///  - `v6` es la [series]: el número de la carpeta viva ("Mirdaily APP V6").
///    Es una constante, no sale de git: una rama se renombra y el sello no
///    debería moverse con ella. Al empezar la V7 se cambia aquí.
///  - `<sha>` es el hash corto de git, que el `versionName` de Android trae
///    como sufijo (ver `android/app/build.gradle.kts`, se aplica a debug y
///    release). Es lo único que distingue dos builds de la misma serie
///    mientras no publiquemos: la versión y el build number de `pubspec` no
///    cambian en desarrollo.
///
/// Se puede además pasar `--dart-define=BUILD_LABEL=F3` y [label] lo intercala
/// (`v6 · F3 · <sha>`).
class BuildInfo {
  BuildInfo._();

  /// El número de la carpeta viva. Cambia al pasar a la V7.
  static const String series = 'v6';

  static const String _override =
      String.fromEnvironment('BUILD_LABEL', defaultValue: '');

  /// Los builds de Play se compilan con `--dart-define=HIDE_BUILD_TAG=true`.
  static const bool _hidden = bool.fromEnvironment('HIDE_BUILD_TAG');

  /// El sufijo de versionName tiene forma "-<sha 8 hex>-<fecha>".
  static final RegExp _shaPattern = RegExp(r'-([0-9a-f]{8})-');

  static String _label = _compose(null);

  /// Texto corto para mostrar en la esquina de desarrollo.
  static String get label => _label;

  /// Hoy todos los builds son de prueba: el sello se ve siempre (debug y
  /// release), salvo que se pase `--dart-define=HIDE_BUILD_TAG=true`.
  static bool get visible => !_hidden;

  /// Junta serie + (override) + hash, saltándose las partes que falten.
  static String _compose(String? sha) => [
        series,
        if (_override.isNotEmpty) _override,
        if (sha != null) sha,
      ].join(' · ');

  static Future<void> load() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final sha = _shaPattern.firstMatch(info.version)?.group(1) ?? info.version;
      _label = _compose(sha);
    } catch (_) {
      _label = _compose(null);
    }
  }
}
