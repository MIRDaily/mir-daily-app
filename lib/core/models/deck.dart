class Deck {
  final String id;
  String name;
  String description;
  List<String> questionIds;
  DateTime createdAt;
  DateTime updatedAt;

  Deck({
    required this.id,
    required this.name,
    this.description = '',
    this.questionIds = const [],
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  int get questionCount => questionIds.length;

  factory Deck.fromJson(Map<String, dynamic> json) {
    return Deck(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] ?? '',
      questionIds: List<String>.from(json['questionIds'] ?? []),
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt: DateTime.parse(json['updatedAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'questionIds': questionIds,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  Deck copyWith({
    String? name,
    String? description,
    List<String>? questionIds,
  }) {
    return Deck(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      questionIds: questionIds ?? this.questionIds,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}
