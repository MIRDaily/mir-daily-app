import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../core/providers/settings_provider.dart';

/// La musiquilla de la pantalla de carga.
///
/// MOCKUP: es una prueba de cómo quedaría una intro con música, no una
/// decisión cerrada. Para quitarlo entero: borrar este fichero, las llamadas
/// desde `loading_screen.dart`, el ajuste `introMusic` de [SettingsProvider],
/// el asset `assets/audio/` y la dependencia `audioplayers`.
///
/// Cómo suena:
///  - Arranca al abrir la pantalla y se repite en bucle, con un silencio de
///    entre [_silencioMin] y [_silencioMax] segundos entre vuelta y vuelta.
///  - Al pulsar "Continuar" se apaga con un fundido largo ([_fundido]).
///  - Se calla sola si la app se va a segundo plano o se apaga la pantalla, y
///    vuelve al volver.
///
/// Tres cosas que no se pidieron pero no son opcionales, porque esto se abre
/// en bibliotecas, en clase y de madrugada:
///
///  - Se **mezcla** con lo que ya esté sonando (Spotify, un podcast) en vez de
///    secuestrar el audio del móvil.
///  - Respeta el **interruptor de silencio**.
///  - Se puede **silenciar** desde la propia pantalla o desde Preferencias, y
///    se recuerda entre sesiones.
class IntroMusic with WidgetsBindingObserver {
  IntroMusic(this._settings);

  final SettingsProvider _settings;

  static const String _asset = 'audio/intro.mp3';

  /// Silencio entre una vuelta y la siguiente.
  static const int _silencioMin = 5;
  static const int _silencioMax = 10;

  /// Cuánto tarda en apagarse al pulsar "Continuar".
  ///
  /// Largo a propósito: la animación de salida dura menos de un segundo, así
  /// que el fundido sigue sonando un rato después de que la pantalla de carga
  /// haya desaparecido. Por eso no se corta al destruirse el widget (ver
  /// [dispose]): antes duraba 1,8s pero se cortaba en seco a los 850ms.
  static const Duration _fundido = Duration(seconds: 5);

  /// Volumen al que suena. Por debajo del de una app de música a propósito:
  /// acompaña, no compite.
  static const double _volumen = 0.55;

  final AudioPlayer _player = AudioPlayer();

  StreamSubscription<void>? _finDeVuelta;
  Timer? _esperaEntreVueltas;
  Timer? _pasoDelFundido;

  bool _apagando = false;
  bool _muerto = false;

  /// En segundo plano: pausada por el ciclo de vida, no por el usuario.
  bool _enPausaPorFondo = false;

  /// Para los tests: si está callada porque la app se fue a segundo plano.
  @visibleForTesting
  bool get enPausaPorFondo => _enPausaPorFondo;

  /// Para los tests: si ya se soltó el reproductor.
  @visibleForTesting
  bool get soltado => _muerto;

  /// Si el usuario la ha silenciado. Lo escucha la pantalla para pintar el
  /// botón; el valor que manda es el de [SettingsProvider].
  final ValueNotifier<bool> silenciada = ValueNotifier<bool>(false);

  double get _volumenActual => silenciada.value ? 0 : _volumen;

  /// Arranca. Si algo falla (un códec, un permiso, un emulador sin audio) se
  /// traga el error: una intro no puede impedir entrar en la app.
  Future<void> start() async {
    try {
      silenciada.value = !_settings.introMusic;
      _settings.addListener(_ajusteCambiado);
      WidgetsBinding.instance.addObserver(this);

      await _player.setAudioContext(_contextoAmbiente);
      await _player.setReleaseMode(ReleaseMode.stop);
      await _player.setVolume(_volumenActual);

      // El bucle se hace a mano, no con ReleaseMode.loop, porque entre vuelta
      // y vuelta tiene que haber silencio.
      _finDeVuelta = _player.onPlayerComplete.listen((_) => _programarVuelta());

      if (_muerto) return;
      await _player.play(AssetSource(_asset));
    } catch (e) {
      debugPrint('IntroMusic: no se pudo arrancar ($e)');
    }
  }

  /// El ajuste ha cambiado (desde esta pantalla o desde Preferencias).
  void _ajusteCambiado() {
    final callar = !_settings.introMusic;
    if (callar == silenciada.value) return;
    silenciada.value = callar;
    if (!_apagando) _player.setVolume(_volumenActual).catchError((_) {});
  }

  // ---- Ciclo de vida ----

  /// Apagar la pantalla o irse a otra app tiene que callarla. Sin esto seguía
  /// sonando con la tablet bloqueada, que es lo último que quieres de una app
  /// de estudio.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_muerto) return;
    switch (state) {
      case AppLifecycleState.resumed:
        if (_enPausaPorFondo && !_apagando) {
          _enPausaPorFondo = false;
          _player.resume().catchError((_) {});
        }
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        if (!_enPausaPorFondo) {
          _enPausaPorFondo = true;
          _esperaEntreVueltas?.cancel();
          _player.pause().catchError((_) {});
        }
    }
  }

  void _programarVuelta() {
    if (_muerto || _apagando || _enPausaPorFondo) return;
    final segundos = _silencioMin +
        (DateTime.now().millisecond % (_silencioMax - _silencioMin + 1));
    _esperaEntreVueltas?.cancel();
    _esperaEntreVueltas = Timer(Duration(seconds: segundos), () async {
      if (_muerto || _apagando || _enPausaPorFondo) return;
      try {
        await _player.play(AssetSource(_asset));
      } catch (_) {
        // Si la segunda vuelta falla, se queda en silencio y ya.
      }
    });
  }

  /// Silenciar / volver a oír desde la pantalla de carga. Escribe el ajuste,
  /// así que también queda cambiado en Preferencias.
  Future<void> toggleSilencio() =>
      _settings.setIntroMusic(!_settings.introMusic);

  /// Apaga con un fundido largo. Es lo que se llama al pulsar "Continuar".
  ///
  /// Baja el volumen a pasos cortos en vez de parar en seco. **No se espera a
  /// que termine**: la app entra cuando quiere, y el fundido sigue sonando por
  /// su cuenta hasta apagarse solo.
  Future<void> fadeOutAndStop() async {
    if (_apagando || _muerto) return;
    _apagando = true;
    _esperaEntreVueltas?.cancel();

    if (silenciada.value) {
      await _apagar();
      return;
    }

    const paso = Duration(milliseconds: 60);
    final pasos = _fundido.inMilliseconds ~/ paso.inMilliseconds;
    var restantes = pasos;

    _pasoDelFundido = Timer.periodic(paso, (t) async {
      restantes--;
      if (_muerto || restantes <= 0) {
        t.cancel();
        await _apagar();
        return;
      }
      try {
        // Al cuadrado: el oído no percibe el volumen de forma lineal, y un
        // descenso recto se oye como si cayera de golpe al principio y luego
        // se quedara colgando.
        final f = restantes / pasos;
        await _player.setVolume(_volumen * f * f);
      } catch (_) {
        t.cancel();
        await _apagar();
      }
    });
  }

  /// Suelta todo. Idempotente.
  Future<void> _apagar() async {
    if (_muerto) return;
    _muerto = true;
    _esperaEntreVueltas?.cancel();
    _pasoDelFundido?.cancel();
    await _finDeVuelta?.cancel();
    _settings.removeListener(_ajusteCambiado);
    WidgetsBinding.instance.removeObserver(this);
    silenciada.dispose();
    try {
      await _player.stop();
      await _player.dispose();
    } catch (_) {}
  }

  /// Lo llama la pantalla al destruirse.
  ///
  /// Si hay un fundido en marcha NO corta: el fundido dura más que la
  /// animación de salida y se apaga solo al terminar. Cortar aquí era
  /// justamente lo que hacía que "Continuar" sonara a tijeretazo.
  Future<void> dispose() async {
    if (_apagando) return;
    await _apagar();
  }
}

/// Sonar sin apropiarse del audio del móvil.
///
/// `audioFocus: none` para no cortar ni bajar la música que el usuario ya
/// tenga puesta, y categoría `ambient` en iOS, que es la que se calla con el
/// interruptor de silencio.
final AudioContext _contextoAmbiente = AudioContext(
  android: const AudioContextAndroid(
    isSpeakerphoneOn: false,
    stayAwake: false,
    contentType: AndroidContentType.music,
    usageType: AndroidUsageType.media,
    audioFocus: AndroidAudioFocus.none,
  ),
  iOS: AudioContextIOS(
    // `ambient` YA se mezcla con lo que suene y ya se calla con el interruptor
    // de silencio: son las dos cosas que se buscan aquí. No lleva
    // `mixWithOthers` explícito porque la librería lo prohíbe con esta
    // categoría (solo playback, playAndRecord y multiRoute) y tiraba un assert.
    category: AVAudioSessionCategory.ambient,
    options: const {},
  ),
);
