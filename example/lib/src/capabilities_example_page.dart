import 'package:filegate/filegate.dart';
import 'package:flutter/material.dart';

class CapabilitiesExamplePage extends StatelessWidget {
  const CapabilitiesExamplePage({super.key, required this.filegate});

  final Filegate filegate;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Capabilities')),
      body: FutureBuilder<FilegateCapabilities>(
        future: filegate.getCapabilities(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Unable to load capabilities: ${snapshot.error}',
                key: const ValueKey<String>('capabilities-error'),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final capabilities = snapshot.requireData;
          return ListView(
            key: const ValueKey<String>('capabilities-list'),
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              _CapabilityTile(
                label: 'File picking',
                value: capabilities.supportsFilePicking,
              ),
              _CapabilityTile(
                label: 'Directory picking',
                value: capabilities.supportsDirectoryPicking,
              ),
              _CapabilityTile(
                label: 'Mixed selection',
                value: capabilities.supportsMixedPicking,
              ),
              _CapabilityTile(
                label: 'Initial directory',
                value: capabilities.supportsInitialDirectory,
              ),
              _CapabilityTile(
                label: 'Persisted access',
                value: capabilities.supportsPersistedAccess,
              ),
              _CapabilityTile(
                label: 'Native URI read',
                value: capabilities.supportsNativeUriRead,
              ),
              _CapabilityTile(
                label: 'File saving',
                value: capabilities.supportsFileSaving,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CapabilityTile extends StatelessWidget {
  const _CapabilityTile({required this.label, required this.value});

  final String label;
  final bool value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(value ? Icons.check_circle : Icons.cancel),
      title: Text(label),
      trailing: Text(value ? 'Supported' : 'Unavailable'),
    );
  }
}
