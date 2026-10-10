// Tipos de la IA de MIRDaily (mapas, flashcards y resúmenes activos).
//
// El texto se extrae EN EL DISPOSITIVO: el archivo nunca se sube; al servidor
// solo viaja el texto (misma arquitectura que la web). Refleja los contratos
// del backend compartido con la web: src/lib/mapas/ia/types.ts y stream.ts.

/// Una sección de texto extraída de un documento. `pagina` es el número de
/// página o diapositiva de origen (para la revisión guiada).
class Seccion {
  final String? titulo;
  final String texto;
  final int? pagina;

  const Seccion({this.titulo, required this.texto, this.pagina});

  Map<String, dynamic> toJson() => {
        if (titulo != null) 'titulo': titulo,
        'texto': texto,
        if (pagina != null) 'pagina': pagina,
      };

  factory Seccion.fromJson(Map<String, dynamic> j) => Seccion(
        titulo: j['titulo'] is String ? j['titulo'] as String : null,
        texto: (j['texto'] ?? '').toString(),
        pagina: j['pagina'] is int ? j['pagina'] as int : null,
      );
}

/// Fases del diálogo de generación, en orden.
enum FaseIa { leyendo, estructura, tablas, tarjetas, parrafos, ordenando }

/// Estado de un tema en un documento largo (tema a tema).
enum EstadoTema { empieza, listo, fallo }

/// Una línea provisional de una rama mientras el modelo escribe.
class LineaProvisional {
  final int parte;
  final int? tema;
  final int d;
  final String t;

  const LineaProvisional({
    required this.parte,
    this.tema,
    required this.d,
    required this.t,
  });
}

/// Rama reconstruida a partir de las líneas provisionales (vista previa).
class RamaProvisional {
  final String key;
  final String t;
  final List<RamaProvisional> hijos;

  const RamaProvisional({required this.key, required this.t, required this.hijos});
}

/// Referencia a un tema de un documento largo (título y tamaño en caracteres).
class TemaRef {
  final String titulo;
  final int chars;
  const TemaRef({required this.titulo, required this.chars});
}

/// Evento recibido por el canal de streaming (NDJSON). Los eventos desconocidos
/// se descartan, así que `leerEvento` devuelve null para ellos.
sealed class EventoIa {
  const EventoIa();
}

class EventoFase extends EventoIa {
  final FaseIa fase;
  const EventoFase(this.fase);
}

class EventoRama extends EventoIa {
  final int parte;
  final int? tema;
  final int d;
  final String t;
  const EventoRama({required this.parte, this.tema, required this.d, required this.t});
}

class EventoReinicio extends EventoIa {
  final int parte;
  final int? tema;
  const EventoReinicio({required this.parte, this.tema});
}

class EventoTemas extends EventoIa {
  final List<TemaRef> temas;
  const EventoTemas(this.temas);
}

class EventoTema extends EventoIa {
  final int i;
  final EstadoTema estado;
  final int? nodos;
  const EventoTema({required this.i, required this.estado, this.nodos});
}

class EventoLatido extends EventoIa {
  const EventoLatido();
}

/// Datos finales validados (sin el campo `tipo`).
class EventoFin extends EventoIa {
  final Map<String, dynamic> datos;
  const EventoFin(this.datos);
}

class EventoError extends EventoIa {
  final String error;
  final String codigo;
  final int status;
  const EventoError({required this.error, required this.codigo, required this.status});
}

/// Un apartado dentro de un tema del índice (para el selector «Qué parte usar»).
class ApartadoIndice {
  final String titulo;
  final int desde;
  const ApartadoIndice({required this.titulo, required this.desde});
}

/// Un tema del índice de un documento largo (rangos sobre las secciones).
class TemaIndice {
  final String titulo;
  final int desde;
  final int hasta;
  final int chars;
  final int? paginaDesde;
  final int? paginaHasta;
  final List<ApartadoIndice> apartados;

  const TemaIndice({
    required this.titulo,
    required this.desde,
    required this.hasta,
    required this.chars,
    this.paginaDesde,
    this.paginaHasta,
    required this.apartados,
  });
}

/// Un marcador del índice de un documento (título y página donde empieza).
class Marcador {
  final String titulo;
  final int pagina;
  final int nivel; // 1 o 2
  const Marcador({required this.titulo, required this.pagina, required this.nivel});
}

/// Resultado de leer un documento: texto por secciones + metadatos.
class Extraido {
  final String titulo;
  final List<Seccion> secciones;
  final int paginas;
  final int tablas;

  /// Cómo se llaman las «páginas» de este formato: 'página' | 'diapositiva'.
  final String unidad;
  final int caracteres;
  final List<String> avisos;
  final bool truncado;
  final List<Marcador>? marcadores;

  const Extraido({
    required this.titulo,
    required this.secciones,
    required this.paginas,
    required this.tablas,
    required this.unidad,
    required this.caracteres,
    required this.avisos,
    required this.truncado,
    this.marcadores,
  });
}

/// Error de extracción de un documento, con mensaje listo para el usuario.
class ExtractException implements Exception {
  final String message;
  const ExtractException(this.message);

  @override
  String toString() => message;
}

/// Error con mensaje listo para enseñar al usuario. Espeja `IAError` de la web:
/// el permiso (rol admin, interruptor y cupos) lo valida SIEMPRE el backend.
class IaException implements Exception {
  final String message;
  final int status;
  final String codigo;

  const IaException(this.message, {this.status = 0, this.codigo = ''});

  @override
  String toString() => message;
}
