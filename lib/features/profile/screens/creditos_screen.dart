import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/creditos_ia.dart';
import '../../../core/models/ia.dart';
import '../../../core/responsive/content_shell.dart';
import '../../../core/services/creditos_ia_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/sticker/sticker.dart';

const _nombrePlan = {'prueba': 'Prueba', 'mensual': 'Mensual', 'anual': 'Anual', 'admin': 'Equipo (sin límite)'};
const _nombreBolsa = {
  'periodo': 'Del mes',
  'regalo': 'Regalo del primer mes',
  'prueba': 'Prueba',
  'recarga': 'Recarga',
  'ajuste': 'Regalo del equipo',
};

/// «Créditos de IA» (perfil): el saldo, la barra del mes, las demás bolsas con su caducidad, las
/// cancelaciones gratis, qué gasta y qué no, y el historial. Puerto de /profile/creditos de la web.
class CreditosScreen extends StatefulWidget {
  const CreditosScreen({super.key});

  @override
  State<CreditosScreen> createState() => _CreditosScreenState();
}

class _CreditosScreenState extends State<CreditosScreen> {
  final List<MovimientoIa> _movimientos = [];
  int? _siguiente;
  bool _cargandoHistorial = false;
  bool _historialCargado = false;
  String? _errorHistorial;

  @override
  void initState() {
    super.initState();
    context.read<CreditosIa>().refrescar();
    _masHistorial();
  }

  Future<void> _masHistorial() async {
    if (_cargandoHistorial) return;
    setState(() {
      _cargandoHistorial = true;
      _errorHistorial = null;
    });
    try {
      final r = await context.read<CreditosIa>().api.movimientos(antes: _siguiente);
      if (!mounted) return;
      setState(() {
        _movimientos.addAll(r.movimientos);
        _siguiente = r.siguiente;
        _historialCargado = true;
      });
    } on IaException catch (e) {
      if (mounted) setState(() => _errorHistorial = e.codigo == 'apagado' ? null : 'No se pudo cargar el historial');
    } catch (_) {
      if (mounted) setState(() => _errorHistorial = 'No se pudo cargar el historial');
    } finally {
      if (mounted) setState(() => _cargandoHistorial = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final creditos = context.watch<CreditosIa>();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text('Créditos de IA', style: TextStyle(color: kInk, fontWeight: FontWeight.w900)),
      ),
      body: SafeArea(
        child: !creditos.cargado
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : !creditos.activo || creditos.saldo == null
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        'Los créditos de IA no están activados todavía.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.5),
                      ),
                    ),
                  )
                : RefreshIndicator(
                    color: AppColors.primary,
                    onRefresh: () async {
                      _movimientos.clear();
                      _siguiente = null;
                      await Future.wait([creditos.refrescar(), _masHistorial()]);
                    },
                    child: BodyConstraint(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                        children: [
                          _saldo(creditos.saldo!),
                          const SizedBox(height: 24),
                          _queGasta(creditos.tarifa),
                          const SizedBox(height: 24),
                          const SectionLabel('Historial'),
                          ..._historial(),
                        ],
                      ),
                    ),
                  ),
      ),
    );
  }

  Widget _saldo(SaldoIa s) {
    final mes = s.bolsaDelMes;
    final otras = s.bolsas.where((b) => b.tipo != 'periodo' && b.saldo > 0).toList();
    final plan = s.plan != null ? 'Plan ${_nombrePlan[s.plan] ?? s.plan}' : 'Sin plan';
    final estado = s.estado != null && s.estado != 'activo' ? ' · ${s.estado}' : '';
    final dias = s.plan == 'prueba' && s.puedeUsar && s.periodoFin != null
        ? ' · quedan ${s.periodoFin!.difference(DateTime.now()).inHours <= 0 ? 0 : (s.periodoFin!.difference(DateTime.now()).inHours / 24).ceil()} días'
        : '';
    return StickerCard(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                s.ilimitado ? 'Sin límite' : fmtCreditos(s.total),
                style: const TextStyle(color: kInk, fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: -1),
              ),
              if (!s.ilimitado) const Text('créditos', style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text('$plan$estado$dias', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: s.puedeUsar ? const Color(0xFFEAF3E8) : const Color(0xFFFAEAED),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: kInk, width: 2),
            ),
            child: Text(
              s.puedeUsar ? 'Activo' : 'Sin plan activo',
              style: TextStyle(color: s.puedeUsar ? const Color(0xFF3F6E3C) : const Color(0xFFB04A5E), fontSize: 12.5, fontWeight: FontWeight.w900),
            ),
          ),
        ]),
        if (s.ilimitado) ...[
          const SizedBox(height: 12),
          const Text('Tu cuenta no descuenta créditos: cada generación se apunta para medir el consumo.', style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4)),
        ],
        if (mes != null && !s.ilimitado) ...[
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: mes.iniciales > 0 ? (mes.saldo / mes.iniciales).clamp(0, 1).toDouble() : 0,
              minHeight: 12,
              backgroundColor: const Color(0xFFF3EDE6),
              color: const Color(0xFFC9A227),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${fmtCreditos(mes.saldo)} de ${fmtCreditos(mes.iniciales)} del mes · se renuevan el ${fechaCortaIa(mes.caduca)} (no se acumulan)',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
        ],
        for (final b in otras) ...[
          const SizedBox(height: 10),
          Text(
            '${_nombreBolsa[b.tipo] ?? b.tipo}: ${fmtCreditos(b.saldo)} · caducan el ${fechaCortaIa(b.caduca)}'
            '${b.congelada ? ' · congelados: necesitas un plan activo para usarlos' : ''}',
            style: const TextStyle(color: kInk, fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        ],
        if (!s.ilimitado && s.cancelacionesGratisMes > 0) ...[
          const SizedBox(height: 14),
          Text(
            'Cancelaciones gratis este mes: te quedan ${fmtCreditos(s.cancelacionesGratisRestantes)} de ${fmtCreditos(s.cancelacionesGratisMes)}. '
            'Si cancelas en los primeros segundos, o se corta la conexión, no cuenta.',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.4),
          ),
        ],
      ]),
    );
  }

  Widget _queGasta(TarifaIa? t) {
    String ejemplo(String clave, int caracteres, [String? densidad]) {
      final n = precioIa(t, clave: clave, caracteres: caracteres, densidad: densidad);
      return n == null ? '—' : (n == 0 ? 'gratis' : fmtCreditos(n));
    }

    final filas = [
      ('Mapa esquemático de un tema mediano', ejemplo('mapa:esquema', 25000)),
      ('Mapa con tablas de un tema grande', ejemplo('mapa:esquema+tablas', 84000)),
      ('Flashcards de un tema mediano', ejemplo('flashcards:documento', 25000, 'normal')),
      ('Resumen activo de un tema mediano', ejemplo('resumenes:resumen', 25000, 'normal')),
      ('Rehacer o ampliar una rama del mapa', ejemplo('rama', 0)),
      ('«Más» flashcards de un tema', ejemplo('flashcards_mas', 0)),
      ('«Más» párrafos de un tema', ejemplo('resumenes_mas', 0)),
      ('Rehacer un párrafo', ejemplo('resumenes_rehacer', 0)),
      ('Sacar el índice de un libro', ejemplo('indice', 0)),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SectionLabel('Qué gasta y qué no'),
      const Text(
        'Estudiar, repasar y editar es gratis. Solo gasta generar con la IA, y siempre ves el precio antes.',
        style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
      ),
      const SizedBox(height: 10),
      for (final (texto, n) in filas)
        Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: kHairline)),
          child: Row(children: [
            Expanded(child: Text(texto, style: const TextStyle(color: kInk, fontSize: 13))),
            Text(n, style: const TextStyle(color: AppColors.error, fontSize: 13, fontWeight: FontWeight.w900)),
          ]),
        ),
    ]);
  }

  List<Widget> _historial() {
    if (_errorHistorial != null) {
      return [Text(_errorHistorial!, style: const TextStyle(color: AppColors.error, fontSize: 13, fontWeight: FontWeight.w700))];
    }
    if (!_historialCargado) {
      return [const Text('Cargando…', style: TextStyle(color: AppColors.textSecondary, fontSize: 13))];
    }
    if (_movimientos.isEmpty) {
      return [const Text('Todavía no hay movimientos.', style: TextStyle(color: AppColors.textSecondary, fontSize: 13))];
    }
    return [
      for (final m in _movimientos)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(describirMovimiento(m), style: const TextStyle(color: kInk, fontSize: 13.5, fontWeight: FontWeight.w600)),
                Text(fechaCortaIa(m.creado), style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5)),
              ]),
            ),
            Text(
              '${m.creditos > 0 ? '+' : (m.creditos < 0 ? '−' : '')}${fmtCreditos(m.creditos.abs())}',
              style: TextStyle(
                color: m.creditos < 0 ? AppColors.error : AppColors.successDark,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
          ]),
        ),
      if (_siguiente != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: TextButton(
            onPressed: _cargandoHistorial ? null : _masHistorial,
            child: Text(_cargandoHistorial ? 'Cargando…' : 'Ver más', style: const TextStyle(color: AppColors.primaryDark, fontWeight: FontWeight.w800)),
          ),
        ),
    ];
  }
}
