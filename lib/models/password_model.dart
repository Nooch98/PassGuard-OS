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

  String get faviconUrl {
    String domain = platform.toLowerCase().trim();
    
    domain = domain.replaceAll('www.', '');
    
    domain = domain.replaceAll(RegExp(r'[^a-z0-9\-\.]'), '');
    
    if (!domain.contains('.')) {
      domain = _detectDomain(domain);
    }
    
    return 'https://www.google.com/s2/favicons?domain=$domain&sz=64';
  }
  
  String _detectDomain(String service) {
    final Map<String, String> knownServices = {
      'google': 'google.com',
      'gmail': 'gmail.com',
      'facebook': 'facebook.com',
      'twitter': 'twitter.com',
      'instagram': 'instagram.com',
      'github': 'github.com',
      'linkedin': 'linkedin.com',
      'netflix': 'netflix.com',
      'amazon': 'amazon.com',
      'microsoft': 'microsoft.com',
      'apple': 'apple.com',
      'spotify': 'spotify.com',
      'discord': 'discord.com',
      'slack': 'slack.com',
      'dropbox': 'dropbox.com',
      'paypal': 'paypal.com',
      'ebay': 'ebay.com',
      'reddit': 'reddit.com',
      'youtube': 'youtube.com',
      'twitch': 'twitch.tv',
      'steam': 'steampowered.com',
      'yahoo': 'yahoo.com',
      'outlook': 'outlook.com',
      'zoom': 'zoom.us',
      'tiktok': 'tiktok.com',
      'whatsapp': 'whatsapp.com',
      'telegram': 'telegram.org',
    };
    
    return knownServices[service] ?? '$service.com';
  }

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
