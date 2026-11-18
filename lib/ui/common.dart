import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../model/device.dart';
import '../model/home.dart';

void showSnack(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 4)),
    );
}

Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String body,
  required String action,
  bool destructive = false,
}) async {
  final l = context.l10n;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l.cancel),
        ),
        TextButton(
          style: destructive
              ? TextButton.styleFrom(
                  foregroundColor: Theme.of(ctx).colorScheme.error,
                )
              : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(action),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Asks for a name. Null when cancelled or left empty.
Future<String?> askName(
  BuildContext context, {
  required String title,
  required String label,
  String initial = '',
}) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => _NameDialog(title: title, label: label, initial: initial),
  );
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.title,
    required this.label,
    required this.initial,
  });
  final String title;
  final String label;
  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _name = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _done() {
    final name = _name.text.trim();
    Navigator.pop(context, name.isEmpty ? null : name);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _name,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        maxLength: 40,
        decoration: InputDecoration(labelText: widget.label, counterText: ''),
        onSubmitted: (_) => _done(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        TextButton(onPressed: _done, child: Text(l.save)),
      ],
    );
  }
}

/// Shown when a list is empty.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.action,
  });
  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text(title, style: t.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(body, style: t.bodyMedium, textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 24), action!],
          ],
        ),
      ),
    );
  }
}

IconData roomIcon(RoomKind kind) => switch (kind) {
  RoomKind.living => Icons.weekend_outlined,
  RoomKind.kitchen => Icons.kitchen_outlined,
  RoomKind.bedroom => Icons.bed_outlined,
  RoomKind.bathroom => Icons.bathtub_outlined,
  RoomKind.office => Icons.desk_outlined,
  RoomKind.kids => Icons.toys_outlined,
  RoomKind.hallway => Icons.door_front_door_outlined,
  RoomKind.balcony => Icons.balcony_outlined,
  RoomKind.garden => Icons.yard_outlined,
  RoomKind.garage => Icons.garage_outlined,
  RoomKind.other => Icons.meeting_room_outlined,
};

String roomKindName(AppL10n l, RoomKind kind) => switch (kind) {
  RoomKind.living => l.roomLiving,
  RoomKind.kitchen => l.roomKitchen,
  RoomKind.bedroom => l.roomBedroom,
  RoomKind.bathroom => l.roomBathroom,
  RoomKind.office => l.roomOffice,
  RoomKind.kids => l.roomKids,
  RoomKind.hallway => l.roomHallway,
  RoomKind.balcony => l.roomBalcony,
  RoomKind.garden => l.roomGarden,
  RoomKind.garage => l.roomGarage,
  RoomKind.other => l.roomOther,
};

IconData deviceIcon(DeviceType type) => switch (type) {
  DeviceType.light => Icons.lightbulb_outline,
  DeviceType.plug => Icons.power_outlined,
  DeviceType.wallSwitch => Icons.toggle_on_outlined,
  DeviceType.sensor => Icons.sensors,
  DeviceType.lock => Icons.lock_outline,
  DeviceType.thermostat => Icons.thermostat,
  DeviceType.blind => Icons.blinds_outlined,
  DeviceType.fan => Icons.mode_fan_off_outlined,
  DeviceType.camera => Icons.videocam_outlined,
  DeviceType.other => Icons.devices_other_outlined,
};
