import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/home_store.dart';
import '../l10n/l10n.dart';
import '../model/home.dart';
import 'add_device_page.dart';
import 'common.dart';
import 'device_tile.dart';

/// One room: its devices, and renaming or deleting it.
class RoomPage extends ConsumerWidget {
  const RoomPage({super.key, required this.roomId});
  final String roomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final room = (ref.watch(roomsProvider).value ?? const <Room>[])
        .where((r) => r.id == roomId)
        .firstOrNull;
    // Deleted here or on another phone: nothing left to show.
    if (room == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) Navigator.maybePop(context);
      });
      return const Scaffold();
    }
    final devices = ref
        .watch(currentDevicesProvider)
        .where((d) => d.roomId == roomId)
        .toList();
    final repo = ref.read(homeRepositoryProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(room.name),
        actions: [
          IconButton(
            tooltip: l.renameRoom,
            icon: const Icon(Icons.edit_outlined),
            onPressed: () async {
              final name = await askName(
                context,
                title: l.renameRoom,
                label: l.roomName,
                initial: room.name,
              );
              if (name != null) await repo.saveRoom(room.copyWith(name: name));
            },
          ),
          IconButton(
            tooltip: l.deleteRoom,
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              final ok = await confirm(
                context,
                title: l.deleteRoom,
                body: l.deleteRoomBody(room.name),
                action: l.delete,
                destructive: true,
              );
              if (ok) await repo.deleteRoom(room.id);
            },
          ),
        ],
      ),
      body: devices.isEmpty
          ? EmptyState(
              icon: roomIcon(room.kind),
              title: l.roomEmptyTitle,
              body: l.roomEmptyBody,
              action: FilledButton.tonal(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AddDevicePage(),
                  ),
                ),
                child: Text(l.addDevice),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [DeviceGrid(devices: devices)],
            ),
    );
  }
}

/// Asks for a new room's type and name, and adds it to [homeId].
Future<void> addRoom(BuildContext context, WidgetRef ref, String homeId) async {
  final l = context.l10n;
  final kind = await showModalBottomSheet<RoomKind>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                l.roomType,
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
            for (final kind in RoomKind.values)
              ListTile(
                leading: Icon(roomIcon(kind)),
                title: Text(roomKindName(l, kind)),
                onTap: () => Navigator.pop(ctx, kind),
              ),
          ],
        ),
      ),
    ),
  );
  if (kind == null || !context.mounted) return;
  final name = await askName(
    context,
    title: l.addRoom,
    label: l.roomName,
    initial: kind == RoomKind.other ? '' : roomKindName(l, kind),
  );
  if (name == null) return;
  await ref.read(homeRepositoryProvider).addRoom(homeId, name, kind);
}
