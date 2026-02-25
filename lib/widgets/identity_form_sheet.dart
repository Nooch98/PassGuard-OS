import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../models/identity_model.dart';
import '../services/db_helper.dart';
import '../services/encryption_service.dart';
import '../services/identity_generator_service.dart';

class IdentityFormSheet extends StatefulWidget {
  final Uint8List masterKey;
  final IdentityModel? existingIdentity;
  final VoidCallback onSaved;

  const IdentityFormSheet({
    super.key,
    required this.masterKey,
    this.existingIdentity,
    required this.onSaved,
  });

  @override
  State<IdentityFormSheet> createState() => _IdentityFormSheetState();
}

class _IdentityFormSheetState extends State<IdentityFormSheet> {
  final _formKey = GlobalKey<FormState>();
  
  late TextEditingController _titleController;
  String _selectedType = 'PERSON';
  
  // Personal
  late TextEditingController _fullNameController;
  late TextEditingController _emailController;
  late TextEditingController _phoneController;
  late TextEditingController _dobController;
  
  // Address
  late TextEditingController _address1Controller;
  late TextEditingController _cityController;
  late TextEditingController _stateController;
  late TextEditingController _zipController;
  late TextEditingController _countryController;
  
  // Card
  late TextEditingController _cardNumberController;
  late TextEditingController _cardHolderController;
  late TextEditingController _expirationController;
  late TextEditingController _cvvController;
  String _cardType = 'VISA';
  
  // Document
  late TextEditingController _documentNumberController;
  late TextEditingController _issuingAuthorityController;
  late TextEditingController _issueDateController;
  late TextEditingController _expiryDateController;
  
  // Notes
  late TextEditingController _notesController;

  GeneratorCountry _selectedCountry = GeneratorCountry.usa;

  @override
  void initState() {
    super.initState();
    
    final existing = widget.existingIdentity;
    _selectedType = existing?.type ?? 'PERSON';
    
    _titleController = TextEditingController(text: existing?.title ?? '');
    _fullNameController = TextEditingController(text: existing?.fullName ?? '');
    _emailController = TextEditingController(text: existing?.email ?? '');
    _phoneController = TextEditingController(text: existing?.phone ?? '');
    _dobController = TextEditingController(text: existing?.dateOfBirth ?? '');
    _address1Controller = TextEditingController(text: existing?.address1 ?? '');
    _cityController = TextEditingController(text: existing?.city ?? '');
    _stateController = TextEditingController(text: existing?.state ?? '');
    _zipController = TextEditingController(text: existing?.zipCode ?? '');
    _countryController = TextEditingController(text: existing?.country ?? '');
    _cardNumberController = TextEditingController(
      text: existing?.cardNumber != null 
        ? _decryptField(existing!.cardNumber!) 
        : ''
    );
    _cardHolderController = TextEditingController(text: existing?.cardHolder ?? '');
    _expirationController = TextEditingController(text: existing?.expirationDate ?? '');
    _cvvController = TextEditingController(
      text: existing?.cvv != null 
        ? _decryptField(existing!.cvv!) 
        : ''
    );
    _cardType = existing?.cardType ?? 'VISA';
    _documentNumberController = TextEditingController(
      text: existing?.documentNumber != null 
        ? _decryptField(existing!.documentNumber!) 
        : ''
    );
    _issuingAuthorityController = TextEditingController(text: existing?.issuingAuthority ?? '');
    _issueDateController = TextEditingController(text: existing?.issueDate ?? '');
    _expiryDateController = TextEditingController(text: existing?.expiryDate ?? '');
    _notesController = TextEditingController(
      text: existing?.notes != null 
        ? _decryptField(existing!.notes!) 
        : ''
    );
  }

  String _decryptField(String encrypted) {
    if (encrypted.isEmpty) return "";
    
    try {
      final String masterKeyAsBase64 = base64Encode(widget.masterKey);
      final Uint8List compatibleBytes = Uint8List.fromList(utf8.encode(masterKeyAsBase64));

      return EncryptionService.decrypt(combinedText: encrypted, masterKeyBytes: compatibleBytes);
    } catch (e) {
      return "Error al leer datos"; 
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _fullNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _dobController.dispose();
    _address1Controller.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _zipController.dispose();
    _countryController.dispose();
    _cardNumberController.dispose();
    _cardHolderController.dispose();
    _expirationController.dispose();
    _cvvController.dispose();
    _documentNumberController.dispose();
    _issuingAuthorityController.dispose();
    _issueDateController.dispose();
    _expiryDateController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _showGenerateMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0A0A0E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        side: BorderSide(color: Color(0xFFFF00FF), width: 1),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) => SingleChildScrollView(
            controller: scrollController,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  
                  const Row(
                    children: [
                      Icon(Icons.auto_awesome, color: Color(0xFFFF00FF), size: 20),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'GENERATE FAKE IDENTITY',
                          style: TextStyle(
                            color: Color(0xFFFF00FF),
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'TARGET REGION',
                    style: TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: GeneratorCountry.values.map((country) {
                      bool isSelected = _selectedCountry == country;
                      return GestureDetector(
                        onTap: () {
                          setModalState(() => _selectedCountry = country);
                          setState(() => _selectedCountry = country);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: isSelected ? const Color(0xFFFF00FF).withOpacity(0.2) : Colors.transparent,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: isSelected ? const Color(0xFFFF00FF) : Colors.white10,
                            ),
                          ),
                          child: Text(
                            country.name.toUpperCase(),
                            style: TextStyle(
                              color: isSelected ? Colors.white : Colors.white38,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 8),
                  const Divider(color: Colors.white10, height: 24),

                  _buildCompactGenerateOption(
                    icon: Icons.person,
                    title: 'Personal Info',
                    color: const Color(0xFF00FBFF),
                    onTap: () {
                      Navigator.pop(context);
                      _generatePersonIdentity();
                    },
                  ),
                  const SizedBox(height: 8),
                  _buildCompactGenerateOption(
                    icon: Icons.credit_card,
                    title: 'Credit Card',
                    color: const Color(0xFFFF00FF),
                    onTap: () {
                      Navigator.pop(context);
                      _generateCreditCard();
                    },
                  ),
                  const SizedBox(height: 8),
                  _buildCompactGenerateOption(
                    icon: Icons.badge,
                    title: 'National ID / License',
                    color: const Color(0xFF00FF00),
                    onTap: () {
                      Navigator.pop(context);
                      _generateLicense();
                    },
                  ),
                  const SizedBox(height: 8),
                  _buildCompactGenerateOption(
                    icon: Icons.flight,
                    title: 'Passport',
                    color: const Color(0xFFFFFF00),
                    onTap: () {
                      Navigator.pop(context);
                      _generatePassport();
                    },
                  ),
                  
                  const SizedBox(height: 16),
                  
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.orange.withOpacity(0.3)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.warning_amber, color: Colors.orange, size: 16),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Fake data for privacy testing only. Not for illegal use.',
                            style: TextStyle(color: Colors.orange, fontSize: 9),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompactGenerateOption({
    required IconData icon,
    required String title,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF16161D),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Icon(Icons.arrow_forward_ios, color: color.withOpacity(0.5), size: 14),
          ],
        ),
      ),
    );
  }

  void _generatePersonIdentity() {
    final data = IdentityGeneratorService.generatePersonIdentity(country: _selectedCountry);
    
    setState(() {
      _selectedType = 'PERSON';
      _titleController.text = 'Fake Identity - ${data['firstName']} (${_selectedCountry.name.toUpperCase()})';
      _fullNameController.text = data['fullName']!;
      _emailController.text = data['email']!;
      _phoneController.text = data['phone']!;
      _dobController.text = data['dateOfBirth']!;
      _address1Controller.text = data['address']!;
      _cityController.text = data['city']!;
      _stateController.text = data['state']!;
      _zipController.text = data['zipCode']!;
      _countryController.text = data['country']!;
    });
    
    _showSuccessSnackBar('✨ FAKE_IDENTITY_GENERATED [${_selectedCountry.name.toUpperCase()}]');
  }

  void _generateCreditCard() {
    final data = IdentityGeneratorService.generateCreditCard();
    
    setState(() {
      _selectedType = 'CARD';
      _titleController.text = 'Fake ${data['cardType']} Card';
      _cardNumberController.text = data['cardNumber']!;
      _cardHolderController.text = data['cardHolder']!;
      _expirationController.text = data['expiration']!;
      _cvvController.text = data['cvv']!;
      _cardType = data['cardType']!;
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('💳 FAKE_CARD_GENERATED (Non-functional)'),
        backgroundColor: Color(0xFFFF00FF),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _generateLicense() {
    final data = IdentityGeneratorService.generateLicense(country: _selectedCountry);
    
    setState(() {
      _selectedType = 'LICENSE';
      _titleController.text = 'Fake License - ${_selectedCountry.name.toUpperCase()}';
      _documentNumberController.text = data['documentNumber']!;
      _issuingAuthorityController.text = data['issuingAuthority']!;
      _issueDateController.text = data['issueDate']!;
      _expiryDateController.text = data['expiryDate']!;
    });
    
    _showSuccessSnackBar('🪪 DOCUMENT_GENERATED (${data['issuingAuthority']})');
  }

  void _generatePassport() {
    final data = IdentityGeneratorService.generatePassport(country: _selectedCountry);
    
    setState(() {
      _selectedType = 'PASSPORT';
      _titleController.text = 'Fake Passport - ${_selectedCountry.name.toUpperCase()}';
      _documentNumberController.text = data['documentNumber']!;
      _issuingAuthorityController.text = data['issuingAuthority']!;
      _issueDateController.text = data['issueDate']!;
      _expiryDateController.text = data['expiryDate']!;
    });
    
    _showSuccessSnackBar('🛂 PASSPORT_GENERATED [${_selectedCountry.name.toUpperCase()}]');
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFFFF00FF),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      widget.existingIdentity == null 
                        ? '> NEW_IDENTITY' 
                        : '> EDIT_IDENTITY',
                      style: const TextStyle(
                        color: Color(0xFF00FBFF),
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  if (widget.existingIdentity == null)
                    IconButton(
                      icon: const Icon(Icons.auto_awesome, color: Color(0xFFFF00FF)),
                      tooltip: "GENERATE_FAKE_IDENTITY",
                      onPressed: _showGenerateMenu,
                    ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(color: Colors.white10),
              const SizedBox(height: 16),

              TextFormField(
                controller: _titleController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Title *',
                  hintText: 'e.g., Personal Info, Visa Card',
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Title is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              const Text(
                'TYPE',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  _buildTypeChip('PERSON', Icons.person, 'Personal'),
                  _buildTypeChip('CARD', Icons.credit_card, 'Card'),
                  _buildTypeChip('LICENSE', Icons.badge, 'License'),
                  _buildTypeChip('PASSPORT', Icons.flight, 'Passport'),
                  _buildTypeChip('OTHER', Icons.folder, 'Other'),
                ],
              ),
              const SizedBox(height: 24),

              if (_selectedType == 'PERSON') ..._buildPersonFields(),
              if (_selectedType == 'CARD') ..._buildCardFields(),
              if (_selectedType == 'LICENSE' || _selectedType == 'PASSPORT') 
                ..._buildDocumentFields(),
              
              const SizedBox(height: 16),
              TextFormField(
                controller: _notesController,
                style: const TextStyle(color: Colors.white),
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                ),
              ),

              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00FBFF),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onPressed: _saveIdentity,
                  child: Text(
                    widget.existingIdentity == null ? 'CREATE' : 'UPDATE',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTypeChip(String type, IconData icon, String label) {
    final isSelected = _selectedType == type;
    return ChoiceChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: isSelected ? Colors.black : Colors.white54),
          const SizedBox(width: 4),
          Text(label),
        ],
      ),
      selected: isSelected,
      onSelected: (selected) {
        setState(() => _selectedType = type);
      },
      selectedColor: const Color(0xFF00FBFF),
      backgroundColor: const Color(0xFF16161D),
      labelStyle: TextStyle(
        color: isSelected ? Colors.black : Colors.white54,
        fontSize: 12,
      ),
    );
  }

  List<Widget> _buildPersonFields() {
    return [
      const Text(
        'PERSONAL INFORMATION',
        style: TextStyle(color: Color(0xFF00FBFF), fontSize: 12, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: _fullNameController,
        style: const TextStyle(color: Colors.white),
        decoration: const InputDecoration(labelText: 'Full Name'),
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: _emailController,
        style: const TextStyle(color: Colors.white),
        decoration: const InputDecoration(labelText: 'Email'),
        keyboardType: TextInputType.emailAddress,
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: _phoneController,
        style: const TextStyle(color: Colors.white),
        decoration: const InputDecoration(labelText: 'Phone'),
        keyboardType: TextInputType.phone,
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: _dobController,
        style: const TextStyle(color: Colors.white),
        decoration: const InputDecoration(labelText: 'Date of Birth'),
      ),
      const SizedBox(height: 20),
      const Text(
        'ADDRESS',
        style: TextStyle(color: Color(0xFF00FBFF), fontSize: 12, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: _address1Controller,
        style: const TextStyle(color: Colors.white),
        decoration: const InputDecoration(labelText: 'Address'),
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: TextFormField(
              controller: _cityController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'City'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextFormField(
              controller: _stateController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'State'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: TextFormField(
              controller: _zipController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'ZIP Code'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextFormField(
              controller: _countryController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'Country'),
            ),
          ),
        ],
      ),
    ];
  }

  List<Widget> _buildCardFields() {
    return [
      const Text(
        'CARD INFORMATION',
        style: TextStyle(color: Color(0xFF00FBFF), fontSize: 12, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: _cardNumberController,
        style: const TextStyle(color: Colors.white),
        decoration: const InputDecoration(
          labelText: 'Card Number *',
          hintText: '1234 5678 9012 3456',
        ),
        keyboardType: TextInputType.number,
        validator: (value) {
          if (value == null || value.isEmpty) {
            return 'Card number is required';
          }
          return null;
        },
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: _cardHolderController,
        style: const TextStyle(color: Colors.white),
        decoration: const InputDecoration(labelText: 'Card Holder'),
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            flex: 2,
            child: TextFormField(
              controller: _expirationController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Expiration',
                hintText: 'MM/YY',
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextFormField(
              controller: _cvvController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'CVV'),
              keyboardType: TextInputType.number,
              obscureText: true,
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        value: _cardType,
        style: const TextStyle(color: Colors.white),
        dropdownColor: const Color(0xFF16161D),
        decoration: const InputDecoration(labelText: 'Card Type'),
        items: ['VISA', 'MASTERCARD', 'AMEX', 'DISCOVER', 'OTHER']
            .map((type) => DropdownMenuItem(value: type, child: Text(type)))
            .toList(),
        onChanged: (value) {
          if (value != null) setState(() => _cardType = value);
        },
      ),
    ];
  }

  List<Widget> _buildDocumentFields() {
    return [
      const Text(
        'DOCUMENT INFORMATION',
        style: TextStyle(color: Color(0xFF00FBFF), fontSize: 12, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: _documentNumberController,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: '${_selectedType == 'PASSPORT' ? 'Passport' : 'License'} Number *',
        ),
        validator: (value) {
          if (value == null || value.isEmpty) {
            return 'Document number is required';
          }
          return null;
        },
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: _issuingAuthorityController,
        style: const TextStyle(color: Colors.white),
        decoration: const InputDecoration(labelText: 'Issuing Authority'),
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: TextFormField(
              controller: _issueDateController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Issue Date',
                hintText: 'YYYY-MM-DD',
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextFormField(
              controller: _expiryDateController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Expiry Date',
                hintText: 'YYYY-MM-DD',
              ),
            ),
          ),
        ],
      ),
    ];
  }

  Future<void> _saveIdentity() async {
    if (!_formKey.currentState!.validate()) return;

    final String masterKeyString = base64Encode(widget.masterKey);

    String? encryptedCardNumber;
    String? encryptedCVV;
    String? encryptedDocNumber;
    String? encryptedNotes;

    if (_cardNumberController.text.isNotEmpty) {
      encryptedCardNumber = EncryptionService.encrypt(
        _cardNumberController.text,
        masterKeyString,
      );
    }

    if (_cvvController.text.isNotEmpty) {
      encryptedCVV = EncryptionService.encrypt(
        _cvvController.text,
        masterKeyString,
      );
    }

    if (_documentNumberController.text.isNotEmpty) {
      encryptedDocNumber = EncryptionService.encrypt(
        _documentNumberController.text,
        masterKeyString,
      );
    }

    if (_notesController.text.isNotEmpty) {
      encryptedNotes = EncryptionService.encrypt(
        _notesController.text,
        masterKeyString,
      );
    }

    final identity = IdentityModel(
      id: widget.existingIdentity?.id,
      title: _titleController.text,
      type: _selectedType,
      fullName: _fullNameController.text.isNotEmpty ? _fullNameController.text : null,
      email: _emailController.text.isNotEmpty ? _emailController.text : null,
      phone: _phoneController.text.isNotEmpty ? _phoneController.text : null,
      dateOfBirth: _dobController.text.isNotEmpty ? _dobController.text : null,
      address1: _address1Controller.text.isNotEmpty ? _address1Controller.text : null,
      city: _cityController.text.isNotEmpty ? _cityController.text : null,
      state: _stateController.text.isNotEmpty ? _stateController.text : null,
      zipCode: _zipController.text.isNotEmpty ? _zipController.text : null,
      country: _countryController.text.isNotEmpty ? _countryController.text : null,
      cardNumber: encryptedCardNumber,
      cardHolder: _cardHolderController.text.isNotEmpty ? _cardHolderController.text : null,
      expirationDate: _expirationController.text.isNotEmpty ? _expirationController.text : null,
      cvv: encryptedCVV,
      cardType: _selectedType == 'CARD' ? _cardType : null,
      documentNumber: encryptedDocNumber,
      issuingAuthority: _issuingAuthorityController.text.isNotEmpty ? _issuingAuthorityController.text : null,
      issueDate: _issueDateController.text.isNotEmpty ? _issueDateController.text : null,
      expiryDate: _expiryDateController.text.isNotEmpty ? _expiryDateController.text : null,
      notes: encryptedNotes,
      createdAt: widget.existingIdentity?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final db = await DBHelper.database;

    if (widget.existingIdentity == null) {
      await db.insert('identities', identity.toMap());
    } else {
      await db.update(
        'identities',
        identity.toMap(),
        where: 'id = ?',
        whereArgs: [widget.existingIdentity!.id],
      );
    }

    widget.onSaved();
    
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.existingIdentity == null 
              ? 'IDENTITY_CREATED' 
              : 'IDENTITY_UPDATED'
          ),
          backgroundColor: const Color(0xFF00FBFF),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}
