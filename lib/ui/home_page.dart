import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/home_store.dart';
import '../l10n/l10n.dart';
import '../model/device.dart';
import 'add_device_page.dart';
import 'common.dart';
import 'device_tile.dart';
import 'homes_page.dart';
import 'room_page.dart';
import 'settings_page.dart';
import 'setup_home_page.dart';

/// The current home: favourites on top, then each room with its devices.
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  void _open(BuildContext context, Widget page) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final homes = ref.watch(homesProvider);
    final home = ref.watch(currentHomeProvider);
    final settings = IconButton(
      tooltip: l.settings,
      icon: const Icon(Icons.settings_outlined),
      onPressed: () => _open(context, const HomeSettingsPage()),
    );

    if (home == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('ZT Home'), actions: [settings]),
        body: homes.value == null
            ? const Center(child: CircularProgressIndicator())
            : EmptyState(
                icon: Icons.home_outlined,
                title: l.setupTitle,
                body: l.setupBody,
                action: FilledButton(
                  onPressed: () => _open(context, const SetupHomePage()),
                  child: Text(l.setupStart),
                ),
              ),
      );
    }

    final rooms = ref.watch(currentRoomsProvider);
    final devices = ref.watch(currentDevicesProvider);
    final favourites = devices.where((d) => d.favourite).toList();
    final roomIds = {for (final r in rooms) r.id};
    final unplaced = devices.where((d) => !roomIds.contains(d.roomId)).toList();

    return Scaffold(
      appBar: AppBar(
        // The home's name; a tap lists the homes to switch or manage.
        title: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _open(context, const HomesPage()),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(home.name, overflow: TextOverflow.ellipsis),
                ),
                const Icon(Icons.arrow_drop_down),
              ],
            ),
          ),
        ),
        actions: [settings],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: Text(l.add),
        onPressed: () => _showAdd(context, ref, home.id),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          if (devices.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.noDevicesTitle,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(l.noDevicesBody),
                    const SizedBox(height: 12),
                    FilledButton.tonal(
                      onPressed: () => _open(context, const AddDevicePage()),
                      child: Text(l.addDevice),
                    ),
                  ],
                ),
              ),
            ),
          if (favourites.isNotEmpty)
            _Section(
              icon: Icons.star_outline,
              title: l.favourites,
              devices: favourites,
            ),
          for (final room in rooms)
            _Section(
              icon: roomIcon(room.kind),
              title: room.name,
              devices: devices.where((d) => d.roomId == room.id).toList(),
              showCount: true,
              onTap: () => _open(context, RoomPage(roomId: room.id)),
            ),
          if (unplaced.isNotEmpty)
            _Section(
              icon: Icons.devices_other_outlined,
              title: l.noRoom,
              devices: unplaced,
            ),
        ],
      ),
    );
  }

  void _showAdd(BuildContext context, WidgetRef ref, String homeId) {
    final l = context.l10n;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.lightbulb_outline),
              title: Text(l.addDevice),
              onTap: () {
                Navigator.pop(ctx);
                _open(context, const AddDevicePage());
              },
            ),
            ListTile(
              leading: const Icon(Icons.meeting_room_outlined),
              title: Text(l.addRoom),
              onTap: () {
                Navigator.pop(ctx);
                addRoom(context, ref, homeId);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// A heading (a room, Favourites) with its device tiles under it.
class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.title,
    required this.devices,
    this.showCount = false,
    this.onTap,
  });
  final IconData icon;
  final String title;
  final List<HomeDevice> devices;
  final bool showCount;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                Icon(icon, size: 20, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: t.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (showCount)
                  Text(
                    l.deviceCount(devices.length),
                    style: t.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                if (onTap != null)
                  Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
        if (devices.isNotEmpty) ...[
          DeviceGrid(devices: devices),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}
