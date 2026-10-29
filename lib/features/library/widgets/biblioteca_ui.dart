import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_config.dart';
import '../../../core/models/biblioteca.dart';
import '../../../core/models/flashcards.dart' show visualAsignatura;
import '../../../core/services/api_service.dart';
import '../../../core/services/carpetas.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/sticker/sticker.dart';
import '../../flashcards/flashcard_deck_screen.dart';
import '../../resumenes/resumen_detail_screen.dart';
import '../../resumenes/resumenes_api.dart';
import '../../resumenes/resumenes_grupo.dart' show resolveColorResumen;

/* ════════════════════════════════════════════════════════════════════════
   Piezas de la Biblioteca. Puerto de components/library/biblioteca/ui.tsx y
   dominioUi.tsx de la web: sigla de la asignatura, cifras del material y de
   las preguntas MIR (separadas, nunca mezcladas), fila de material y la
   señal de dominio con su propio color (azul cielo; verde si está bien
   llevado), que no se confunda con la escala del acierto en preguntas.
═══════════════════════════════════════════════════════════════════════════ */

const _cielo = Color(0xFF4E7C9B);
const _cieloSuave = Color(0xFFE7F0F6);
const _verde = Color(0xFF5C7A59);
const _verdeSuave = Color(0xFFEAF1E9);

Color colorDominio(bool bien) => bien ? _verde : _cielo;

Color colorAcierto(double p) => switch (tonoAcierto(p)) {
      TonoAcierto.bien => const Color(0xFF5C7A59),
      TonoAcierto.regular => const Color(0xFFB8862E),
      TonoAcierto.mal => const Color(0xFFB5675A),
    };

const tipoVisual = <TipoElemento, ({IconData icono, String nombre, Color color})>{
  TipoElemento.mapa: (icono: Icons.account_tree_rounded, nombre: 'Mapa', color: Color(0xFF7BA7C4)),
  TipoElemento.flashcards: (icono: Icons.style_rounded, nombre: 'Flashcards', color: Color(0xFFE8A598)),
  TipoElemento.resumenes: (icono: Icons.notes_rounded, nombre: 'Resumen', color: Color(0xFF8BA888)),
};

/// La sigla del catálogo sobre el color de la asignatura (el mismo que en flashcards).
class SiglaAsignatura extends StatelessWidget {
  final AsignaturaCatalogo asignatura;
  final bool grande;
  const SiglaAsignatura({super.key, required this.asignatura, this.grande = false});

  @override
  Widget build(BuildContext context) {
    final color = resolveColorResumen(visualAsignatura(asignatura.nombre).color).bg;
    final lado = grande ? 56.0 : 40.0;
    final sigla = asignatura.sigla ??
        (asignatura.nombre.length >= 2 ? asignatura.nombre.substring(0, 2) : asignatura.nombre).toUpperCase();
    return ExcludeSemantics(
      child: Container(
        width: lado,
        height: lado,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(grande ? 16 : 12),
          border: Border.all(color: kInk, width: 2),
          boxShadow: inkShadow(grande ? 3 : 2),
        ),
        child: Text(sigla,
            style: TextStyle(color: Colors.white, fontSize: grande ? 20 : 14, fontWeight: FontWeight.w900)),
      ),
    );
  }
}

/// Tres cifras pequeñas (mapas, flashcards, resúmenes); sin nada, «Sin material».
class CifrasMaterial extends StatelessWidget {
  final Cuenta cuenta;
  const CifrasMaterial({super.key, required this.cuenta});

  @override
  Widget build(BuildContext context) {
    if (cuenta.total == 0) {
      return const Text('Sin material', style: TextStyle(color: AppColors.textLight, fontSize: 12.5, fontWeight: FontWeight.w600));
    }
    final items = [
      (TipoElemento.mapa, cuenta.mapas),
      (TipoElemento.flashcards, cuenta.flashcards),
      (TipoElemento.resumenes, cuenta.resumenes),
    ].where((e) => e.$2 > 0);
    return Semantics(
      label: textoCuenta(cuenta),
      excludeSemantics: true,
      child: Wrap(spacing: 10, runSpacing: 4, children: [
        for (final (t, n) in items)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(tipoVisual[t]!.icono, size: 15, color: tipoVisual[t]!.color),
            const SizedBox(width: 3),
            Text('$n', style: const TextStyle(color: kInk, fontSize: 13, fontWeight: FontWeight.w900)),
          ]),
      ]),
    );
  }
}

/// «Preguntas MIR»: cuántas hay y el acierto del usuario (de /api/analytics, lo de siempre).
class CifrasPreguntas extends StatelessWidget {
  final int? preguntas;
  final double? acierto;
  final int respondidas;
  const CifrasPreguntas({super.key, this.preguntas, this.acierto, this.respondidas = 0});

  @override
  Widget build(BuildContext context) {
    final a = acierto;
    return Wrap(spacing: 10, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
      if (preguntas != null)
        Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.quiz_outlined, size: 15, color: kMuted),
          const SizedBox(width: 3),
          Text('$preguntas', style: const TextStyle(color: kInk, fontSize: 13, fontWeight: FontWeight.w900)),
        ]),
      if (respondidas > 0 && a != null)
        Text.rich(TextSpan(children: [
          TextSpan(text: '${a.round()} %', style: TextStyle(color: colorAcierto(a), fontWeight: FontWeight.w900)),
          const TextSpan(text: ' de acierto'),
        ]), style: const TextStyle(color: kMuted, fontSize: 12.5))
      else
        const Text('sin responder', style: TextStyle(color: AppColors.textLight, fontSize: 12.5)),
    ]);
  }
}

/// Indicador pequeño de una carpeta (en la lista de la asignatura): «recordarías ~72 % · 80 % visto».
class IndicadorDominio extends StatelessWidget {
  final DominioCarpeta? d;
  final bool cargando;
  const IndicadorDominio({super.key, this.d, this.cargando = false});

  @override
  Widget build(BuildContext context) {
    if (cargando) return const Text('…', style: TextStyle(color: AppColors.textLight));
    final estado = estadoCarpeta(d);
    if (estado == EstadoDominio.vacio) {
      return const Text('sin señal', style: TextStyle(color: AppColors.textLight, fontSize: 12));
    }
    if (estado == EstadoDominio.sinEstudiar) {
      return const Text('sin estudiar aún', style: TextStyle(color: AppColors.textLight, fontSize: 12));
    }
    final bien = estado == EstadoDominio.bien;
    final color = colorDominio(bien);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 4, children: [
        Icon(bien ? Icons.verified_rounded : Icons.psychology_rounded, size: 15, color: color),
        Text('recordarías ~${porcentajeDe(d!.dominio!)} %', style: TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.w800)),
        Text('· ${porcentajeDe(d!.cobertura!)} % visto', style: const TextStyle(color: kMuted, fontSize: 12)),
      ]),
      const SizedBox(height: 4),
      BarraFina(valor: d!.dominio!, color: color, etiqueta: 'Dominio del material'),
    ]);
  }
}

class BarraFina extends StatelessWidget {
  final double valor;
  final Color color;
  final String etiqueta;
  const BarraFina({super.key, required this.valor, required this.color, required this.etiqueta});

  @override
  Widget build(BuildContext context) => Semantics(
        label: '$etiqueta: ${porcentajeDe(valor)} %',
        child: ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: Container(
            height: 6,
            color: const Color(0xFFF0EAE6),
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(widthFactor: valor.clamp(0.0, 1.0), child: Container(color: color)),
          ),
        ),
      );
}

/// Una línea por grupo, bajo su título: «recordarías hoy ~64 % · 12 de 20 estudiadas».
class LineaDominioGrupo extends StatelessWidget {
  final DominioGrupo? g;
  const LineaDominioGrupo({super.key, this.g});

  @override
  Widget build(BuildContext context) {
    final grupo = g;
    if (grupo == null || grupo.elementos == 0 || grupo.dominio == null) return const SizedBox.shrink();
    if (grupo.estudiados == 0) {
      return const Text('Sin estudiar aún', style: TextStyle(color: AppColors.textLight, fontSize: 12));
    }
    final bien = estadoGrupo(grupo) == EstadoDominio.bien;
    final unidad = grupo.tipo == TipoElemento.flashcards ? 'estudiadas' : 'estudiados';
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: textoRecordarias(grupo.dominio!), style: TextStyle(color: colorDominio(bien), fontWeight: FontWeight.w800)),
        TextSpan(text: ' · ${grupo.estudiados} de ${grupo.elementos} $unidad', style: const TextStyle(color: kMuted)),
      ]),
      style: const TextStyle(fontSize: 12),
    );
  }
}

/// La señal de una carpeta, arriba de su lista: cuánto recordarías hoy, cuánto has visto, el último
/// repaso, si está «bien llevado» y los huecos de resúmenes que más se resisten.
class SenalDominio extends StatelessWidget {
  final DominioCarpeta? d;
  final bool soloMapas;
  const SenalDominio({super.key, this.d, this.soloMapas = false});

  @override
  Widget build(BuildContext context) {
    final estado = estadoCarpeta(d);
    if (estado == EstadoDominio.vacio) {
      return _aviso(soloMapas
          ? 'Los mapas no registran estudio. Añade flashcards o resúmenes para medirlo.'
          : 'Sin tarjetas ni párrafos que medir todavía.');
    }
    final c = d!;
    final bien = estado == EstadoDominio.bien;
    final color = colorDominio(bien);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bien ? _verdeSuave : _cieloSuave,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kInk, width: 2),
        boxShadow: inkShadow(3),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('DOMINIO DEL MATERIAL',
                  style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
              const SizedBox(height: 2),
              if (estado == EstadoDominio.sinEstudiar)
                const Text('Aún no has estudiado nada de aquí', style: TextStyle(color: kInk, fontSize: 15, fontWeight: FontWeight.w800))
              else
                Wrap(crossAxisAlignment: WrapCrossAlignment.end, spacing: 6, children: [
                  Text('~${porcentajeDe(c.dominio!)} %', style: TextStyle(color: color, fontSize: 26, fontWeight: FontWeight.w900, height: 1.1)),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 3),
                    child: Text('recordarías hoy', style: TextStyle(color: kMuted, fontSize: 12.5, fontWeight: FontWeight.w700)),
                  ),
                ]),
            ]),
          ),
          if (bien) const DocChip(label: 'Bien llevado', icon: Icons.verified_rounded, tone: DocTone.success),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          const Expanded(child: Text('Estudiado al menos una vez', style: TextStyle(color: kMuted, fontSize: 12))),
          Text('${c.estudiados} de ${c.elementos} · ${porcentajeDe(c.cobertura!)} %',
              style: const TextStyle(color: kInk, fontSize: 12, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 4),
        BarraFina(valor: c.cobertura!, color: color, etiqueta: 'Cobertura'),
        const SizedBox(height: 8),
        Row(children: [
          const Expanded(child: Text('Último repaso', style: TextStyle(color: kMuted, fontSize: 12))),
          Text(haceCuanto(c.ultimoRepaso) ?? 'nunca', style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w800)),
        ]),
        if (!bien) ...[
          const SizedBox(height: 8),
          Text(
            '«Bien llevado» = recordarías hoy al menos el ${porcentajeDe(umbralBienLlevado.dominio)} % y has visto el '
            '${porcentajeDe(umbralBienLlevado.cobertura)} % o más. Lo que no has estudiado cuenta como olvidado.',
            style: const TextStyle(color: kMuted, fontSize: 11.5, height: 1.4),
          ),
        ],
        if (c.huecosDebiles.isNotEmpty) ...[
          const SizedBox(height: 10),
          const Text('Huecos que más se te resisten', style: TextStyle(color: kInk, fontSize: 12.5, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final h in c.huecosDebiles)
              Tooltip(
                message: '${h.fallos} de ${h.intentos} veces «No lo sabía»${h.falladoAhora ? ' · fallado la última vez' : ''}',
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(99), border: Border.all(color: kHairline, width: 1.5)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Flexible(
                      child: Text(h.texto, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: kInk, fontSize: 12, fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 5),
                    Text('${h.fallos}/${h.intentos}', style: const TextStyle(color: AppColors.error, fontSize: 11, fontWeight: FontWeight.w900)),
                  ]),
                ),
              ),
          ]),
        ],
      ]),
    );
  }

  Widget _aviso(String texto) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(14)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.psychology_alt_rounded, size: 18, color: kMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(TextSpan(children: [
              const TextSpan(text: 'Dominio del material: ', style: TextStyle(fontWeight: FontWeight.w900, color: kInk)),
              TextSpan(text: texto),
            ]), style: const TextStyle(color: kMuted, fontSize: 12.5, height: 1.4)),
          ),
        ]),
      );
}

/// Sin la señal de dominio (la base de datos aún no la calcula): se dice, en vez de enseñar un 0.
class HuecoDominio extends StatelessWidget {
  const HuecoDominio({super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kHairline, width: 2),
        ),
        child: const Row(children: [
          Icon(Icons.psychology_alt_rounded, size: 18, color: kMuted),
          SizedBox(width: 8),
          Expanded(
            child: Text('Dominio del material · todavía no disponible: cuánto recordarías hoy de lo que has estudiado aquí.',
                style: TextStyle(color: kMuted, fontSize: 12.5, height: 1.4)),
          ),
        ]),
      );
}

/// Una fila de material: icono, título, cuántas tarjetas, y abrir. [inicio] va antes del icono (la
/// casilla de selección), [extra] bajo el título (la sugerencia o el dominio) y [acciones] a la derecha.
class FilaElemento extends StatelessWidget {
  final ElementoMaterial e;
  final Widget? inicio;
  final Widget? extra;
  final List<Widget> acciones;
  final VoidCallback? onAbierto;
  const FilaElemento({super.key, required this.e, this.inicio, this.extra, this.acciones = const [], this.onAbierto});

  @override
  Widget build(BuildContext context) {
    final t = tipoVisual[e.tipo]!;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kHairline, width: 2),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          if (inicio != null) inicio!,
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: kInk, width: 2),
              boxShadow: inkShadow(2),
            ),
            child: Icon(t.icono, color: t.color, size: 19),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.titulo, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: kInk, fontSize: 14, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(detalleElemento(e), style: const TextStyle(color: kMuted, fontSize: 12)),
            ]),
          ),
          IconButton(
            tooltip: e.tipo == TipoElemento.mapa ? 'Abrir en la web' : 'Abrir',
            onPressed: () async {
              await abrirElemento(context, e);
              onAbierto?.call();
            },
            icon: Icon(e.tipo == TipoElemento.mapa ? Icons.open_in_new_rounded : Icons.chevron_right_rounded, color: kInk),
          ),
        ]),
        if (extra != null) Padding(padding: const EdgeInsets.only(left: 46, top: 6, right: 8), child: extra!),
        if (acciones.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 40, top: 2),
            child: Wrap(spacing: 4, children: acciones),
          ),
      ]),
    );
  }
}

/// Abre un elemento en su pantalla. Los mapas aún no existen en la app (tanda 12): se abren en la web.
Future<void> abrirElemento(BuildContext context, ElementoMaterial e) async {
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  void fallo(String m) => messenger.showSnackBar(SnackBar(content: Text(m), behavior: SnackBarBehavior.floating));
  switch (e.tipo) {
    case TipoElemento.mapa:
      final ok = await launchUrl(Uri.parse('${AppConfig.webBaseUrl}/mapas/${e.id}'), mode: LaunchMode.externalApplication)
          .catchError((_) => false);
      if (!ok) fallo('No se pudo abrir el mapa en la web');
    case TipoElemento.flashcards:
      try {
        final grupos = await context.read<ApiService>().getFlashDecks();
        final g = grupos.where((d) => d.id == e.id).firstOrNull;
        if (g == null) return fallo('Ese grupo ya no existe');
        await navigator.push(MaterialPageRoute(builder: (_) => FlashcardDeckScreen(deck: g)));
      } catch (_) {
        fallo('No se pudo abrir el grupo');
      }
    case TipoElemento.resumenes:
      try {
        final r = await context.read<ResumenesApi>().cargarGrupo(e.id);
        await navigator.push(MaterialPageRoute(builder: (_) => ResumenDetailScreen(grupo: r.grupo)));
      } catch (_) {
        fallo('No se pudo abrir el grupo');
      }
  }
}

/// Mensaje de carga o de error dentro de una tarjeta.
class EstadoBiblioteca extends StatelessWidget {
  final String texto;
  final bool error;
  const EstadoBiblioteca(this.texto, {super.key, this.error = false});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(texto,
            textAlign: TextAlign.center,
            style: TextStyle(color: error ? AppColors.error : kMuted, fontSize: 14, fontWeight: FontWeight.w600)),
      );
}
