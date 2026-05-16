import 'package:filegate/filegate.dart';
import 'package:flutter/material.dart';

class FilePickerExamplePage extends StatefulWidget {
  const FilePickerExamplePage({super.key, required this.filegate});

  final Filegate filegate;

  @override
  State<FilePickerExamplePage> createState() => _FilePickerExamplePageState();
}

class _FilePickerExamplePageState extends State<FilePickerExamplePage> {
  List<PickedEntry>? _entries;
  String _status = 'No files selected';

  Future<void> _pickFiles() async {
    setState(() {
      _status = 'Opening picker...';
    });

    try {
      final entries = await widget.filegate.pickFiles(
        allowMultiple: true,
        allowedExtensions: const ['txt', 'md', 'json'],
        title: 'Pick files',
      );
      if (!mounted) return;

      setState(() {
        _entries = entries;
        _status = entries == null
            ? 'Selection cancelled'
            : '${entries.length} file(s) selected';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _entries = null;
        _status = 'Pick failed: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Files')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          FilledButton.icon(
            key: const ValueKey<String>('pick-files-button'),
            onPressed: _pickFiles,
            icon: const Icon(Icons.upload_file),
            label: const Text('Pick files'),
          ),
          const SizedBox(height: 16),
          Text(_status, key: const ValueKey<String>('files-status')),
          const SizedBox(height: 16),
          for (final entry in _entries ?? const <PickedEntry>[])
            ListTile(
              leading: const Icon(Icons.description),
              title: Text(entry.name),
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
