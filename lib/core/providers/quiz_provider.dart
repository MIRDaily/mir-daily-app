import 'package:flutter/material.dart';
import '../models/question.dart';
import '../data/questions_data.dart';

class QuizProvider extends ChangeNotifier {
  List<Question> _allQuestions = [];
  List<Question> _dailyQuestions = [];
  int _currentIndex = 0;
  int? _selectedAnswer;
  bool _hasAnswered = false;
  bool _showExplanation = false;
  
  // Estadísticas de la sesión
  int _sessionCorrect = 0;
  int _sessionTotal = 0;
  
  // Estadísticas globales (en producción vendrían del backend/local storage)
  final int _totalAnswered = 0;
  final int _totalCorrect = 0;
  final int _currentStreak = 0;

  QuizProvider() {
    _loadQuestions();
  }

  // Getters
  List<Question> get allQuestions => _allQuestions;
  List<Question> get dailyQuestions => _dailyQuestions;
  Question? get currentQuestion => 
      _dailyQuestions.isNotEmpty ? _dailyQuestions[_currentIndex] : null;
  int get currentIndex => _currentIndex;
  int? get selectedAnswer => _selectedAnswer;
  bool get hasAnswered => _hasAnswered;
  bool get showExplanation => _showExplanation;
  int get sessionCorrect => _sessionCorrect;
  int get sessionTotal => _sessionTotal;
  bool get isLastQuestion => _currentIndex >= _dailyQuestions.length - 1;
  int get totalQuestions => _dailyQuestions.length;
  
  double get sessionAccuracy {
    if (_sessionTotal == 0) return 0;
    return (_sessionCorrect / _sessionTotal) * 100;
  }
  
  // Estadísticas del usuario para el Studio
  Map<String, int> get userStats => {
    'answered': _totalAnswered + _sessionTotal,
    'correct': _totalCorrect + _sessionCorrect,
    'streak': _currentStreak,
  };

  void _loadQuestions() {
    _allQuestions = QuestionsData.getSampleQuestions();
    _generateDailyQuestions();
  }

  /// Nº de preguntas del sobre diario. Coincide con el estándar del backend
  /// (QUESTIONS_PER_DAILY = 5 en mir-daily-backend/src/routes/daily.js).
  static const int dailyQuestionCount = 5;

  void _generateDailyQuestions() {
    // El sobre diario contiene exactamente [dailyQuestionCount] preguntas,
    // igual que la mecánica de la web (cron diario que selecciona 5).
    final shuffled = List<Question>.from(_allQuestions)..shuffle();
    _dailyQuestions = shuffled.take(dailyQuestionCount).toList();
    notifyListeners();
  }

  void selectAnswer(int index) {
    if (_hasAnswered) return;
    _selectedAnswer = index;
    notifyListeners();
  }

  void confirmAnswer() {
    if (_selectedAnswer == null || _hasAnswered) return;
    
    _hasAnswered = true;
    _sessionTotal++;
    
    if (_selectedAnswer == currentQuestion?.correctIndex) {
      _sessionCorrect++;
    }
    
    notifyListeners();
  }

  void toggleExplanation() {
    _showExplanation = !_showExplanation;
    notifyListeners();
  }

  void nextQuestion() {
    if (_currentIndex < _dailyQuestions.length - 1) {
      _currentIndex++;
      _selectedAnswer = null;
      _hasAnswered = false;
      _showExplanation = false;
      notifyListeners();
    }
  }

  void previousQuestion() {
    if (_currentIndex > 0) {
      _currentIndex--;
      _selectedAnswer = null;
      _hasAnswered = false;
      _showExplanation = false;
      notifyListeners();
    }
  }

  void resetQuiz() {
    _currentIndex = 0;
    _selectedAnswer = null;
    _hasAnswered = false;
    _showExplanation = false;
    _sessionCorrect = 0;
    _sessionTotal = 0;
    _generateDailyQuestions();
  }

  void goToQuestion(int index) {
    if (index >= 0 && index < _dailyQuestions.length) {
      _currentIndex = index;
      _selectedAnswer = null;
      _hasAnswered = false;
      _showExplanation = false;
      notifyListeners();
    }
  }

  Question? getQuestionById(String id) {
    try {
      return _allQuestions.firstWhere((q) => q.id == id);
    } catch (e) {
      return null;
    }
  }
}
