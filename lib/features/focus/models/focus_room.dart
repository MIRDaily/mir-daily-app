class FocusRoom {
  final String id;
  final String name;
  final String creatorId;
  final DateTime startTime;
  final Duration duration;
  final List<FocusUser> participants;
  final bool isMusicPlaying;
  final String? musicUrl;

  FocusRoom({
    required this.id,
    required this.name,
    required this.creatorId,
    required this.startTime,
    required this.duration,
    required this.participants,
    this.isMusicPlaying = true,
    this.musicUrl,
  });

  DateTime get endTime => startTime.add(duration);
  
  Duration get remainingTime {
    final now = DateTime.now();
    final remaining = endTime.difference(now);
    return remaining.isNegative ? Duration.zero : remaining;
  }

  bool get isActive {
    final now = DateTime.now();
    return now.isAfter(startTime) && now.isBefore(endTime);
  }

  int get participantCount => participants.length;

  FocusRoom copyWith({
    String? id,
    String? name,
    String? creatorId,
    DateTime? startTime,
    Duration? duration,
    List<FocusUser>? participants,
    bool? isMusicPlaying,
    String? musicUrl,
  }) {
    return FocusRoom(
      id: id ?? this.id,
      name: name ?? this.name,
      creatorId: creatorId ?? this.creatorId,
      startTime: startTime ?? this.startTime,
      duration: duration ?? this.duration,
      participants: participants ?? this.participants,
      isMusicPlaying: isMusicPlaying ?? this.isMusicPlaying,
      musicUrl: musicUrl ?? this.musicUrl,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'creatorId': creatorId,
      'startTime': startTime.toIso8601String(),
      'duration': duration.inSeconds,
      'participants': participants.map((p) => p.toJson()).toList(),
      'isMusicPlaying': isMusicPlaying,
      'musicUrl': musicUrl,
    };
  }

  factory FocusRoom.fromJson(Map<String, dynamic> json) {
    return FocusRoom(
      id: json['id'],
      name: json['name'],
      creatorId: json['creatorId'],
      startTime: DateTime.parse(json['startTime']),
      duration: Duration(seconds: json['duration']),
      participants: (json['participants'] as List)
          .map((p) => FocusUser.fromJson(p))
          .toList(),
      isMusicPlaying: json['isMusicPlaying'] ?? true,
      musicUrl: json['musicUrl'],
    );
  }
}

class FocusUser {
  final String id;
  final String name;
  final String? avatarUrl;
  final DateTime joinedAt;

  FocusUser({
    required this.id,
    required this.name,
    this.avatarUrl,
    required this.joinedAt,
  });

  FocusUser copyWith({
    String? id,
    String? name,
    String? avatarUrl,
    DateTime? joinedAt,
  }) {
    return FocusUser(
      id: id ?? this.id,
      name: name ?? this.name,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      joinedAt: joinedAt ?? this.joinedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'avatarUrl': avatarUrl,
      'joinedAt': joinedAt.toIso8601String(),
    };
  }

  factory FocusUser.fromJson(Map<String, dynamic> json) {
    return FocusUser(
      id: json['id'],
      name: json['name'],
      avatarUrl: json['avatarUrl'],
      joinedAt: DateTime.parse(json['joinedAt']),
    );
  }
}
