import 'package:flutter/foundation.dart';

/// Qué preguntas sabe la app que están guardadas en algún mazo.
///
/// Existe porque "guardada" no puede vivir dentro del icono que la muestra.
/// El `SaveToDeckButton` es un `StatefulWidget` y su estado dura lo que dure
/// ese widget concreto: en cuanto la pantalla cambia de forma —al pulsar
/// "Comprobar" en el simulacro la cabecera se rehace, y en la revisión final
/// pasa lo mismo— Flutter tira el State y el badge verde volvía a blanco
/// aunque la pregunta siguiera guardada en el mazo.
///
/// Aquí el dato sobrevive a esas reconstrucciones y, de paso, lo comparten
/// todos los sitios que enseñan la misma pregunta.
///
/// Solo guarda lo que se ha visto en esta sesión: no pregunta nada al
/// servidor por su cuenta. Se rellena cuando se abre la hoja de "guardar en
/// un mazo", que es donde ya se consulta ese dato de todas formas.
class SavedQuestionsProvider extends ChangeNotifier {
  final Set<String> _saved = {};

  bool isSaved(String? questionId) =>
      questionId != null && _saved.contains(questionId);

  /// Deja constancia de si [questionId] está guardada en algún mazo.
  void setSaved(String questionId, bool saved) {
    if (questionId.isEmpty) return;
    final cambio = saved ? _saved.add(questionId) : _saved.remove(questionId);
    if (cambio) notifyListeners();
  }
}
