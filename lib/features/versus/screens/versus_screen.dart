import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/responsive/content_shell.dart';
import '../../../core/services/api_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/sticker/sticker.dart';
import '../../../shared/widgets/misc_widgets.dart';
import '../../../shared/widgets/pressable.dart';
import '../models/versus_models.dart';
import '../services/versus_api.dart';
import '../services/versus_links.dart';
import 'versus_room_screen.dart';
import 'versus_scan_screen.dart';

/// Pestaña VERSUS: crear una sala o entrar en la de alguien con su PIN.
///
/// Solo por invitación, igual que en la web: no hay emparejamiento con
/// desconocidos. El PIN son 6 caracteres (letras y números) que genera el
/// servidor.
class VersusScreen extends StatefulWidget {
  const VersusScreen({super.key});

  @override
  State<VersusScreen> createState() => _VersusScreenState();
}

class _VersusScreenState extends State<VersusScreen> {
  final TextEditingController _pinController = TextEditingController();

  bool _creating = false;
  bool _joining = false;
  String? _error;

  bool get _busy => _creating || _joining;

  late final VersusApi _api = VersusApi(context.read<ApiService>());

  @override
  void initState() {
    super.initState();
    // Un enlace puede haber llegado ANTES de que existiera esta pantalla (app
    // abierta desde el QR estando cerrada), así que además de escuchar se mira
    // si ya había uno esperando.
    VersusLinks.instance.pendingPin.addListener(_onPendingLink);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onPendingLink());
  }

  @override
  void dispose() {
    VersusLinks.instance.pendingPin.removeListener(_onPendingLink);
    _pinController.dispose();
    super.dispose();
  }

  void _fail(Object error) {
    if (!mounted) return;
    setState(() {
      _error = error is VersusException
          ? error.message
          : 'No hay conexión. Inténtalo de nuevo.';
    });
  }

  /// Abre la sala y se queda dentro mientras el podio pida otra partida.
  ///
  /// Es un bucle y no una llamada recursiva a propósito: encadenar partidas
  /// dejaría una llamada viva por cada una, y la primera no terminaría hasta
  /// que se acabaran todas.
  Future<void> _openRoom(VersusRoomState state) async {
    var current = state;
    // Se coge el Navigator ANTES del bucle: dentro, cada vuelta viene detrás de
    // un await y usar el context de nuevo sería usarlo cruzando un hueco async.
    final navigator = Navigator.of(context);

    while (mounted) {
      _pinController.clear();
      final again = await navigator.push<Object?>(
        MaterialPageRoute(
          builder: (_) =>
              VersusRoomScreen(pin: current.room.pin, initial: current),
        ),
      );

      // El podio devuelve `true` al pulsar "Otra partida": se monta sala nueva
      // sin obligar a volver aquí y pulsar Crear. Si falla, lo recoge el
      // try/catch de quien llamó.
      if (again != true || !mounted) return;
      current = await _api.createRoom();
    }
  }

  Future<void> _create() async {
    if (_busy) return;
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      final state = await _api.createRoom();
      await _openRoom(state);
    } catch (e) {
      _fail(e);
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _join() async {
    if (_busy) return;
    final pin = _pinController.text.trim().toUpperCase();
    if (pin.length != 6) {
      setState(() => _error = 'El código son 6 caracteres.');
      return;
    }

    await _joinPin(pin);
  }

  Future<void> _joinPin(String pin) async {
    setState(() {
      _joining = true;
      _error = null;
    });
    try {
      final state = await _api.joinRoom(pin);
      await _openRoom(state);
    } catch (e) {
      _fail(e);
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  /// Escanea el QR de una sala y entra directamente. Es el camino corto: en
  /// persona nadie quiere teclear seis caracteres.
  Future<void> _scan() async {
    if (_busy) return;
    final pin = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const VersusScanScreen()),
    );
    if (pin == null || !mounted) return;
    await _joinPin(pin);
  }

  /// Un enlace de sala abierto desde fuera (el QR de otro móvil, o el mensaje
  /// de WhatsApp). Entra sin pasar por el formulario.
  void _onPendingLink() {
    final pin = VersusLinks.instance.pendingPin.value;
    if (pin == null || _busy || !mounted) return;
    VersusLinks.instance.consume();
    unawaited(_joinPin(pin));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: BodyConstraint(
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
          children: [
            const StickerHero(
              badge: 'Versus',
              badgeIcon: Icons.bolt_rounded,
              title: 'Compite en directo',
              subtitle: 'Las mismas preguntas y el mismo reloj. Abre una sala '
                  'y pasa el código, o entra en la de alguien.',
            ),
            const SizedBox(height: 24),

            SlideFadeIn(
              delay: const Duration(milliseconds: 160),
              beginOffset: const Offset(0, 0.12),
              child: _CreateCard(busy: _creating, onTap: _busy ? null : _create),
            ),
            const SizedBox(height: 14),

            SlideFadeIn(
              delay: const Duration(milliseconds: 230),
              beginOffset: const Offset(0, 0.12),
              child: _JoinCard(
                controller: _pinController,
                busy: _joining,
                enabled: !_busy,
                onSubmit: _join,
                onScan: _scan,
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 14),
              _ErrorBanner(message: _error!),
            ],

            const SizedBox(height: 30),
            const SectionLabel('Modos por llegar'),
            ..._upcomingModes.map(
              (mode) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: SlideFadeIn(
                  delay: const Duration(milliseconds: 340),
                  beginOffset: const Offset(0, 0.1),
                  child: _UpcomingModeTile(mode: mode),
                ),
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }
}

// ==========================
// Crear sala
// ==========================

class _CreateCard extends StatelessWidget {
  final bool busy;
  final VoidCallback? onTap;

  const _CreateCard({required this.busy, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: StickerCard(
        depth: 5,
        radius: 20,
        background: AppColors.primary,
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: kInk, width: 2),
              ),
              child: busy
                  ? const Padding(
                      padding: EdgeInsets.all(13),
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.bolt_rounded,
                      color: Colors.white, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    busy ? 'Abriendo sala…' : 'Crear una sala',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Eliges asignaturas y cuántas preguntas, y repartes el código.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 12.5,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================
// Entrar con PIN
// ==========================

class _JoinCard extends StatelessWidget {
  final TextEditingController controller;
  final bool busy;
  final bool enabled;
  final VoidCallback onSubmit;
  final VoidCallback onScan;

  const _JoinCard({
    required this.controller,
    required this.busy,
    required this.enabled,
    required this.onSubmit,
    required this.onScan,
  });

  @override
  Widget build(BuildContext context) {
    return StickerCard(
      depth: 5,
      radius: 20,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Entrar con un código',
                  style: TextStyle(
                    color: kInk,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              // Escanear es el camino corto: en persona nadie quiere teclear
              // seis caracteres.
              GhostButton(
                label: 'Escanear',
                icon: Icons.qr_code_scanner_rounded,
                compact: true,
                onPressed: enabled ? onScan : null,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  enabled: enabled,
                  autocorrect: false,
                  enableSuggestions: false,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 6,
                  onSubmitted: (_) => onSubmit(),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp('[a-zA-Z0-9]')),
                    _UpperCaseFormatter(),
                  ],
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 6,
                    color: AppColors.textPrimary,
                  ),
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: 'ABC123',
                    hintStyle: TextStyle(
                      color: kMuted.withValues(alpha: 0.55),
                      letterSpacing: 6,
                      fontWeight: FontWeight.w900,
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: kHairline, width: 2),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: kHairline, width: 2),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: kInk, width: 2),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              StickerButton(
                label: busy ? '…' : 'Entrar',
                color: AppColors.secondary,
                onPressed: enabled ? onSubmit : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// El PIN se guarda siempre en mayúsculas: el backend compara contra
/// `/^[A-Z0-9]{6}$/` y rechazaría un código escrito en minúsculas.
class _UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
      composing: TextRange.empty,
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;

  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.errorSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.error, width: 2),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              color: AppColors.error, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.error,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ==========================
// Modos por llegar
// ==========================

class _UpcomingMode {
  final IconData icon;
  final String title;
  final String description;

  const _UpcomingMode(this.icon, this.title, this.description);
}

// Los que TODAVÍA no tienen reglas escritas. Clásico, Guardia y Número de
// orden ya se juegan y se eligen en el panel de la sala, así que no pintan
// aquí: anunciarlos como futuros era mentirle al usuario.
const List<_UpcomingMode> _upcomingModes = [
  _UpcomingMode(
    Icons.visibility_rounded,
    'Ojo clínico',
    'Solo la imagen, sin enunciado y con diez segundos.',
  ),
  _UpcomingMode(
    Icons.schedule_rounded,
    'Reto asíncrono',
    'Juegas tu tanda y tu rival las mismas preguntas cuando pueda.',
  ),
];

class _UpcomingModeTile extends StatelessWidget {
  final _UpcomingMode mode;

  const _UpcomingModeTile({required this.mode});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
        // Trazo discontinuo en espíritu: el mismo grosor que el resto pero en
        // gris, para que se lea "esto todavía no".
        border: Border.all(color: kHairline, width: 2),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: kHairline, width: 2),
            ),
            child: Icon(mode.icon, color: kMuted, size: 19),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  mode.title,
                  style: const TextStyle(
                    color: kMuted,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  mode.description,
                  style: const TextStyle(
                    color: AppColors.textLight,
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.lock_outline_rounded,
              color: AppColors.textLight, size: 18),
        ],
      ),
    );
  }
}
