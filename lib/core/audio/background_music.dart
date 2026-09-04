import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';

/// Música de fondo mientras se navega por la app.
///
/// MOCKUP: el tema es provisional y se reemplazará. Para quitarlo entero:
/// borrar este fichero, el `ChangeNotifierProvider` de `main.dart`, la llamada
/// a [start] de ahí mismo, los `with SilencesBackgroundMusic` de las pantallas
/// interactivas, los dos ajustes de [SettingsProvider], su fila en Perfil y el
/// recurso `assets/audio/main.mp3`.
///
/// Cómo suena:
///  - Entra con un fundido de [_fundidoEntrada] al empezar cada vuelta y se
///    va con uno de [_fundidoSalida] antes de acabar, así que ni aparece ni
///    desaparece de golpe.
///  - Entre vuelta y vuelta descansa [_descansoMin]-[_descansoMax] segundos.
///    El tema dura 5-6 minutos: sonando sin pausa cansa.
///  - Se calla en los modos interactivos (ver [SilencesBackgroundMusic]) y en
///    segundo plano, y vuelve al salir de ellos.
///
/// El volumen y el silencio los manda el usuario desde Perfil.
class BackgroundMusic extends ChangeNotifier with WidgetsBindingObserver {
  /// [audio] a `false` deja toda la lógica en pie pero no crea reproductor.
  /// Lo usan los tests: sin plugin nativo, construir un `AudioPlayer` lanza un
  /// error asíncrono que no se puede capturar desde aquí. Lo que se prueba son
  /// las decisiones (cuándo callar y cuándo volver), no que suene.
  BackgroundMusic(this._settings, {bool audio = true}) : _audioActivado = audio;

  final SettingsProvider _settings;
  final bool _audioActivado;

  static const String _asset = 'audio/main.mp3';

  static const Duration _fundidoEntrada = Duration(seconds: 3);
  static const Duration _fundidoSalida = Duration(seconds: 5);

  /// Fundido corto al entrar o salir de un modo interactivo: ahí la música
  /// tiene que quitarse de en medio rápido, pero sin dar un corte.
  static const Duration _fundidoCorte = Duration(milliseconds: 1200);

  static const int _descansoMin = 30;
  static const int _descansoMax = 60;

  /// Cada cuánto se recalcula el volumen mientras hay un fundido en curso.
  static const Duration _pasoFundido = Duration(milliseconds: 80);

  /// Techo absoluto del volumen, por encima del ajuste del usuario.
  ///
  /// Es música de fondo: tiene que quedar por debajo del umbral en el que uno
  /// deja de leer para escucharla. El deslizador del usuario se aplica SOBRE
  /// este techo, así que su 100% sigue siendo discreto. Al 35% de fábrica la
  /// amplitud real es 0,0875 — unos 12 dB por debajo de lo que sonaba antes.
  static const double _techo = 0.25;

  /// Recorrido del fundido en decibelios.
  ///
  /// A 45 dB, el arranque del fundido es inaudible y el final es el volumen
  /// completo, con el cambio repartido de forma pareja al oído.
  static const double _rangoDb = 45;

  AudioPlayer? _player;

  StreamSubscription<Duration>? _posicion;
  StreamSubscription<void>? _finDeVuelta;
  Timer? _descanso;
  Timer? _fundido;

  /// Cuántos motivos hay ahora mismo para estar callada. Es un contador y no
  /// un booleano porque pueden solaparse: un simulacro que abre encima la hoja
  /// de un mazo, por ejemplo. La música vuelve cuando se cierran todos.
  int _silencios = 0;

  bool _enFondo = false;
  bool _arrancada = false;
  bool _muerto = false;

  /// Lo que [_sincronizar] dejó decidido la última vez. Sirve para distinguir
  /// "ha cambiado si debe sonar" de "solo ha cambiado el volumen".
  bool _estabaSonando = false;

  /// Cuántas veces se ha arrancado la reproducción desde cero. Para los tests:
  /// mover el volumen NO puede incrementarlo.
  @visibleForTesting
  int reproduccionesIniciadas = 0;

  /// Avance del fundido, 0..1. NO es el volumen: es la posición dentro del
  /// recorrido, y la amplitud sale de pasarla por [_amplitud].
  double _fade = 0;

  /// Duración del tema, en cuanto el reproductor la sabe. Hace falta para
  /// empezar el fundido de salida antes de que termine.
  Duration? _duracion;

  bool _saliendo = false;

  /// Si debería estar sonando: el usuario la quiere y nada la calla.
  bool get _deberiaSonar =>
      _settings.backgroundMusic &&
      _settings.backgroundMusicVolume > 0 &&
      _silencios == 0 &&
      !_enFondo &&
      !_muerto;

  /// Para los tests y para la pantalla de ajustes.
  @visibleForTesting
  int get silencios => _silencios;

  @visibleForTesting
  bool get sonando => _arrancada && _deberiaSonar;

  /// Amplitud que se le pediría al reproductor con el fundido a [avance].
  /// Para los tests: es lo que de verdad se oye.
  @visibleForTesting
  double volumenPara(double avance) =>
      (_techo * _settings.backgroundMusicVolume * _amplitud(avance))
          .clamp(0.0, 1.0);

  /// Arranca el servicio. Se llama al entrar en la app, no antes: en la
  /// pantalla de carga manda la intro y no deben pisarse.
  Future<void> start() async {
    if (_arrancada || _muerto) return;
    _arrancada = true;
    try {
      _settings.addListener(_ajustesCambiaron);
      WidgetsBinding.instance.addObserver(this);

      if (_audioActivado) _player = AudioPlayer();

      await _player?.setAudioContext(_contextoAmbiente);
      await _player?.setReleaseMode(ReleaseMode.stop);
      await _player?.setVolume(0);

      _player?.onDurationChanged.listen((d) => _duracion = d);
      _posicion = _player?.onPositionChanged.listen(_vigilarFinal);
      _finDeVuelta = _player?.onPlayerComplete.listen((_) => _programarDescanso());

      _estabaSonando = _deberiaSonar;
      if (_estabaSonando) await _empezarVuelta();
    } catch (e) {
      debugPrint('BackgroundMusic: no se pudo arrancar ($e)');
    }
  }

  // ---- Motivos para callarse -----------------------------------------------

  /// Entra un modo interactivo. Lo llama [SilencesBackgroundMusic].
  void pushSilence() {
    _silencios++;
    if (_silencios == 1) _sincronizar();
  }

  /// Sale un modo interactivo.
  void popSilence() {
    if (_silencios == 0) return;
    _silencios--;
    if (_silencios == 0) _sincronizar();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_muerto) return;
    final fondo = state != AppLifecycleState.resumed;
    if (fondo == _enFondo) return;
    _enFondo = fondo;
    // Al fondo se corta sin fundido: la pantalla ya se ha ido y nadie lo oiría.
    _sincronizar(inmediato: fondo);
  }

  void _ajustesCambiaron() {
    _sincronizar();
    notifyListeners();
  }

  /// ÚNICO punto que decide arrancar o parar.
  ///
  /// Compara con el estado anterior y solo actúa si ha cambiado de verdad.
  /// Sin esa comparación, cada notificación del ajuste de volumen entraba por
  /// el camino de "reanudar" y, como ya estaba sonando, relanzaba la
  /// reproducción del MP3 entero: mover el deslizador con el dedo son decenas
  /// de notificaciones por segundo y la app se quedaba clavada.
  void _sincronizar({bool inmediato = false}) {
    if (!_arrancada || _muerto) return;

    final debe = _deberiaSonar;
    if (debe == _estabaSonando) {
      // Nada que arrancar ni parar: como mucho ha cambiado el volumen.
      if (debe) _aplicarVolumen();
      return;
    }

    _estabaSonando = debe;
    if (debe) {
      _reanudar();
    } else {
      _apagarPorAhora(inmediato: inmediato);
    }
  }

  // ---- Reproducción --------------------------------------------------------

  Future<void> _empezarVuelta() async {
    if (!_deberiaSonar) return;
    reproduccionesIniciadas++;
    _saliendo = false;
    _duracion = null;
    try {
      await _player?.play(AssetSource(_asset));
      _fundirHasta(1, _fundidoEntrada);
    } catch (e) {
      debugPrint('BackgroundMusic: no se pudo reproducir ($e)');
    }
  }

  /// Empieza el fundido de salida cuando quedan [_fundidoSalida] para el final.
  void _vigilarFinal(Duration pos) {
    final total = _duracion;
    if (total == null || _saliendo || !_deberiaSonar) return;
    if (total - pos <= _fundidoSalida) {
      _saliendo = true;
      _fundirHasta(0, _fundidoSalida);
    }
  }

  void _programarDescanso() {
    if (!_deberiaSonar) return;
    final segundos = _descansoMin +
        (DateTime.now().millisecondsSinceEpoch % (_descansoMax - _descansoMin + 1));
    _descanso?.cancel();
    _descanso = Timer(Duration(seconds: segundos), () {
      if (_deberiaSonar) _empezarVuelta();
    });
  }

  /// Callar por un motivo temporal (modo interactivo, ajuste apagado, fondo).
  void _apagarPorAhora({bool inmediato = false}) {
    _descanso?.cancel();
    if (inmediato) {
      _cancelarTemporizadores();
      _fade = 0;
      _player?.pause().catchError((_) {});
      return;
    }
    _fundirHasta(0, _fundidoCorte, alTerminar: () {
      _player?.pause().catchError((_) {});
    });
  }

  void _reanudar() {
    final p = _player;
    if (p == null) {
      // Sin reproductor (modo de test): se recorre el mismo camino de
      // decisión, y `_empezarVuelta` no toca audio porque el player es null.
      _empezarVuelta();
      return;
    }
    switch (p.state) {
      case PlayerState.playing:
        // Ya suena (por ejemplo, se apagó y encendió el ajuste antes de que
        // terminara el fundido de bajada): solo hay que volver a subirlo.
        _fundirHasta(1, _fundidoCorte);
      case PlayerState.paused:
        // Estaba a media vuelta: sigue donde iba.
        p.resume().then((_) => _fundirHasta(1, _fundidoCorte)).catchError((_) {});
      case PlayerState.stopped:
      case PlayerState.completed:
      case PlayerState.disposed:
        _empezarVuelta();
    }
  }

  // ---- Fundidos ------------------------------------------------------------

  /// Lleva el multiplicador de volumen hasta [destino] en [duracion].
  void _fundirHasta(double destino, Duration duracion, {VoidCallback? alTerminar}) {
    _fundido?.cancel();
    if (_muerto) return;

    final desde = _fade;
    final pasos = (duracion.inMilliseconds / _pasoFundido.inMilliseconds).ceil();
    if (pasos <= 0) {
      _fade = destino;
      _aplicarVolumen();
      alTerminar?.call();
      return;
    }

    var paso = 0;
    _fundido = Timer.periodic(_pasoFundido, (t) {
      paso++;
      final t01 = (paso / pasos).clamp(0.0, 1.0);
      // El avance sí es lineal; la curva la pone [_amplitud], en decibelios.
      _fade = desde + (destino - desde) * t01;
      _aplicarVolumen();
      if (t01 >= 1) {
        t.cancel();
        _fade = destino;
        _aplicarVolumen();
        alTerminar?.call();
      }
    });
  }

  /// Amplitud para un avance de fundido, interpolando en decibelios.
  ///
  /// El oído percibe el volumen de forma logarítmica, así que una rampa lineal
  /// —y peor aún una cuadrática— reparte el cambio de forma muy desigual: a
  /// mitad de una rampa cuadrática vas por 0,25 de amplitud, unos −12 dB, y
  /// toda la segunda mitad concentra esos 12 dB de golpe. Se oye como un
  /// salto. Interpolando en dB, cada tramo suena como el mismo escalón.
  static double _amplitud(double avance) {
    if (avance <= 0) return 0;
    if (avance >= 1) return 1;
    return math.pow(10, (avance - 1) * _rangoDb / 20).toDouble();
  }

  void _aplicarVolumen() {
    if (_muerto) return;
    final v =
        (_techo * _settings.backgroundMusicVolume * _amplitud(_fade))
            .clamp(0.0, 1.0);
    _player?.setVolume(v).catchError((_) {});
  }

  void _cancelarTemporizadores() {
    _descanso?.cancel();
    _fundido?.cancel();
  }

  @override
  void dispose() {
    if (_muerto) {
      super.dispose();
      return;
    }
    _muerto = true;
    _cancelarTemporizadores();
    _posicion?.cancel();
    _finDeVuelta?.cancel();
    _settings.removeListener(_ajustesCambiaron);
    WidgetsBinding.instance.removeObserver(this);
    _player?.stop().catchError((_) {});
    _player?.dispose().catchError((_) {});
    super.dispose();
  }
}

/// Calla la música de fondo mientras la pantalla esté montada.
///
/// Se pone en las pantallas donde el usuario está respondiendo: el daily, el
/// runner del simulacro, una sala de Versus y el estudio de mazos y
/// flashcards. En los menús, la biblioteca, Premium y Perfil sigue sonando.
///
/// Es un contador, no un interruptor: si se solapan dos motivos, la música no
/// vuelve hasta que se cierran los dos.
mixin SilencesBackgroundMusic<T extends StatefulWidget> on State<T> {
  BackgroundMusic? _musica;

  @override
  void initState() {
    super.initState();
    // En el frame siguiente: en initState el árbol aún no está listo para
    // buscar el provider en algunas rutas.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _musica = context.read<BackgroundMusic?>();
      _musica?.pushSilence();
    });
  }

  @override
  void dispose() {
    _musica?.popSilence();
    _musica = null;
    super.dispose();
  }
}

/// Sonar sin apropiarse del audio del móvil: se mezcla con lo que ya suene y
/// respeta el interruptor de silencio.
final AudioContext _contextoAmbiente = AudioContext(
  android: const AudioContextAndroid(
    isSpeakerphoneOn: false,
    stayAwake: false,
    contentType: AndroidContentType.music,
    usageType: AndroidUsageType.media,
    audioFocus: AndroidAudioFocus.none,
  ),
  iOS: AudioContextIOS(
    category: AVAudioSessionCategory.ambient,
    options: const {},
  ),
);
