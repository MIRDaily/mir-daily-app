// Cuándo se abrió cada mapa en ESTE móvil, para que «Recientes» cuente las aperturas además de las
// ediciones (la BD solo sabe de ediciones: `updated_at`). Va en el propio móvil y por cuenta: no se
// comparte con la web ni con otro dispositivo, y no toca el servidor.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class AperturasMapas {
  AperturasMapas._();

  /// Como mucho tantas: las más viejas se olvidan.
  static const int maximo = 300;

  static String _clave(String cuenta) => 'mapas.aperturas.$cuenta';

  static Future<Map<String, DateTime>> leer(String cuenta) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_clave(cuenta));
      if (raw == null) return {};
      final j = jsonDecode(raw);
      if (j is! Map) return {};
      return {
        for (final e in j.entries)
          if (e.key is String && e.value is int) e.key as String: DateTime.fromMillisecondsSinceEpoch(e.value as int),
      };
    } catch (_) {
      return {};
    }
  }

  /// Apunta que [mapaId] se abrió [cuando]. Devuelve todas las aperturas tal como quedan.
  static Future<Map<String, DateTime>> apuntar(String cuenta, String mapaId, DateTime cuando) async {
    final todas = await leer(cuenta)
      ..[mapaId] = cuando;
    final ordenadas = todas.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final quedan = Map.fromEntries(ordenadas.take(maximo));
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _clave(cuenta),
        jsonEncode({for (final e in quedan.entries) e.key: e.value.millisecondsSinceEpoch}),
      );
    } catch (_) {
      // Sin almacenamiento, la lista sigue ordenándose por edición.
    }
    return quedan;
  }
}
