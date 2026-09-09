import 'dart:async';

import 'package:flutter/widgets.dart';

import '../models/logros.dart';
import '../models/progress.dart';
import '../services/api_service.dart';
import '../theme/levels.dart';

/// Qué meta de mentira disparar. Solo para pruebas de desarrollo.
enum SimulacionLogro {
  desafio,

  /// Los tres a la vez: sirve para ver cómo se apilan los avisos.
  desafiosAMontones,
  nivel,
  rango,
  racha,

  /// Rango + racha + los tres desafíos: el relevo completo, tarjeta primero y
  /// avisos después.
  todo,
}

/* ════════════════════════════════════════════════════════════════════════
   Nivel, XP, racha y desafíos, compartidos por toda la app.

   Vive arriba del árbol y no en cada pantalla porque hay varios consumidores
   a la vez (el aro del nivel en la barra de navegación, la sección del perfil
   y la celebración). Con un consumidor por pantalla serían tres peticiones
   idénticas en cada navegación, y cada una arrastra una sincronización de
   desafíos en el servidor.

   SIN SESIÓN NO PIDE NADA. En la web ese descuido provocaba un 401 en cada
   visita a la portada.
═══════════════════════════════════════════════════════════════════════════ */

class ProgressProvider extends ChangeNotifier with WidgetsBindingObserver {
  final ApiService api;
  final LogrosStore _store;

  ProgressProvider(this.api, {LogrosStore store = const LogrosStore()})
      : _store = store {
    WidgetsBinding.instance.addObserver(this);
    // Lo que quedara pendiente de una sesión anterior entra ya en la cola: un
    // logro conseguido justo antes de cerrar la app sigue ahí al volver.
    _store.leerPendientes().then((pendientes) {
      if (pendientes.isEmpty || _dispuesto) return;
      _logros.insertAll(0, pendientes);
      notifyListeners();
    });
  }

  bool _dispuesto = false;

  /// Hay sesión iniciada. Lo fija AuthProvider a través de main.dart.
  bool _autenticado = false;

  ProgressSnapshot? _data;
  ProgressSnapshot? get data => _data;

  UserProgress? get progress => _data?.progress;

  bool _loading = false;
  bool get loading => _loading;

  String? _error;
  String? get error => _error;

  final List<Logro> _logros = [];

  /// Metas cumplidas pendientes de celebrar. Se llenan solas al recargar, pero
  /// NO se enseñan hasta que alguien da permiso con [permitirCelebracion].
  List<Logro> get logros => List.unmodifiable(_logros);

  bool _permitido = false;

  /// Hay algo que celebrar Y estamos en un momento en que se puede.
  bool get celebracionLista => _permitido && _logros.isNotEmpty;

  /// Evita que dos recargas simultáneas (volver del segundo plano justo al
  /// terminar un daily) detecten el mismo logro dos veces.
  Future<void>? _enCurso;

  // ---------------------------------------------------------------------
  // Sesión
  // ---------------------------------------------------------------------

  /// Enciende o apaga el provider según haya sesión.
  ///
  /// Al cerrar sesión se tira todo, referencia incluida: es de un usuario
  /// concreto y arrastrarla a la cuenta siguiente celebraría cosas que esa
  /// cuenta no ha conseguido.
  ///
  /// El trabajo se aplaza a un microtask porque lo llama `main.dart` desde el
  /// `update` del proxy, que corre DENTRO de la fase de construcción: avisar a
  /// los oyentes ahí reventaría con "markNeedsBuild called during build", y el
  /// primer arranque es justo cuando pasa.
  void setAutenticado(bool valor) {
    if (_autenticado == valor) return;
    _autenticado = valor;
    scheduleMicrotask(() {
      if (_dispuesto || _autenticado != valor) return;
      if (valor) {
        refresh();
      } else {
        _data = null;
        _error = null;
        _loading = false;
        _logros.clear();
        _permitido = false;
        _store.limpiar();
        notifyListeners();
      }
    });
  }

  // ---------------------------------------------------------------------
  // Carga
  // ---------------------------------------------------------------------

  /// Vuelve a leer el estado. Se llama al abrir la app, al volver del segundo
  /// plano y al terminar un daily, un simulacro o una sesión de mazos: el
  /// backend ya ha sumado el XP dentro de esas llamadas, así que basta con
  /// releer. No hace falta sondear.
  Future<void> refresh() {
    if (!_autenticado) return Future.value();
    return _enCurso ??= _cargar().whenComplete(() => _enCurso = null);
  }

  Future<void> _cargar() async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final nuevo = await api.getProgress();
      if (_dispuesto) return;
      _data = nuevo;

      // La primera vez que se ve a este usuario no se celebra nada: solo se
      // toma la foto. Si no, entrar por primera vez dispararía un aluvión de
      // avisos por cosas que no acaba de conseguir.
      final ref = await _store.leerReferencia();
      if (_dispuesto) return;
      if (ref != null) {
        final nuevos = detectarLogros(ref, nuevo);
        if (nuevos.isNotEmpty) {
          _logros.addAll(nuevos);
          await _store.guardarPendientes(_logros);
        }
      }
      await _store.guardarReferencia(Referencia.de(nuevo));
    } on ApiException catch (e) {
      _error = e.message;
    } catch (_) {
      _error = 'No se pudo cargar tu progreso.';
    } finally {
      if (!_dispuesto) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refresh();
  }

  // ---------------------------------------------------------------------
  // Celebración
  // ---------------------------------------------------------------------

  /// "Ya no estoy en mitad de nada, puedes celebrar."
  ///
  /// El permiso es explícito a propósito. La alternativa —que cada pantalla
  /// avise de que está ocupada— falla en el lado malo: si un modo nuevo se
  /// olvida de declararse, interrumpe al usuario en mitad de una pregunta.
  /// Así, lo peor que pasa si alguien olvida llamar es que la celebración
  /// espera al siguiente momento seguro.
  void permitirCelebracion() {
    if (_permitido) return;
    _permitido = true;
    notifyListeners();
  }

  /// Mete logros en la cola sin pasar por el servidor.
  ///
  /// NO se persiste: son de mentira y no deben reaparecer en la próxima
  /// sesión. Tampoco tocan el XP de nadie.
  void encolarLogros(List<Logro> nuevos) {
    if (nuevos.isEmpty) return;
    _logros.addAll(nuevos);
    notifyListeners();
  }

  /// Dispara logros de mentira para poder MIRAR las animaciones sin tener que
  /// conseguirlos de verdad.
  ///
  /// Es el `simularLogro` de la web, y existe porque no hay otra forma
  /// razonable de ver un salto de dos peldaños o la tarjeta de rango: harían
  /// falta semanas de racha real. NO toca el servidor ni el XP: solo mete las
  /// metas en la cola, exactamente como haría la detección normal, y abre el
  /// permiso porque quien pulsa el botón ya está diciendo "enséñamelo ahora".
  void simularLogro(SimulacionLogro que) {
    final desafios = [
      const Logro(
        id: '',
        tipo: TipoLogro.desafio,
        titulo: 'Haz el Daily',
        xp: 30,
        scope: 'daily',
      ),
      const Logro(
        id: '',
        tipo: TipoLogro.desafio,
        titulo: 'Sesión de fondo',
        xp: 25,
        scope: 'daily',
      ),
      const Logro(
        id: '',
        tipo: TipoLogro.desafio,
        titulo: 'Cinco de siete',
        xp: 150,
        scope: 'weekly',
      ),
    ];

    // Tramos de mentira pero COHERENTES con la curva, para que la barra
    // recorra de verdad lo que le toca en vez de saltar a un sitio imposible.
    final nivel = Logro(
      id: '',
      tipo: TipoLogro.nivel,
      nivel: 12,
      xpAntes: xpParaNivel(11) + 30,
      xpDespues: xpParaNivel(12) + 90,
    );
    final rango = Logro(
      id: '',
      tipo: TipoLogro.rango,
      nivel: 20,
      rango: 'Residente R1',
      // Dos peldaños de golpe, para ver el encadenado y que la segunda salva
      // de chispas se sume a la primera en vez de borrarla.
      xpAntes: xpParaNivel(18) + 120,
      xpDespues: xpParaNivel(20) + 140,
    );
    const racha = Logro(id: '', tipo: TipoLogro.racha, dias: 30);

    final tanda = switch (que) {
      SimulacionLogro.desafio => [desafios.first],
      SimulacionLogro.desafiosAMontones => desafios,
      SimulacionLogro.nivel => [nivel],
      SimulacionLogro.rango => [rango],
      SimulacionLogro.racha => [racha],
      SimulacionLogro.todo => [rango, racha, ...desafios],
    };

    // Identidad propia para cada uno: sin ella dos avisos seguidos comparten
    // clave, se recicla el nodo y el texto cambia SIN animar.
    encolarLogros([
      for (final l in tanda) _conId(l),
    ]);
    permitirCelebracion();
  }

  static Logro _conId(Logro l) => Logro(
        id: nuevoIdLogro(),
        tipo: l.tipo,
        nivel: l.nivel,
        rango: l.rango,
        dias: l.dias,
        titulo: l.titulo,
        xp: l.xp,
        scope: l.scope,
        xpAntes: l.xpAntes,
        xpDespues: l.xpDespues,
      );

  /// Quita UN logro de la cola, por identificador. Solo se llama cuando se ha
  /// enseñado de verdad.
  void descartarLogro(String id) => descartarLogros([id]);

  /// Quita varios de golpe. Lo usa la tarjeta al cerrarse.
  void descartarLogros(List<String> ids) {
    final fuera = ids.toSet();
    final antes = _logros.length;
    _logros.removeWhere((l) => fuera.contains(l.id));
    if (_logros.length == antes) return;
    _store.guardarPendientes(_logros);
    // El permiso solo se cierra si NO queda nada. Si al cerrar la tarjeta
    // quedan desafíos, siguen teniendo vía libre para salir como avisos.
    if (_logros.isEmpty) _permitido = false;
    notifyListeners();
  }

  /// Se ha visto todo: fuera de la cola y se cierra el grifo del permiso, que
  /// vale para una tanda y no para siempre.
  void cerrarCelebracion() {
    if (_logros.isEmpty && !_permitido) return;
    _logros.clear();
    _store.guardarPendientes(const []);
    _permitido = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _dispuesto = true;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
