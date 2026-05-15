import 'dart:typed_data';

import 'package:filegate/filegate.dart';
import 'package:flutter/material.dart';

class ReadFileExamplePage extends StatefulWidget {
  const ReadFileExamplePage({super.key, required this.filegate});

  final Filegate filegate;

  @override
  State<ReadFileExamplePage> createState() => _ReadFileExamplePageState();
}

class _ReadFileExamplePageState extends State<ReadFileExamplePage> {
  PickedEntry? _entry;
  int? _size;
  Uint8List? _bytes;
  String _status = 'No file loaded';

  Future<void> _pickAndRead() async {
    setState(() {
      _status = 'Opening picker...';
      _entry = null;
      _size = null;
      _bytes = null;
    });

    try {
      final entries = await widget.filegate.pickFiles(
        allowedExtensions: const ['txt', 'md', 'json'],
        title: 'Pick a file to read',
      );
      if (entries == null || entries.isEmpty) {
        if (!mounted) return;
        setState(() {
          _status = 'Selection cancelled';
        });
        return;
      }

      final entry = entries.first;
      final size = await widget.filegate.getFileSize(entry.path);
      final bytes = await widget.filegate.readAllBytes(
        entry.path,
        maxBytes: 256,
      );
      if (!mounted) return;

      setState(() {
        _entry = entry;
        _size = size;
        _bytes = bytes;
        _status = 'Loaded ${entry.name}';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _status = 'Read failed: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    return Scaffold(
      appBar: AppBar(title: const Text('Read file')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          FilledButton.icon(
            key: const ValueKey<String>('read-file-button'),
            onPressed: _pickAndRead,
            icon: const Icon(Icons.text_snippet),
            label: const Text('Pick and read file'),
          ),
          const SizedBox(height: 16),
          Text(_status, key: const ValueKey<String>('read-status')),
          if (_entry != null) ...[
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.description),
              title: Text(_entry!.name),
              subtitle: Text(_entry!.path),
            ),
            ListTile(
              leading: const Icon(Icons.data_object),
              title: const Text('Size'),
              subtitle: Text(_size == null ? 'Unknown' : '$_size bytes'),
            ),
          ],
          if (bytes != null) ...[
            const SizedBox(height: 16),
            Text(
              _formatBytes(bytes),
              key: const ValueKey<String>('read-preview'),
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
            ),
          ],
        ],
      ),
    );
  }

  String _formatBytes(Uint8List bytes) {
    if (bytes.isEmpty) {
      return '(empty file)';
    }
    return bytes
        .take(32)
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join(' ');
  }
}
