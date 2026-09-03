import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// La musiquilla de la pantalla de carga.
///
/// MOCKUP: esto es una prueba de cómo quedaría una intro con música, no una
/// decisión cerrada. Para quitarlo entero: borrar este fichero, la llamada
/// desde `loading_screen.dart`, el asset `assets/audio/` y la dependencia
/// `audioplayers` del pubspec. No hay nada más enganchado.
///
/// Cómo suena:
///  - Arranca al abrir la pantalla y se repite en bucle, con un silencio de
///    entre [_silencioMin] y [_silencioMax] segundos entre vuelta y vuelta.
///  - Al pulsar "Continuar" se apaga con un fundido lento en vez de cortarse.
///
/// Tres cosas que NO son opcionales aunque no se pidieran, porque el usuario
/// abre esto en una biblioteca, en clase o a las dos de la mañana:
///
///  - Se **mezcla** con lo que ya esté sonando (Spotify, un podcast) en vez de
///    secuestrar el audio del móvil.
///  - Respeta el **interruptor de silencio**: si el móvil está en silencio, no
///    suena. En Android eso es el modo ambiente; en iOS, la categoría
///    `ambient`, que es justo la que se calla con el interruptor.
///  - Se puede **silenciar** desde la propia pantalla y se recuerda.
class IntroMusic {
  IntroMusic();

  static const String _asset = 'audio/intro.mp3';
  static const String _prefSilenciada = 'intro_music_muted';

  /// Silencio entre una vuelta y la siguiente.
  static const int _silencioMin = 5;
  static const int _silencioMax = 10;

  /// Cuánto tarda en apagarse al pulsar "Continuar".
  static const Duration _fundido = Duration(milliseconds: 1800);

  /// Volumen al que suena. Por debajo del de una app de música a propósito:
  /// acompaña, no compite.
  static const double _volumen = 0.55;

  final AudioPlayer _player = AudioPlayer();

  StreamSubscription<void>? _finDeVuelta;
  Timer? _esperaEntreVueltas;
  Timer? _pasoDelFundido;

  bool _silenciada = false;
  bool _apagando = false;
  bool _muerto = false;

  /// Si el usuario la ha silenciado. Lo escucha la pantalla para pintar el
  /// botón.
  final ValueNotifier<bool> silenciada = ValueNotifier<bool>(false);

  /// Arranca. Si algo falla (un códec, un permiso, un emulador sin audio) se
  /// traga el error: una intro no puede impedir entrar en la app.
  Future<void> start() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _silenciada = prefs.getBool(_prefSilenciada) ?? false;
      silenciada.value = _silenciada;
      if (_muerto) return;

      await _player.setAudioContext(_contextoAmbiente);
      await _player.setReleaseMode(ReleaseMode.stop);
      await _player.setVolume(_silenciada ? 0 : _volumen);

      // El bucle se hace a mano, no con ReleaseMode.loop, porque entre vuelta
      // y vuelta tiene que haber silencio.
      _finDeVuelta = _player.onPlayerComplete.listen((_) => _programarVuelta());

      if (_muerto) return;
      await _player.play(AssetSource(_asset));
    } catch (e) {
      debugPrint('IntroMusic: no se pudo arrancar ($e)');
    }
  }

  void _programarVuelta() {
    if (_muerto || _apagando) return;
    final segundos =
        _silencioMin + (DateTime.now().millisecond % (_silencioMax - _silencioMin + 1));
    _esperaEntreVueltas?.cancel();
    _esperaEntreVueltas = Timer(Duration(seconds: segundos), () async {
      if (_muerto || _apagando) return;
      try {
        await _player.play(AssetSource(_asset));
      } catch (_) {
        // Si la segunda vuelta falla, se queda en silencio y ya.
      }
    });
  }

  /// Silenciar / volver a oír. Se recuerda para la próxima vez.
  Future<void> toggleSilencio() async {
    _silenciada = !_silenciada;
    silenciada.value = _silenciada;
    try {
      await _player.setVolume(_silenciada ? 0 : _volumen);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefSilenciada, _silenciada);
    } catch (_) {}
  }

  /// Apaga con un fundido lento. Es lo que se llama al pulsar "Continuar".
  ///
  /// Se baja el volumen a pasos cortos en vez de parar en seco: cortar una
  /// canción a mitad se nota mucho más que bajarla.
  Future<void> fadeOutAndStop() async {
    if (_apagando || _muerto) return;
    _apagando = true;
    _esperaEntreVueltas?.cancel();

    if (_silenciada) {
      await dispose();
      return;
    }

    const paso = Duration(milliseconds: 60);
    final pasos = _fundido.inMilliseconds ~/ paso.inMilliseconds;
    var restantes = pasos;

    final terminado = Completer<void>();
    _pasoDelFundido = Timer.periodic(paso, (t) async {
      restantes--;
      if (_muerto || restantes <= 0) {
        t.cancel();
        if (!terminado.isCompleted) terminado.complete();
        return;
      }
      try {
        await _player.setVolume(_volumen * (restantes / pasos));
      } catch (_) {
        t.cancel();
        if (!terminado.isCompleted) terminado.complete();
      }
    });

    await terminado.future;
    await dispose();
  }

  Future<void> dispose() async {
    if (_muerto) return;
    _muerto = true;
    _esperaEntreVueltas?.cancel();
    _pasoDelFundido?.cancel();
    await _finDeVuelta?.cancel();
    silenciada.dispose();
    try {
      await _player.stop();
      await _player.dispose();
    } catch (_) {}
  }
}

/// Sonar sin apropiarse del audio del móvil.
///
/// `duckOthers`/`stopAudio` a `false` para que no corte ni baje la música que
/// el usuario ya tenga puesta, y categoría `ambient` en iOS, que es la que se
/// calla con el interruptor de silencio.
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
    // `mixWithOthers` explícito porque la propia librería lo prohíbe con esta
    // categoría (solo lo admiten playback, playAndRecord y multiRoute), y
    // ponerlo tiraba un assert al arrancar.
    category: AVAudioSessionCategory.ambient,
    options: const {},
  ),
);
