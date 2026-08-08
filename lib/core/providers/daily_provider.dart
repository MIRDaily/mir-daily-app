import 'package:flutter/foundation.dart';

import '../models/models.dart';
import '../services/api_service.dart';

enum DailyStatus {
  idle, // sin comprobar
  checking, // pidiendo preguntas
  ready, // preguntas cargadas, sobre listo para rasgar
  playing, // quiz en curso
  submitting, // enviando respuestas
  completed, // daily de hoy ya hecho
  error,
}

/// Orquesta el flujo del sobre diario:
/// abrir sobre → responder → enviar → resultados.
class DailyProvider extends ChangeNotifier {
  final ApiService api;

  DailyProvider(this.api);

  DailyStatus _status = DailyStatus.idle;
  DailyStatus get status => _status;

  String? _error;
  String? get error => _error;

  List<DailyQuestion> _questions = [];
  List<DailyQuestion> get questions => _questions;

  final List<UserAnswer> _answers = [];
  List<UserAnswer> get answers => List.unmodifiable(_answers);

  int _currentIndex = 0;
  int get currentIndex => _currentIndex;

  DailyQuestion? get currentQuestion =>
      _currentIndex < _questions.length ? _questions[_currentIndex] : null;

  SubmitResult? _submitResult;
  SubmitResult? get submitResult => _submitResult;

  DailyResults? _results;
  DailyResults? get results => _results;

  List<RankingEntry> _ranking = [];
  List<RankingEntry> get ranking => _ranking;

  ScoreDistribution? _scoreDistribution;
  ScoreDistribution? get scoreDistribution => _scoreDistribution;

  StatsSummary? _statsSummary;
  StatsSummary? get statsSummary => _statsSummary;

  int get correctSoFar {
    var count = 0;
    for (final a in _answers) {
      final q = _questions.where((q) => q.id == a.questionId).firstOrNull;
      if (q != null && q.correctIndex == a.selectedIndex) count++;
    }
    return count;
  }

  /// Pide las preguntas de hoy. Devuelve true si el sobre se puede abrir.
  Future<bool> fetchDaily() async {
    _status = DailyStatus.checking;
    _error = null;
    notifyListeners();

    try {
      _questions = await api.getDailyQuestions();
      _answers.clear();
      _currentIndex = 0;
      _submitResult = null;
      _status = DailyStatus.ready;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      if (e.alreadyCompleted) {
        _status = DailyStatus.completed;
      } else {
        _status = DailyStatus.error;
        _error = e.message;
      }
    } catch (_) {
      _status = DailyStatus.error;
      _error = 'Sin conexión con el servidor.';
    }
    notifyListeners();
    return false;
  }

  void startQuiz() {
    _status = DailyStatus.playing;
    notifyListeners();
  }

  /// Registra la respuesta de la pregunta actual (índice 0-based, o `null` si
  /// se deja EN BLANCO) y avanza. Devuelve true si era la última.
  bool answerCurrent({required int? selectedIndex, required int timeSpent}) {
    final q = currentQuestion;
    if (q == null) return true;

    _answers.add(UserAnswer(
      questionId: q.id,
      selectedIndex: selectedIndex,
      timeSpent: timeSpent,
    ));

    final isLast = _currentIndex >= _questions.length - 1;
    if (!isLast) {
      _currentIndex++;
    }
    notifyListeners();
    return isLast;
  }

  Future<bool> submit() async {
    _status = DailyStatus.submitting;
    _error = null;
    notifyListeners();

    try {
      _submitResult = await api.submitAnswers(_answers);
      _status = DailyStatus.completed;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      if (e.alreadyCompleted) {
        _status = DailyStatus.completed;
        notifyListeners();
        return true;
      }
      _error = e.message;
    } catch (_) {
      _error = 'No se pudieron enviar tus respuestas. Revisa tu conexión.';
    }

    _status = DailyStatus.playing;
    notifyListeners();
    return false;
  }

  Future<void> loadResults() async {
    try {
      _results = await api.getResultsToday();
      notifyListeners();
    } catch (_) {
      // Mantiene los datos del submit si los hay.
    }
    try {
      _ranking = await api.getRanking();
      notifyListeners();
    } catch (_) {}
    try {
      _scoreDistribution = await api.getScoreDistribution();
      notifyListeners();
    } catch (_) {}
    try {
      _statsSummary = await api.getStatsSummary();
      notifyListeners();
    } catch (_) {}
  }

  /// Vuelve al estado inicial (p. ej. al cerrar sesión).
  void reset() {
    _status = DailyStatus.idle;
    _questions = [];
    _answers.clear();
    _currentIndex = 0;
    _submitResult = null;
    _results = null;
    _ranking = [];
    _scoreDistribution = null;
    _statsSummary = null;
    _error = null;
    notifyListeners();
  }
}
