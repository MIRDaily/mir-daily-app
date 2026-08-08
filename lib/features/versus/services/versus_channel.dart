import 'dart:async';

import 'package:realtime_client/realtime_client.dart';

import '../../../core/config/app_config.dart';

/// Escucha el canal en vivo de una sala de Versus.
///
/// El canal es PÚBLICO (cualquiera que conozca el PIN puede escuchar), así que
/// el servidor solo emite por aquí lo que puede verse en cada fase: durante la
/// pregunta viaja el enunciado y un contador anónimo, en `picks` qué eligió
/// cada uno pero todavía no la correcta, y la corrección solo en `reveal`. Por
/// eso basta la anon key y no hace falta el JWT del usuario.
///
/// Se usa `realtime_client` a pelo en vez de `supabase_flutter`: la app tiene su
/// propia capa de auth contra la API REST de Supabase y no necesita (ni debe
/// duplicar) el cliente completo.
class VersusChannel {
  final String pin;

  /// Un evento del servidor: `players`, `progress`, `question`, `picks`,
  /// `reveal`, `ended` o `room_closed`.
  final void Function(String event, Map<String, dynamic> payload) onEvent;

  /// Cambio de conexión. Al pasar a true hay que RESINCRONIZAR con el backend:
  /// mientras el socket estuvo caído pudieron pasar rondas enteras y esos
  /// broadcasts se perdieron para siempre.
  final void Function(bool connected) onConnectionChange;

  RealtimeClient? _client;
  RealtimeChannel? _channel;
  bool _disposed = false;

  VersusChannel({
    required this.pin,
    required this.onEvent,
    required this.onConnectionChange,
  });

  static const List<String> _events = [
    'players',
    'progress',
    'question',
    'picks',
    'reveal',
    'ended',
    'host_changed',
    'continue',
    'rematch',
    'rematch_ready',
    'room_closed',
  ];

  void connect() {
    if (_disposed || _channel != null) return;

    final client = RealtimeClient(
      // wss://<ref>.supabase.co/realtime/v1
      '${AppConfig.supabaseUrl.replaceFirst('https://', 'wss://')}/realtime/v1',
      params: {'apikey': AppConfig.supabaseAnonKey},
    );
    _client = client;

    // El topic tiene que ser el mismo que compone roomTopic() en el backend.
    final channel = client.channel('versus:$pin');
    _channel = channel;

    for (final event in _events) {
      channel.onBroadcast(
        event: event,
        callback: (payload) {
          if (_disposed) return;
          onEvent(event, _unwrap(payload));
        },
      );
    }

    channel.subscribe((status, error) {
      if (_disposed) return;
      onConnectionChange(status == RealtimeSubscribeStatus.subscribed);
    });
  }

  /// Comprobado contra el Supabase de producción: `realtime_client` entrega el
  /// contenido del broadcast APLANADO (las claves del payload en el primer
  /// nivel, más `event` y `type`), no anidado bajo `payload` como en JS. Se
  /// admiten las dos formas porque la de aquí depende de la versión del
  /// protocolo que negocien cliente y servidor, y equivocarse dejaría todos los
  /// campos a null sin ningún error visible.
  static Map<String, dynamic> _unwrap(Map<String, dynamic> payload) {
    final inner = payload['payload'];
    if (inner is Map) return Map<String, dynamic>.from(inner);
    return payload;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    final channel = _channel;
    final client = _client;
    _channel = null;
    _client = null;

    try {
      if (channel != null) await client?.removeChannel(channel);
      await client?.disconnect();
    } catch (_) {
      // Cerrar un socket que ya se cayó no es un problema que deba propagarse.
    }
  }
}
