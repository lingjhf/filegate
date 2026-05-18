import 'dart:typed_data';

import 'package:filegate/filegate.dart';
import 'package:flutter/material.dart';

class SaveFileExamplePage extends StatefulWidget {
  const SaveFileExamplePage({super.key, required this.filegate});

  final Filegate filegate;

  @override
  State<SaveFileExamplePage> createState() => _SaveFileExamplePageState();
}

class _SaveFileExamplePageState extends State<SaveFileExamplePage> {
  PickedEntry? _entry;
  String _status = 'No file saved';

  Future<void> _saveFile() async {
    setState(() {
      _entry = null;
      _status = 'Opening save dialog...';
    });

    try {
      final entry = await widget.filegate.saveFile(
        Uint8List.fromList('filegate export\n'.codeUnits),
        suggestedName: 'filegate-export.txt',
        allowedExtensions: const ['txt'],
        title: 'Save export',
        mimeType: 'text/plain',
      );
      if (!mounted) return;

      setState(() {
        _entry = entry;
        _status = entry == null ? 'Save cancelled' : 'Saved ${entry.name}';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _entry = null;
        _status = 'Save failed: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final entry = _entry;
    return Scaffold(
      appBar: AppBar(title: const Text('Save file')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          FilledButton.icon(
            key: const ValueKey<String>('save-file-button'),
            onPressed: _saveFile,
            icon: const Icon(Icons.save_alt),
            label: const Text('Save sample file'),
          ),
          const SizedBox(height: 16),
          Text(_status, key: const ValueKey<String>('save-status')),
          if (entry != null) ...[
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.description),
              title: Text(entry.name),
              subtitle: Text(_entrySubtitle(entry)),
            ),
          ],
        ],
      ),
    );
  }
}

String _entrySubtitle(PickedEntry entry) {
  final parts = <String>[entry.path];
  if (entry.size != null) {
    parts.add('${entry.size} bytes');
  }
  if (entry.mimeType != null) {
    parts.add(entry.mimeType!);
  }
  return parts.join(' | ');
}
