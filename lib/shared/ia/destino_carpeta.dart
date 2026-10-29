import 'package:flutter/material.dart';

import '../../core/responsive/adaptive_modal.dart';
import '../../core/services/carpetas.dart';
import '../../core/theme/app_theme.dart';
import '../sticker/sticker.dart';

/// «Dónde lo guardamos»: la carpeta (asignatura y tema) de lo que se crea con IA, con la sugerida
/// preseleccionada. Puerto reducido de <DestinoCarpeta> de la web: una fila que abre la lista.
class DestinoCarpeta extends StatelessWidget {
  final List<AsignaturaCatalogo> arbol;
  final Carpeta valor;
  final Carpeta? sugerida;
  final List<Carpeta> candidatas;
  final ValueChanged<Carpeta> onChanged;

  const DestinoCarpeta({
    super.key,
    required this.arbol,
    required this.valor,
    required this.onChanged,
    this.sugerida,
    this.candidatas = const [],
  });

  @override
  Widget build(BuildContext context) {
    final esSugerida = sugerida != null && sugerida == valor && valor.subjectId != null;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () async {
        final c = await elegirCarpeta(context, arbol: arbol, valor: valor, sugerida: sugerida, candidatas: candidatas);
        if (c != null) onChanged(c);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kInk, width: 2),
        ),
        child: Row(children: [
          Icon(valor.subjectId == null ? Icons.inbox_outlined : Icons.folder_rounded, color: kInk, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(nombreCarpeta(arbol, valor), style: const TextStyle(color: kInk, fontSize: 14, fontWeight: FontWeight.w800)),
              if (esSugerida)
                const Text('Sugerida por el título del documento', style: TextStyle(color: AppColors.textSecondary, fontSize: 11.5)),
            ]),
          ),
          const Text('Cambiar', style: TextStyle(color: AppColors.primaryDark, fontSize: 12.5, fontWeight: FontWeight.w800)),
        ]),
      ),
    );
  }
}

/// La lista para elegir carpeta: «Sin clasificar», las propuestas y todas las asignaturas con sus temas.
Future<Carpeta?> elegirCarpeta(
  BuildContext context, {
  required List<AsignaturaCatalogo> arbol,
  required Carpeta valor,
  Carpeta? sugerida,
  List<Carpeta> candidatas = const [],
}) {
  final propuestas = <Carpeta>[
    if (sugerida != null && sugerida.subjectId != null) sugerida,
    ...candidatas.where((c) => c != sugerida),
  ];

  Widget fila(BuildContext ctx, Carpeta c, String texto, {IconData? icono, bool sangria = false}) {
    final sel = c == valor;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.only(left: sangria ? 36 : 12, right: 12),
      leading: icono != null ? Icon(icono, color: kInk, size: 20) : null,
      title: Text(texto, style: TextStyle(color: kInk, fontSize: 13.5, fontWeight: sel ? FontWeight.w900 : FontWeight.w600)),
      trailing: sel ? const Icon(Icons.check_rounded, color: AppColors.primaryDark) : null,
      onTap: () => Navigator.pop(ctx, c),
    );
  }

  return showAdaptiveModal<Carpeta>(
    context: context,
    dialogScrollable: false,
    builder: (ctx) => SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(ctx).height * 0.75,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(8, 16, 8, 24),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Text('Dónde lo guardamos', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 19, color: kInk)),
            ),
            fila(ctx, Carpeta.sinClasificar, 'Sin clasificar', icono: Icons.inbox_outlined),
            if (propuestas.isNotEmpty) ...[
              const Padding(padding: EdgeInsets.fromLTRB(12, 12, 12, 4), child: SectionLabel('Propuestas')),
              for (final c in propuestas) fila(ctx, c, nombreCarpeta(arbol, c), icono: Icons.auto_awesome_rounded),
            ],
            const Padding(padding: EdgeInsets.fromLTRB(12, 12, 12, 4), child: SectionLabel('Asignaturas')),
            for (final a in arbol)
              Theme(
                data: Theme.of(ctx).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  initiallyExpanded: a.id == valor.subjectId,
                  tilePadding: const EdgeInsets.symmetric(horizontal: 12),
                  title: Text(a.nombre, style: const TextStyle(color: kInk, fontSize: 14, fontWeight: FontWeight.w800)),
                  children: [
                    fila(ctx, Carpeta(subjectId: a.id), 'General', sangria: true),
                    for (final t in a.temas) fila(ctx, Carpeta(subjectId: a.id, topicId: t.id), t.nombre, sangria: true),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
