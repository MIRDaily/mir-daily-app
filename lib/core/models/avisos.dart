// Bandeja de avisos (notificaciones del servidor): GET /api/notifications y compañía.
// Puerto de la web: src/service/api/notifications.js (formato de la hora e icono).
//
// No confundir con el recordatorio local del daily (core/services/notification_service.dart):
// ese lo programa el teléfono; estos los escribe el servidor (daily disponible, reporte revisado…).

class Aviso {
  final String id;
  final String title;
  final String body;
  final String kind;
  final String type;
  final String icon;
  final String? actionUrl;
  final bool unread;
  final DateTime? createdAt;
  final num? metricValue;
  final String? metricUnit;

  const Aviso({
    required this.id,
    required this.title,
    required this.body,
    this.kind = '',
    this.type = '',
    this.icon = '',
    this.actionUrl,
    required this.unread,
    this.createdAt,
    this.metricValue,
    this.metricUnit,
  });

  factory Aviso.fromJson(Map<String, dynamic> j) => Aviso(
        id: '${j['id']}',
        title: '${j['title'] ?? ''}',
        body: '${j['body'] ?? ''}',
        kind: '${j['kind'] ?? ''}',
        type: '${j['type'] ?? ''}',
        icon: '${j['icon'] ?? ''}',
        actionUrl: j['actionUrl'] is String && (j['actionUrl'] as String).isNotEmpty ? j['actionUrl'] as String : null,
        unread: j['unread'] == true,
        createdAt: j['createdAt'] is String ? DateTime.tryParse(j['createdAt'] as String) : null,
        metricValue: j['metricValue'] is num ? j['metricValue'] as num : null,
        metricUnit: j['metricUnit'] is String ? j['metricUnit'] as String : null,
      );

  Aviso leido() => Aviso(
        id: id,
        title: title,
        body: body,
        kind: kind,
        type: type,
        icon: icon,
        actionUrl: actionUrl,
        unread: false,
        createdAt: createdAt,
        metricValue: metricValue,
        metricUnit: metricUnit,
      );

  /// La línea de la métrica, como la web («12 preguntas»). Vacía si no hay.
  String get metrica => [if (metricValue != null) '$metricValue', if (metricUnit != null) metricUnit!].join(' ');
}

/// «Hace unos minutos», «Hace 3 h», «Ayer» o dd/mm/aaaa, igual que `formatNotificationTime`.
String horaAviso(DateTime? fecha, {DateTime? ahora}) {
  if (fecha == null) return '';
  final now = (ahora ?? DateTime.now()).toLocal();
  final d = fecha.toLocal();
  final horas = now.difference(d).inMinutes ~/ 60;
  if (horas < 1) return 'Hace unos minutos';
  if (horas < 24) return 'Hace $horas h';
  final ayer = DateTime(now.year, now.month, now.day - 1);
  if (d.year == ayer.year && d.month == ayer.month && d.day == ayer.day) return 'Ayer';
  String dos(int n) => n.toString().padLeft(2, '0');
  return '${dos(d.day)}/${dos(d.month)}/${d.year}';
}

/// Nombre del Material Symbol del aviso, con las mismas reglas que `resolveNotificationIcon`.
String iconoAviso(Aviso a) {
  const porTipo = {'daily_available': 'mail', 'daily_expiring': 'hourglass_bottom'};
  final type = a.type.trim().toLowerCase();
  if (porTipo.containsKey(type)) return porTipo[type]!;
  final icon = a.icon.trim().toLowerCase();
  final kind = a.kind.trim().toLowerCase();
  final title = a.title.trim().toLowerCase();
  if (icon.contains('daily') || title.contains('daily') || kind == 'study') return 'mail';
  if (icon.isNotEmpty && RegExp(r'^[a-z0-9_]+$').hasMatch(icon)) return icon;
  return 'notifications';
}

/// Adónde lleva tocar el aviso en la app. Hoy el servidor solo manda `/dashboard` (el daily); el resto
/// de rutas de la web no tienen equivalente y el aviso solo se marca como leído.
enum DestinoAviso { daily }

DestinoAviso? destinoAviso(String? actionUrl) {
  if (actionUrl == null) return null;
  final ruta = actionUrl.split('?').first.split('#').first;
  if (ruta == '/dashboard' || ruta.startsWith('/dashboard/')) return DestinoAviso.daily;
  return null;
}

/// Contador para el globo: «9+» a partir de 10, nada con 0.
String? textoGlobo(int n) => n <= 0 ? null : (n > 9 ? '9+' : '$n');
