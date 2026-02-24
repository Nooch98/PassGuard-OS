import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:passguard/widgets/identity_details_sheet.dart';
import 'package:passguard/widgets/identity_form_sheet.dart';
import '../models/identity_model.dart';
import '../services/db_helper.dart';
import '../services/encryption_service.dart';

class IdentitiesVaultScreen extends StatefulWidget {
  final Uint8List masterKey;

  const IdentitiesVaultScreen({super.key, required this.masterKey});

  @override
  State<IdentitiesVaultScreen> createState() => IdentitiesVaultScreenState();
}

// Nota: He quitado el "_" a la clase State para que sea accesible vía GlobalKey
class IdentitiesVaultScreenState extends State<IdentitiesVaultScreen> {
  List<IdentityModel> _identities = [];
  String _searchQuery = '';
  String _filterType = 'ALL';

  @override
  void initState() {
    super.initState();
    _loadIdentities();
  }

  // Método para desencriptar campos rápidos (como el número de tarjeta para el subtítulo)
  String _decryptField(String? encrypted) {
    if (encrypted == null || encrypted.isEmpty) return '';
    try {
      return EncryptionService.decrypt(encrypted, widget.masterKey);
    } catch (e) {
      return '***';
    }
  }

  Future<void> _loadIdentities() async {
    final db = await DBHelper.database;
    final List<Map<String, dynamic>> maps = await db.query('identities', orderBy: 'created_at DESC');
    
    setState(() {
      _identities = maps.map((map) => IdentityModel.fromMap(map)).toList();
    });
  }

  List<IdentityModel> get _filteredIdentities {
    return _identities.where((identity) {
      final matchesSearch = _searchQuery.isEmpty ||
          identity.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          (identity.fullName?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false);
      
      final matchesType = _filterType == 'ALL' || identity.type == _filterType;
      
      return matchesSearch && matchesType;
    }).toList();
  }

  // MÉTODO PÚBLICO: Para ser llamado desde el FAB de la HomePage
  void showIdentityFormExternal({IdentityModel? existingIdentity}) {
    _showIdentityForm(existingIdentity: existingIdentity);
  }

  @override
  Widget build(BuildContext context) {
    // Ya no usamos Scaffold aquí, usamos un Container o Column
    return Column(
      children: [
        // Buscador Estilo Terminal
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            style: const TextStyle(color: Colors.white, fontFamily: 'monospace'),
            decoration: InputDecoration(
              hintText: 'SEARCH_IDENTITIES...',
              hintStyle: const TextStyle(color: Colors.white24),
              prefixIcon: const Icon(Icons.search, color: Color(0xFF00FBFF)),
              filled: true,
              fillColor: const Color(0xFF16161D),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Colors.white10),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFF00FBFF)),
              ),
              suffixIcon: IconButton(
                icon: const Icon(Icons.filter_list, color: Color(0xFF00FBFF)),
                onPressed: () => _showFilterMenu(context),
              ),
            ),
            onChanged: (value) => setState(() => _searchQuery = value),
          ),
        ),

        // Lista de identidades
        Expanded(
          child: _filteredIdentities.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _filteredIdentities.length,
                  itemBuilder: (context, index) {
                    return _buildIdentityCard(_filteredIdentities[index]);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.badge_outlined, size: 64, color: Colors.white10),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isEmpty ? 'NO_IDENTITIES_ENROLLED' : 'NO_MATCHES_FOUND',
            style: const TextStyle(color: Colors.white24, fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }

  void _showFilterMenu(BuildContext context) async {
    final RenderBox button = context.findRenderObject() as RenderBox;
    final RenderBox overlay = Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
    
    await showMenu<String>(
      context: context,
      color: const Color(0xFF16161D),
      position: RelativeRect.fromRect(
        Rect.fromPoints(
          button.localToGlobal(Offset.zero, ancestor: overlay),
          button.localToGlobal(button.size.bottomRight(Offset.zero), ancestor: overlay),
        ),
        Offset.zero & overlay.size,
      ),
      items: [
        const PopupMenuItem(value: 'ALL', child: Text('ALL', style: TextStyle(color: Colors.white))),
        const PopupMenuItem(value: 'PERSON', child: Text('PERSONAL', style: TextStyle(color: Colors.white))),
        const PopupMenuItem(value: 'CARD', child: Text('CARDS', style: TextStyle(color: Colors.white))),
        const PopupMenuItem(value: 'LICENSE', child: Text('LICENSES', style: TextStyle(color: Colors.white))),
        const PopupMenuItem(value: 'PASSPORT', child: Text('PASSPORTS', style: TextStyle(color: Colors.white))),
      ],
    ).then((value) {
      if (value != null) setState(() => _filterType = value);
    });
  }

  Widget _buildIdentityCard(IdentityModel identity) {
    IconData icon;
    Color color;

    switch (identity.type) {
      case 'PERSON': icon = Icons.person; color = const Color(0xFF00FBFF); break;
      case 'CARD': icon = Icons.credit_card; color = const Color(0xFFFF00FF); break;
      case 'LICENSE': icon = Icons.badge; color = const Color(0xFF00FF00); break;
      case 'PASSPORT': icon = Icons.flight; color = const Color(0xFFFFFF00); break;
      default: icon = Icons.folder; color = Colors.white54;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF16161D),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        leading: Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: color.withOpacity(0.05),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.2)),
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        title: Text(
          identity.title.toUpperCase(),
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13, fontFamily: 'monospace'),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              _getIdentitySubtitle(identity),
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
            Text(
              identity.type,
              style: TextStyle(color: color.withOpacity(0.7), fontSize: 9, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        onTap: () => _showIdentityDetails(identity),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: Colors.white24),
          color: const Color(0xFF16161D),
          onSelected: (value) {
            if (value == 'edit') _showIdentityForm(existingIdentity: identity);
            if (value == 'delete') _deleteIdentity(identity);
          },
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'edit', child: Text('EDIT', style: TextStyle(color: Colors.white))),
            const PopupMenuItem(value: 'delete', child: Text('DELETE', style: TextStyle(color: Colors.red))),
          ],
        ),
      ),
    );
  }

  String _getIdentitySubtitle(IdentityModel identity) {
    switch (identity.type) {
      case 'PERSON':
        return identity.fullName ?? identity.email ?? 'ID_UNSET';
      case 'CARD':
        // Desencriptamos para mostrar los últimos 4 dígitos
        final rawCard = _decryptField(identity.cardNumber);
        return rawCard.length > 4 
            ? '•••• ${rawCard.substring(rawCard.length - 4)}' 
            : 'CARD_PROTECTED';
      case 'LICENSE':
      case 'PASSPORT':
        return _decryptField(identity.documentNumber);
      default:
        return 'VIEW_DETAILS';
    }
  }

  void _showIdentityForm({IdentityModel? existingIdentity}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => IdentityFormSheet(
        masterKey: widget.masterKey,
        existingIdentity: existingIdentity,
        onSaved: () => _loadIdentities(),
      ),
    );
  }

  void _showIdentityDetails(IdentityModel identity) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => IdentityDetailsSheet(
        identity: identity,
        masterKey: widget.masterKey,
      ),
    );
  }

  Future<void> _deleteIdentity(IdentityModel identity) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0A0A0E),
        title: const Text('> DELETE_ID?', style: TextStyle(color: Colors.red, fontFamily: 'monospace')),
        content: Text('Erase ${identity.title} permanently?', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('NO')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('YES', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm == true) {
      final db = await DBHelper.database;
      await db.delete('identities', where: 'id = ?', whereArgs: [identity.id]);
      _loadIdentities();
    }
  }
}