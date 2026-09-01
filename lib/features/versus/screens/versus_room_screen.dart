import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/services/haptics_service.dart';

import '../../../core/services/api_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/sticker/sticker.dart';
import '../models/versus_models.dart';
import '../providers/versus_room_controller.dart';
import '../services/versus_api.dart';
import '../widgets/versus_avatar.dart';
import '../widgets/versus_notices.dart';
import '../widgets/versus_runner.dart';
import '../widgets/versus_start_panel.dart';

/// Una sala de Versus: el lobby mientras se espera y la partida cuando arranca.
///
/// La pantalla no navega al empezar la partida: la sala cambia de fase y el
/// contenido cambia con ella, que es lo que permite reconectar en cualquier
/// momento y caer justo donde está el resto.
class VersusRoomScreen extends StatefulWidget {
  final String pin;

  /// Estado con el que se entró (crear o unirse), para no pintar un spinner
  /// mientras llega el primer refresco.
  final VersusRoomState? initial;

  const VersusRoomScreen({super.key, required this.pin, this.initial});

  @override
  State<VersusRoomScreen> createState() => _VersusRoomScreenState();
}

class _VersusRoomScreenState extends State<VersusRoomScreen> {
  late final VersusRoomController _controller;
  bool _leaving = false;

  /// Ya se ha saltado a la sala de revancha. Sin esto, cada notificación del
  /// controlador empujaría otra pantalla encima.
  bool _jumped = false;

  @override
  void initState() {
    super.initState();
    _controller = VersusRoomController(
      api: VersusApi(context.read<ApiService>()),
      pin: widget.pin,
    );
    _controller.addListener(_maybeJumpToRematch);
    _controller.start();
  }

  @override
  void dispose() {
    _controller.removeListener(_maybeJumpToRematch);
    _controller.dispose();
    super.dispose();
  }

  /// En cuanto existe la sala de revancha, los que VOTARON entran solos. No se
  /// llama a `/leave`: el servidor ya les ha metido dentro, con su apodo y su
  /// avatar, y salir de la vieja no aporta nada.
  ///
  /// Solo los que votaron: `rematch_ready` va al canal entero, así que esto
  /// arrastraba también a quien no quiso repetir, y ese acababa en una sala en
  /// la que el servidor no le había metido —sin salir en la lista y sin que
  /// nadie le contara—.
  ///
  /// Va con `pushReplacement` para que el botón atrás no devuelva a un podio de
  /// una partida que ya terminó.
  void _maybeJumpToRematch() {
    final next = _controller.rematchPin;
    if (next == null || _jumped || _leaving || !mounted) return;
    if (!_controller.votedRematch) return;
    _jumped = true;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => VersusRoomScreen(pin: next)),
    );
  }

  /// Salir avisando al servidor. Con la partida empezada el jugador se marca
  /// como ido (conserva su puesto y sus respuestas) y la ronda deja de
  /// esperarle; en el lobby, sencillamente desaparece.
  /// [result] vuelve a la pestaña de Versus: `true` significa "monta otra
  /// sala", para que el botón del podio no obligue a dar dos pasos.
  Future<void> _leave({required bool confirm, Object? result}) async {
    if (_leaving) return;

    // Al terminar la partida ya no hay nada que abandonar: preguntar "¿seguro?"
    // sobre el podio solo estorba.
    if (confirm && !_controller.closed && !_controller.finished) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surface,
          surfaceTintColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text('¿Salir de la sala?'),
          // Cerrar la sala para todos es cosa del LOBBY. Con la partida en
          // marcha nadie la conduce —la avanza el reloj del servidor—, así que
          // el anfitrión que se va es un jugador más que se va, y decirle otra
          // cosa le hacía creer que estaba reventando la partida de los demás.
          content: Text(
            _controller.isHost &&
                    (_controller.room?.status ?? VersusStatus.lobby) ==
                        VersusStatus.lobby
                ? 'Eres el anfitrión: al salir se cierra la sala para todos.'
                : 'La partida sigue sin ti. Podrás volver a entrar con el mismo código mientras la sala siga abierta.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Seguir jugando'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Salir'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }

    _leaving = true;
    if (!_controller.closed) await _controller.leave();
    if (mounted) Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final c = _controller;

        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _leave(confirm: true);
          },
          child: Scaffold(
            backgroundColor: AppColors.background,
            // Con la partida en marcha la cabecera desaparece: el código de la
            // sala ya no hace falta (nadie más va a entrar) y ese espacio lo
            // aprovecha el combate. Se sale con el gesto atrás o con la X.
            appBar: _playing(c)
                ? null
                : AppBar(
                    backgroundColor: AppColors.background,
                    leading: IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => _leave(confirm: true),
                    ),
                    title:
                        Text(c.closed ? 'Sala cerrada' : 'Sala ${widget.pin}'),
                    actions: [
                      if (!c.closed)
                        Padding(
                          padding: const EdgeInsets.only(right: 14),
                          child: _ConnectionDot(connected: c.connected),
                        ),
                    ],
                  ),
            body: SafeArea(
              child: Stack(
                children: [
                  _buildBody(c),
                  if (_playing(c))
                    Positioned(
                      top: 2,
                      right: 2,
                      child: IconButton(
                        icon: const Icon(Icons.close_rounded,
                            size: 20, color: AppColors.textLight),
                        onPressed: () => _leave(confirm: true),
                      ),
                    ),
                  // Van por encima de todo, lobby y partida por igual: enterarse
                  // de que a alguien se le ha caído el wifi explica por qué la
                  // ronda avanza de golpe sin esperarle.
                  VersusNotices(notices: c.notices),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Hay partida en marcha (o podio): manda la fase, no el estado de la sala.
  bool _playing(VersusRoomController c) => !c.closed && c.phase != null;

  Widget _buildBody(VersusRoomController c) {
    if (c.closed) return _buildClosed();

    if (c.loading && c.room == null && widget.initial == null) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    final room = c.room ?? widget.initial?.room;
    if (room == null) {
      return _buildError(c.error ?? 'No se pudo cargar la sala.');
    }

    // Manda la FASE, no el estado de la sala: en el lobby no hay fase, así que
    // que exista una significa que la partida ya ha arrancado. Mirar el estado
    // dejaría el lobby puesto en la ventana entre que llega el evento de
    // arranque y responde el refresco por HTTP.
    if (c.phase == null && room.status == VersusStatus.lobby) {
      return _buildLobby(c, room);
    }

    // Llegar a una sala que ya juega sin estar dentro. Antes el servidor mandaba
    // la partida entera a cualquiera con el PIN y esto no pasaba; ahora la fase
    // solo viaja a los de dentro, y sin ella el runner se quedaba dando vueltas
    // en un spinner para siempre.
    if (c.playerId == null && c.phase == null) {
      return _buildError('Esta partida ya ha empezado y no estás en ella. '
          'Pídeles el código de la siguiente, o monta tú una sala.');
    }

    return VersusRunner(
      controller: c,
      onPlayAgain: () => _leave(confirm: false, result: true),
      onExit: () => _leave(confirm: false),
    );
  }

  // ==========================
  // Lobby
  // ==========================

  Widget _buildLobby(VersusRoomController c, VersusRoom room) {
    final players = c.players.isNotEmpty
        ? c.players
        : (widget.initial?.players ?? const <VersusPlayer>[]);
    final isHost = c.room != null ? c.isHost : (widget.initial?.isHost ?? false);
    // El backend exige al menos dos jugadores: una sala de uno no es un versus.
    final canStart = players.length >= 2;

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        // Se llegó a la sala pero no se pudo entrar (empezada, llena…). Decirlo
        // es lo único que evita quedarse esperando a una partida en la que no
        // se está.
        if (c.playerId == null && c.joinError != null) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.error.withValues(alpha: 0.25),
                width: 2,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.visibility_rounded,
                    size: 20, color: AppColors.error),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Estás mirando, no jugando',
                        style: TextStyle(
                          color: AppColors.error,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        c.joinError!,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        _PinCard(pin: room.pin),
        const SizedBox(height: 20),

        Row(
          children: [
            const Text(
              'EN LA SALA',
              style: TextStyle(
                color: AppColors.textLight,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              // Se cuentan los que ESTAN: decir "2 / 8" con una sola persona
              // delante de la pantalla es justo lo que hacia que se empezaran
              // partidas con un fantasma dentro.
              '${players.where((p) => !p.away).length} / ${room.config.maxPlayers}'
              '${players.any((p) => p.away) ? "  (${players.where((p) => p.away).length} sin conexión)" : ""}',
              style: const TextStyle(
                color: AppColors.textLight,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: players
              .map((p) => _PlayerChip(
                    player: p,
                    isHost: p.id == c.playerId && isHost,
                    isMe: p.id == c.playerId,
                  ))
              .toList(),
        ),

        const SizedBox(height: 24),

        if (isHost)
          VersusStartPanel(
            onStart: c.startGame,
            canStart: canStart,
            onDraftChanged: c.publishDraft,
          )
        else
          _WaitingForHost(draft: c.lobbyDraft),

        if (c.error != null) ...[
          const SizedBox(height: 16),
          Text(
            c.error!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.error,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }

  // ==========================
  // Estados terminales
  // ==========================

  Widget _buildClosed() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.door_front_door_outlined,
                size: 52, color: AppColors.textLight),
            const SizedBox(height: 16),
            const Text(
              'La sala se ha cerrado',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'El anfitrión ha salido o la sala ha caducado.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 22),
            ElevatedButton(
              onPressed: () => _leave(confirm: false),
              child: const Text('Volver a Versus'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded,
                size: 48, color: AppColors.textLight),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _controller.refresh,
              child: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================
// Piezas del lobby
// ==========================

class _PinCard extends StatelessWidget {
  final String pin;

  const _PinCard({required this.pin});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.primaryHover],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: kInk, width: 2),
        boxShadow: [
          const BoxShadow(
            color: kInk,
            offset: Offset(6, 6),
            blurRadius: 0,
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            'CÓDIGO DE LA SALA',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            pin,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 42,
              fontWeight: FontWeight.w900,
              letterSpacing: 8,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _PinAction(
                icon: Icons.copy_rounded,
                label: 'Copiar',
                onTap: () {
                  Clipboard.setData(ClipboardData(text: pin));
                  HapticsService.light();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Código copiado'),
                      behavior: SnackBarBehavior.floating,
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
              ),
              const SizedBox(width: 8),
              // Abre la hoja del sistema: WhatsApp, Telegram, lo que tenga el
              // móvil. Es lo que de verdad se usa para pasar el código.
              _PinAction(
                icon: Icons.ios_share_rounded,
                label: 'Compartir',
                onTap: () {
                  HapticsService.light();
                  SharePlus.instance.share(
                    ShareParams(
                      text: 'Te reto en MIRDaily. Entra en Versus con el '
                          'código $pin\n\n${_roomLink(pin)}',
                      subject: 'Partida de MIRDaily',
                    ),
                  );
                },
              ),
              const SizedBox(width: 8),
              _PinAction(
                icon: Icons.qr_code_rounded,
                label: 'QR',
                onTap: () {
                  HapticsService.light();
                  showDialog<void>(
                    context: context,
                    builder: (_) => _QrDialog(pin: pin),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Enlace para COMPARTIR (WhatsApp y demás). Va en https a propósito: quien no
/// tenga la app tiene que poder abrir la web. Cuando esté publicado el
/// assetlinks.json del dominio, Android lo abrirá directo en la app.
String _roomLink(String pin) => 'https://mirdaily.com/versus/$pin';

/// Enlace del QR. Esquema propio en vez de https porque el QR se escanea EN
/// PERSONA, entre dos que ya tienen la app, y así abre la sala directamente sin
/// pasar por el navegador y sin depender de configurar nada en el dominio.
String _roomDeepLink(String pin) => 'com.mirdaily.app://versus/$pin';

class _PinAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _PinAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: Colors.white.withValues(alpha: 0.18),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      icon: Icon(icon, size: 17),
      label: Text(label, style: const TextStyle(fontSize: 13)),
    );
  }
}

/// El QR grande, para que lo escaneen desde el móvil de al lado sin teclear
/// nada. Lleva el enlace, no solo el PIN: así la cámara del sistema —que no
/// sabe nada de MIRDaily— ofrece abrirlo.
class _QrDialog extends StatelessWidget {
  final String pin;

  const _QrDialog({required this.pin});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Escanea para entrar',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kHairline, width: 2),
              ),
              child: QrImageView(
                data: _roomDeepLink(pin),
                version: QrVersions.auto,
                size: 220,
                backgroundColor: Colors.white,
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: AppColors.textPrimary,
                ),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              pin,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 26,
                fontWeight: FontWeight.w900,
                letterSpacing: 6,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'O teclea el código en Versus',
              style: TextStyle(color: AppColors.textLight, fontSize: 12),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cerrar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayerChip extends StatelessWidget {
  final VersusPlayer player;
  final bool isHost;
  final bool isMe;

  const _PlayerChip({
    required this.player,
    required this.isHost,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 14, 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: isMe ? kInk : kHairline,
          width: 2,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          VersusAvatar(player: player, size: 30, dimmed: player.away),
          const SizedBox(width: 9),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                player.nickname,
                style: TextStyle(
                  color: player.away
                      ? AppColors.textLight
                      : AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              // Atenuar la ficha se pasa por alto: quien cerraba la app seguia
              // en la lista casi igual que quien estaba delante, y el anfitrion
              // empezaba la partida contando con el.
              if (player.away)
                const Text(
                  'sin conexión',
                  style: TextStyle(
                    color: AppColors.textLight,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
            ],
          ),
          if (isHost) ...[
            const SizedBox(width: 6),
            const Icon(Icons.star_rounded,
                size: 15, color: AppColors.gold),
          ],
        ],
      ),
    );
  }
}

/// Lo que ve quien NO es anfitrión. Enseña, en solo lectura, lo que el
/// anfitrión va marcando: sin esto se esperaba a ciegas, sin saber siquiera a
/// qué modo se iba a jugar.
class _WaitingForHost extends StatelessWidget {
  final VersusLobbyDraft? draft;

  const _WaitingForHost({required this.draft});

  @override
  Widget build(BuildContext context) {
    final d = draft;
    final survival = d?.mode == VersusMode.survival;

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kHairline, width: 2),
      ),
      child: Column(
        children: [
          const SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(
              strokeWidth: 2.6,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Esperando al anfitrión',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            d == null
                ? 'Está configurando la partida.'
                : 'Esto es lo que lleva elegido.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),

          if (d != null) ...[
            const SizedBox(height: 18),
            const Divider(color: AppColors.border, height: 1),
            const SizedBox(height: 16),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  switch (d.mode) {
                    VersusMode.survival => Icons.favorite_rounded,
                    VersusMode.mirRank => Icons.trending_up_rounded,
                    VersusMode.classic => Icons.bolt_rounded,
                    _ => Icons.help_outline_rounded,
                  },
                  size: 18,
                  color: d.mode == null ? kMuted : AppColors.primaryDark,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    VersusMode.labelOf(d.mode),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: d.mode == null ? kMuted : kInk,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (survival) ...[
                  const SizedBox(width: 10),
                  for (int i = 0; i < d.lives; i++)
                    const Padding(
                      padding: EdgeInsets.only(right: 2),
                      child: Icon(Icons.favorite_rounded,
                          size: 14, color: AppColors.error),
                    ),
                ],
              ],
            ),

            const SizedBox(height: 14),
            if (d.subjects.isEmpty)
              const Text(
                'Todavía no ha elegido asignaturas',
                style: TextStyle(color: AppColors.textLight, fontSize: 12),
              )
            else
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final name in d.subjects)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        name,
                        style: const TextStyle(
                          color: AppColors.primaryDark,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),

            const SizedBox(height: 12),
            Text(
              '${d.count} preguntas',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Estado del canal en vivo. En gris significa que los eventos no están
/// llegando; al reconectar la pantalla se resincroniza sola.
class _ConnectionDot extends StatelessWidget {
  final bool connected;

  const _ConnectionDot({required this.connected});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: connected ? AppColors.success : AppColors.textLight,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          connected ? 'En vivo' : 'Conectando',
          style: const TextStyle(
            color: AppColors.textLight,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
