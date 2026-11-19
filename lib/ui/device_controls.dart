import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../adapters/device_adapter.dart';
import '../l10n/l10n.dart';
import '../model/device.dart';
import 'common.dart';

/// A number as shown: whole when it is, else one decimal ("21.5").
String formatNumber(num n) {
  final text = n.toStringAsFixed(1);
  return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
}

/// What a device's tile says about it: "On · 12 W", "Locked",
/// "Open 40%", "21.5°C · 45%"...
String deviceSummary(AppL10n l, HomeDevice device, DeviceState state) {
  final v = state.values;
  final parts = <String>[];
  final on = v[Capability.onOff];
  if (on is bool) parts.add(on ? l.stateOn : l.stateOff);
  final locked = v[Capability.locked];
  if (locked is bool) parts.add(locked ? l.stateLocked : l.stateUnlocked);
  final position = v[Capability.position];
  if (position is num) {
    parts.add(
      position <= 0
          ? l.stateClosed
          : position >= 100
          ? l.stateOpen
          : l.stateOpenPercent(position.round()),
    );
  }
  final contact = v[Capability.contact];
  if (contact is bool) parts.add(contact ? l.stateOpen : l.stateClosed);
  final motion = v[Capability.motion];
  if (motion is bool) parts.add(motion ? l.stateMotion : l.stateNoMotion);
  final temperature = v[Capability.temperature];
  if (temperature is num) parts.add(l.degrees(formatNumber(temperature)));
  final target = v[Capability.targetTemperature];
  if (target is num && on != false) {
    parts.add(l.setTo(l.degrees(formatNumber(target))));
  }
  final humidity = v[Capability.humidity];
  if (humidity is num) parts.add(l.percent(humidity.round()));
  final power = v[Capability.power];
  // What it draws, while it draws something.
  if (power is num && power > 0 && on != false) {
    parts.add(l.watts(formatWatts(power)));
  }
  final battery = v[Capability.battery];
  if (battery is num && parts.isEmpty) {
    parts.add(l.batteryLevel(battery.round()));
  }
  return parts.join(' · ');
}

/// The controls and readings of a device, in its details: brightness,
/// speed, position, lock, temperature, and what its sensors read.
class DeviceControls extends ConsumerWidget {
  const DeviceControls({super.key, required this.device});
  final HomeDevice device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final state = ref.watch(deviceStateProvider(device.id)).value;
    if (state == null || !state.reachable) return const SizedBox.shrink();
    final v = state.values;

    Future<void> send(Capability c, Object value) async {
      try {
        await ref
            .read(deviceControlProvider)
            .send(device, DeviceCommand(c, value));
      } on Object {
        if (context.mounted) showSnack(context, l.commandFailed(device.name));
      }
    }

    final children = <Widget>[];
    final on = v[Capability.onOff];
    final brightness = v[Capability.brightness];
    if (device.can(Capability.brightness) && brightness is num && on != false) {
      children.add(
        _SliderRow(
          key: const ValueKey('brightness'),
          icon: Icons.brightness_6_outlined,
          label: l.brightness,
          value: brightness.toDouble(),
          min: 1,
          onDone: (x) => send(Capability.brightness, x.round()),
        ),
      );
    }
    final speed = v[Capability.fanSpeed];
    if (device.can(Capability.fanSpeed) && speed is num && on != false) {
      children.add(
        _SliderRow(
          key: const ValueKey('speed'),
          icon: Icons.air,
          label: l.fanSpeed,
          value: speed.toDouble(),
          min: 1,
          onDone: (x) => send(Capability.fanSpeed, x.round()),
        ),
      );
    }
    final position = v[Capability.position];
    if (device.can(Capability.position) && position is num) {
      children.add(
        _SliderRow(
          key: const ValueKey('position'),
          icon: Icons.blinds_outlined,
          label: l.position,
          value: position.toDouble(),
          min: 0,
          onDone: (x) => send(Capability.position, x.round()),
        ),
      );
      children.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => send(Capability.position, 0),
                  child: Text(l.close),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => send(Capability.position, 100),
                  child: Text(l.open),
                ),
              ),
            ],
          ),
        ),
      );
    }
    final locked = v[Capability.locked];
    if (device.can(Capability.locked) && locked is bool) {
      children.add(
        ListTile(
          leading: Icon(locked ? Icons.lock_outline : Icons.lock_open_outlined),
          title: Text(locked ? l.stateLocked : l.stateUnlocked),
          trailing: FilledButton.tonal(
            // The suite's buttons are full width; not in a row's corner.
            style: FilledButton.styleFrom(minimumSize: const Size(96, 40)),
            onPressed: () async {
              // An open door is the one mistake worth asking about.
              if (locked &&
                  !await confirm(
                    context,
                    title: l.unlockTitle(device.name),
                    body: l.unlockBody,
                    action: l.unlock,
                  )) {
                return;
              }
              await send(Capability.locked, !locked);
            },
            child: Text(locked ? l.unlock : l.lock),
          ),
        ),
      );
    }
    final target = v[Capability.targetTemperature];
    if (device.can(Capability.targetTemperature) && target is num) {
      children.add(
        ListTile(
          leading: const Icon(Icons.thermostat),
          title: Text(l.targetTemperature),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: l.colder,
                icon: const Icon(Icons.remove),
                onPressed: () =>
                    send(Capability.targetTemperature, target - 0.5),
              ),
              Text(
                l.degrees(formatNumber(target)),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              IconButton(
                tooltip: l.warmer,
                icon: const Icon(Icons.add),
                onPressed: () =>
                    send(Capability.targetTemperature, target + 0.5),
              ),
            ],
          ),
        ),
      );
    }

    Widget reading(IconData icon, String title, String value) => ListTile(
      leading: Icon(icon),
      title: Text(title),
      trailing: Text(value, style: Theme.of(context).textTheme.titleMedium),
    );
    final temperature = v[Capability.temperature];
    if (temperature is num) {
      children.add(
        reading(
          Icons.device_thermostat,
          l.temperatureNow,
          l.degrees(formatNumber(temperature)),
        ),
      );
    }
    final humidity = v[Capability.humidity];
    if (humidity is num) {
      children.add(
        reading(
          Icons.water_drop_outlined,
          l.humidity,
          l.percent(humidity.round()),
        ),
      );
    }
    final contact = v[Capability.contact];
    if (contact is bool) {
      children.add(
        reading(
          Icons.sensor_door_outlined,
          l.contact,
          contact ? l.stateOpen : l.stateClosed,
        ),
      );
    }
    final motion = v[Capability.motion];
    if (motion is bool) {
      children.add(
        reading(
          Icons.directions_walk,
          l.motion,
          motion ? l.stateMotion : l.stateNoMotion,
        ),
      );
    }
    final power = v[Capability.power];
    if (power is num) {
      children.add(
        reading(Icons.bolt_outlined, l.powerNow, l.watts(formatWatts(power))),
      );
    }
    final energy = v[Capability.energy];
    if (energy is num) {
      children.add(
        reading(
          Icons.electric_meter_outlined,
          l.energy,
          l.kwh(formatNumber(energy)),
        ),
      );
    }
    final battery = v[Capability.battery];
    if (battery is num) {
      children.add(
        reading(
          Icons.battery_std_outlined,
          l.battery,
          l.percent(battery.round()),
        ),
      );
    }
    return Column(mainAxisSize: MainAxisSize.min, children: children);
  }
}

/// A slider that follows the device, but not while a finger is on it.
class _SliderRow extends StatefulWidget {
  const _SliderRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.min,
    required this.onDone,
  });
  final IconData icon;
  final String label;
  final double value;
  final double min;
  final ValueChanged<double> onDone;

  @override
  State<_SliderRow> createState() => _SliderRowState();
}

class _SliderRowState extends State<_SliderRow> {
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final value = (_dragging ?? widget.value).clamp(widget.min, 100.0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
      child: Row(
        children: [
          Icon(widget.icon),
          const SizedBox(width: 8),
          Expanded(
            child: Slider(
              value: value,
              min: widget.min,
              max: 100,
              label: context.l10n.percent(value.round()),
              divisions: 100 - widget.min.round(),
              semanticFormatterCallback: (x) =>
                  '${widget.label} ${context.l10n.percent(x.round())}',
              onChanged: (x) => setState(() => _dragging = x),
              onChangeEnd: (x) {
                setState(() => _dragging = null);
                widget.onDone(x);
              },
            ),
          ),
          SizedBox(
            width: 48,
            child: Text(
              context.l10n.percent(value.round()),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}
