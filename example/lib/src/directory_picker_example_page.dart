import 'package:filegate/filegate.dart';
import 'package:flutter/material.dart';

class DirectoryPickerExamplePage extends StatefulWidget {
  const DirectoryPickerExamplePage({super.key, required this.filegate});

  final Filegate filegate;

  @override
  State<DirectoryPickerExamplePage> createState() =>
      _DirectoryPickerExamplePageState();
}

class _DirectoryPickerExamplePageState
    extends State<DirectoryPickerExamplePage> {
  List<PickedEntry>? _entries;
  String _status = 'No directory selected';

  Future<void> _pickDirectory() async {
    setState(() {
      _status = 'Opening picker...';
    });

    try {
      final entries = await widget.filegate.pickDirectoryFiles(
        recursive: true,
        allowedExtensions: const ['txt', 'md', 'json'],
        title: 'Pick a directory',
      );
      if (!mounted) return;

      setState(() {
        _entries = entries;
        _status = entries == null
            ? 'Selection cancelled'
            : '${entries.length} file(s) found';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _entries = null;
        _status = 'Directory pick failed: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Directory')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          FilledButton.icon(
            key: const ValueKey<String>('pick-directory-button'),
            onPressed: _pickDirectory,
            icon: const Icon(Icons.folder_open),
            label: const Text('Pick directory'),
          ),
          const SizedBox(height: 16),
          Text(_status, key: const ValueKey<String>('directory-status')),
          const SizedBox(height: 16),
          for (final entry in _entries ?? const <PickedEntry>[])
            ListTile(
              leading: const Icon(Icons.insert_drive_file),
              title: Text(entry.relativePath ?? entry.name),
              subtitle: Text(_entrySubtitle(entry)),
            ),
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
