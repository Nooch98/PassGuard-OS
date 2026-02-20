class PasswordModel {
  final int? id;
  final String platform;
  final String username;
  final String password;
  final String? otpSeed;
  final String category;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? lastUsed;
  final String? notes;
  final bool isFavorite;
  final List<String>? passwordHistory;

  PasswordModel({
    this.id,
    required this.platform,
    required this.username,
    required this.password,
    this.otpSeed,
    this.category = 'PERSONAL',
    this.createdAt,
    this.updatedAt,
    this.lastUsed,
    this.notes,
    this.isFavorite = false,
    this.passwordHistory,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'platform': platform,
      'username': username,
      'password': password,
      'otp_seed': otpSeed,
      'category': category,
      'created_at': (createdAt ?? DateTime.now()).toIso8601String(),
      'updated_at': (updatedAt ?? DateTime.now()).toIso8601String(),
      'last_used': lastUsed?.toIso8601String(),
      'notes': notes,
      'is_favorite': isFavorite ? 1 : 0,
      'password_history': passwordHistory?.join('|||'),
    };
  }

  factory PasswordModel.fromMap(Map<String, dynamic> map) {
    return PasswordModel(
      id: map['id'],
      platform: map['platform'] ?? '',
      username: map['username'] ?? '',
      password: map['password'] ?? '',
      otpSeed: map['otp_seed'],
      category: map['category'] ?? 'PERSONAL',
      createdAt: map['created_at'] != null 
        ? DateTime.parse(map['created_at']) 
        : null,
      updatedAt: map['updated_at'] != null 
        ? DateTime.parse(map['updated_at']) 
        : null,
      lastUsed: map['last_used'] != null 
        ? DateTime.parse(map['last_used']) 
        : null,
      notes: map['notes'],
      isFavorite: map['is_favorite'] == 1,
      passwordHistory: map['password_history'] != null
        ? (map['password_history'] as String).split('|||')
        : null,
    );
  }

  PasswordModel copyWith({
    int? id,
    String? platform,
    String? username,
    String? password,
    String? otpSeed,
    String? category,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastUsed,
    String? notes,
    bool? isFavorite,
    List<String>? passwordHistory,
  }) {
    return PasswordModel(
      id: id ?? this.id,
      platform: platform ?? this.platform,
      username: username ?? this.username,
      password: password ?? this.password,
      otpSeed: otpSeed ?? this.otpSeed,
      category: category ?? this.category,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastUsed: lastUsed ?? this.lastUsed,
      notes: notes ?? this.notes,
      isFavorite: isFavorite ?? this.isFavorite,
      passwordHistory: passwordHistory ?? this.passwordHistory,
    );
  }
}
