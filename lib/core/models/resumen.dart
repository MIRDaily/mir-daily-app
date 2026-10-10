// Modelos de los "Resúmenes activos": grupos de párrafos con huecos que se
// estudian destapando y autoevaluando. Reflejan los contratos del backend
// compartido con la web (src/lib/resumenes/api.ts y huecos.ts).

/// Nivel de un hueco y nota de repaso (FSRS): 1-4.
const int nivelMinResumen = 1;
const int nivelMaxResumen = 4;
const List<int> nivelesResumen = [1, 2, 3, 4];

const int maxHuecosResumen = 8;
const int minTextoResumen = 20;
const int maxTextoResumen = 800;
const int maxTemaResumen = 120;

bool esNivelResumen(Object? v) => v is int && v >= 1 && v <= 4;

/// Cómo se generó un párrafo: la IA condensa (`resumen`) o copia el texto
/// original (`literal`).
enum ModoResumen { resumen, literal }

/// Un hueco: el trozo `texto[i, f)` se tapa al estudiar y `n` (1-4) es su nivel.
class Hueco {
  final int i;
  final int f;
  final int n;

  const Hueco(this.i, this.f, this.n);

  Hueco copyWith({int? i, int? f, int? n}) => Hueco(i ?? this.i, f ?? this.f, n ?? this.n);

  Map<String, dynamic> toJson() => {'i': i, 'f': f, 'n': n};
}

/// Cuentas por estado de un grupo.
class ResumenEstados {
  final int nuevo;
  final int failed;
  final int learning;
  final int mastered;

  const ResumenEstados({
    required this.nuevo,
    required this.failed,
    required this.learning,
    required this.mastered,
  });
}

/// De dónde sale un párrafo (documento, página y un fragmento corto).
class OrigenGuardado {
  final String? name;
  final int? page;
  final String? unit; // 'pagina' | 'diapositiva'
  final String? fragmento;

  const OrigenGuardado({this.name, this.page, this.unit, this.fragmento});
}

/// Estado SRS de un párrafo (derivado por el servidor).
enum EstadoParrafoSrs { new_, failed, learning, mastered }

class GrupoResumen {
  final String id;
  final String name;
  final String? description;
  final String? color;
  final String? icon;
  final String? createdAt;
  final int total;
  final int pendientes;
  final ResumenEstados resumen;

  const GrupoResumen({
    required this.id,
    required this.name,
    this.description,
    this.color,
    this.icon,
    this.createdAt,
    required this.total,
    required this.pendientes,
    required this.resumen,
  });
}

class Parrafo {
  final int itemId;
  final String id;
  final String? tema;
  final ModoResumen modo;
  final String texto;
  final List<Hueco> huecos;
  final bool aiGenerated;
  final OrigenGuardado? origen;
  final EstadoParrafoSrs? status;
  final bool? due;
  final String? nextDueAt;

  /// Posiciones de los huecos cuyo último resultado fue «No lo sabía».
  final List<int>? huecosFallados;
  final int fallos;

  const Parrafo({
    required this.itemId,
    required this.id,
    this.tema,
    required this.modo,
    required this.texto,
    required this.huecos,
    required this.aiGenerated,
    this.origen,
    this.status,
    this.due,
    this.nextDueAt,
    this.huecosFallados,
    required this.fallos,
  });
}

/// Párrafo nuevo para crear (a mano o desde la IA).
class ParrafoNuevo {
  final String? tema;
  final ModoResumen? modo;
  final String texto;
  final List<Hueco> huecos;
  final OrigenGuardado? origen;

  const ParrafoNuevo({this.tema, this.modo, required this.texto, required this.huecos, this.origen});

  Map<String, dynamic> toJson() => {
        if (tema != null) 'tema': tema,
        if (modo != null) 'modo': modo == ModoResumen.literal ? 'literal' : 'resumen',
        'texto': texto,
        'huecos': huecos.map((h) => h.toJson()).toList(),
        if (origen != null)
          'origen': {
            if (origen!.name != null) 'name': origen!.name,
            if (origen!.page != null) 'page': origen!.page,
            if (origen!.unit != null) 'unit': origen!.unit,
            if (origen!.fragmento != null) 'fragmento': origen!.fragmento,
          },
      };
}

/// Ajustes de una sesión de estudio.
class AjustesEstudio {
  final List<int>? levels;
  final List<String>? topics;
  final String? onlyStatus; // 'failed' | 'due' | 'new'
  final int? cardLimit;
  final bool? soloHuecosFallados;
  final List<int>? itemIds;

  const AjustesEstudio({
    this.levels,
    this.topics,
    this.onlyStatus,
    this.cardLimit,
    this.soloHuecosFallados,
    this.itemIds,
  });

  Map<String, dynamic> toJson() => {
        if (levels != null) 'levels': levels,
        if (topics != null) 'topics': topics,
        if (onlyStatus != null) 'onlyStatus': onlyStatus,
        if (cardLimit != null) 'cardLimit': cardLimit,
        if (soloHuecosFallados != null) 'soloHuecosFallados': soloHuecosFallados,
        if (itemIds != null) 'itemIds': itemIds,
      };
}
