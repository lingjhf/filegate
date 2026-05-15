import 'package:filegate/filegate.dart';
import 'package:flutter/material.dart';

import 'src/capabilities_example_page.dart';
import 'src/directory_picker_example_page.dart';
import 'src/file_picker_example_page.dart';
import 'src/read_file_example_page.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.filegate = const Filegate()});

  final Filegate filegate;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(home: _ExampleListPage(filegate: filegate));
  }
}

class _ExampleListPage extends StatelessWidget {
  const _ExampleListPage({required this.filegate});

  final Filegate filegate;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('filegate example')),
      body: ListView(
        children: <Widget>[
          ListTile(
            key: const ValueKey<String>('capabilities-example-tile'),
            title: const Text('Capabilities'),
            subtitle: const Text('Inspect supported platform features'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => CapabilitiesExamplePage(filegate: filegate),
                ),
              );
            },
          ),
          ListTile(
            key: const ValueKey<String>('files-example-tile'),
            title: const Text('Files'),
            subtitle: const Text('Pick one or more files'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => FilePickerExamplePage(filegate: filegate),
                ),
              );
            },
          ),
          ListTile(
            key: const ValueKey<String>('directory-example-tile'),
            title: const Text('Directory'),
            subtitle: const Text('Pick a directory and enumerate files'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      DirectoryPickerExamplePage(filegate: filegate),
                ),
              );
            },
          ),
          ListTile(
            key: const ValueKey<String>('read-example-tile'),
            title: const Text('Read file'),
            subtitle: const Text('Pick a file and preview its bytes'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ReadFileExamplePage(filegate: filegate),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
