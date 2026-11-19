import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../adapters/device_adapter.dart';
import '../data/home_store.dart';
import '../l10n/l10n.dart';
import '../model/device.dart';
import 'common.dart';

/// One device: icon, name and state. A tap turns it on or off (when it can
/// be), a long press opens its details.
class DeviceTile extends ConsumerWidget {
  const DeviceTile({super.key, required this.device});
  final HomeDevice device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final supported = ref.watch(deviceControlProvider).supports(device);
    final state = ref.watch(deviceStateProvider(device.id)).value;
    final reachable = supported && (state?.reachable ?? false);
    final on = reachable && state?.on == true;
    final canToggle =
        reachable && device.can(Capability.onOff) && state?.on != null;

    final String status;
    if (!supported) {
      status = l.stateUnsupported;
    } else if (!reachable) {
      status = l.stateUnreachable;
    } else if (state?.on != null) {
      final onOff = on ? l.stateOn : l.stateOff;
      final power = state?.number(Capability.power);
      // What it draws, while it draws something.
      status = on && power != null && power > 0
          ? l.stateWithPower(onOff, formatWatts(power))
          : onOff;
    } else {
      status = '';
    }

    return Card(
      margin: EdgeInsets.zero,
      color: on ? scheme.primaryContainer : null,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: canToggle
            ? () async {
                try {
                  await ref
                      .read(deviceControlProvider)
                      .send(device, DeviceCommand.turn(!on));
                } on Object {
                  if (context.mounted) {
                    showSnack(context, l.commandFailed(device.name));
                  }
                }
              }
            : () => showDeviceDetails(context, device),
        onLongPress: () => showDeviceDetails(context, device),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(
                deviceIcon(device.type),
                color: on
                    ? scheme.onPrimaryContainer
                    : reachable
                    ? scheme.onSurfaceVariant
                    : scheme.outline,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleSmall?.copyWith(
                        color: on ? scheme.onPrimaryContainer : null,
                      ),
                    ),
                    if (status.isNotEmpty)
                      Text(
                        status,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodySmall?.copyWith(
                          color: on
                              ? scheme.onPrimaryContainer
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Device tiles, two to a row.
class DeviceGrid extends StatelessWidget {
  const DeviceGrid({super.key, required this.devices});
  final List<HomeDevice> devices;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        const gap = 8.0;
        final columns = box.maxWidth >= 600 ? 3 : 2;
        final width = (box.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final d in devices)
              SizedBox(
                width: width,
                height: 68,
                child: DeviceTile(key: ValueKey(d.id), device: d),
              ),
          ],
        );
      },
    );
  }
}

/// Rename, move to a room, favourite or remove a device.
Future<void> showDeviceDetails(BuildContext context, HomeDevice device) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _DeviceDetails(deviceId: device.id),
  );
}

class _DeviceDetails extends ConsumerWidget {
  const _DeviceDetails({required this.deviceId});
  final String deviceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final devices = ref.watch(devicesProvider).value ?? const <HomeDevice>[];
    final device = devices.where((d) => d.id == deviceId).firstOrNull;
    if (device == null) return const SizedBox(height: 48);
    final repo = ref.read(homeRepositoryProvider);
    final power = ref
        .watch(deviceStateProvider(deviceId))
        .value
        ?.number(Capability.power);
    final rooms =
        (ref.watch(roomsProvider).value ?? const [])
            .where((r) => r.homeId == device.homeId)
            .toList()
          ..sort((a, b) => a.order.compareTo(b.order));
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(deviceIcon(device.type)),
              title: Text(
                device.name,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              trailing: IconButton(
                tooltip: l.rename,
                icon: const Icon(Icons.edit_outlined),
                onPressed: () async {
                  final name = await askName(
                    context,
                    title: l.rename,
                    label: l.name,
                    initial: device.name,
                  );
                  if (name != null) {
                    await repo.saveDevice(device.copyWith(name: name));
                  }
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: DropdownButtonFormField<String?>(
                // Rebuilt when the room changes on another phone.
                key: ValueKey(device.roomId),
                initialValue: rooms.any((r) => r.id == device.roomId)
                    ? device.roomId
                    : null,
                decoration: InputDecoration(labelText: l.deviceRoom),
                items: [
                  DropdownMenuItem(value: null, child: Text(l.noRoom)),
                  for (final r in rooms)
                    DropdownMenuItem(value: r.id, child: Text(r.name)),
                ],
                onChanged: (roomId) =>
                    repo.saveDevice(device.copyWith(roomId: roomId)),
              ),
            ),
            if (power != null)
              ListTile(
                leading: const Icon(Icons.bolt_outlined),
                title: Text(l.powerNow),
                trailing: Text(
                  l.watts(formatWatts(power)),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            SwitchListTile(
              secondary: const Icon(Icons.star_outline),
              title: Text(l.deviceFavourite),
              value: device.favourite,
              onChanged: (on) =>
                  repo.saveDevice(device.copyWith(favourite: on)),
            ),
            ListTile(
              leading: Icon(
                Icons.delete_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(l.removeDevice),
              onTap: () async {
                final ok = await confirm(
                  context,
                  title: l.removeDevice,
                  body: l.removeDeviceBody(device.name),
                  action: l.removeDevice,
                  destructive: true,
                );
                if (!ok) return;
                await repo.deleteDevice(device.id);
                if (context.mounted) Navigator.pop(context);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
