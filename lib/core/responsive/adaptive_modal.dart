import 'package:flutter/material.dart';

import 'breakpoints.dart';

/// Muestra una hoja/diálogo que se adapta al tamaño de ventana:
///
/// - **compact (móvil):** `showModalBottomSheet` — idéntico a lo de siempre.
/// - **medium / expanded (tablet):** un `Dialog` centrado con ancho acotado,
///   que es lo que se espera en pantalla grande (una hoja a lo ancho de una
///   tablet queda enorme y descolgada del gesto).
///
/// El `builder` es el mismo en los dos casos. Si el contenido ya trae un
/// `SafeArea` + `Padding` (como casi todas las hojas de la app), encaja en el
/// diálogo sin tocar nada.
Future<T?> showAdaptiveModal<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
  bool useRootNavigator = false,
  Color? backgroundColor,
  double dialogMaxWidth = 460,
}) {
  final bg = backgroundColor ?? Colors.white;

  if (!context.isWide) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      useRootNavigator: useRootNavigator,
      backgroundColor: bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: builder,
    );
  }

  return showDialog<T>(
    context: context,
    useRootNavigator: useRootNavigator,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    builder: (context) {
      return Dialog(
        backgroundColor: bg,
        surfaceTintColor: bg,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 40),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: dialogMaxWidth,
            maxHeight: MediaQuery.sizeOf(context).height * 0.82,
          ),
          // Las hojas suelen construirse contando con que hacen scroll ellas
          // mismas; si no, este SingleChildScrollView evita overflow en el
          // diálogo.
          child: SingleChildScrollView(child: builder(context)),
        ),
      );
    },
  );
}
