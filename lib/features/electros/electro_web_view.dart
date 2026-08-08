import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/theme/app_theme.dart';
import 'local_asset_server.dart';

/// Muestra una de las herramientas de Electros (web) dentro de la app, servida
/// por un [LocalAssetServer] local. Gestiona la carga, los errores y el botón
/// atrás (navega dentro de la web si puede; si no, cierra la pantalla).
class ElectroWebView extends StatefulWidget {
  const ElectroWebView({
    super.key,
    required this.title,
    required this.assetPrefix,
    this.onOpenSimulador,
  });

  final String title;

  /// Prefijo del asset de la web-app, p. ej. `assets/electros/academia`.
  final String assetPrefix;

  /// Callback opcional cuando la web pide abrir el simulador (botón final de la
  /// Academia). Permite encadenar herramientas sin salir de Electros.
  final VoidCallback? onOpenSimulador;

  @override
  State<ElectroWebView> createState() => _ElectroWebViewState();
}

class _ElectroWebViewState extends State<ElectroWebView> {
  LocalAssetServer? _server;
  WebViewController? _controller;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    try {
      _server = LocalAssetServer(widget.assetPrefix);
      final url = await _server!.start();

      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(AppColors.background)
        ..addJavaScriptChannel(
          'MirdailyElectros',
          onMessageReceived: (msg) {
            if (msg.message == 'open-simulador') widget.onOpenSimulador?.call();
          },
        )
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageFinished: (_) {
              if (mounted) setState(() => _loading = false);
            },
            onWebResourceError: (err) {
              if (mounted && (err.isForMainFrame ?? true)) {
                setState(() {
                  _error = 'No se pudo cargar la herramienta.';
                  _loading = false;
                });
              }
            },
          ),
        )
        ..loadRequest(Uri.parse(url));

      if (!mounted) return;
      setState(() => _controller = controller);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'No se pudo iniciar la herramienta.';
          _loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _server?.stop();
    super.dispose();
  }

  Future<bool> _handleBack() async {
    final c = _controller;
    if (c != null && await c.canGoBack()) {
      await c.goBack();
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (await _handleBack()) nav.pop();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: Text(widget.title),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            onPressed: () async {
              final nav = Navigator.of(context);
              if (await _handleBack()) nav.pop();
            },
          ),
        ),
        body: SafeArea(
          top: false,
          child: Stack(
            children: [
              if (_controller != null && _error == null)
                WebViewWidget(controller: _controller!),
              if (_error != null) _ErrorView(message: _error!),
              if (_loading && _error == null)
                Container(
                  color: AppColors.background,
                  alignment: Alignment.center,
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: AppColors.primary),
                      SizedBox(height: 16),
                      Text(
                        'Preparando el electro…',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, color: AppColors.textLight, size: 40),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }
}
