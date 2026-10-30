// Perfil → Preferencias → Tutoriales. Puerto de la tarjeta «Tutoriales» de la web
// (src/components/Profile/SettingsCard.tsx):
//  - El interruptor apaga o enciende la mascota en ESTE dispositivo.
//  - «Volver a verlos desde el principio» los olvida en la cuenta (todos los dispositivos), los
//    enciende y lleva al daily para empezar, como la web.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/providers/auth_provider.dart';
import '../../core/responsive/adaptive_modal.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/sticker/sticker.dart';
import '../navigation/pestana_pedida.dart';
import 'tutoriales_controller.dart';

Future<void> abrirAjustesTutoriales(BuildContext context) {
  final tutoriales = context.read<Tutoriales>();
  return showAdaptiveModal<void>(
    context: context,
    builder: (_) => ChangeNotifierProvider<Tutoriales>.value(
      value: tutoriales,
      child: const AjustesTutoriales(),
    ),
  );
}

class AjustesTutoriales extends StatefulWidget {
  const AjustesTutoriales({super.key});

  @override
  State<AjustesTutoriales> createState() => _AjustesTutorialesState();
}

class _AjustesTutorialesState extends State<AjustesTutoriales> {
  bool _reiniciando = false;
  String? _error;

  Future<void> _volverAVerlos() async {
    final tutoriales = context.read<Tutoriales>();
    final auth = context.read<AuthProvider?>();
    final navegador = Navigator.of(context);
    setState(() {
      _reiniciando = true;
      _error = null;
    });
    try {
      await tutoriales.reiniciar();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _reiniciando = false;
        _error = 'No se pudieron reiniciar los tutoriales. Inténtalo de nuevo.';
      });
      return;
    }
    // El perfil en memoria aún trae la lista vieja: se pide el nuevo (el controlador no resucita la
    // vieja mientras tanto).
    auth?.refreshProfile();
    // Al daily, que es donde empieza el recorrido.
    navegador.popUntil((r) => r.isFirst);
    pestanaPedida.value = PestanaApp.quiz;
  }

  @override
  Widget build(BuildContext context) {
    final activos = context.watch<Tutoriales>().activos;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Tutoriales', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 19, color: kInk)),
                      SizedBox(height: 4),
                      Text(
                        'La mascota te enseña cada pantalla la primera vez que entras. Apágalos y no volverá a aparecer.',
                        style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Semantics(
                  toggled: activos,
                  label: 'Activar o desactivar los tutoriales de la mascota',
                  child: InkSwitch(
                    value: activos,
                    onChanged: (v) => context.read<Tutoriales>().setActivos(v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              activos ? 'ACTIVADOS' : 'DESACTIVADOS',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.6,
                color: Color(0xFFB9B2AD),
              ),
            ),
            const SizedBox(height: 16),
            GhostButton(
              label: _reiniciando ? 'Reiniciando…' : 'Volver a verlos desde el principio',
              icon: Icons.replay_rounded,
              expand: true,
              onPressed: _reiniciando ? null : _volverAVerlos,
            ),
            const SizedBox(height: 8),
            const Text(
              'Se te olvidan en todos tus dispositivos, no solo en este, y te lleva al Daily para empezar.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(fontSize: 12.5, color: AppColors.error, fontWeight: FontWeight.w600)),
            ],
          ],
        ),
      ),
    );
  }
}
