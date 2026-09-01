import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/responsive/orientation_lock.dart';
import '../../../core/theme/system_ui.dart';
import '../models/focus_room.dart';

class FocusProvider extends ChangeNotifier with WidgetsBindingObserver {
  FocusRoom? _currentRoom;
  bool _isInFocusMode = false;
  Timer? _timer;
  bool _isMusicPlaying = true;
  
  // Estado de UI
  bool _isCreatingRoom = false;
  bool _isJoiningRoom = false;

  // Sistema de detección de salida
  int _exitCount = 0;
  int _distractionCount = 0;
  DateTime? _lastExitTime;
  Duration _totalDistractionTime = Duration.zero;
  bool _showDistractedWarning = false;
  
  // Estadísticas de sesión
  int _focusScore = 100; // Empieza en 100, baja con distracciones
  List<DateTime> _distractionTimestamps = [];
  
  // Contador de sesiones diarias
  int _todaySessions = 0;
  DateTime? _lastSessionDate;

  FocusRoom? get currentRoom => _currentRoom;
  bool get isInFocusMode => _isInFocusMode;
  bool get isMusicPlaying => _isMusicPlaying;
  bool get isCreatingRoom => _isCreatingRoom;
  bool get isJoiningRoom => _isJoiningRoom;
  bool get hasActiveRoom => _currentRoom != null && _currentRoom!.isActive;
  
  // Getters de distracción
  int get exitCount => _exitCount;
  int get distractionCount => _distractionCount;
  Duration get totalDistractionTime => _totalDistractionTime;
  bool get showDistractedWarning => _showDistractedWarning;
  int get focusScore => _focusScore;
  List<DateTime> get distractionTimestamps => _distractionTimestamps;
  int get todaySessions => _todaySessions;

  Duration get remainingTime => _currentRoom?.remainingTime ?? Duration.zero;

  /// Crear una nueva sala de concentración
  Future<void> createRoom({
    required String name,
    required Duration duration,
    required FocusUser creator,
  }) async {
    _isCreatingRoom = true;
    notifyListeners();

    try {
      // Simular llamada a API (aquí conectarías con tu backend)
      await Future.delayed(const Duration(milliseconds: 500));

      final room = FocusRoom(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: name,
        creatorId: creator.id,
        startTime: DateTime.now(),
        duration: duration,
        participants: [creator],
        isMusicPlaying: true,
      );

      _currentRoom = room;
      _isInFocusMode = true;
      _isMusicPlaying = true;
      
      // Incrementar contador de sesiones
      _incrementTodaySessions();
      
      // Resetear contadores de distracción
      _resetDistractionMetrics();
      
      // Registrar observer para detectar salidas
      WidgetsBinding.instance.addObserver(this);
      
      _startTimer();
      await _enterFullscreen();
      
      notifyListeners();
    } finally {
      _isCreatingRoom = false;
      notifyListeners();
    }
  }

  /// Unirse a una sala existente
  Future<void> joinRoom({
    required String roomId,
    required FocusUser user,
  }) async {
    _isJoiningRoom = true;
    notifyListeners();

    try {
      // Simular llamada a API para obtener la sala
      await Future.delayed(const Duration(milliseconds: 500));

      // Aquí conectarías con tu backend para obtener la sala real
      // Por ahora, creamos una sala de ejemplo
      final room = FocusRoom(
        id: roomId,
        name: 'Sala de Estudio',
        creatorId: 'otro_usuario',
        startTime: DateTime.now().subtract(const Duration(minutes: 10)),
        duration: const Duration(hours: 2),
        participants: [
          user,
          FocusUser(
            id: 'otro_usuario',
            name: 'Estudiante MIR',
            joinedAt: DateTime.now().subtract(const Duration(minutes: 10)),
          ),
        ],
        isMusicPlaying: true,
      );

      _currentRoom = room;
      _isInFocusMode = true;
      _isMusicPlaying = room.isMusicPlaying;
      
      _startTimer();
      await _enterFullscreen();
      
      notifyListeners();
    } finally {
      _isJoiningRoom = false;
      notifyListeners();
    }
  }

  /// Salir de la sala actual
  Future<void> leaveRoom() async {
    _stopTimer();
    await _exitFullscreen();
    
    // Remover observer
    WidgetsBinding.instance.removeObserver(this);
    
    _currentRoom = null;
    _isInFocusMode = false;
    _isMusicPlaying = true;
    
    notifyListeners();
  }

  /// Toggle música de concentración
  void toggleMusic() {
    _isMusicPlaying = !_isMusicPlaying;
    
    if (_currentRoom != null) {
      _currentRoom = _currentRoom!.copyWith(isMusicPlaying: _isMusicPlaying);
    }
    
    notifyListeners();
  }

  /// Iniciar temporizador para actualizar el tiempo restante
  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_currentRoom != null) {
        if (!_currentRoom!.isActive) {
          // La sesión ha terminado
          leaveRoom();
        } else {
          notifyListeners(); // Actualizar UI con nuevo tiempo restante
        }
      } else {
        timer.cancel();
      }
    });
  }

  /// Detener temporizador
  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  /// Entrar en modo pantalla completa
  Future<void> _enterFullscreen() async {
    try {
      // Ocultar todas las barras del sistema (status bar y navigation bar)
      await SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.immersiveSticky,
        overlays: [],  // Sin overlays = pantalla totalmente limpia
      );
      
      // Configurar preferencias adicionales para máxima inmersión
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,  // Bloquear en vertical
      ]);
      
      // Establecer colores transparentes para las barras
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,  // Barra de estado transparente
          statusBarIconBrightness: Brightness.light,  // Iconos blancos
          systemNavigationBarColor: Colors.transparent,  // Barra de navegación transparente
          systemNavigationBarIconBrightness: Brightness.light,  // Iconos blancos
        ),
      );
      
      debugPrint('✅ Modo pantalla completa activado');
    } catch (e) {
      debugPrint('❌ Error entering fullscreen: $e');
    }
  }

  /// Salir del modo pantalla completa
  Future<void> _exitFullscreen() async {
    try {
      // Se vuelve a las barras normales de la app, que NO incluyen la de
      // estado: restaurarlas todas aquí la dejaría visible para siempre a
      // partir del primer focus.
      await SystemUi.apply();

      // Restaurar la política de orientación del dispositivo: móvil vertical,
      // tablet las 4 (no reabrir landscape en un móvil al salir del focus).
      await OrientationLock.apply();

      SystemUi.applyStyle();
      
      debugPrint('✅ Modo pantalla completa desactivado');
    } catch (e) {
      debugPrint('❌ Error exiting fullscreen: $e');
    }
  }

  /// Agregar participante a la sala
  void addParticipant(FocusUser user) {
    if (_currentRoom != null) {
      final updatedParticipants = List<FocusUser>.from(_currentRoom!.participants)
        ..add(user);
      
      _currentRoom = _currentRoom!.copyWith(participants: updatedParticipants);
      notifyListeners();
    }
  }

  /// Remover participante de la sala
  void removeParticipant(String userId) {
    if (_currentRoom != null) {
      final updatedParticipants = _currentRoom!.participants
          .where((p) => p.id != userId)
          .toList();
      
      _currentRoom = _currentRoom!.copyWith(participants: updatedParticipants);
      notifyListeners();
    }
  }

  /// Detectar cambios en el ciclo de vida de la app
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_isInFocusMode) return;

    switch (state) {
      case AppLifecycleState.inactive:
        // App en transición (por ejemplo, apagando pantalla, notificación pull-down)
        // NO contar como distracción todavía, solo marcar el tiempo
        _lastExitTime = DateTime.now();
        debugPrint('📱 App en transición (inactive)');
        break;
        
      case AppLifecycleState.paused:
        // App pausada - puede ser:
        // 1. Usuario apagó la pantalla (screen lock) - OK ✅
        // 2. Usuario fue a otra app - DISTRACCIÓN ❌
        // Como ambos casos llegan aquí, esperamos a ver si vuelve rápido (screen lock)
        // o tarda más (fue a otra app)
        _lastExitTime = DateTime.now();
        debugPrint('⏸️ App pausada');
        break;
        
      case AppLifecycleState.resumed:
        // Usuario volvió a la app
        _onUserReturnedToApp();
        break;
        
      case AppLifecycleState.detached:
        // App siendo cerrada
        break;
        
      case AppLifecycleState.hidden:
        // App oculta (Android 13+)
        // NOTA: Este estado también se dispara al apagar pantalla en algunos dispositivos
        // Por eso NO penalizamos aquí, dejamos que el threshold de tiempo decida
        _lastExitTime = DateTime.now();
        debugPrint('👻 App oculta (hidden)');
        break;
    }
  }

  /// Cuando el usuario vuelve a la app
  void _onUserReturnedToApp() {
    if (_lastExitTime != null) {
      final awayDuration = DateTime.now().difference(_lastExitTime!);
      
      // ESTRATEGIA: Si estuvo fuera menos de 2 segundos, probablemente solo apagó la pantalla
      // Si estuvo fuera más de 2 segundos, probablemente fue a otra app
      const screenLockThreshold = Duration(seconds: 2);
      
      if (awayDuration > screenLockThreshold) {
        // Fue a otra app o estuvo distraído más tiempo
        _exitCount++;
        _distractionCount++;
        _totalDistractionTime += awayDuration;
        _distractionTimestamps.add(DateTime.now());
        
        // Penalización adicional por tiempo fuera
        final minutesAway = awayDuration.inMinutes;
        _focusScore = (_focusScore - (minutesAway * 5).clamp(10, 50)).clamp(0, 100);
        
        // Mostrar warning
        _showDistractedWarning = true;
        
        debugPrint('⚠️ Usuario volvió después de ${awayDuration.inSeconds}s. Salidas: $_exitCount, Score: $_focusScore');
        
        notifyListeners();
        
        // Ocultar warning después de 3 segundos
        Future.delayed(const Duration(seconds: 3), () {
          _showDistractedWarning = false;
          notifyListeners();
        });
      } else {
        // Probablemente solo apagó la pantalla - NO penalizar
        debugPrint('✅ Pantalla apagada brevemente (${awayDuration.inSeconds}s) - No cuenta como distracción');
      }
      
      _lastExitTime = null;
    }
  }

  /// Resetear métricas de distracción
  void _resetDistractionMetrics() {
    _exitCount = 0;
    _distractionCount = 0;
    _lastExitTime = null;
    _totalDistractionTime = Duration.zero;
    _showDistractedWarning = false;
    _focusScore = 100;
    _distractionTimestamps.clear();
  }

  /// Obtener calificación de concentración
  String getFocusRating() {
    if (_focusScore >= 90) return '🏆 Excelente';
    if (_focusScore >= 70) return '👍 Bueno';
    if (_focusScore >= 50) return '😐 Regular';
    if (_focusScore >= 30) return '😕 Necesitas mejorar';
    return '😰 Muy distraído';
  }

  /// Obtener color para el score
  Color getFocusScoreColor() {
    if (_focusScore >= 70) return Colors.green;
    if (_focusScore >= 40) return Colors.orange;
    return Colors.red;
  }
  
  /// Incrementar contador de sesiones del día
  void _incrementTodaySessions() {
    final today = DateTime.now();
    
    // Si es un nuevo día, resetear el contador
    if (_lastSessionDate == null ||
        _lastSessionDate!.year != today.year ||
        _lastSessionDate!.month != today.month ||
        _lastSessionDate!.day != today.day) {
      _todaySessions = 1;
    } else {
      _todaySessions++;
    }
    
    _lastSessionDate = today;
  }

  @override
  void dispose() {
    _stopTimer();
    _exitFullscreen();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
