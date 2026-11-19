import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/home_store.dart';
import '../model/device.dart';
import '../model/scene.dart';
import 'homeassistant/ha_adapter.dart';
import 'homeassistant/ha_providers.dart';
import 'matter/matter_adapter.dart';
import 'matter/matter_providers.dart';
import 'tuya/tuya_adapter.dart';
import 'tuya/tuya_providers.dart';

/// One way of reaching devices: Matter, Home Assistant, a Hue bridge, a
/// brand's local protocol. The rest of the app only knows [HomeDevice],
/// [DeviceState] and [DeviceCommand], so a new brand is one new adapter.
abstract class DeviceAdapter {
  /// Saved on each device (`HomeDevice.adapter`). Never change it.
  String get id;

  /// The device's state now and whenever it changes. Emits
  /// [DeviceState.unreachable] while the device doesn't answer.
  Stream<DeviceState> watch(HomeDevice device);

  /// Throws when the device didn't take the command.
  Future<void> send(HomeDevice device, DeviceCommand command);

  /// The device is being deleted from the app: drop what is kept about it
  /// and, where the device itself has to be told, tell it. [others] are
  /// the remaining devices of this adapter. Never throws.
  Future<void> forget(HomeDevice device, {required List<HomeDevice> others});
}

/// How a device is added. Shown on the "Add a device" page, in this order;
/// one becomes available when an adapter for it is registered.
enum ConnectionKind {
  matter('matter'),
  homeAssistant('homeassistant'),
  hue('hue'),
  tuya('tuya'),
  shelly('shelly'),
  switcher('switcher');

  const ConnectionKind(this.adapterId);
  final String adapterId;
}

/// The adapters this build has, by id. Tests register their own.
final deviceAdaptersProvider = Provider<Map<String, DeviceAdapter>>(
  (ref) => {
    MatterAdapter.adapterId: ref.watch(matterAdapterProvider),
    HomeAssistantAdapter.adapterId: ref.watch(haAdapterProvider),
    TuyaAdapter.adapterId: ref.watch(tuyaAdapterProvider),
  },
);

/// The live state of one device, by id. Null while there is no adapter for
/// it on this phone (a device added by a newer version of the app).
final deviceStateProvider = StreamProvider.autoDispose
    .family<DeviceState?, String>((ref, deviceId) {
      final devices = ref.watch(devicesProvider).value ?? const [];
      final device = devices.where((d) => d.id == deviceId).firstOrNull;
      if (device == null) return Stream.value(null);
      final adapter = ref.watch(deviceAdaptersProvider)[device.adapter];
      if (adapter == null) return Stream.value(null);
      return adapter.watch(device);
    });

final deviceControlProvider = Provider<DeviceControl>(DeviceControl.new);

/// Sends commands to devices through their adapters.
class DeviceControl {
  DeviceControl(this._ref);
  final Ref _ref;

  /// False when this phone has no adapter for the device.
  bool supports(HomeDevice device) =>
      _ref.read(deviceAdaptersProvider).containsKey(device.adapter);

  Future<void> send(HomeDevice device, DeviceCommand command) async {
    final adapter = _ref.read(deviceAdaptersProvider)[device.adapter];
    if (adapter == null) {
      throw StateError('No adapter "${device.adapter}" on this phone');
    }
    await adapter.send(device, command);
  }

  /// Carries out [scene]: every device at once, each one's steps in order
  /// (on before brightness). Returns the devices that didn't take every
  /// step; a device deleted since the scene was made is left out.
  Future<List<HomeDevice>> runScene(
    Scene scene, {
    Duration wait = const Duration(seconds: 15),
  }) async {
    final devices = {
      for (final d in _ref.read(devicesProvider).value ?? const <HomeDevice>[])
        d.id: d,
    };
    final steps = <String, List<SceneAction>>{};
    for (final a in scene.actions) {
      if (devices.containsKey(a.deviceId)) {
        (steps[a.deviceId] ??= []).add(a);
      }
    }
    final failed = <HomeDevice>[];
    await Future.wait([
      for (final MapEntry(key: id, value: actions) in steps.entries)
        () async {
          final device = devices[id]!;
          try {
            for (final a in actions) {
              await send(device, a.command).timeout(wait);
            }
          } on Object {
            failed.add(device);
          }
        }(),
    ]);
    return failed;
  }

  /// Call before a device is deleted (see [DeviceAdapter.forget]).
  Future<void> forget(HomeDevice device) => forgetAll([device]);

  /// Call before several devices are deleted at once, such as a whole
  /// home's. Each is told about only the devices still left, so the last
  /// part of a shared device lets it go. Each one is given [wait] at most:
  /// one unplugged device never keeps the others from being tried.
  Future<void> forgetAll(
    List<HomeDevice> gone, {
    Duration wait = const Duration(seconds: 10),
  }) async {
    final adapters = _ref.read(deviceAdaptersProvider);
    final left = [...?_ref.read(devicesProvider).value];
    for (final device in gone) {
      left.removeWhere((d) => d.id == device.id);
      final adapter = adapters[device.adapter];
      if (adapter == null) continue;
      try {
        await adapter
            .forget(
              device,
              others: [
                for (final d in left)
                  if (d.adapter == device.adapter) d,
              ],
            )
            .timeout(wait);
      } on Object {
        // Deleting from the app never depends on the device answering.
      }
    }
  }
}
