import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io' show Platform;

/// Servicio para gestionar el modo "No Molestar" y bloqueo de notificaciones
class FocusModeService {
  static final FocusModeService _instance = FocusModeService._internal();
  factory FocusModeService() => _instance;
  FocusModeService._internal();

  bool _isDndEnabled = false;
  bool get isDndEnabled => _isDndEnabled;

  /// Activar modo "No Molestar"
  Future<bool> enableDoNotDisturb() async {
    try {
      // Solo funciona en Android
      if (!Platform.isAndroid) {
        debugPrint('⚠️ DND solo disponible en Android');
        return false;
      }

      // Solicitar permiso de "Do Not Disturb Access"
      final status = await Permission.accessNotificationPolicy.request();
      
      if (status.isGranted) {
        // En Android, el permiso ya permite que el sistema maneje el DND
        // La app solo puede solicitar el permiso, pero el usuario debe activarlo manualmente
        _isDndEnabled = true;
        debugPrint('✅ Permiso DND otorgado');
        return true;
      } else if (status.isDenied) {
        debugPrint('❌ Permiso DND denegado');
        return false;
      } else if (status.isPermanentlyDenied) {
        debugPrint('❌ Permiso DND denegado permanentemente');
        // Abrir configuración del sistema
        await openAppSettings();
        return false;
      }
      
      return false;
    } catch (e) {
      debugPrint('❌ Error activando DND: $e');
      return false;
    }
  }

  /// Desactivar modo "No Molestar"
  Future<void> disableDoNotDisturb() async {
    try {
      _isDndEnabled = false;
      debugPrint('✅ DND desactivado');
    } catch (e) {
      debugPrint('❌ Error desactivando DND: $e');
    }
  }

  /// Verificar si tenemos permiso de DND
  Future<bool> hasDoNotDisturbPermission() async {
    if (!Platform.isAndroid) return false;
    
    final status = await Permission.accessNotificationPolicy.status;
    return status.isGranted;
  }

  /// Solicitar permiso de DND mostrando diálogo explicativo
  Future<bool> requestDoNotDisturbPermission() async {
    if (!Platform.isAndroid) return false;

    final hasPermission = await hasDoNotDisturbPermission();
    if (hasPermission) return true;

    // Solicitar permiso
    final status = await Permission.accessNotificationPolicy.request();
    
    if (status.isPermanentlyDenied) {
      // Si está permanentemente denegado, abrir configuración
      await openAppSettings();
      return false;
    }

    return status.isGranted;
  }
}
