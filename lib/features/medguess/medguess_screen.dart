// MedGuess, el reto médico diario. Puerto de la web: src/app/medguess/components.
//
// Arriba el término oculto, en medio el tablero de 6 intentos y las pistas, y abajo, fijo, un
// teclado propio (QWERTY + Enviar + Borrar): no se usa el del sistema, que taparía el tablero.
// Al enviar, las 5 casillas se voltean una tras otra, cada una con su toque y su «blip».
//
// Diferencias con la web, a propósito:
//  - Una letra que ya estaba descubierta (`known`) se pinta en verde claro y no en oscuro como una
//    letra que no está: sí está en el término, solo que ya se sabía.
//  - El término completo solo se enseña con la partida terminada (ver core/models/medguess.dart).

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/config/app_config.dart';
import '../../core/models/medguess.dart';
import '../../core/responsive/adaptive_modal.dart';
import '../../core/responsive/breakpoints.dart';
import '../../core/services/api_service.dart';
import '../../core/services/haptics_service.dart';
import '../../core/services/medguess_api.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/sticker/sticker.dart';
import '../../shared/sticker/textures.dart';
import '../tutorial/voz_mascota.dart';
import 'medguess_controller.dart';

const Color _verde = Color(0xFFA0BD9C);
const Color _verdeTinta = Color(0xFF334D33);
const Color _verdeClaro = Color(0xFFD9E6D6);
const Color _oscuro = Color(0xFF1C2430);
const Color _oscuroTexto = Color(0xFFCBD5E1);
const Color _rosa = Color(0xFFE8A598);
const Color _rosaTinta = Color(0xFF6A3930);

/// Lo que tarda en voltearse cada casilla y el desfase entre una y la siguiente.
const int _msVolteo = 360;
const int _msEntreCasillas = 120;
const int _msRevelado = _msEntreCasillas * (largoIntentoMedGuess - 1) + _msVolteo;

class MedGuessScreen extends StatefulWidget {
  /// Para los tests: si no se pasa, se usa la API real con la sesión de la app.
  final MedGuessApi? api;

  const MedGuessScreen({super.key, this.api});

  @override
  State<MedGuessScreen> createState() => _MedGuessScreenState();
}

class _MedGuessScreenState extends State<MedGuessScreen> {
  late final MedGuessController _c;
  final List<Timer> _timers = [];

  @override
  void initState() {
    super.initState();
    final api = widget.api ?? _apiReal(context.read<ApiService>());
    _c = MedGuessController(api)..cargar();
  }

  static MedGuessApi _apiReal(ApiService sesion) =>
      MedGuessApi(token: sesion.validToken, baseUrl: AppConfig.apiBaseUrl, client: sesion.clienteConSesion);

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    _c.dispose();
    super.dispose();
  }

  void _despues(int ms, VoidCallback f) {
    _timers.add(Timer(Duration(milliseconds: ms), () {
      if (mounted) f();
    }));
  }

  void _teclear(String l) {
    if (!_c.puedeTeclear) return;
    HapticsService.light();
    _c.teclear(l);
  }

  void _borrar() {
    if (!_c.puedeTeclear) return;
    HapticsService.light();
    _c.borrar();
  }

  Future<void> _enviar() async {
    final r = await _c.enviar();
    if (!mounted || r == null) return;
    switch (r) {
      case ResultadoEnvio.noValida:
      case ResultadoEnvio.error:
        HapticsService.medium();
      case ResultadoEnvio.revelado:
        // Cada casilla, al darse la vuelta: un toque y un blip (más agudo si la letra está).
        final res = _c.estado!.intentos.last.resultado;
        for (var i = 0; i < largoIntentoMedGuess; i++) {
          _despues(i * _msEntreCasillas + _msVolteo ~/ 2, () {
            final esta = res[i] != LetraMedGuess.ausente;
            if (esta) HapticsService.light();
            VozMascota.instancia.blip(esta ? 3 + i : i);
          });
        }
        final e = _c.estado!;
        if (e.terminado) {
          _despues(_msRevelado + 250, () {
            e.resuelto ? HapticsService.strong() : HapticsService.medium();
            _abrirResultado(e);
          });
        }
    }
  }

  void _abrirResultado(EstadoMedGuess e) {
    showAdaptiveModal<void>(
      context: context,
      builder: (_) => _Resultado(estado: e),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('MedGuess')),
      body: SafeArea(
        top: false,
        child: ListenableBuilder(
          listenable: _c,
          builder: (context, _) {
            if (_c.cargando && _c.estado == null) {
              return const Center(child: CircularProgressIndicator(color: AppColors.primary));
            }
            final e = _c.estado;
            if (e == null) return _ErrorCarga(mensaje: _c.errorCarga, onReintentar: _c.cargar);
            return Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(context.bodyGutter, 8, context.bodyGutter, 20),
                    children: [
                      Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: context.usesTwoPane ? 980 : 560),
                          child: _Contenido(c: _c, onVerResultado: () => _abrirResultado(e)),
                        ),
                      ),
                    ],
                  ),
                ),
                if (!e.terminado)
                  _Teclado(
                    estados: estadoTeclasMedGuess(e.intentos),
                    activo: _c.puedeTeclear,
                    puedeEnviar: _c.puedeEnviar,
                    enviando: _c.enviando,
                    onLetra: _teclear,
                    onBorrar: _borrar,
                    onEnviar: _enviar,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/* ════════════════════════════════════════════════════════════════════════
   Contenido
═══════════════════════════════════════════════════════════════════════════ */

class _Contenido extends StatelessWidget {
  final MedGuessController c;
  final VoidCallback onVerResultado;

  const _Contenido({required this.c, required this.onVerResultado});

  @override
  Widget build(BuildContext context) {
    final e = c.estado!;
    final dosColumnas = context.usesTwoPane;
    final juego = <Widget>[
        _TarjetaTermino(estado: e, conPista: !dosColumnas),
        const SizedBox(height: 18),
        _Tablero(c: c),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          child: c.aviso == null
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: _Aviso(texto: c.aviso!),
                ),
        ),
        if (e.terminado) ...[
          const SizedBox(height: 18),
          _Final(estado: e, onVer: onVerResultado),
        ],
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Text(
              'RETO DEL DÍA',
              style: TextStyle(color: kMuted, fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1.2),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text.rich(
                textAlign: TextAlign.right,
              TextSpan(children: [
                TextSpan(
                  text: '${e.intentosUsados}',
                  style: const TextStyle(color: kInk, fontWeight: FontWeight.w900),
                ),
                const TextSpan(text: ' / $maxIntentosMedGuess intentos'),
              ]),
              style: const TextStyle(color: kMuted, fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (dosColumnas)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: juego)),
              const SizedBox(width: 28),
              Expanded(flex: 2, child: _Pistas(estado: e)),
            ],
          )
        else ...[
          ...juego,
          const SizedBox(height: 22),
          _Pistas(estado: e),
        ],
      ],
    );
  }
}

class _TarjetaTermino extends StatelessWidget {
  final EstadoMedGuess estado;

  /// En el móvil la lista de pistas queda bajo el tablero, tapada por el teclado: la última pista
  /// abierta se repite aquí, a la vista.
  final bool conPista;

  const _TarjetaTermino({required this.estado, this.conPista = false});

  @override
  Widget build(BuildContext context) {
    final terminos = estado.terminos;
    return StickerCard(
      radius: 22,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      texture: graphPaper(tint: _rosa, step: 12),
      child: Column(
        children: [
          if (estado.categoria.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: tinted(_rosa, 0.2),
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: kInk, width: 1.5),
              ),
              child: Text(
                estado.categoria.toUpperCase(),
                textAlign: TextAlign.center,
                style: const TextStyle(color: kInk, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.8),
              ),
            ),
          const SizedBox(height: 12),
          if (terminos.isEmpty)
            const Text('Término médico del día', style: TextStyle(color: kMuted, fontWeight: FontWeight.w700))
          else
            for (var i = 0; i < terminos.length; i++) ...[
              if (i > 0)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: Text('o también', style: TextStyle(color: kMuted, fontSize: 11.5, fontWeight: FontWeight.w700)),
                ),
              _FilaTermino(termino: terminos[i]),
            ],
          if (conPista && estado.pistas.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: kHairline, width: 1.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'PISTA ${estado.pistas.length} DE ${math.max(estado.totalPistas, estado.pistas.length)}',
                    style: const TextStyle(color: kMuted, fontSize: 10.5, fontWeight: FontWeight.w900, letterSpacing: 1),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    estado.pistas.last,
                    style: const TextStyle(color: kInk, fontSize: 13.5, height: 1.4, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FilaTermino extends StatelessWidget {
  final TerminoMedGuess termino;

  const _FilaTermino({required this.termino});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 14,
      runSpacing: 8,
      children: [
        for (final palabra in termino.palabras)
          // Una palabra larga («BRONCOESPASMO») no cabe a tamaño normal en un móvil: se encoge
          // entera antes que partirla.
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < palabra.length; i++) ...[
                  if (i > 0) const SizedBox(width: 4),
                  _CasillaTermino(caracter: palabra[i]),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _CasillaTermino extends StatelessWidget {
  final String? caracter;

  const _CasillaTermino({required this.caracter});

  @override
  Widget build(BuildContext context) {
    final c = caracter;
    final esLetra = c != null && RegExp(r'[A-ZÁÉÍÓÚÜÑ]').hasMatch(c);
    if (c != null && !esLetra) {
      // Guiones, números, puntos: tal cual, sin casilla.
      return SizedBox(
        width: 12,
        height: 36,
        child: Center(child: Text(c, style: const TextStyle(color: kInk, fontWeight: FontWeight.w900))),
      );
    }
    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      curve: kEaseOut,
      width: 26,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: esLetra ? _rosa : Colors.white,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: esLetra ? kInk : kHairline, width: esLetra ? 1.5 : 1.5),
      ),
      child: Text(
        c ?? '',
        style: const TextStyle(color: _rosaTinta, fontSize: 15, fontWeight: FontWeight.w900),
      ),
    );
  }
}

/* ════════════════════════════════════════════════════════════════════════
   Tablero
═══════════════════════════════════════════════════════════════════════════ */

class _Tablero extends StatelessWidget {
  final MedGuessController c;

  const _Tablero({required this.c});

  @override
  Widget build(BuildContext context) {
    final e = c.estado!;
    return LayoutBuilder(
      builder: (context, cons) {
        const hueco = 8.0;
        final lado = math.min(56.0, (cons.maxWidth - hueco * (largoIntentoMedGuess - 1)) / largoIntentoMedGuess);
        return Column(
          children: [
            for (var fila = 0; fila < maxIntentosMedGuess; fila++) ...[
              if (fila > 0) const SizedBox(height: hueco),
              _fila(e, fila, lado, hueco),
            ],
          ],
        );
      },
    );
  }

  Widget _fila(EstadoMedGuess e, int fila, double lado, double hueco) {
    final intento = fila < e.intentos.length ? e.intentos[fila] : null;
    final activa = intento == null && fila == e.intentos.length && !e.terminado;
    final letras = intento?.palabra ?? (activa ? c.actual : '');
    final revelando = intento != null && c.filaRevelando == fila;
    final cerrada = e.terminado && intento == null;

    Widget row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < largoIntentoMedGuess; i++) ...[
          if (i > 0) SizedBox(width: hueco),
          _Casilla(
            key: ValueKey('c-$fila-$i-${revelando ? c.cicloRevelado : 0}'),
            lado: lado,
            letra: i < letras.length ? letras[i] : '',
            estado: intento?.resultado[i],
            revelar: revelando,
            orden: i,
            cerrada: cerrada,
            enviando: activa && c.enviando,
          ),
        ],
      ],
    );
    if (activa) {
      // Palabra rechazada: la fila tiembla.
      row = TweenAnimationBuilder<double>(
        key: ValueKey('sacudida-${c.sacudidas}'),
        tween: Tween(begin: c.sacudidas == 0 ? 1 : 0, end: 1),
        duration: const Duration(milliseconds: 420),
        builder: (_, t, child) =>
            Transform.translate(offset: Offset(math.sin(t * math.pi * 6) * 8 * (1 - t), 0), child: child),
        child: row,
      );
    }
    return Semantics(
      label: intento != null
          ? 'Intento ${fila + 1}: ${intento.palabra}'
          : activa
              ? 'Intento ${fila + 1}, escribiendo: ${letras.isEmpty ? 'vacío' : letras}'
              : null,
      child: ExcludeSemantics(child: row),
    );
  }
}

class _Casilla extends StatelessWidget {
  final double lado;
  final String letra;
  final LetraMedGuess? estado;
  final bool revelar;
  final int orden;
  final bool cerrada;
  final bool enviando;

  const _Casilla({
    super.key,
    required this.lado,
    required this.letra,
    required this.estado,
    required this.revelar,
    required this.orden,
    required this.cerrada,
    required this.enviando,
  });

  @override
  Widget build(BuildContext context) {
    if (!revelar) return _cara(estado, 1);
    // Se voltea sobre su eje horizontal: a mitad de giro cambia de color.
    final inicio = orden * _msEntreCasillas / _msRevelado;
    final fin = (orden * _msEntreCasillas + _msVolteo) / _msRevelado;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: _msRevelado),
      curve: Interval(inicio, fin, curve: Curves.easeInOut),
      builder: (_, t, __) => _cara(t < 0.5 ? null : estado, (math.cos(t * math.pi)).abs().clamp(0.02, 1.0)),
    );
  }

  Widget _cara(LetraMedGuess? e, double escalaY) {
    final conLetra = letra.isNotEmpty;
    final (Color fondo, Color texto, Color borde) = switch (e) {
      LetraMedGuess.encontrada => (_verde, _verdeTinta, kInk),
      LetraMedGuess.conocida => (_verdeClaro, _verdeTinta, kInk),
      LetraMedGuess.ausente => (_oscuro, _oscuroTexto, _oscuro),
      null when cerrada => (const Color(0xFFEEE8E6), const Color(0xFFB9A9A6), const Color(0xFFD7CCC9)),
      null when conLetra => (Colors.white, kInk, kInk),
      null => (Colors.white, kMuted, kHairline),
    };
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.diagonal3Values(1, escalaY, 1),
      child: AnimatedOpacity(
        opacity: enviando ? 0.55 : 1,
        duration: const Duration(milliseconds: 300),
        child: Container(
          width: lado,
          height: lado,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: fondo,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borde, width: conLetra || e != null ? 2 : 1.5),
            boxShadow: e == LetraMedGuess.encontrada ? inkShadow(2) : null,
          ),
          child: Text(
            cerrada && !conLetra ? '×' : letra,
            style: TextStyle(color: texto, fontSize: lado * 0.42, fontWeight: FontWeight.w900),
          ),
        ),
      ),
    );
  }
}

class _Aviso extends StatelessWidget {
  final String texto;

  const _Aviso({required this.texto});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF2EF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _rosa, width: 1.5),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, size: 18, color: Color(0xFF7F3D33)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              texto,
              style: const TextStyle(color: Color(0xFF7F3D33), fontSize: 13.5, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/* ════════════════════════════════════════════════════════════════════════
   Pistas y final
═══════════════════════════════════════════════════════════════════════════ */

class _Pistas extends StatelessWidget {
  final EstadoMedGuess estado;

  const _Pistas({required this.estado});

  @override
  Widget build(BuildContext context) {
    final total = math.max(estado.totalPistas, estado.pistas.length);
    if (total == 0) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel('Pistas', trailing: Text('${estado.pistas.length} de $total', style: const TextStyle(color: kMuted, fontWeight: FontWeight.w700))),
        const SizedBox(height: 10),
        for (var i = 0; i < total; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          if (i < estado.pistas.length)
            TweenAnimationBuilder<double>(
              key: ValueKey('pista-$i'),
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 380),
              curve: kEaseOut,
              builder: (_, t, child) => Opacity(
                opacity: t,
                child: Transform.translate(offset: Offset(0, 10 * (1 - t)), child: child),
              ),
              child: StickerCard(
                depth: 4,
                radius: 18,
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                texture: ruledPaper(step: 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PISTA ${i + 1}',
                      style: const TextStyle(color: kMuted, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1),
                    ),
                    const SizedBox(height: 4),
                    Text(estado.pistas[i], style: const TextStyle(color: kInk, fontSize: 14.5, height: 1.45, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: kHairline, width: 1.5),
              ),
              child: Row(
                children: [
                  const Icon(Icons.lock_rounded, size: 16, color: kMuted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      i == estado.pistas.length && !estado.terminado
                          ? 'Pista ${i + 1} · se abre si este intento no lo resuelve'
                          : 'Pista ${i + 1}',
                      style: const TextStyle(color: kMuted, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

class _Final extends StatelessWidget {
  final EstadoMedGuess estado;
  final VoidCallback onVer;

  const _Final({required this.estado, required this.onVer});

  @override
  Widget build(BuildContext context) {
    final gano = estado.resuelto;
    return StickerCard(
      radius: 20,
      background: gano ? tinted(_verde, 0.35) : tinted(_rosa, 0.25),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      onTap: onVer,
      pressDelay: const Duration(milliseconds: 120),
      child: Row(
        children: [
          Icon(gano ? Icons.emoji_events_rounded : Icons.nightlight_round, color: kInk, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  gano ? 'Reto completado' : 'Intentos agotados',
                  style: const TextStyle(color: kInk, fontSize: 16, fontWeight: FontWeight.w900),
                ),
                const Text(
                  'Mañana hay un MedGuess nuevo.',
                  style: TextStyle(color: kMuted, fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: kInk),
        ],
      ),
    );
  }
}

class _Resultado extends StatelessWidget {
  final EstadoMedGuess estado;

  const _Resultado({required this.estado});

  /// Como la web: una exclamación que no cambia si se vuelve a abrir el mismo resultado.
  String get _exclamacion {
    final opciones = estado.resuelto
        ? const ['Increíble', 'Perfecto', 'Dominado', 'Nivel MIR']
        : const ['Casi...', 'Buen intento', 'Mañana lo clavas'];
    final semilla = '${estado.intentosUsados}-${estado.respuesta ?? ''}-${estado.resuelto}';
    var h = 0;
    for (final u in semilla.codeUnits) {
      h = (h * 31 + u) & 0x7fffffff;
    }
    return opciones[h % opciones.length];
  }

  @override
  Widget build(BuildContext context) {
    final gano = estado.resuelto;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            gano ? 'Reto completado' : 'Intentos agotados',
            style: const TextStyle(color: kInk, fontSize: 24, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 2),
          Text('¡$_exclamacion!', style: const TextStyle(color: Color(0xFF865046), fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
            gano
                ? 'Lo has resuelto en ${estado.intentosUsados} ${estado.intentosUsados == 1 ? 'intento' : 'intentos'}.'
                : 'No pasa nada: mañana tendrás un MedGuess nuevo.',
            style: const TextStyle(color: kMuted, fontSize: 14, height: 1.4),
          ),
          if (estado.respuesta != null) ...[
            const SizedBox(height: 16),
            StickerCard(
              depth: 4,
              radius: 18,
              background: tinted(_rosa, 0.22),
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'TÉRMINO MÉDICO',
                    style: TextStyle(color: Color(0xFF865046), fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    estado.respuesta!,
                    style: const TextStyle(color: _rosaTinta, fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 0.8),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          StickerButton(
            label: 'Cerrar',
            expand: true,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }
}

/* ════════════════════════════════════════════════════════════════════════
   Teclado
═══════════════════════════════════════════════════════════════════════════ */

class _Teclado extends StatelessWidget {
  final Map<String, LetraMedGuess> estados;
  final bool activo;
  final bool puedeEnviar;
  final bool enviando;
  final ValueChanged<String> onLetra;
  final VoidCallback onBorrar;
  final VoidCallback onEnviar;

  const _Teclado({
    required this.estados,
    required this.activo,
    required this.puedeEnviar,
    required this.enviando,
    required this.onLetra,
    required this.onBorrar,
    required this.onEnviar,
  });

  static const _filas = ['QWERTYUIOP', 'ASDFGHJKL', 'ZXCVBNM'];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: kHairline, width: 1.5)),
      ),
      padding: const EdgeInsets.fromLTRB(6, 10, 6, 8),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var f = 0; f < _filas.length; f++) ...[
                if (f > 0) const SizedBox(height: 7),
                Row(
                  children: [
                    if (f == 1) const Spacer(flex: 1),
                    if (f == 2)
                      _Tecla(
                        flex: 3,
                        etiqueta: 'Enviar',
                        semantica: 'Enviar intento',
                        fondo: puedeEnviar ? _rosa : Colors.white,
                        texto: puedeEnviar ? Colors.white : kMuted,
                        cargando: enviando,
                        onTap: puedeEnviar ? onEnviar : null,
                      ),
                    for (final l in _filas[f].split(''))
                      _Tecla(
                        flex: 2,
                        etiqueta: l,
                        semantica: l,
                        fondo: switch (estados[l]) {
                          LetraMedGuess.encontrada || LetraMedGuess.conocida => _verde,
                          LetraMedGuess.ausente => _oscuro,
                          null => Colors.white,
                        },
                        texto: switch (estados[l]) {
                          LetraMedGuess.encontrada || LetraMedGuess.conocida => _verdeTinta,
                          LetraMedGuess.ausente => _oscuroTexto,
                          null => kInk,
                        },
                        onTap: activo ? () => onLetra(l) : null,
                      ),
                    if (f == 1) const Spacer(flex: 1),
                    if (f == 2)
                      _Tecla(
                        flex: 3,
                        icono: Icons.backspace_outlined,
                        semantica: 'Borrar',
                        fondo: Colors.white,
                        texto: kInk,
                        onTap: activo ? onBorrar : null,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Tecla extends StatefulWidget {
  final int flex;
  final String? etiqueta;
  final IconData? icono;
  final String semantica;
  final Color fondo;
  final Color texto;
  final bool cargando;
  final VoidCallback? onTap;

  const _Tecla({
    required this.flex,
    this.etiqueta,
    this.icono,
    required this.semantica,
    required this.fondo,
    required this.texto,
    this.cargando = false,
    this.onTap,
  });

  @override
  State<_Tecla> createState() => _TeclaState();
}

class _TeclaState extends State<_Tecla> {
  bool _abajo = false;

  @override
  Widget build(BuildContext context) {
    final activa = widget.onTap != null;
    return Expanded(
      flex: widget.flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2.5),
        child: Semantics(
          button: true,
          enabled: activa,
          label: widget.semantica,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            // En el teclado el toque cuenta al bajar el dedo: es lo que se espera de una tecla.
            onTapDown: activa
                ? (_) {
                    setState(() => _abajo = true);
                    widget.onTap!();
                  }
                : null,
            onTapUp: (_) => setState(() => _abajo = false),
            onTapCancel: () => setState(() => _abajo = false),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 70),
              height: 50,
              alignment: Alignment.center,
              transform: Matrix4.translationValues(0, _abajo ? 2 : 0, 0),
              decoration: BoxDecoration(
                color: widget.fondo,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: widget.fondo == _oscuro ? _oscuro : kInk, width: 1.5),
                boxShadow: _abajo || !activa
                    ? null
                    : const [BoxShadow(color: kInk, offset: Offset(0, 2), blurRadius: 0)],
              ),
              child: ExcludeSemantics(
                child: widget.cargando
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: kInk),
                      )
                    : widget.icono != null
                        ? Icon(widget.icono, size: 20, color: widget.texto)
                        : FittedBox(
                            child: Text(
                              widget.etiqueta!,
                              style: TextStyle(color: widget.texto, fontSize: 16, fontWeight: FontWeight.w800),
                            ),
                          ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorCarga extends StatelessWidget {
  final String? mensaje;
  final VoidCallback onReintentar;

  const _ErrorCarga({required this.mensaje, required this.onReintentar});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.extension_off_rounded, size: 40, color: kMuted),
            const SizedBox(height: 12),
            Text(
              mensaje ?? 'No se pudo cargar MedGuess',
              textAlign: TextAlign.center,
              style: const TextStyle(color: kInk, fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            StickerButton(label: 'Reintentar', icon: Icons.refresh_rounded, onPressed: onReintentar),
          ],
        ),
      ),
    );
  }
}
