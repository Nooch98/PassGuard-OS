import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:open_file/open_file.dart';
import 'file_service.dart';
import 'db_helper.dart';

class FileVaultScreen extends StatefulWidget {
  final Uint8List masterKey;
  const FileVaultScreen({super.key, required this.masterKey});

  @override
  State<FileVaultScreen> createState() => _FileVaultScreenState();
}

class _FileVaultScreenState extends State<FileVaultScreen> {
  List<Map<String, dynamic>> _files = [];

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  Future<void> _loadFiles() async {
    try {
      final db = await DBHelper.database;
      final List<Map<String, dynamic>> maps = await db.query('file_vault', orderBy: 'id DESC');

      if (mounted) {
        setState(() {
          _files = List<Map<String, dynamic>>.from(maps);
        });
      }
    } catch (e) {
      debugPrint("DB_FETCH_ERROR: $e");
    }
  }

  void _showFileOptions(Map<String, dynamic> file) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0A0A0E),
      shape: const Border(top: BorderSide(color: Color(0xFFFF00FF), width: 1)),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.file_download, color: Color(0xFF00FBFF)),
              title: const Text("EXPORT_TO_DOWNLOADS", style: TextStyle(color: Colors.white, fontSize: 12)),
              onTap: () async {
                Navigator.pop(context);
                await FileService.exportFile(file['encrypted_path'], widget.masterKey, file['file_name']);
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("FILE_EXPORTED_TO_DOWNLOADS"), backgroundColor: Colors.green)
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_forever, color: Colors.red),
              title: const Text("PERMANENT_WIPE", style: TextStyle(color: Colors.red, fontSize: 12)),
              onTap: () {
                Navigator.pop(context);
                _confirmDelete(file);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(Map<String, dynamic> file) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0A0A0E),
        title: const Text("PERMANENT_WIPE?",
            style: TextStyle(color: Colors.red, fontFamily: 'monospace', fontSize: 14)),
        content: Text("This will physically delete the encrypted buffer of: ${file['file_name']}",
            style: const TextStyle(color: Colors.white70, fontSize: 12)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("ABORT", style: TextStyle(color: Colors.white38))
          ),
          TextButton(
              onPressed: () async {
                final db = await DBHelper.database;
                await db.delete('file_vault', where: 'id = ?', whereArgs: [file['id']]);

                final f = File(file['encrypted_path']);
                if (await f.exists()) {
                  await f.delete();
                }

                if (mounted) {
                  Navigator.pop(context);
                  _loadFiles();
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("NODE_PURGED"), backgroundColor: Colors.red)
                  );
                }
              },
              child: const Text("CONFIRM_WIPE", style: TextStyle(color: Colors.red))
          ),
        ],
      ),
    );
  }

  IconData _getIconForFile(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    if (['jpg', 'jpeg', 'png', 'gif'].contains(ext)) return Icons.image;
    if (['pdf'].contains(ext)) return Icons.picture_as_pdf;
    if (['mp4', 'mov', 'avi'].contains(ext)) return Icons.videocam;
    if (['zip', 'rar', '7z'].contains(ext)) return Icons.folder_zip;
    if (['doc', 'docx', 'txt'].contains(ext)) return Icons.description;
    return Icons.insert_drive_file;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(16.0),
          child: Text("> ENCRYPTED_STORAGE_SUBSYSTEM",
              style: TextStyle(color: Color(0xFFFF00FF), fontSize: 12, fontFamily: 'monospace')),
        ),
        Expanded(
          child: _files.isEmpty
              ? const Center(
            child: Text(
                "> EMPTY_VAULT_DEPOSITS",
                style: TextStyle(color: Colors.white10, fontFamily: 'monospace', fontSize: 12)
            ),
          )
              : RefreshIndicator(
            onRefresh: _loadFiles,
            color: const Color(0xFFFF00FF),
            backgroundColor: const Color(0xFF16161D),
            child: GridView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _files.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 0.8,
              ),
              itemBuilder: (context, index) {
                if (index >= _files.length) return const SizedBox.shrink();

                final file = _files[index];
                return GestureDetector(
                  onLongPress: () => _showFileOptions(file),
                  onTap: () async {
                    File decrypted = await FileService.decryptFile(
                        file['encrypted_path'],
                        widget.masterKey,
                        file['file_name']
                    );

                    await OpenFile.open(decrypted.path);

                    Future.delayed(const Duration(minutes: 2), () async {
                      if (await decrypted.exists()) {
                        await decrypted.delete();
                        debugPrint("SECURE_WIPE: Temporary file purged.");
                      }
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF101015),
                      border: Border.all(color: const Color(0xFFFF00FF).withOpacity(0.2)),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                            _getIconForFile(file['file_name']),
                            color: const Color(0xFFFF00FF),
                            size: 28
                        ),
                        const SizedBox(height: 5),
                        Text(
                          file['file_name'],
                          maxLines: 2,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 9,
                              fontFamily: 'monospace',
                              color: Colors.white70
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          "${(file['file_size'] / 1024).toStringAsFixed(0)}KB",
                          style: const TextStyle(fontSize: 7, color: Colors.white24, fontFamily: 'monospace'),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  void _showDeleteDialog(Map<String, dynamic> file) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0A0A0E),
        title: const Text("DELETE_NODE?", style: TextStyle(color: Colors.red, fontFamily: 'monospace')),
        content: Text("Confirm permanent deletion of ${file['file_name']}?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCEL")),
          TextButton(
              onPressed: () async {
                final db = await DBHelper.database;
                await db.delete('file_vault', where: 'id = ?', whereArgs: [file['id']]);
                final f = File(file['encrypted_path']);
                if (await f.exists()) await f.delete();
                Navigator.pop(context);
                _loadFiles();
              },
              child: const Text("DELETE", style: TextStyle(color: Colors.red))
          ),
        ],
      ),
    );
  }
}
