import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../adapters/device_adapter.dart';
import '../l10n/l10n.dart';
import 'matter_add_page.dart';
import 'tuya_add_page.dart';

/// The ways a device can be added. One that this version can't do yet is
/// listed, greyed out, as "Coming soon".
class AddDevicePage extends ConsumerWidget {
  const AddDevicePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final adapters = ref.watch(deviceAdaptersProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l.addDevice)),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(l.addDeviceIntro),
          ),
          for (final kind in ConnectionKind.values)
            _ConnectionRow(
              kind: kind,
              available: adapters.containsKey(kind.adapterId),
            ),
        ],
      ),
    );
  }
}

class _ConnectionRow extends StatelessWidget {
  const _ConnectionRow({required this.kind, required this.available});
  final ConnectionKind kind;
  final bool available;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final (IconData icon, String title, String body) = switch (kind) {
      ConnectionKind.matter => (
        Icons.hub_outlined,
        l.connMatter,
        l.connMatterBody,
      ),
      ConnectionKind.homeAssistant => (
        Icons.home_work_outlined,
        l.connHa,
        l.connHaBody,
      ),
      ConnectionKind.hue => (Icons.lightbulb_outline, l.connHue, l.connHueBody),
      ConnectionKind.tuya => (Icons.power_outlined, l.connTuya, l.connTuyaBody),
      ConnectionKind.shelly => (
        Icons.electrical_services_outlined,
        l.connShelly,
        l.connShellyBody,
      ),
      ConnectionKind.switcher => (
        Icons.water_drop_outlined,
        l.connSwitcher,
        l.connSwitcherBody,
      ),
    };
    return ListTile(
      enabled: available,
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(body),
      isThreeLine: true,
      trailing: available
          ? const Icon(Icons.chevron_right)
          : Text(l.comingSoon, style: Theme.of(context).textTheme.labelSmall),
      onTap: switch (kind) {
        ConnectionKind.matter => () => Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => const MatterAddPage())),
        ConnectionKind.tuya => () => Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => const TuyaAddPage())),
        // Their own pages come with their adapters.
        _ => null,
      },
    );
  }
}
