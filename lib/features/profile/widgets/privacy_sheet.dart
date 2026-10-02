import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/config/app_config.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/daily_provider.dart';
import '../../../core/responsive/adaptive_modal.dart';
import '../../../core/services/api_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/sticker/sticker.dart';

/// Perfil › Privacidad: textos legales (en la web) y eliminar la cuenta.
///
/// Eliminar la cuenta desde la propia app lo exige Apple (App Store Review
/// Guideline 5.1.1(v)) y el RGPD (derecho de supresión). Usa el mismo
/// endpoint que la web, que lo borra todo en una sola transacción.
void openPrivacySheet(BuildContext context) {
  showAdaptiveModal<void>(
    context: context,
    builder: (sheetCtx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Privacidad',
              style: TextStyle(
                  fontWeight: FontWeight.w900, fontSize: 19, color: kInk),
            ),
            const SizedBox(height: 4),
            const Text(
              'Qué datos guardamos, para qué y cómo borrarlos.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 10),
            _PrivacyOption(
              icon: Icons.privacy_tip_outlined,
              title: 'Política de privacidad',
              onTap: () => _openWeb('/privacidad'),
            ),
            _PrivacyOption(
              icon: Icons.gavel_rounded,
              title: 'Aviso legal',
              onTap: () => _openWeb('/aviso-legal'),
            ),
            const Divider(height: 20, color: kHairline),
            _PrivacyOption(
              icon: Icons.delete_forever_rounded,
              title: 'Eliminar mi cuenta',
              subtitle: 'Borra tu cuenta y todo tu progreso',
              danger: true,
              onTap: () {
                Navigator.of(sheetCtx).pop();
                _confirmDeleteAccount(context);
              },
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    ),
  );
}

Future<void> _openWeb(String path) async {
  await launchUrl(
    Uri.parse('${AppConfig.webBaseUrl}$path'),
    mode: LaunchMode.inAppBrowserView,
  );
}

Future<void> _confirmDeleteAccount(BuildContext context) async {
  // Se leen antes del await: tras borrar, el perfil se desmonta al cerrar
  // la sesión y el context deja de valer.
  final api = context.read<ApiService>();
  final daily = context.read<DailyProvider>();
  final auth = context.read<AuthProvider>();

  final deleted = await showDialog<bool>(
    context: context,
    builder: (_) => _DeleteAccountDialog(api: api),
  );
  if (deleted != true) return;

  daily.reset();
  await auth.signOut();
}

class _PrivacyOption extends StatelessWidget {
  const _PrivacyOption({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool danger;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.error : kInk;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      leading: Icon(icon, color: color),
      title: Text(title,
          style: TextStyle(
              fontWeight: FontWeight.w800, fontSize: 15, color: color)),
      subtitle: subtitle == null
          ? null
          : Text(subtitle!,
              style: const TextStyle(
                  fontSize: 12.5, color: AppColors.textSecondary)),
      trailing: danger
          ? null
          : const Icon(Icons.open_in_new_rounded,
              size: 18, color: AppColors.textSecondary),
    );
  }
}

/// Pide escribir ELIMINAR (como en la web) para que no se borre de un toque
/// sin querer. Devuelve true si la cuenta se ha borrado.
class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog({required this.api});

  final ApiService api;

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  static const _palabra = 'ELIMINAR';

  final _controller = TextEditingController();
  bool _deleting = false;
  String? _error;

  bool get _confirmed => _controller.text.trim().toUpperCase() == _palabra;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    if (!_confirmed || _deleting) return;
    setState(() {
      _deleting = true;
      _error = null;
    });
    try {
      await widget.api.deleteAccount();
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _deleting = false;
        _error = e is ApiException
            ? e.message
            : 'No se pudo eliminar la cuenta. Revisa tu conexión.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_deleting,
      child: AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        title: const Text('Eliminar cuenta'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Se borrarán para siempre tu cuenta y todo tu progreso: '
              'respuestas, dailies, simulacros, mazos, flashcards, mapas, '
              'nivel y rachas. No se puede deshacer.',
              style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              enabled: !_deleting,
              autofocus: true,
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.characters,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _delete(),
              decoration: const InputDecoration(
                labelText: 'Escribe $_palabra para confirmar',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style: const TextStyle(
                      color: AppColors.error, fontWeight: FontWeight.w700)),
            ],
          ],
        ),
        actions: [
          TextButton(
              onPressed: _deleting ? null : () => Navigator.pop(context, false),
              child: const Text('Cancelar',
                  style: TextStyle(color: Colors.grey))),
          ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white),
              onPressed: _confirmed && !_deleting ? _delete : null,
              child: Text(_deleting ? 'Eliminando…' : 'Eliminar')),
        ],
      ),
    );
  }
}
