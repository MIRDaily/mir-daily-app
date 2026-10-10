// Modelos de la generación de resúmenes con IA: lo que devuelve el servidor y
// se guarda como borrador local antes de aprobarlo. Reflejan los contratos de
// la web (src/lib/resumenes/borrador.ts e ia.ts).

import 'resumen.dart';

/// Densidad de los huecos al generar: pocos, normal o muchos.
enum Densidad {
  pocas('pocas'),
  normal('normal'),
  muchas('muchas');

  const Densidad(this.id);
  final String id;
}

/// Lo que dice la revisión de la IA de un párrafo: origen y si es dudoso.
class OrigenParrafo {
  final int? pagina;
  final int? diapositiva;
  final String? seccion;
  final String? dudoso;
  final String? fragmento;

  const OrigenParrafo({this.pagina, this.diapositiva, this.seccion, this.dudoso, this.fragmento});
}

/// De qué documento salen unos párrafos, firmado por el servidor (no se cambia).
class FuenteFirmada {
  final String hash; // 64 hex
  final int caracteres;
  final String firma; // 64 hex

  const FuenteFirmada({required this.hash, required this.caracteres, required this.firma});

  Map<String, dynamic> toJson() => {'hash': hash, 'caracteres': caracteres, 'firma': firma};
}

/// Un párrafo de la vista previa (aún no guardado en el grupo).
class ParrafoBorrador {
  final String key;
  final String tema;
  final String texto;
  final List<Hueco> huecos;
  final bool incluir;

  /// En un documento tema a tema, el tema del libro.
  final String? grupo;
  final OrigenParrafo? ia;

  /// Hash de su fuente firmada.
  final String? doc;
  final bool incluirParecido;
  final bool nuevo;

  const ParrafoBorrador({
    required this.key,
    required this.tema,
    required this.texto,
    required this.huecos,
    required this.incluir,
    this.grupo,
    this.ia,
    this.doc,
    this.incluirParecido = false,
    this.nuevo = false,
  });

  ParrafoBorrador copyWith({bool? incluir}) => ParrafoBorrador(
        key: key,
        tema: tema,
        texto: texto,
        huecos: huecos,
        incluir: incluir ?? this.incluir,
        grupo: grupo,
        ia: ia,
        doc: doc,
        incluirParecido: incluirParecido,
        nuevo: nuevo,
      );
}

/// Un borrador local: lo generado (y editado) aún sin guardar, por documento.
class BorradorResumen {
  final String clave;
  final String usuario;
  final String documento; // SHA-256 del archivo (o «documento»)
  final String titulo;
  final String nombreGrupo;
  final ModoResumen modo;
  final String? fuenteNombre;
  final String? fuenteUnidad;
  final List<FuenteFirmada> fuentes;
  final List<ParrafoBorrador> lista;
  final List<String> fallidos;
  final int creado;
  final int actualizado;
  final int caduca;

  const BorradorResumen({
    required this.clave,
    required this.usuario,
    required this.documento,
    required this.titulo,
    required this.nombreGrupo,
    required this.modo,
    this.fuenteNombre,
    this.fuenteUnidad,
    required this.fuentes,
    required this.lista,
    required this.fallidos,
    required this.creado,
    required this.actualizado,
    required this.caduca,
  });
}

/// Resultado de generar (un documento, o un libro tema a tema).
class ResumenGenerado {
  final String titulo;
  final List<ParrafoBorrador> parrafos;
  final List<TemaGenerado> temas;
  final List<({int i, String titulo, String motivo})> fallidos;
  final List<FuenteFirmada> fuentes;

  const ResumenGenerado({
    required this.titulo,
    required this.parrafos,
    required this.temas,
    required this.fallidos,
    required this.fuentes,
  });

  bool get esLibro => temas.isNotEmpty;
}

class TemaGenerado {
  final int i;
  final String titulo;
  final List<ParrafoBorrador> parrafos;
  const TemaGenerado({required this.i, required this.titulo, required this.parrafos});
}
