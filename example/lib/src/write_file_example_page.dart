import 'dart:typed_data';

import 'package:filegate/filegate.dart';
import 'package:flutter/material.dart';

class WriteFileExamplePage extends StatefulWidget {
  const WriteFileExamplePage({super.key, required this.filegate});

  final Filegate filegate;

  @override
  State<WriteFileExamplePage> createState() => _WriteFileExamplePageState();
}

class _WriteFileExamplePageState extends State<WriteFileExamplePage> {
  PickedEntry? _target;
  String _status = 'No target selected';

  Future<void> _pickTarget() async {
    setState(() {
      _status = 'Opening picker...';
      _target = null;
    });

    try {
      final entries = await widget.filegate.pickFiles(
        allowedExtensions: const ['txt', 'md', 'json'],
        title: 'Pick a file to write',
      );
      if (!mounted) return;
      final target = entries == null || entries.isEmpty ? null : entries.first;
      setState(() {
        _target = target;
        _status = target == null
            ? 'Selection cancelled'
            : 'Selected ${target.name}';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _target = null;
        _status = 'Pick failed: $error';
      });
    }
  }

  Future<void> _write(FilegateWriteMode mode) async {
    final target = _target;
    if (target == null) {
      return;
    }

    setState(() {
      _status = mode == FilegateWriteMode.append
          ? 'Appending to ${target.name}...'
          : 'Replacing ${target.name}...';
    });

    final text = mode == FilegateWriteMode.append
        ? '\nappended by filegate\n'
        : 'replaced by filegate\n';

    try {
      final updated = await widget.filegate.writeFile(
        target.path,
        Uint8List.fromList(text.codeUnits),
        mode: mode,
      );
      if (!mounted) return;
      setState(() {
        _target = updated;
        _status = mode == FilegateWriteMode.append
            ? 'Appended to ${updated.name}'
            : 'Replaced ${updated.name}';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _status = 'Write failed: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final target = _target;
    return Scaffold(
      appBar: AppBar(title: const Text('Write file')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          FilledButton.icon(
            key: const ValueKey<String>('pick-write-target-button'),
            onPressed: _pickTarget,
            icon: const Icon(Icons.upload_file),
            label: const Text('Pick target file'),
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            key: const ValueKey<String>('append-file-button'),
            onPressed: target == null
                ? null
                : () => _write(FilegateWriteMode.append),
            icon: const Icon(Icons.playlist_add),
            label: const Text('Append sample line'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const ValueKey<String>('replace-file-button'),
            onPressed: target == null
                ? null
                : () => _write(FilegateWriteMode.replace),
            icon: const Icon(Icons.edit_document),
            label: const Text('Replace file contents'),
          ),
          const SizedBox(height: 16),
          Text(_status, key: const ValueKey<String>('write-status')),
          if (target != null) ...[
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.description),
              title: Text(target.name),
              subtitle: Text(_entrySubtitle(target)),
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
