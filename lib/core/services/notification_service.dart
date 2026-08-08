import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tzdata;

/// Notificaciones locales de la app. Por ahora: un recordatorio DIARIO de que el
/// sobre del daily está listo (equivalente a la web, que avisa cuando hay daily),
/// programado en el dispositivo con flutter_local_notifications (sin push/FCM).
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  // Ids / claves.
  static const int _dailyReminderId = 1001;
  static const String _channelId = 'daily_reminder';
  static const String _channelName = 'Recordatorio del daily';
  static const String _prefEnabled = 'daily_reminder_enabled';
  static const String _prefHour = 'daily_reminder_hour';
  static const String _prefMinute = 'daily_reminder_minute';
  static const String _prefPrompted = 'daily_reminder_prompted';

  // Valor por defecto del recordatorio: 10:00.
  static const int _defaultHour = 10;
  static const int _defaultMinute = 0;

  /// Inicializa el plugin y las zonas horarias. Idempotente.
  Future<void> init() async {
    if (_initialized) return;
    try {
      tzdata.initializeTimeZones();
      // Audiencia MIR (España). Si en el futuro hay usuarios fuera, cambiar por
      // la zona del dispositivo (p. ej. con flutter_timezone).
      tz.setLocalLocation(tz.getLocation('Europe/Madrid'));

      const androidInit =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwinInit = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      await _plugin.initialize(
        const InitializationSettings(android: androidInit, iOS: darwinInit),
      );

      // Canal Android (obligatorio en Android 8+).
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: 'Aviso diario de que tu sobre del daily está listo.',
          importance: Importance.high,
        ),
      );
      _initialized = true;
    } catch (e) {
      debugPrint('NotificationService.init error: $e');
    }
  }

  /// Pide permiso de notificaciones (Android 13+ / iOS). Devuelve si está concedido.
  Future<bool> requestPermission() async {
    await init();
    try {
      if (Platform.isAndroid) {
        final granted = await _plugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission();
        return granted ?? true; // en <13 no hay permiso runtime
      }
      if (Platform.isIOS) {
        final granted = await _plugin
            .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin>()
            ?.requestPermissions(alert: true, badge: true, sound: true);
        return granted ?? false;
      }
    } catch (e) {
      debugPrint('NotificationService.requestPermission error: $e');
    }
    return false;
  }

  // ---- Estado persistido ----
  Future<bool> isEnabled() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_prefEnabled) ?? false;
  }

  Future<TimeOfDay> reminderTime() async {
    final p = await SharedPreferences.getInstance();
    return TimeOfDay(
      hour: p.getInt(_prefHour) ?? _defaultHour,
      minute: p.getInt(_prefMinute) ?? _defaultMinute,
    );
  }

  Future<bool> wasPrompted() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_prefPrompted) ?? false;
  }

  Future<void> _markPrompted() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_prefPrompted, true);
  }

  // ---- Acciones ----

  /// Activa el recordatorio diario a [time] (pide permiso). Devuelve true si se
  /// programó (permiso concedido).
  Future<bool> enableDailyReminder(TimeOfDay time) async {
    await init();
    final granted = await requestPermission();
    if (!granted) {
      await _markPrompted();
      return false;
    }
    await _scheduleDaily(time);
    final p = await SharedPreferences.getInstance();
    await p.setBool(_prefEnabled, true);
    await p.setInt(_prefHour, time.hour);
    await p.setInt(_prefMinute, time.minute);
    await _markPrompted();
    return true;
  }

  /// Desactiva y cancela el recordatorio.
  Future<void> disableDailyReminder() async {
    await init();
    try {
      await _plugin.cancel(_dailyReminderId);
    } catch (_) {}
    final p = await SharedPreferences.getInstance();
    await p.setBool(_prefEnabled, false);
    await _markPrompted();
  }

  /// Reprograma el recordatorio al arrancar si el usuario lo tenía activado
  /// (por si se perdió tras reinicio/actualización).
  Future<void> rescheduleIfEnabled() async {
    await init();
    if (!await isEnabled()) return;
    await _scheduleDaily(await reminderTime());
  }

  Future<void> _scheduleDaily(TimeOfDay time) async {
    try {
      await _plugin.cancel(_dailyReminderId);
      await _plugin.zonedSchedule(
        _dailyReminderId,
        'Tu daily de hoy está listo 📩',
        'Abre tu sobre diario, pon a prueba tu conocimiento y mantén tu racha.',
        _nextInstanceOf(time.hour, time.minute),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription:
                'Aviso diario de que tu sobre del daily está listo.',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time, // se repite cada día
      );
    } catch (e) {
      debugPrint('NotificationService._scheduleDaily error: $e');
    }
  }

  tz.TZDateTime _nextInstanceOf(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }
}
