// Quién decide que un tutorial se enseña. Puerto de la web: src/providers/TutorialProvider.tsx y la
// parte de caché de src/lib/tutorials/storage.ts.
//
// Las tres reglas de la web:
//  1. Nunca arranca solo por estar en una pantalla: la pantalla tiene que decir «estoy lista»
//     (`TutorialListo`), y eso incluye que su pestaña esté a la vista y que no haya nada encima.
//  2. Uno cada vez, y nunca a la vez que una celebración de logros: la celebración va primero.
//  3. Saltar cuenta como visto: insistir a quien ya dijo que no es peor que no haberlo enseñado.
//
// Lo visto vive en la cuenta (users.tutorials_seen, que llega con el perfil) y se escribe con
// POST /api/profile/tutorials. Por delante hay una caché local por cuenta, que se escribe ANTES de la
// red: si el POST falla, el mismo tutorial no se repite en bucle. «Tutoriales encendidos» es una
// preferencia de este dispositivo, no de la cuenta (como en la web: quien lo apaga en el portátil no
// tiene por qué apagarlo en el móvil).

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models/models.dart';
import '../../core/models/tutoriales.dart';
import '../../core/services/tutoriales_api.dart';

class Tutoriales extends ChangeNotifier {
  final TutorialesApi api;
  final Map<String, Tutorial> catalogo;

  Tutoriales(this.api, {Map<String, Tutorial>? catalogo}) : catalogo = catalogo ?? tutorialesApp {
    _cargarActivos();
  }

  static const claveActivos = 'tutorials.enabled';
  static String claveVistos(String usuario) => 'tutorials.seen.$usuario';

  // ── Preferencia del dispositivo ─────────────────────────────────────────
  bool _activos = true;
  bool _activosCargado = false;
  bool get activos => _activos;

  Future<void> _cargarActivos() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _activos = prefs.getBool(claveActivos) ?? true;
    } catch (_) {
      // Sin almacenamiento la preferencia vive en memoria: se repite un tutorial, no se rompe nada.
    }
    _activosCargado = true;
    notifyListeners();
    _intentar();
  }

  Future<void> setActivos(bool valor) async {
    if (valor == _activos) return;
    _activos = valor;
    // Apagarlos con uno abierto lo cierra, sin marcarlo: no se ha visto.
    if (!valor) _cerrar();
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(claveActivos, valor);
    } catch (_) {}
    _intentar();
  }

  // ── Cuenta y lo visto ───────────────────────────────────────────────────
  String? _usuario;
  String? get usuario => _usuario;
  UserProfile? _perfilAplicado;
  Set<String> _servidor = {};
  Set<String> _local = {};
  bool _localCargado = false;

  /// Lo marcado en esta sesión. Sin esto, volver a la pantalla antes de que el perfil se refresque
  /// relanzaría el tutorial que se acaba de ver.
  final Set<String> _ahora = {};

  bool _celebrando = false;

  Set<String> get vistos => unirVistos(_servidor, _local, _ahora);

  /// Lo llama el ProxyProvider con la sesión, el perfil y si hay una celebración en pantalla.
  void sincronizar({required String? usuario, required UserProfile? perfil, required bool celebrando}) {
    var cambio = false;
    if (usuario != _usuario) {
      _usuario = usuario;
      _perfilAplicado = null;
      _servidor = {};
      _local = {};
      _ahora.clear();
      _localCargado = false;
      _cerrar();
      _candidato = null;
      if (usuario != null) _cargarLocal(usuario);
      cambio = true;
    }
    // La lista del servidor se toma solo de un perfil NUEVO: tras «volver a verlos» el perfil viejo
    // (con la lista de antes) sigue en memoria hasta que llega el refrescado, y no debe resucitarla.
    if (perfil != null && !identical(perfil, _perfilAplicado) && usuario != null && perfil.id == usuario) {
      _perfilAplicado = perfil;
      _servidor = perfil.tutorialsSeen.toSet();
      cambio = true;
      _guardarLocal();
    }
    if (celebrando != _celebrando) {
      _celebrando = celebrando;
      cambio = true;
    }
    // Llega desde el `update` de un ProxyProvider, en pleno build: se avisa después.
    if (cambio) {
      scheduleMicrotask(() {
        notifyListeners();
        _intentar();
      });
    }
  }

  Future<void> _cargarLocal(String usuario) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final l = prefs.getStringList(claveVistos(usuario)) ?? const [];
      if (usuario != _usuario) return;
      _local = {..._local, ...l};
    } catch (_) {}
    if (usuario != _usuario) return;
    _localCargado = true;
    _guardarLocal();
    _intentar();
  }

  /// La caché se pone al día con todo lo que se sabe (también lo que dijo el servidor, que es quien
  /// sabe lo visto en la web).
  Future<void> _guardarLocal() async {
    final u = _usuario;
    if (u == null || !_localCargado) return;
    _local = vistos;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(claveVistos(u), _local.toList()..sort());
    } catch (_) {}
  }

  // ── Arranque ────────────────────────────────────────────────────────────
  String? _candidato;
  String? _enCurso;
  List<PasoTutorial> _pasos = const [];
  int _indice = 0;
  Timer? _arranque;

  String? get enCurso => _enCurso;
  int get indice => _indice;
  int get total => _pasos.length;
  PasoTutorial? get pasoActual => _enCurso == null || _indice >= _pasos.length ? null : _pasos[_indice];

  /// La pantalla avisa de que su tutorial ya se puede enseñar (o de que ya no).
  void declararListo(String id, bool listo) {
    if (listo) {
      _candidato = id;
    } else if (_candidato == id) {
      _candidato = null;
    }
    _intentar();
  }

  void _intentar() {
    if (!_activosCargado || !_localCargado) return;
    final id = tutorialQueToca(
      candidato: _candidato,
      enCurso: _enCurso,
      conSesion: _usuario != null,
      activos: _activos,
      celebrando: _celebrando,
      vistos: vistos,
      catalogo: catalogo,
    );
    if (id == null || _arranque != null) return;
    // Un fotograma de margen: la pantalla acaba de decir que está lista y todavía se está pintando.
    _arranque = Timer(Duration.zero, () {
      _arranque = null;
      final sigue = tutorialQueToca(
        candidato: _candidato,
        enCurso: _enCurso,
        conSesion: _usuario != null,
        activos: _activos,
        celebrando: _celebrando,
        vistos: vistos,
        catalogo: catalogo,
      );
      if (sigue != id) return;
      _pasos = armarGuion(catalogo[id]!);
      _indice = 0;
      _enCurso = id;
      notifyListeners();
    });
  }

  // ── Avanzar y cerrar ────────────────────────────────────────────────────
  void avanzar() {
    if (_enCurso == null) return;
    if (_indice + 1 >= _pasos.length) {
      _terminar();
      return;
    }
    _indice++;
    notifyListeners();
  }

  /// Saltar cuenta como visto.
  void saltar() => _terminar();

  void _terminar() {
    final id = _enCurso;
    _cerrar();
    _candidato = null;
    notifyListeners();
    if (id == null) return;
    _marcar(id);
  }

  void _cerrar() {
    _arranque?.cancel();
    _arranque = null;
    _enCurso = null;
    _pasos = const [];
    _indice = 0;
  }

  Future<void> _marcar(String id) async {
    _ahora.add(id);
    await _guardarLocal();
    try {
      await api.marcar(id);
    } catch (_) {
      // Se queda en la caché local: no se repite aquí, y el servidor se enterará la próxima vez.
    }
  }

  /// «Volver a verlos desde el principio»: los borra en el servidor (todos los dispositivos) y aquí, y
  /// los vuelve a encender. Si el servidor falla, lanza y no se toca nada.
  Future<void> reiniciar() async {
    await api.reiniciar();
    _servidor = {};
    _ahora.clear();
    _local = {};
    final u = _usuario;
    if (u != null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList(claveVistos(u), const []);
      } catch (_) {}
    }
    if (!_activos) {
      await setActivos(true);
    } else {
      notifyListeners();
      _intentar();
    }
  }

  // ── Anclas ──────────────────────────────────────────────────────────────
  final Map<String, Set<GlobalKey>> _anclas = {};

  void registrarAncla(String nombre, GlobalKey key) => (_anclas[nombre] ??= {}).add(key);

  void quitarAncla(String nombre, GlobalKey key) {
    final s = _anclas[nombre];
    if (s == null) return;
    s.remove(key);
    if (s.isEmpty) _anclas.remove(nombre);
  }

  Iterable<GlobalKey> anclas(String nombre) => _anclas[nombre] ?? const {};

  @override
  void dispose() {
    _arranque?.cancel();
    super.dispose();
  }
}
