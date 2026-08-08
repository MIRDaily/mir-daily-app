import 'dart:async';

import 'package:flame/flame.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/auth_provider.dart';
import '../providers/daily_provider.dart';

/// El trabajo que la pantalla de carga hace de verdad mientras el usuario lee
/// las frases: pedir el sobre de hoy y dejar decodificado lo que pinta la
/// primera pestaña. Todo esto arrancaba antes al pulsar "Continuar", y por eso
/// la espera caía justo ahí.
///
/// Ninguna tarea puede tumbar el arranque: si una falla se da por terminada y
/// la pantalla que dependa de ella mostrará su propio error (el sobre, por
/// ejemplo, ya tiene su pantalla de "Reintentar").
class AppWarmup {
  AppWarmup({
    required AuthProvider auth,
    required DailyProvider daily,
    this.minimumDuration = const Duration(seconds: 2),
    this.timeout = const Duration(seconds: 12),
  })  : _auth = auth,
        _daily = daily;

  final AuthProvider _auth;
  final DailyProvider _daily;

  /// Suelo de tiempo en pantalla: sin él, con buena red la carga sería un
  /// parpadeo y no daría tiempo ni a leer una frase.
  final Duration minimumDuration;

  /// Techo de espera. Si el backend no contesta se entra igual, que el sobre ya
  /// sabe mostrar su error; es mejor eso que dejar al usuario mirando la barra.
  final Duration timeout;

  /// Fracción de trabajo terminado (0..1). Solo avanza.
  final ValueNotifier<double> progress = ValueNotifier<double>(0);

  /// Pasa a true cuando ya se puede entrar a la app.
  final ValueNotifier<bool> ready = ValueNotifier<bool>(false);

  /// Prefs ya leídas, para que la puerta del onboarding decida sin un frame de
  /// spinner por delante.
  SharedPreferences? get prefs => _prefs;
  SharedPreferences? _prefs;

  /// Los sprites que pide PackOpeningGame.onLoad(). loadSprite() resuelve
  /// contra la caché global (Flame.images), que es la misma que llena loadAll:
  /// al montarse el juego salen de caché en vez de decodificarse (~325 KB de
  /// PNG) en su primer frame.
  static const List<String> _packSprites = [
    'pack_closed.png',
    'card_back.png',
    'card_front.png',
  ];

  bool _started = false;
  double _weightDone = 0;
  double _weightTotal = 0;

  Future<void> start() async {
    if (_started) return;
    _started = true;

    final tasks = <_WarmupTask>[
      // El sobre de hoy: LA petición que antes empezaba a contar después del
      // clic. QuizScreen solo vuelve a pedirlo si el estado sigue en idle o
      // error, así que hacerlo aquí le ahorra la ida y vuelta entera.
      _WarmupTask(5, _daily.fetchDaily),
      _WarmupTask(4, () => Flame.images.loadAll(List.of(_packSprites))),
      // El perfil es quien decide entre onboarding y app.
      _WarmupTask(2, _awaitProfile),
      _WarmupTask(1, _loadPrefs),
      // Primera cara de quien ya hizo el daily de hoy: rootBundle cachea el
      // ByteData, así que GooFissionLoader se lo encuentra leído.
      _WarmupTask(1, () => rootBundle.load('assets/images/goo_loader.webp')),
    ];
    _weightTotal = tasks.fold<double>(0, (sum, t) => sum + t.weight);

    final floor = Future<void>.delayed(minimumDuration);
    final work = Future.wait(tasks.map(_run)).then<void>((_) {});

    // El techo corre contra el trabajo; el suelo se respeta siempre.
    await Future.any<void>([work, Future<void>.delayed(timeout)]);
    await floor;

    progress.value = 1;
    ready.value = true;
  }

  Future<void> _run(_WarmupTask task) async {
    try {
      await task.run().timeout(timeout);
    } catch (_) {
      // Una tarea caída no bloquea la entrada: de su error ya se encarga la
      // pantalla que la necesite.
    }
    _weightDone += task.weight;
    progress.value = _weightDone / _weightTotal;
  }

  Future<void> _loadPrefs() async {
    // Además de dejar el valor a mano, la instancia queda cacheada dentro del
    // plugin: las siguientes getInstance() ya no tocan disco.
    _prefs = await SharedPreferences.getInstance();
  }

  /// AuthProvider pide el perfil por su cuenta en cuanto hay sesión; aquí solo
  /// se espera a que conteste (marca profileChecked tanto si va bien como si
  /// falla).
  Future<void> _awaitProfile() {
    if (_auth.profileChecked) return Future<void>.value();

    final completer = Completer<void>();
    void listener() {
      if (_auth.profileChecked && !completer.isCompleted) completer.complete();
    }

    _auth.addListener(listener);
    // Pase lo que pase hay que soltar el listener, de ahí el timeout propio.
    return completer.future
        .timeout(timeout, onTimeout: () {})
        .whenComplete(() => _auth.removeListener(listener));
  }

  void dispose() {
    progress.dispose();
    ready.dispose();
  }
}

class _WarmupTask {
  const _WarmupTask(this.weight, this.run);

  final double weight;
  final Future<void> Function() run;
}
