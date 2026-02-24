class IdentityModel {
  final int? id;
  final String title;
  final String type;
  
  // Datos personales
  final String? fullName;
  final String? firstName;
  final String? middleName;
  final String? lastName;
  final String? email;
  final String? phone;
  final String? dateOfBirth;
  final String? gender;
  
  // Dirección
  final String? address1;
  final String? address2;
  final String? city;
  final String? state;
  final String? zipCode;
  final String? country;
  
  // Tarjeta de crédito
  final String? cardNumber;
  final String? cardHolder;
  final String? expirationDate;
  final String? cvv;
  final String? cardType;
  
  // Documentos
  final String? documentNumber;
  final String? issuingAuthority;
  final String? issueDate;
  final String? expiryDate;
  
  // Otros
  final String? notes;
  final bool isFavorite;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  IdentityModel({
    this.id,
    required this.title,
    required this.type,
    this.fullName,
    this.firstName,
    this.middleName,
    this.lastName,
    this.email,
    this.phone,
    this.dateOfBirth,
    this.gender,
    this.address1,
    this.address2,
    this.city,
    this.state,
    this.zipCode,
    this.country,
    this.cardNumber,
    this.cardHolder,
    this.expirationDate,
    this.cvv,
    this.cardType,
    this.documentNumber,
    this.issuingAuthority,
    this.issueDate,
    this.expiryDate,
    this.notes,
    this.isFavorite = false,
    this.createdAt,
    this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'type': type,
      'full_name': fullName,
      'first_name': firstName,
      'middle_name': middleName,
      'last_name': lastName,
      'email': email,
      'phone': phone,
      'date_of_birth': dateOfBirth,
      'gender': gender,
      'address1': address1,
      'address2': address2,
      'city': city,
      'state': state,
      'zip_code': zipCode,
      'country': country,
      'card_number': cardNumber,
      'card_holder': cardHolder,
      'expiration_date': expirationDate,
      'cvv': cvv,
      'card_type': cardType,
      'document_number': documentNumber,
      'issuing_authority': issuingAuthority,
      'issue_date': issueDate,
      'expiry_date': expiryDate,
      'notes': notes,
      'is_favorite': isFavorite ? 1 : 0,
      'created_at': (createdAt ?? DateTime.now()).toIso8601String(),
      'updated_at': (updatedAt ?? DateTime.now()).toIso8601String(),
    };
  }

  factory IdentityModel.fromMap(Map<String, dynamic> map) {
    return IdentityModel(
      id: map['id'],
      title: map['title'] ?? '',
      type: map['type'] ?? 'PERSON',
      fullName: map['full_name'],
      firstName: map['first_name'],
      middleName: map['middle_name'],
      lastName: map['last_name'],
      email: map['email'],
      phone: map['phone'],
      dateOfBirth: map['date_of_birth'],
      gender: map['gender'],
      address1: map['address1'],
      address2: map['address2'],
      city: map['city'],
      state: map['state'],
      zipCode: map['zip_code'],
      country: map['country'],
      cardNumber: map['card_number'],
      cardHolder: map['card_holder'],
      expirationDate: map['expiration_date'],
      cvv: map['cvv'],
      cardType: map['card_type'],
      documentNumber: map['document_number'],
      issuingAuthority: map['issuing_authority'],
      issueDate: map['issue_date'],
      expiryDate: map['expiry_date'],
      notes: map['notes'],
      isFavorite: map['is_favorite'] == 1,
      createdAt: map['created_at'] != null 
        ? DateTime.parse(map['created_at']) 
        : null,
      updatedAt: map['updated_at'] != null 
        ? DateTime.parse(map['updated_at']) 
        : null,
    );
  }

  IdentityModel copyWith({
    int? id,
    String? title,
    String? type,
    String? fullName,
    String? firstName,
    String? middleName,
    String? lastName,
    String? email,
    String? phone,
    String? dateOfBirth,
    String? gender,
    String? address1,
    String? address2,
    String? city,
    String? state,
    String? zipCode,
    String? country,
    String? cardNumber,
    String? cardHolder,
    String? expirationDate,
    String? cvv,
    String? cardType,
    String? documentNumber,
    String? issuingAuthority,
    String? issueDate,
    String? expiryDate,
    String? notes,
    bool? isFavorite,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return IdentityModel(
      id: id ?? this.id,
      title: title ?? this.title,
      type: type ?? this.type,
      fullName: fullName ?? this.fullName,
      firstName: firstName ?? this.firstName,
      middleName: middleName ?? this.middleName,
      lastName: lastName ?? this.lastName,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      gender: gender ?? this.gender,
      address1: address1 ?? this.address1,
      address2: address2 ?? this.address2,
      city: city ?? this.city,
      state: state ?? this.state,
      zipCode: zipCode ?? this.zipCode,
      country: country ?? this.country,
      cardNumber: cardNumber ?? this.cardNumber,
      cardHolder: cardHolder ?? this.cardHolder,
      expirationDate: expirationDate ?? this.expirationDate,
      cvv: cvv ?? this.cvv,
      cardType: cardType ?? this.cardType,
      documentNumber: documentNumber ?? this.documentNumber,
      issuingAuthority: issuingAuthority ?? this.issuingAuthority,
      issueDate: issueDate ?? this.issueDate,
      expiryDate: expiryDate ?? this.expiryDate,
      notes: notes ?? this.notes,
      isFavorite: isFavorite ?? this.isFavorite,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}