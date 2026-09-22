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

   ─── Lo que cambió tras el incidente del 21/09/2026 ────────────────────
   Entrar al perfil disparó varios avisos de subida de nivel seguidos, con el
   servidor perfectamente sano. Las cuatro reglas que salieron de ahí (la
   especificación completa, compartida con la web, está en `models/logros.dart`):

   · El estado va atado a un USUARIO, no al aparato: [setUsuario].
   · Una respuesta de una GENERACIÓN vieja se tira: [_generacion].
   · Una foto anómala no se pinta ni se guarda: [fotoAnomala].
   · El permiso de celebrar CADUCA si al concederlo no había nada.
═══════════════════════════════════════════════════════════════════════════ */

class ProgressProvider extends ChangeNotifier with WidgetsBindingObserver {
  final ApiService api;
  final LogrosStore _store;

  /// Cuánto se queda abierto el permiso cuando se concede sin nada que
  /// enseñar. Ver [permitirCelebracion].
  final Duration ventanaPermiso;

  ProgressProvider(
    this.api, {
    LogrosStore store = const LogrosStore(),
    this.ventanaPermiso = const Duration(seconds: 8),
  }) : _store = store {
    WidgetsBinding.instance.addObserver(this);
    // Las claves globales de antes de que esto fuera por usuario. Se tiran una
    // vez y para siempre: no llevan dueño y no se pueden adoptar sin arriesgar
    // celebrarle a una cuenta lo que consiguió otra.
    _store.purgarSinDuenno();
  }

  bool _dispuesto = false;

  /// Quién tiene la sesión abierta. Lo fija AuthProvider a través de main.dart.
  /// `null` = nadie.
  String? _usuario;
  String? get usuario => _usuario;

  /// Sube con cada cambio de cuenta y con cada apagado.
  ///
  /// Una carga guarda la generación con la que empezó y, al volver, comprueba
  /// que siga siendo la misma. Sin esto, una respuesta lenta de la cuenta
  /// anterior aterrizaba en la cuenta siguiente: le pintaba su nivel y, peor,
  /// le guardaba su referencia.
  int _generacion = 0;

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

  /// El temporizador de la rendija. Ver [permitirCelebracion].
  Timer? _cierrePermiso;

  /// Hay algo que celebrar Y estamos en un momento en que se puede.
  bool get celebracionLista => _permitido && _logros.isNotEmpty;

  /// Evita que dos recargas simultáneas (volver del segundo plano justo al
  /// terminar un daily) detecten el mismo logro dos veces.
  Future<void>? _enCurso;

  // ---------------------------------------------------------------------
  // Sesión
  // ---------------------------------------------------------------------

  /// Enciende o apaga el provider según quién tenga la sesión.
  ///
  /// Lo que hay en memoria se tira siempre: es de la cuenta anterior. Lo que
  /// hay en DISCO no se toca, porque ya va bajo el id de su dueño; antes era
  /// una clave global y había que borrarla al salir, lo que además hacía que
  /// quedarse sin conexión —que te echaba de la sesión— se llevara por delante
  /// las celebraciones pendientes.
  ///
  /// El trabajo se aplaza a un microtask porque lo llama `main.dart` desde el
  /// `update` del proxy, que corre DENTRO de la fase de construcción: avisar a
  /// los oyentes ahí reventaría con "markNeedsBuild called during build", y el
  /// primer arranque es justo cuando pasa.
  void setUsuario(String? uid) {
    if (_usuario == uid) return;
    _usuario = uid;
    _generacion += 1;
    final gen = _generacion;

    _data = null;
    _error = null;
    _loading = false;
    _logros.clear();
    _permitido = false;
    _cierrePermiso?.cancel();
    _cierrePermiso = null;

    scheduleMicrotask(() async {
      if (_dispuesto || _generacion != gen) return;
      notifyListeners();
      if (uid == null) return;

      // Lo que quedara pendiente de una sesión anterior DE ESTA CUENTA entra
      // ya en la cola: un logro conseguido justo antes de cerrar la app sigue
      // ahí al volver.
      final pendientes = await _store.leerPendientes(uid);
      if (_dispuesto || _generacion != gen) return;
      if (pendientes.isNotEmpty) {
        _logros.insertAll(0, fusionarSaltos(pendientes));
        notifyListeners();
      }
      refresh();
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
    final uid = _usuario;
    if (uid == null) return Future.value();
    return _enCurso ??=
        _cargar(uid, _generacion).whenComplete(() => _enCurso = null);
  }

  Future<void> _cargar(String usuario, int gen) async {
    _loading = true;
    _error = null;
    notifyListeners();

    var vigente = true;
    try {
      final nuevo = await api.getProgress();
      if (_dispuesto || _generacion != gen) {
        vigente = false;
        return;
      }

      final ref = await _store.leerReferencia(usuario);
      if (_dispuesto || _generacion != gen) {
        vigente = false;
        return;
      }

      if (fotoAnomala(ref, nuevo)) {
        // Ni se pinta ni se guarda. Un nivel 1 con cero XP encima de una
        // referencia de nivel 12 es el servidor tragándose un error (o un 2xx
        // que no era JSON), y guardarlo como referencia es exactamente lo que
        // hacía celebrar el nivel entero en la siguiente lectura buena. Se
        // conserva lo que ya había en pantalla: es viejo, pero es verdad.
        _error = 'Tu progreso no está disponible ahora mismo.';
        return;
      }

      _data = nuevo;

      // La primera vez que se ve a este usuario no se celebra nada: solo se
      // toma la foto. Si no, entrar por primera vez dispararía un aluvión de
      // avisos por cosas que no acaba de conseguir.
      if (ref != null) {
        final nuevos = detectarLogros(ref, nuevo);
        if (nuevos.isNotEmpty) {
          _logros.addAll(nuevos);
          // Una subida de tres peldaños repartida en tres recargas es UNA
          // subida, no tres tarjetas.
          final fundidos = fusionarSaltos(_logros);
          _logros
            ..clear()
            ..addAll(fundidos);
          await _store.guardarPendientes(usuario, _logros);
        }
      }
      await _store.guardarReferencia(usuario, Referencia.de(nuevo));
    } on ApiException catch (e) {
      _error = e.message;
    } catch (_) {
      _error = 'No se pudo cargar tu progreso.';
    } finally {
      if (!_dispuesto && vigente && _generacion == gen) {
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
  ///
  /// Y CADUCA. Antes no: quien lo concedía era `dispose` de la pantalla de
  /// resultados, que no puede saber si hay algo que enseñar, así que un daily
  /// sin logros dejaba el permiso abierto para siempre y lo siguiente que
  /// detectara cualquier recarga —al entrar al perfil, por ejemplo— salía de
  /// golpe. La rendija existe porque la recarga que dispara esa misma pantalla
  /// suele llegar un instante DESPUÉS del permiso; cerrar el grifo del todo se
  /// comería la celebración legítima.
  void permitirCelebracion() {
    _cierrePermiso?.cancel();
    _cierrePermiso = null;

    final cambia = !_permitido;
    _permitido = true;

    if (_logros.isEmpty) {
      _cierrePermiso = Timer(ventanaPermiso, () {
        _cierrePermiso = null;
        // Si en la rendija llegó algo, el permiso se queda: ya hay una tanda
        // en marcha y la cierra `descartarLogros` al vaciarse.
        if (_dispuesto || _logros.isNotEmpty || !_permitido) return;
        _permitido = false;
        notifyListeners();
      });
    }

    if (cambia) notifyListeners();
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
    final uid = _usuario;
    if (uid != null) _store.guardarPendientes(uid, _logros);
    // El permiso solo se cierra si NO queda nada. Si al cerrar la tarjeta
    // quedan desafíos, siguen teniendo vía libre para salir como avisos.
    if (_logros.isEmpty) {
      _permitido = false;
      _cierrePermiso?.cancel();
      _cierrePermiso = null;
    }
    notifyListeners();
  }

  /// Se ha visto todo: fuera de la cola y se cierra el grifo del permiso, que
  /// vale para una tanda y no para siempre.
  void cerrarCelebracion() {
    if (_logros.isEmpty && !_permitido) return;
    _logros.clear();
    final uid = _usuario;
    if (uid != null) _store.guardarPendientes(uid, const []);
    _permitido = false;
    _cierrePermiso?.cancel();
    _cierrePermiso = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _dispuesto = true;
    _cierrePermiso?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
