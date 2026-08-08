import 'package:flutter/material.dart';

import '../../../core/config/app_config.dart';
import '../../../shared/widgets/misc_widgets.dart';
import '../models/versus_models.dart';

/// Avatar de un jugador de la sala. Mismo bucket que la web; si la imagen no
/// carga se cae a la inicial, que es lo que ya hace el resto de la app.
class VersusAvatar extends StatelessWidget {
  final VersusPlayer player;
  final double size;

  /// Los que se han ido siguen en el marcador, pero apagados.
  final bool dimmed;

  const VersusAvatar({
    super.key,
    required this.player,
    this.size = 36,
    this.dimmed = false,
  });

  @override
  Widget build(BuildContext context) {
    final fallback = UserAvatar(name: player.nickname, size: size);

    Widget avatar = ClipOval(
      child: Image.network(
        AppConfig.avatarUrl(player.avatarId),
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : fallback,
        errorBuilder: (_, __, ___) => fallback,
      ),
    );

    if (dimmed) {
      avatar = Opacity(opacity: 0.45, child: avatar);
    }

    return SizedBox(width: size, height: size, child: avatar);
  }
}
