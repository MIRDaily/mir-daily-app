import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/sticker/sticker.dart';
import '../../../shared/sticker/textures.dart';
import 'profile_card_fields.dart';

/// El carné del perfil.
///
/// Vive aparte de la pantalla por dos razones: eran 150 líneas dentro de un
/// fichero de mil, y así se puede renderizar en un test sin montar media app
/// con sus providers.
///
/// Se lee como un documento acreditativo de arriba abajo: **número de serie,
/// foto y datos, presentación y firma**. Qué campos aparecen lo decide el
/// usuario (ver [CardField]), así que el carné se adapta sin dejar huecos.
class ProfileCard extends StatelessWidget {
  final String name;
  final String handle;

  /// La imagen del avatar ya construida. Se inyecta en vez de resolverla aquí
  /// para que el carné no dependa de la red ni de la configuración: así se
  /// puede pintar en un test.
  final Widget avatar;
  final bool isPremium;

  /// Estatus académico ya resuelto: "Estudiante de 3º", "Médico/a"…
  final String? estatus;
  final String? especialidad;
  final String? universidad;

  /// Presentación libre. Si está vacía se enseña una invitación a escribirla:
  /// sin ella, el campo no existía a ojos del usuario y no había forma de
  /// saber que se podía rellenar.
  final String? bio;

  /// Semilla del código de barras y del número: el id del usuario.
  final String seed;

  /// Qué campos se enseñan.
  final Set<CardField> campos;

  final VoidCallback onTapAvatar;
  final VoidCallback onTapBio;
  final VoidCallback onTapCampos;

  const ProfileCard({
    super.key,
    required this.name,
    required this.handle,
    required this.avatar,
    required this.seed,
    required this.campos,
    required this.onTapAvatar,
    required this.onTapBio,
    required this.onTapCampos,
    this.estatus,
    this.especialidad,
    this.universidad,
    this.bio,
    this.isPremium = false,
  });

  static const double _photo = 92;

  /// Lo que acompaña al nombre: la especialidad, que es lo que más te
  /// identifica de un vistazo.
  List<String> get _chips => [
        if (campos.contains(CardField.especialidad) &&
            (especialidad ?? '').isNotEmpty)
          especialidad!,
      ];

  /// Lo que va al pie, repartido a partes iguales.
  ///
  /// Antes ahí abajo solo cabía uno, porque el código de barras se comía media
  /// fila y dejaba un hueco enorme en medio; el badge acababa comprimido con
  /// sitio de sobra al lado.
  List<({String label, IconData icon})> get _pieBadges => [
        if (campos.contains(CardField.estatus) && (estatus ?? '').isNotEmpty)
          (label: estatus!, icon: Icons.school_rounded),
        if (campos.contains(CardField.universidad) &&
            (universidad ?? '').isNotEmpty)
          (label: universidad!, icon: Icons.account_balance_rounded),
      ];

  @override
  Widget build(BuildContext context) {
    final texto = (bio ?? '').trim();

    return StickerCard(
      depth: 6,
      radius: 26,
      texture: laminatedPaper(),
      padding: EdgeInsets.zero,
      child: Stack(
        children: [
          // El código de barras es SOLO decoración —el número legible ya está
          // en la cabecera—, así que se va arriba del todo, pegado al borde y
          // por detrás de los datos. Deja de robarle la mitad al pie.
          if (campos.contains(CardField.codigo))
            Positioned(
              top: 12,
              left: 0,
              right: 0,
              // Centrado en el HUECO LIBRE, no en la tarjeta: a la izquierda
              // está el número y a la derecha el botón de campos, así que el
              // medio de lo que queda cae algo a la derecha del centro. Y
              // corto, para que le sobre aire por los dos lados.
              child: Align(
                alignment: const Alignment(0.22, 0),
                child: Opacity(
                  opacity: 0.3,
                  child: SerialBarcode(seed: seed, height: 22, bars: 22),
                ),
              ),
            ),
          // El brillo recorre la tarjeta ENTERA, así que va por encima de la
          // textura y del barras, pero por debajo del contenido. Se recorta
          // contra el radio INTERIOR: recortando la tarjeta entera pintaría
          // sobre la mitad interna del borde y las esquinas perderían la línea.
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: const CardShimmer(),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _cabecera(),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _foto(),
                    const SizedBox(width: 14),
                    Expanded(
                      child: SizedBox(
                        height: _photo,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                color: kInk,
                                height: 1.1,
                                letterSpacing: -0.4,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              handle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                color: kMuted,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const Spacer(),
                            if (_chips.isNotEmpty || isPremium) _pastillas(),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (campos.contains(CardField.bio)) _bio(texto),
              _pie(),
            ],
          ),
        ],
      ),
    );
  }

  /// Franja de documento: el número de serie a la izquierda, como en un carné
  /// de verdad, y el botón de elegir qué se enseña a la derecha.
  Widget _cabecera() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 10, 0),
      child: Row(
        children: [
          Text(
            'Nº ${serialOf(seed)}',
            style: TextStyle(
              color: kMuted.withOpacity(0.9),
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.4,
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: onTapCampos,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(
                Icons.tune_rounded,
                size: 17,
                color: kMuted.withOpacity(0.8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// La foto: cuadrada y solo con su contorno. Nada de relieve — es una foto
  /// pegada al documento, no una pegatina encima.
  Widget _foto() {
    return GestureDetector(
      onTap: onTapAvatar,
      child: Container(
        width: _photo,
        height: _photo,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kInk, width: 2),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            avatar,
            // El lápiz va DENTRO y pegado a la esquina: sobresaliendo era lo
            // que le daba el aire de relieve.
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(6, 4, 4, 3),
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  borderRadius:
                      BorderRadius.only(topLeft: Radius.circular(10)),
                ),
                child: const Icon(Icons.edit, size: 12, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pastillas() {
    // Una sola línea con desplazamiento: en un carné los distintivos van en
    // fila, y con `Wrap` una universidad de nombre largo empujaba todo abajo.
    return SizedBox(
      height: 26,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        children: [
          if (isPremium) ...[
            const DocChip(
              label: 'Premium',
              icon: Icons.verified_rounded,
              tone: DocTone.accent,
            ),
            const SizedBox(width: 6),
          ],
          for (var i = 0; i < _chips.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            DocChip(label: _chips[i], tone: DocTone.accent),
          ],
        ],
      ),
    );
  }

  /// La franja de la presentación.
  Widget _bio(String texto) {
    final vacia = texto.isEmpty;

    return GestureDetector(
      onTap: onTapBio,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
        decoration: const BoxDecoration(
          border: Border(
            top: BorderSide(color: kHairline, width: 2),
            bottom: BorderSide(color: kHairline, width: 2),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              vacia ? Icons.edit_note_rounded : Icons.format_quote_rounded,
              size: 16,
              color: kMuted.withOpacity(0.7),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                // Tres líneas: con el tope de 160 caracteres del backend, una
                // bio larga no cabe entera en el carné. Se recorta aquí y se
                // lee completa al tocarla, que abre el editor.
                vacia ? 'Escribe algo sobre ti' : texto,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: vacia ? kMuted.withOpacity(0.75) : kInk,
                  fontSize: 13.5,
                  height: 1.45,
                  fontStyle: vacia ? FontStyle.italic : FontStyle.normal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Pie del documento: los datos que acreditan, repartiéndose el ancho.
  Widget _pie() {
    final badges = _pieBadges;
    if (badges.isEmpty) return const SizedBox(height: 12);

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 11, 18, 13),
      child: Row(
        children: [
          for (var i = 0; i < badges.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            // Cada uno ocupa LO QUE NECESITA, no la mitad: repartir a partes
            // iguales dejaba un "3º" en un badge enorme y vacío mientras la
            // universidad se recortaba al lado.
            //
            // Los de delante van sin flex, así que se miden por su contenido;
            // el último se lleva lo que sobre — `loose`, no `Expanded`, para
            // que tampoco se estire si su texto es corto. Funciona porque la
            // lista va del dato más corto al más largo.
            if (i == badges.length - 1)
              Flexible(
                fit: FlexFit.loose,
                child: DocChip(
                  label: badges[i].label,
                  icon: badges[i].icon,
                  tone: i == 0 ? DocTone.ink : DocTone.neutral,
                ),
              )
            else
              DocChip(
                label: badges[i].label,
                icon: badges[i].icon,
                tone: i == 0 ? DocTone.ink : DocTone.neutral,
              ),
          ],
          // Sin `Spacer`: tiene flex 1 y se repartiria el hueco a medias con
          // el ultimo badge, que entonces se recortaria teniendo sitio. El
          // sobrante ya se queda a la derecha porque la fila alinea al inicio.
        ],
      ),
    );
  }
}
