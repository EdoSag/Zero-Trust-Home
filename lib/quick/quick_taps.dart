import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../adapters/device_adapter.dart';
import '../data/home_store.dart';
import '../l10n/l10n.dart';
import '../model/device.dart';
import 'quick_store.dart';

/// Carries out a tap from the controls panel, once the app is unlocked: a
/// device switches the other way (a blind opens or closes, a door only
/// locks), a scene runs. Returns what to tell the person, or null when
/// there was no tap or nothing to do.
class QuickTaps {
  QuickTaps(this._ref, {this.firstState = const Duration(seconds: 5)});
  final Ref _ref;

  /// How long to wait for a device's state before switching it.
  final Duration firstState;

  Future<String?> run(AppL10n l) async {
    final tap = await _ref.read(quickVaultProvider).takeTap();
    if (tap == null) return null;
    final control = _ref.read(deviceControlProvider);
    const loading = Duration(seconds: 5);
    final devices = await _ref.read(devicesProvider.future).timeout(loading);
    if (tap.action == 'scene') {
      final scenes = await _ref.read(scenesProvider.future).timeout(loading);
      final scene = scenes.where((s) => s.id == tap.id).firstOrNull;
      if (scene == null) return null;
      final failed = await control.runScene(scene);
      return failed.isEmpty
          ? l.sceneDone(scene.name)
          : l.sceneFailed(
              scene.name,
              [for (final d in failed) d.name].join(', '),
            );
    }
    final device = devices.where((d) => d.id == tap.id).firstOrNull;
    if (device == null) return null;
    final caps = device.capabilities;
    DeviceCommand command;
    if (caps.contains(Capability.locked)) {
      // A tap outside the app never unlocks a door.
      command = const DeviceCommand(Capability.locked, true);
    } else if (caps.contains(Capability.onOff) ||
        caps.contains(Capability.position)) {
      final now = await _state(device.id);
      if (now == null || !now.reachable) return l.quickNoAnswer(device.name);
      command = caps.contains(Capability.onOff)
          ? DeviceCommand.turn(now.values[Capability.onOff] != true)
          : DeviceCommand(
              Capability.position,
              ((now.values[Capability.position] as num?) ?? 0) > 0 ? 0 : 100,
            );
    } else {
      // A sensor: the app opens on it, nothing to switch.
      return null;
    }
    try {
      await control.send(device, command).timeout(const Duration(seconds: 10));
    } on Object {
      return l.quickNoAnswer(device.name);
    }
    return switch ((command.capability, command.value)) {
      (Capability.locked, _) => l.quickLocked(device.name),
      (Capability.position, 0) => l.quickClosed(device.name),
      (Capability.position, _) => l.quickOpened(device.name),
      (_, true) => l.quickTurnedOn(device.name),
      _ => l.quickTurnedOff(device.name),
    };
  }

  /// The device's first reading that reached it. Adapters start out "not
  /// reachable" while they connect, so that alone isn't an answer: only
  /// when nothing better comes in time is it taken as one.
  Future<DeviceState?> _state(String id) async {
    final done = Completer<DeviceState?>();
    DeviceState? last;
    final sub = _ref.listen(deviceStateProvider(id), (_, next) {
      final value = next.value;
      if (value == null) return;
      last = value;
      if (value.reachable && !done.isCompleted) done.complete(value);
    }, fireImmediately: true);
    try {
      return await done.future.timeout(firstState, onTimeout: () => last);
    } finally {
      sub.close();
    }
  }
}

final quickTapsProvider = Provider<QuickTaps>(QuickTaps.new);
