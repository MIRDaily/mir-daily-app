import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;

/// Sirve una web-app empaquetada en los assets de Flutter desde un pequeño
/// servidor HTTP en 127.0.0.1. Es necesario porque las herramientas de Electros
/// usan módulos ES (`<script type="module">`), que los WebView bloquean si se
/// cargan desde `file://` (los módulos exigen un origen con CORS). Servirlas por
/// `http://127.0.0.1` resuelve el problema y no requiere red.
class LocalAssetServer {
  LocalAssetServer(this.assetPrefix);

  /// Prefijo del asset, p. ej. `assets/electros/simulador`.
  final String assetPrefix;

  HttpServer? _server;

  /// Arranca el servidor y devuelve la URL base (termina en `/`).
  Future<String> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.autoCompress = false;
    _server!.listen(_handle);
    return 'http://127.0.0.1:${_server!.port}/';
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    try {
      var path = req.uri.path;
      if (path.isEmpty || path == '/') path = '/index.html';
      // Normaliza y evita salir del prefijo del asset.
      final clean = path.replaceAll('..', '').replaceAll('//', '/');
      final assetKey = '$assetPrefix$clean';

      final data = await rootBundle.load(assetKey);
      final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);

      res.statusCode = HttpStatus.ok;
      res.headers.contentType = _contentTypeFor(clean);
      res.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      res.add(bytes);
    } catch (_) {
      res.statusCode = HttpStatus.notFound;
      res.headers.contentType = ContentType.text;
      res.write('Not found');
    } finally {
      await res.close();
    }
  }

  ContentType _contentTypeFor(String path) {
    final i = path.lastIndexOf('.');
    final ext = i >= 0 ? path.substring(i + 1).toLowerCase() : '';
    switch (ext) {
      case 'html':
        return ContentType('text', 'html', charset: 'utf-8');
      // El MIME de JS debe ser de tipo JavaScript o el WebView rechaza el módulo.
      case 'js':
      case 'mjs':
        return ContentType('text', 'javascript', charset: 'utf-8');
      case 'css':
        return ContentType('text', 'css', charset: 'utf-8');
      case 'json':
        return ContentType('application', 'json', charset: 'utf-8');
      case 'svg':
        return ContentType('image', 'svg+xml', charset: 'utf-8');
      case 'png':
        return ContentType('image', 'png');
      case 'jpg':
      case 'jpeg':
        return ContentType('image', 'jpeg');
      case 'woff2':
        return ContentType('font', 'woff2');
      case 'woff':
        return ContentType('font', 'woff');
      default:
        return ContentType('application', 'octet-stream');
    }
  }
}
