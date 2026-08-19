import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/sticker/sticker.dart';
import '../../../shared/sticker/textures.dart';

/// El carné del perfil.
///
/// Vive aparte de la pantalla por dos razones: eran 150 líneas dentro de un
/// fichero de mil, y así se puede renderizar en un test sin montar media app
/// con sus providers.
///
/// La textura es la de un documento acreditativo: guilloche, campos rotulados,
/// código de barras derivado del id y un destello de laminado. La estructura
/// también: **foto, datos, firma**. Antes el bloque de la derecha se quedaba
/// medio vacío y las pastillas caían sueltas debajo; ahora la columna de datos
/// se llena hasta abajo y el pie es una franja aparte.
class ProfileCard extends StatelessWidget {
  final String name;
  final String handle;

  /// La imagen del avatar ya construida. Se inyecta en vez de resolverla aquí
  /// para que el carné no dependa de la red ni de la configuración: así se
  /// puede pintar en un test.
  final Widget avatar;
  final bool isPremium;
  final bool isPublic;

  /// Especialidad, universidad, curso… ya filtrados por quien llama.
  final List<String> chips;

  /// Presentación libre. Si está vacía se enseña una invitación a escribirla:
  /// sin ella, el campo no existía a ojos del usuario y no había forma de
  /// saber que se podía rellenar.
  final String? bio;

  /// Semilla del código de barras: el id del usuario.
  final String seed;

  final VoidCallback onTapAvatar;
  final VoidCallback onTapBio;

  const ProfileCard({
    super.key,
    required this.name,
    required this.handle,
    required this.avatar,
    required this.chips,
    required this.seed,
    required this.onTapAvatar,
    required this.onTapBio,
    this.bio,
    this.isPremium = false,
    this.isPublic = false,
  });

  /// La foto del carné: cuadrada y con su trazo, no redonda.
  final double _photo = 92;

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
          // El destello del plastificado, por debajo del contenido. Se recorta
          // contra el radio INTERIOR (el de la tarjeta menos el trazo): al
          // recortar la tarjeta entera pintaba sobre la mitad interna del
          // borde y las esquinas perdían la línea.
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: const LaminateSheen(),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _foto(),
                    const SizedBox(width: 14),
                    // La columna de datos ocupa TODO el alto de la foto: el
                    // nombre arriba y las pastillas abajo, en vez de dejar un
                    // hueco a la derecha y las pastillas sueltas más abajo.
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
                            _pastillas(),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              _bio(texto),
              _pie(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _foto() {
    return GestureDetector(
      onTap: onTapAvatar,
      child: SizedBox(
        width: _photo,
        height: _photo,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: _photo,
              height: _photo,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: kInk, width: 2),
                boxShadow: inkShadow(4),
              ),
              clipBehavior: Clip.antiAlias,
              child: avatar,
            ),
            Positioned(
              right: -4,
              bottom: -4,
              child: Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: kInk, width: 2),
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
    // Una sola línea: en un carné los distintivos van en fila, y con `Wrap`
    // una universidad de nombre largo empujaba todo hacia abajo.
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
          DocChip(
            label: isPublic ? 'Público' : 'Privado',
            icon: isPublic ? Icons.visibility_rounded : Icons.lock_rounded,
          ),
          for (final c in chips) ...[
            const SizedBox(width: 6),
            DocChip(label: c, tone: DocTone.accent),
          ],
        ],
      ),
    );
  }

  /// La franja de la presentación, siempre presente.
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

  /// Pie del documento: barras y número de serie.
  Widget _pie() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // El código tiene ancho propio; recortarlo es mejor que estirarlo,
          // que le cambiaría el paso de las barras.
          Flexible(
            child: ClipRect(
              child: Align(
                alignment: Alignment.centerLeft,
                heightFactor: 1,
                child: SerialBarcode(seed: seed, height: 22),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'Nº ${serialOf(seed)}',
            style: TextStyle(
              color: kMuted.withOpacity(0.9),
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}
