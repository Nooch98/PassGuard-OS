/*
|--------------------------------------------------------------------------
| PassGuard OS - PasswordModel (Credential Record Structure)
|--------------------------------------------------------------------------
| Description:
|   Immutable data model representing a stored credential entry inside
|   the PassGuard OS vault.
|
| Core Fields:
|   - platform: Service or website name (e.g., "github.com")
|   - username: Login identifier
|   - password: Encrypted credential (ciphertext, never plaintext at rest)
|   - otpSeed: Encrypted TOTP seed (if 2FA enabled)
|   - otpMeta: Optional metadata for OTP (issuer, digits, period, algorithm)
|
| Additional Metadata:
|   - category: Logical grouping (PERSONAL, WORK, etc.)
|   - notes: Optional user notes (should be encrypted before storage)
|   - isFavorite: Quick-access flag
|   - passwordHistory: Previous encrypted passwords (rotation tracking)
|   - passwordFingerprint: HMAC-based fingerprint used for reuse detection
|   - createdAt / updatedAt / lastUsed timestamps
|
| Security Architecture:
|   - password is expected to be encrypted before persistence.
|   - passwordFingerprint enables reuse detection without exposing plaintext.
|   - otpSeed must be encrypted before storage.
|   - otpMeta contains non-secret OTP configuration data (no shared secret).
|
| Database Mapping:
|   - toMap() serializes model for SQLite storage.
|   - fromMap() reconstructs model from DB row.
|   - Boolean values stored as 1/0 integers.
|   - passwordHistory serialized using custom delimiter "|||".
|   - Dates stored in ISO8601 format.
|
| Favicon Helper:
|   - faviconUrl dynamically generates a Google S2 favicon endpoint.
|   - _detectDomain() maps common service names to proper domains.
|   - Used purely for UI enhancement (no security impact).
|
| Data Classification:
|   HIGH SENSITIVITY:
|     - password
|     - otpSeed
|     - passwordHistory
|
|   MEDIUM SENSITIVITY:
|     - username
|     - notes
|
|   LOW SENSITIVITY:
|     - platform
|     - category
|     - isFavorite
|
| Threat model assumptions:
|   - Vault database is encrypted or OS-sandbox protected.
|   - EncryptionService handles strong authenticated encryption (AES-GCM v4).
|   - Fingerprints use keyed HMAC (pepper derived from master key).
|
| What this model does NOT protect against:
|   - UI layer exposing decrypted passwords
|   - Keyloggers during password entry
|   - Memory scraping while vault is unlocked
|   - Weak master passwords
|
| Design Principles:
|   - Immutable structure
|   - copyWith() for safe updates
|   - Separation of storage, crypto, and UI concerns
|
|--------------------------------------------------------------------------
*/

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
  final bool isTravelSafe;
  final List<String>? passwordHistory;
  final String? passwordFingerprint;
  final String? otpMeta;

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
    this.isTravelSafe = false,
    this.passwordHistory,
    this.passwordFingerprint,
    this.otpMeta,
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
      'password_fp': passwordFingerprint,
      'otp_seed': otpSeed,
      'category': category,
      'created_at': (createdAt ?? DateTime.now()).toIso8601String(),
      'updated_at': (updatedAt ?? DateTime.now()).toIso8601String(),
      'last_used': lastUsed?.toIso8601String(),
      'notes': notes,
      'is_favorite': isFavorite ? 1 : 0,
      'is_travel_safe': isTravelSafe ? 1 : 0,
      'password_history': passwordHistory?.join('|||'),
      'otp_meta': otpMeta,
    };
  }

  factory PasswordModel.fromMap(Map<String, dynamic> map) {
    return PasswordModel(
      id: map['id'],
      platform: map['platform'] ?? '',
      username: map['username'] ?? '',
      password: map['password'] ?? '',
      passwordFingerprint: map['password_fp'],
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
      isTravelSafe: map['is_travel_safe'] == 1,
      passwordHistory: map['password_history'] != null
        ? (map['password_history'] as String).split('|||')
        : null,
      otpMeta: map['otp_meta'],
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
    bool? isTravelSafe,
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
      isTravelSafe: isTravelSafe ?? this.isTravelSafe,
      passwordHistory: passwordHistory ?? this.passwordHistory,
      passwordFingerprint: this.passwordFingerprint,
      otpMeta: this.otpMeta,
    );
  }
}
