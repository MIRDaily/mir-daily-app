import 'package:flutter/foundation.dart';

/// Las pestañas de la barra, en su orden (Studio, Versus, Quiz, Premium, Perfil).
enum PestanaApp { studio, versus, quiz, premium, perfil }

/// Para cambiar de pestaña desde una pantalla apilada encima (p. ej. la bandeja de avisos, que lleva
/// al daily): se vuelve a la raíz y se pide aquí. [MainNavigation] lo escucha y lo consume.
final ValueNotifier<PestanaApp?> pestanaPedida = ValueNotifier<PestanaApp?>(null);
