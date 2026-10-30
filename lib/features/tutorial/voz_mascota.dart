// Los «blips» de la mascota mientras escribe. Puerto de la web: src/lib/tutorials/mascotAudio.ts.
//
// La web los sintetiza con WebAudio; aquí son cinco WAV ya hechos (tools/generar_voz_mascota.mjs),
// uno por grado de la pentatónica, con la misma onda y la misma envolvente. Qué grado suena lo decide
// el texto (`semilla`), como en la web: así la frase se oye como una voz y no como un contador.
//
// - Varios reproductores en rueda: cada blip dura 90 ms y llega uno cada ~56 ms, de modo que se
//   solapan un poco. Con uno solo, cada blip cortaría la cola del anterior.
// - Sin foco de audio: un blip no puede pausar ni bajar la música que la persona tenga puesta.
// - En los tests no hay plugin nativo y construir un AudioPlayer lanza un error asíncrono que no se
//   puede capturar: ahí la voz se queda muda (ver [VozMascota.activa]).
// - En Android no hace falta el «desbloqueo por gesto» del navegador: suena desde el primer cuadro.

import 'dart:io' show Platform;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Pentatónica de la web: cualquier secuencia suena bien.
const List<int> gradosVozMascota = [0, 2, 4, 7, 9];

/// Un blip cada N caracteres a velocidad normal (la `cadencia` de la web).
const int cadenciaVozMascota = 2;

/// Separación mínima entre blips: sin ella, acelerar suena a metralleta (MS_ENTRE_BLIPS de la web).
const int msEntreBlips = 55;

/// Volumen del reproductor. El WAV va a 0,6 de pico; la web suena a 0,05 de ganancia sobre el
/// altavoz del portátil, que en el móvil apenas se oía: este es el equivalente a oído.
const double _volumen = 0.35;

/// Qué grado de la escala toca a la semilla (el `semitono` de la web, pero como índice).
int gradoBlip(int semilla) => semilla.abs() % gradosVozMascota.length;

/// Si toca blip en el carácter [i] (1-based, el último escrito) con el retardo actual: ni en los
/// espacios ni en cada letra, y cuanto más se acelera, más caracteres se salta, para que el ritmo de
/// los blips se mantenga aunque el texto vuele.
bool tocaBlip(String caracter, int i, int retardoMs) {
  if (caracter.trim().isEmpty) return false;
  final cadencia = [cadenciaVozMascota, (msEntreBlips / retardoMs).round()].reduce((a, b) => a > b ? a : b);
  return i % cadencia == 0;
}

class VozMascota {
  VozMascota._();
  static final VozMascota instancia = VozMascota._();

  /// Apagada en los tests (sin plugin nativo); se puede forzar para probar las decisiones.
  @visibleForTesting
  static bool activa = !_enTests();

  static bool _enTests() {
    try {
      return Platform.environment.containsKey('FLUTTER_TEST');
    } catch (_) {
      return false;
    }
  }

  static const int _tamanoRueda = 3;
  final List<AudioPlayer> _rueda = [];
  int _siguiente = 0;
  bool _roto = false;

  static final AudioContext _contexto = AudioContext(
    android: const AudioContextAndroid(
      isSpeakerphoneOn: false,
      stayAwake: false,
      // Por el canal de multimedia, como en el navegador. Con `assistanceSonification` iba por el de
      // sonidos del sistema, que el modo silencio/vibración calla: con el móvil así no se oía nada.
      contentType: AndroidContentType.sonification,
      usageType: AndroidUsageType.media,
      audioFocus: AndroidAudioFocus.none,
    ),
    iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient, options: const {}),
  );

  /// Un blip. Nunca lanza: sin audio, el tutorial funciona igual.
  void blip(int semilla) {
    if (!activa || _roto) return;
    _sonar(gradoBlip(semilla));
  }

  Future<void> _sonar(int grado) async {
    try {
      final AudioPlayer p;
      if (_rueda.length < _tamanoRueda) {
        p = AudioPlayer();
        _rueda.add(p);
        await p.setAudioContext(_contexto);
        await p.setPlayerMode(PlayerMode.lowLatency);
      } else {
        p = _rueda[_siguiente];
        _siguiente = (_siguiente + 1) % _tamanoRueda;
        await p.stop();
      }
      await p.play(AssetSource('audio/mascota/blip_$grado.wav'), volume: _volumen);
    } catch (_) {
      // Un dispositivo sin audio: no se vuelve a intentar en toda la sesión.
      _roto = true;
    }
  }
}
