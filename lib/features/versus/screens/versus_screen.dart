import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/services/api_service.dart';
import '../../../core/theme/app_theme.dart';
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
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
          children: [
            SlideFadeIn(
              child: Text(
                'Versus',
                style: Theme.of(context).textTheme.displayMedium,
              ),
            ),
            const SizedBox(height: 6),
            const SlideFadeIn(
              delay: Duration(milliseconds: 100),
              child: Text(
                'Compite en directo con las mismas preguntas y el mismo reloj. '
                'Abre una sala y pasa el código, o entra en la de alguien.',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 22),

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

            const SizedBox(height: 28),
            const SlideFadeIn(
              delay: Duration(milliseconds: 300),
              child: Text(
                'MODOS PREVISTOS',
                style: TextStyle(
                  color: AppColors.textLight,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            const SizedBox(height: 12),
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
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.primary, AppColors.primaryHover],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.28),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(14),
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
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
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
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Entrar con un código',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              // Escanear es el camino corto: en persona nadie quiere teclear
              // seis caracteres.
              TextButton.icon(
                onPressed: enabled ? onScan : null,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primaryDark,
                  backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                label: const Text('Escanear',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
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
                      color: AppColors.textLight.withValues(alpha: 0.7),
                      letterSpacing: 6,
                      fontWeight: FontWeight.w700,
                    ),
                    filled: true,
                    fillColor: AppColors.surfaceVariant,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 54,
                child: ElevatedButton(
                  onPressed: enabled ? onSubmit : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.secondary,
                    disabledBackgroundColor: AppColors.surfaceVariant,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                  ),
                  child: busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Entrar'),
                ),
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

// Los mismos que anuncia la web: cada uno es un conjunto de reglas sobre el
// motor de sala que ya existe, no una pantalla aparte.
const List<_UpcomingMode> _upcomingModes = [
  _UpcomingMode(
    Icons.trending_up_rounded,
    'Número de orden',
    'Puntuación real del MIR (+3 / −1 / 0) y marcador por puesto y percentil.',
  ),
  _UpcomingMode(
    Icons.flash_on_rounded,
    'Guardia',
    'Supervivencia: quien falla, cae. El último en pie gana.',
  ),
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
        color: AppColors.surface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(mode.icon, color: AppColors.textLight, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  mode.title,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
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
