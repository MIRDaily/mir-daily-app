import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_profile.dart';
import '../models/deck.dart';

class UserProvider extends ChangeNotifier {
  UserProfile _profile = UserProfile();
  List<Deck> _decks = [];
  bool _isLoading = true;
  
  // --- NUEVO: Variable para el avatar (gato 1 por defecto) ---
  int _avatarId = 0;

  UserProvider() {
    _loadData();
  }

  // Getters
  UserProfile get profile => _profile;
  List<Deck> get decks => _decks;
  bool get isLoading => _isLoading;
  
  // --- NUEVO: Getter para el avatar ---
  int get avatarId => _avatarId;

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Cargar perfil
    final profileJson = prefs.getString('user_profile');
    if (profileJson != null) {
      _profile = UserProfile.fromJson(jsonDecode(profileJson));
    }
    
    // Cargar mazos
    final decksJson = prefs.getString('user_decks');
    if (decksJson != null) {
      final List<dynamic> decksList = jsonDecode(decksJson);
      _decks = decksList.map((d) => Deck.fromJson(d)).toList();
    }
    
    // --- NUEVO: Cargar avatar guardado ---
    final savedAvatarId = prefs.getInt('selected_avatar_id');
    if (savedAvatarId != null) {
      _avatarId = savedAvatarId;
    }
    
    _isLoading = false;
    notifyListeners();
  }

  Future<void> _saveProfile() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_profile', jsonEncode(_profile.toJson()));
  }

  Future<void> _saveDecks() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'user_decks', 
      jsonEncode(_decks.map((d) => d.toJson()).toList()),
    );
  }

  // --- NUEVO: Método para cambiar el avatar ---
  Future<void> updateAvatar(int id) async {
    _avatarId = id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('selected_avatar_id', id);
    notifyListeners();
  }
  
  // --- NUEVO: Método para actualizar foto de perfil ---
  Future<void> updateProfileImage(String? imagePath) async {
    _profile.profileImagePath = imagePath;
    await _saveProfile();
    notifyListeners();
  }
  
  // --- NUEVO: Getter para obtener la ruta de la foto ---
  String? get profileImagePath => _profile.profileImagePath;

  // Métodos de perfil existentes
  Future<void> updateProfile({String? name, String? email}) async {
    if (name != null) _profile.name = name;
    if (email != null) _profile.email = email;
    await _saveProfile();
    notifyListeners();
  }

  Future<void> recordAnswer({required bool isCorrect}) async {
    _profile.totalAnswered++;
    if (isCorrect) _profile.totalCorrect++;
    
    // Actualizar racha
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    
    if (_profile.lastActivityDate != null) {
      final lastDate = DateTime(
        _profile.lastActivityDate!.year,
        _profile.lastActivityDate!.month,
        _profile.lastActivityDate!.day,
      );
      
      final difference = today.difference(lastDate).inDays;
      
      if (difference == 1) {
        // Día consecutivo
        _profile.currentStreak++;
      } else if (difference > 1) {
        // Se rompió la racha
        _profile.currentStreak = 1;
      }
      // Si es el mismo día, no cambiamos la racha
    } else {
      _profile.currentStreak = 1;
    }
    
    if (_profile.currentStreak > _profile.bestStreak) {
      _profile.bestStreak = _profile.currentStreak;
    }
    
    _profile.lastActivityDate = now;
    
    await _saveProfile();
    notifyListeners();
  }

  // Métodos de mazos
  Future<void> createDeck(String name, {String description = ''}) async {
    final deck = Deck(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      description: description,
    );
    _decks.add(deck);
    await _saveDecks();
    notifyListeners();
  }

  Future<void> deleteDeck(String deckId) async {
    _decks.removeWhere((d) => d.id == deckId);
    await _saveDecks();
    notifyListeners();
  }

  Future<void> updateDeck(String deckId, {String? name, String? description}) async {
    final index = _decks.indexWhere((d) => d.id == deckId);
    if (index != -1) {
      _decks[index] = _decks[index].copyWith(
        name: name,
        description: description,
      );
      await _saveDecks();
      notifyListeners();
    }
  }

  Future<void> addQuestionToDeck(String deckId, String questionId) async {
    final index = _decks.indexWhere((d) => d.id == deckId);
    if (index != -1) {
      if (!_decks[index].questionIds.contains(questionId)) {
        final updatedIds = List<String>.from(_decks[index].questionIds)
          ..add(questionId);
        _decks[index] = _decks[index].copyWith(questionIds: updatedIds);
        await _saveDecks();
        notifyListeners();
      }
    }
  }

  Future<void> removeQuestionFromDeck(String deckId, String questionId) async {
    final index = _decks.indexWhere((d) => d.id == deckId);
    if (index != -1) {
      final updatedIds = List<String>.from(_decks[index].questionIds)
        ..remove(questionId);
      _decks[index] = _decks[index].copyWith(questionIds: updatedIds);
      await _saveDecks();
      notifyListeners();
    }
  }

  bool isQuestionInAnyDeck(String questionId) {
    return _decks.any((d) => d.questionIds.contains(questionId));
  }

  List<Deck> getDecksContainingQuestion(String questionId) {
    return _decks.where((d) => d.questionIds.contains(questionId)).toList();
  }

  Deck? getDeckById(String deckId) {
    try {
      return _decks.firstWhere((d) => d.id == deckId);
    } catch (e) {
      return null;
    }
  }

  // Métodos de dificultad
  Future<void> setQuestionDifficulty(String questionId, String difficulty) async {
    if (!_profile.difficultyDeckEnabled) return;
    
    final newDifficulties = Map<String, String>.from(_profile.questionDifficulties);
    newDifficulties[questionId] = difficulty;
    _profile.questionDifficulties = newDifficulties;
    
    // Actualizar mazo de difíciles
    await _updateDifficultyDeck();
    await _saveProfile();
    notifyListeners();
  }

  String? getQuestionDifficulty(String questionId) {
    return _profile.questionDifficulties[questionId];
  }

  Future<void> _updateDifficultyDeck() async {
    const difficultyDeckId = 'difficulty_deck_hard';
    
    // Obtener todas las preguntas marcadas como difíciles
    final hardQuestions = _profile.questionDifficulties.entries
        .where((e) => e.value == 'hard')
        .map((e) => e.key)
        .toList();
    
    // Buscar o crear el mazo de difíciles
    final existingIndex = _decks.indexWhere((d) => d.id == difficultyDeckId);
    
    if (hardQuestions.isEmpty) {
      if (existingIndex != -1) {
        _decks.removeAt(existingIndex);
      }
    } else {
      if (existingIndex != -1) {
        _decks[existingIndex] = _decks[existingIndex].copyWith(
          questionIds: hardQuestions,
        );
      } else {
        _decks.insert(0, Deck(
          id: difficultyDeckId,
          name: '🔴 Preguntas Difíciles',
          description: 'Preguntas marcadas como difíciles',
          questionIds: hardQuestions,
        ));
      }
    }
    await _saveDecks();
  }

  Future<void> toggleDifficultyDeck(bool enabled) async {
    _profile.difficultyDeckEnabled = enabled;
    
    if (!enabled) {
      _decks.removeWhere((d) => d.id == 'difficulty_deck_hard');
      _profile.questionDifficulties = {};
      await _saveDecks();
    }
    
    await _saveProfile();
    notifyListeners();
  }

  bool get isDifficultyDeckEnabled => _profile.difficultyDeckEnabled;

  Future<void> resetAllData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    _profile = UserProfile();
    _decks = [];
    _avatarId = 1; // Reseteamos también el avatar
    notifyListeners();
  }
}