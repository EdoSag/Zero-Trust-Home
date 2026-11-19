import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/home_store.dart';
import '../model/device.dart';
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

  /// Call before a device is deleted (see [DeviceAdapter.forget]).
  Future<void> forget(HomeDevice device) async {
    final adapter = _ref.read(deviceAdaptersProvider)[device.adapter];
    if (adapter == null) return;
    final devices = _ref.read(devicesProvider).value ?? const <HomeDevice>[];
    try {
      await adapter.forget(
        device,
        others: [
          for (final d in devices)
            if (d.adapter == device.adapter && d.id != device.id) d,
        ],
      );
    } on Object {
      // Deleting from the app never depends on the device answering.
    }
  }
}
