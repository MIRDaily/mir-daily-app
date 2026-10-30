// GramSwipe: clasificar antibióticos por su espectro deslizando la tarjeta. Puerto de la web:
// src/components/minijuegos/gramswipe (GramSwipeGame.tsx y data.ts). Todo pasa en el cliente: no
// hay servidor ni cuenta para estadísticas.
//
//   → Gram +    ← Gram −    ↑ Amplio espectro    ↓ No sé (la tarjeta vuelve al final del mazo)
//
// Aquí solo la lógica, sin Flutter: la partida es una cola de tarjetas que se va vaciando.

import 'dart:math' as math;

enum Cobertura { gramPositivo, gramNegativo, amplio }

const Map<Cobertura, String> etiquetaCobertura = {
  Cobertura.gramPositivo: 'Gram +',
  Cobertura.gramNegativo: 'Gram −',
  Cobertura.amplio: 'Amplio espectro',
};

class Antibiotico {
  final int id;
  final String nombre;
  final String principioActivo;
  final String familia;
  final String mecanismo;
  final Cobertura cobertura;
  final String foto;

  const Antibiotico({
    required this.id,
    required this.nombre,
    required this.principioActivo,
    required this.familia,
    required this.mecanismo,
    required this.cobertura,
    required this.foto,
  });
}

enum DireccionSwipe { derecha, izquierda, arriba, abajo }

/// La respuesta que da cada dirección; abajo es «no sé».
Cobertura? coberturaDe(DireccionSwipe d) => switch (d) {
      DireccionSwipe.derecha => Cobertura.gramPositivo,
      DireccionSwipe.izquierda => Cobertura.gramNegativo,
      DireccionSwipe.arriba => Cobertura.amplio,
      DireccionSwipe.abajo => null,
    };

/// Cuánto hay que arrastrar (px) para que cuente, y cuánto para que empiece a ser arrastre y no toque.
const double umbralSwipe = 90;
const double umbralArrastre = 8;

/// Hacia dónde apunta un arrastre: manda el eje con más recorrido.
DireccionSwipe direccionDeArrastre(double dx, double dy) {
  if (dx.abs() > dy.abs()) return dx > 0 ? DireccionSwipe.derecha : DireccionSwipe.izquierda;
  return dy < 0 ? DireccionSwipe.arriba : DireccionSwipe.abajo;
}

/// 0..1: lo cerca que está un arrastre de contar.
double intensidadArrastre(double dx, double dy) => (math.max(dx.abs(), dy.abs()) / umbralSwipe).clamp(0.0, 1.0);

/// El arrastre al soltar: la dirección si pasó el umbral en su eje, o null (vuelve a su sitio).
DireccionSwipe? direccionAlSoltar(double dx, double dy) {
  if (dx.abs() > dy.abs()) {
    return dx.abs() > umbralSwipe ? (dx > 0 ? DireccionSwipe.derecha : DireccionSwipe.izquierda) : null;
  }
  return dy.abs() > umbralSwipe ? (dy < 0 ? DireccionSwipe.arriba : DireccionSwipe.abajo) : null;
}

class RespuestaGramSwipe {
  final Antibiotico tarjeta;
  final DireccionSwipe direccion;

  const RespuestaGramSwipe(this.tarjeta, this.direccion);

  bool get acierto => coberturaDe(direccion) == tarjeta.cobertura;
  Cobertura? get marcada => coberturaDe(direccion);
}

class PartidaGramSwipe {
  final List<Antibiotico> _cola;
  final List<RespuestaGramSwipe> respondidas = [];
  final Set<int> saltadas = {};

  /// Las tarjetas con que empezó la partida (para la barra de progreso).
  final int total;

  PartidaGramSwipe(List<Antibiotico> mazo)
      : _cola = List.of(mazo),
        total = mazo.length;

  /// Una partida con el mazo barajado (Fisher-Yates, como `shuffleArray` de la web).
  factory PartidaGramSwipe.barajada(List<Antibiotico> mazo, [math.Random? azar]) {
    final a = List.of(mazo);
    final r = azar ?? math.Random();
    for (var i = a.length - 1; i > 0; i--) {
      final j = r.nextInt(i + 1);
      final t = a[i];
      a[i] = a[j];
      a[j] = t;
    }
    return PartidaGramSwipe(a);
  }

  List<Antibiotico> get cola => List.unmodifiable(_cola);
  Antibiotico? get actual => _cola.isEmpty ? null : _cola.first;
  bool get terminada => _cola.isEmpty;

  int get aciertos => respondidas.where((r) => r.acierto).length;
  int get fallos => respondidas.length - aciertos;

  /// Porcentaje entero de aciertos sobre lo respondido (lo saltado no cuenta).
  int get precision => respondidas.isEmpty ? 0 : (aciertos * 100 / respondidas.length).round();

  List<Antibiotico> get falladas => [for (final r in respondidas) if (!r.acierto) r.tarjeta];

  /// Clasifica la tarjeta de arriba. Abajo («no sé») la manda al final del mazo y no puntúa; devuelve
  /// la respuesta en el resto de direcciones.
  RespuestaGramSwipe? deslizar(DireccionSwipe d) {
    if (_cola.isEmpty) return null;
    final t = _cola.removeAt(0);
    if (d == DireccionSwipe.abajo) {
      _cola.add(t);
      saltadas.add(t.id);
      return null;
    }
    final r = RespuestaGramSwipe(t, d);
    respondidas.add(r);
    return r;
  }

  /// Nueva partida solo con las falladas, barajadas.
  PartidaGramSwipe repetirErrores([math.Random? azar]) => PartidaGramSwipe.barajada(falladas, azar);
}

/// El titular del resultado, como la web.
String tituloResultadoGramSwipe(int precision) => precision == 100
    ? '¡Perfecto!'
    : precision >= 70
        ? '¡Muy bien!'
        : 'Sigue practicando';
