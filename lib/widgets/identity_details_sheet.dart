/*
|--------------------------------------------------------------------------
| PassGuard OS - IdentityDetailsSheet
|--------------------------------------------------------------------------
| Description:
|   Secure bottom sheet used to display decrypted identity information.
|   Supports multiple identity types (PERSON, CARD, LICENSE, PASSPORT)
|   and renders sensitive fields with masking and copy protection logic.
|
| Responsibilities:
|   - Decrypt identity fields in-memory using master key
|   - Render categorized identity data (personal, financial, documents)
|   - Provide optional field masking (e.g. card numbers)
|   - Allow controlled clipboard copy
|   - Display metadata timestamps (created / updated)
|
| Security Notes:
|   - Decryption occurs only at render time (in-memory)
|   - No decrypted values are persisted
|   - Sensitive fields (card number, CVV, document numbers)
|     are visually isolated and optionally masked
|   - Clipboard copy is explicit and user-triggered
|   - Errors during decryption fail safely (DECRYPTION_ERROR)
|
| UI Design:
|   - Cyberpunk neon theme (cyan/pink accents)
|   - Monospace font for secure fields
|   - Mask/unmask toggle for financial data
|   - Optimized for mobile bottom sheet interaction
|
| Important:
|   This widget handles highly sensitive personal data.
|   Any modifications must preserve:
|     - In-memory-only decryption
|     - No background caching
|     - Explicit user-triggered exposure
|--------------------------------------------------------------------------
*/

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/identity_model.dart';
import '../services/encryption_service.dart';

class IdentityDetailsSheet extends StatelessWidget {
  final IdentityModel identity;
  final Uint8List masterKey;

  const IdentityDetailsSheet({
    super.key,
    required this.identity,
    required this.masterKey,
  });

  String _decryptField(String? encrypted) {
    if (encrypted == null || encrypted.isEmpty) return '';

    if (!encrypted.startsWith('v')) return encrypted;

    try {
      return EncryptionService.decrypt(
        combinedText: encrypted, 
        masterKeyBytes: masterKey
      );
    } catch (e) {
      debugPrint("CRYPT_ERROR en IdentityDetails: $e");
      return 'DECRYPTION_ERROR';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Color(0xFF0A0A0E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    '> ${identity.title.toUpperCase()}',
                    style: const TextStyle(
                      color: Color(0xFF00FBFF),
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(color: Colors.white10),
            const SizedBox(height: 16),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _getTypeColor(identity.type).withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _getTypeColor(identity.type).withOpacity(0.3),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _getTypeIcon(identity.type),
                    color: _getTypeColor(identity.type),
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    identity.type,
                    style: TextStyle(
                      color: _getTypeColor(identity.type),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            if (identity.type == 'PERSON') ..._buildPersonDetails(context),
            if (identity.type == 'CARD') ..._buildCardDetails(context),
            if (identity.type == 'LICENSE' || identity.type == 'PASSPORT') 
              ..._buildDocumentDetails(context),

            if (identity.notes != null && identity.notes!.isNotEmpty) ...[
              const SizedBox(height: 24),
              _buildSection('NOTES', context),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF16161D),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white10),
                ),
                child: SelectableText(
                  _decryptField(identity.notes),
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
            ],

            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.02),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  if (identity.createdAt != null)
                    _buildTimestamp('Created', identity.createdAt!),
                  if (identity.updatedAt != null) ...[
                    const SizedBox(height: 8),
                    _buildTimestamp('Updated', identity.updatedAt!),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildPersonDetails(BuildContext context) {
    return [
      if (identity.fullName != null) ...[
        _buildSection('PERSONAL INFORMATION', context),
        const SizedBox(height: 8),
        _buildField('Full Name', _decryptField(identity.fullName), context),
      ],
      if (identity.email != null) 
        _buildField('Email', _decryptField(identity.email), context, canCopy: true),
      if (identity.phone != null) 
        _buildField('Phone', _decryptField(identity.phone), context, canCopy: true),
      if (identity.dateOfBirth != null) 
        _buildField('Date of Birth', _decryptField(identity.dateOfBirth), context),
      
      if (identity.address1 != null) ...[
        const SizedBox(height: 24),
        _buildSection('ADDRESS', context),
        const SizedBox(height: 8),
        _buildField('Address', _decryptField(identity.address1), context),
      ],
      if (identity.city != null) _buildField('City', _decryptField(identity.city), context),
      if (identity.state != null) _buildField('State', _decryptField(identity.state), context),
      if (identity.zipCode != null) _buildField('ZIP Code', _decryptField(identity.zipCode), context),
      if (identity.country != null) _buildField('Country', _decryptField(identity.country), context),
    ];
  }

  List<Widget> _buildCardDetails(BuildContext context) {
    return [
      _buildSection('CARD INFORMATION', context),
      const SizedBox(height: 8),
      
      if (identity.cardNumber != null)
        _buildSecureField('Card Number', _decryptField(identity.cardNumber), context, maskable: true),
      
      if (identity.cardHolder != null)
        _buildField('Card Holder', identity.cardHolder!, context),
      
      if (identity.expirationDate != null)
        _buildField('Expiration', identity.expirationDate!, context),
      
      if (identity.cvv != null)
        _buildSecureField('CVV', _decryptField(identity.cvv), context),
      
      if (identity.cardType != null)
        _buildField('Card Type', identity.cardType!, context),
    ];
  }

  List<Widget> _buildDocumentDetails(BuildContext context) {
    return [
      _buildSection('DOCUMENT INFORMATION', context),
      const SizedBox(height: 8),
      
      if (identity.documentNumber != null)
        _buildSecureField(
          '${identity.type == 'PASSPORT' ? 'Passport' : 'License'} Number',
          _decryptField(identity.documentNumber),
          context,
        ),
      
      if (identity.issuingAuthority != null)
        _buildField('Issuing Authority', identity.issuingAuthority!, context),
      
      if (identity.issueDate != null)
        _buildField('Issue Date', identity.issueDate!, context),
      
      if (identity.expiryDate != null)
        _buildField('Expiry Date', identity.expiryDate!, context),
    ];
  }

  Widget _buildSection(String title, BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        color: Color(0xFF00FBFF),
        fontSize: 12,
        fontWeight: FontWeight.bold,
        letterSpacing: 1,
      ),
    );
  }

  Widget _buildField(String label, String value, BuildContext context, {bool canCopy = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 10,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF16161D),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              children: [
                Expanded(
                  child: SelectableText(
                    value,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                    ),
                  ),
                ),
                if (canCopy)
                  IconButton(
                    icon: const Icon(Icons.copy, color: Color(0xFF00FBFF), size: 16),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: value));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('COPIED_TO_CLIPBOARD'),
                          backgroundColor: Color(0xFF00FBFF),
                          duration: Duration(seconds: 1),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSecureField(String label, String value, BuildContext context, {bool maskable = false}) {
    return _SecureFieldWidget(
      label: label,
      value: value,
      maskable: maskable,
    );
  }

  Widget _buildTimestamp(String label, DateTime date) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white38, fontSize: 11),
        ),
        Text(
          _formatDate(date),
          style: const TextStyle(color: Colors.white54, fontSize: 11),
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  Color _getTypeColor(String type) {
    switch (type) {
      case 'PERSON':
        return const Color(0xFF00FBFF);
      case 'CARD':
        return const Color(0xFFFF00FF);
      case 'LICENSE':
        return const Color(0xFF00FF00);
      case 'PASSPORT':
        return const Color(0xFFFFFF00);
      default:
        return Colors.white54;
    }
  }

  IconData _getTypeIcon(String type) {
    switch (type) {
      case 'PERSON':
        return Icons.person;
      case 'CARD':
        return Icons.credit_card;
      case 'LICENSE':
        return Icons.badge;
      case 'PASSPORT':
        return Icons.flight;
      default:
        return Icons.folder;
    }
  }
}

class _SecureFieldWidget extends StatefulWidget {
  final String label;
  final String value;
  final bool maskable;

  const _SecureFieldWidget({
    required this.label,
    required this.value,
    this.maskable = false,
  });

  @override
  State<_SecureFieldWidget> createState() => _SecureFieldWidgetState();
}

class _SecureFieldWidgetState extends State<_SecureFieldWidget> {
  bool _isVisible = false;

  @override
  Widget build(BuildContext context) {
    String displayValue = widget.value;
    
    if (widget.maskable && !_isVisible && displayValue.length > 4) {
      displayValue = '•' * (displayValue.length - 4) + displayValue.substring(displayValue.length - 4);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.label.toUpperCase(),
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 10,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF16161D),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFFF00FF).withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: SelectableText(
                    displayValue,
                    style: const TextStyle(
                      color: Color(0xFFFF00FF),
                      fontSize: 14,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (widget.maskable)
                  IconButton(
                    icon: Icon(
                      _isVisible ? Icons.visibility_off : Icons.visibility,
                      color: const Color(0xFFFF00FF),
                      size: 16,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () {
                      setState(() => _isVisible = !_isVisible);
                    },
                  ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.copy, color: Color(0xFF00FBFF), size: 16),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: widget.value));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('COPIED_TO_CLIPBOARD'),
                        backgroundColor: Color(0xFF00FBFF),
                        duration: Duration(seconds: 1),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
