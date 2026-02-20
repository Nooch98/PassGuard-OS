class RecoveryCodeModel {
  final int? id;
  final int accountId;
  final String code;
  final bool isUsed;
  final DateTime? createdAt;

  RecoveryCodeModel({
    this.id,
    required this.accountId,
    required this.code,
    this.isUsed = false,
    this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'account_id': accountId,
      'code': code,
      'is_used': isUsed ? 1 : 0,
      'created_at': (createdAt ?? DateTime.now()).toIso8601String(),
    };
  }

  factory RecoveryCodeModel.fromMap(Map<String, dynamic> map) {
    return RecoveryCodeModel(
      id: map['id'],
      accountId: map['account_id'],
      code: map['code'] ?? '',
      isUsed: map['is_used'] == 1,
      createdAt: map['created_at'] != null 
        ? DateTime.parse(map['created_at']) 
        : null,
    );
  }

  RecoveryCodeModel copyWith({
    int? id,
    int? accountId,
    String? code,
    bool? isUsed,
    DateTime? createdAt,
  }) {
    return RecoveryCodeModel(
      id: id ?? this.id,
      accountId: accountId ?? this.accountId,
      code: code ?? this.code,
      isUsed: isUsed ?? this.isUsed,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
