import 'dart:io' show Platform;

/// Si se pueden crear reproductores de `audioplayers`. En los tests no hay plugin nativo y construir
/// un `AudioPlayer` lanza un error asíncrono que no se puede capturar: ahí los sonidos cortos (la voz
/// de la mascota, el pitido del monitor) se quedan mudos y se prueban solo sus decisiones.
final bool audioNativoDisponible = () {
  try {
    return !Platform.environment.containsKey('FLUTTER_TEST');
  } catch (_) {
    return true;
  }
}();
