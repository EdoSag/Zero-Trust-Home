import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';

import '../adapters/device_adapter.dart';
import '../adapters/homeassistant/ha_server.dart';
import '../adapters/matter/matter_fabric.dart';
import '../data/home_store.dart';
import '../model/device.dart';
import 'quick_snapshot.dart';
import 'quick_store.dart';

/// Runs in the background engine that `HomeControlsService.kt` starts when
/// the phone's controls panel opens: the app's own adapters, reading the
/// quick controls' copy instead of the (locked) vault.
@pragma('vm:entry-point')
Future<void> quickMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  final engine = QuickEngine(ProviderContainer(overrides: quickOverrides()));
  const channel = MethodChannel('dev.sagron.zerotrusthome/quick_engine');
  engine.onState = (id, state) => channel.invokeMethod<void>('state', {
    'id': id,
    ...QuickEngine.stateJson(state),
  }).ignore();
  channel.setMethodCallHandler(
    (call) => engine.handle(call.method, call.arguments as Map? ?? const {}),
  );
  await engine.refresh();
  // Tells the service the engine is ready for requests.
  await channel.invokeMethod<void>('ready');
}

/// The copy the background engine works from.
final quickSnapshotProvider =
    NotifierProvider<QuickSnapshotNotifier, QuickSnapshot>(
      QuickSnapshotNotifier.new,
    );

class QuickSnapshotNotifier extends Notifier<QuickSnapshot> {
  @override
  QuickSnapshot build() => const QuickSnapshot();
  void set(QuickSnapshot s) => state = s;
}

/// The app's providers, fed from [quickSnapshotProvider].
List<Override> quickOverrides() => [
  homeRepositoryProvider.overrideWith(SnapshotRepository.new),
  homesProvider.overrideWith(
    (ref) => Stream.value(ref.watch(quickSnapshotProvider).homes),
  ),
  roomsProvider.overrideWith(
    (ref) => Stream.value(ref.watch(quickSnapshotProvider).rooms),
  ),
  devicesProvider.overrideWith(
    (ref) => Stream.value(ref.watch(quickSnapshotProvider).devices),
  ),
  scenesProvider.overrideWith(
    (ref) => Stream.value(ref.watch(quickSnapshotProvider).scenes),
  ),
];

/// Reads Home Assistant servers and Matter keys from the copy. Nothing is
/// saved from the background: the app saves when it next opens.
class SnapshotRepository extends HomeRepository {
  SnapshotRepository(super.ref) : _ref = ref;
  final Ref _ref;

  QuickSnapshot get _snapshot => _ref.read(quickSnapshotProvider);

  @override
  Future<HaServer?> loadHaServer(String homeId) async =>
      _snapshot.haServers.where((s) => s.homeId == homeId).firstOrNull;

  @override
  Future<MatterFabric?> loadFabric(String homeId) async =>
      _snapshot.fabrics.where((f) => f.homeId == homeId).firstOrNull;

  @override
  Future<MatterFabric> fabricFor(String homeId) async {
    final fabric = await loadFabric(homeId);
    if (fabric == null || !fabric.isUsable) {
      throw const MatterFabricNeedsSync();
    }
    return fabric;
  }

  @override
  Future<void> saveDevice(HomeDevice d) async {}
}

/// Answers the controls service: device states, commands and scenes.
class QuickEngine {
  QuickEngine(
    this.container, {
    this.wait = const Duration(seconds: 10),
    this.firstState = const Duration(seconds: 4),
  }) {
    // Kept loaded: scenes look devices up without waiting.
    container.listen(devicesProvider, (_, _) {});
  }

  final ProviderContainer container;

  /// How long a command may take.
  final Duration wait;

  /// How long to wait for a device's first reading.
  final Duration firstState;

  /// Called with each new state of a watched device.
  void Function(String id, DeviceState? state)? onState;

  final _watching = <String, ProviderSubscription<AsyncValue<DeviceState?>>>{};

  Future<void> refresh() async {
    final text = await container.read(quickVaultProvider).load();
    container
        .read(quickSnapshotProvider.notifier)
        .set(QuickSnapshot.decode(text));
    // The new list is in before anything is asked of it.
    await container.read(devicesProvider.future);
  }

  static Map<String, Object?> stateJson(DeviceState? state) => {
    'reachable': state?.reachable ?? false,
    'values': {
      for (final MapEntry(:key, :value) in (state?.values ?? const {}).entries)
        key.name: value,
    },
  };

  HomeDevice? _device(Object? id) => container
      .read(quickSnapshotProvider)
      .devices
      .where((d) => d.id == id)
      .firstOrNull;

  Future<Object?> handle(String method, Map<dynamic, dynamic> args) async {
    switch (method) {
      case 'refresh':
        await refresh();
        return null;
      case 'states':
        final ids = [for (final id in args['ids'] as List) id as String];
        final states = await Future.wait(ids.map(_first));
        return {for (final (i, id) in ids.indexed) id: stateJson(states[i])};
      case 'watch':
        for (final id in args['ids'] as List) {
          _watch(id as String);
        }
        return null;
      case 'unwatch':
        for (final s in _watching.values) {
          s.close();
        }
        _watching.clear();
        return null;
      case 'send':
        final device = _device(args['id']);
        final capability = Capability.parse(args['capability']);
        final value = args['value'];
        if (device == null ||
            capability == null ||
            !capability.writable ||
            (value is! bool && value is! num)) {
          return false;
        }
        // Unlocking a door is a person's tap in the panel, which Android
        // allows only once the phone itself is unlocked.
        try {
          await container
              .read(deviceControlProvider)
              .send(device, DeviceCommand(capability, value as Object))
              .timeout(wait);
          return true;
        } on Object {
          return false;
        }
      case 'scene':
        final scene = container
            .read(quickSnapshotProvider)
            .scenes
            .where((s) => s.id == args['id'])
            .firstOrNull;
        if (scene == null) return null;
        final failed = await container
            .read(deviceControlProvider)
            .runScene(scene, wait: wait);
        return [for (final d in failed) d.name];
    }
    throw MissingPluginException(method);
  }

  Future<DeviceState?> _first(String id) async {
    final done = Completer<DeviceState?>();
    final sub = container.listen(deviceStateProvider(id), (_, next) {
      if (next.hasValue && !done.isCompleted) done.complete(next.value);
    }, fireImmediately: true);
    try {
      return await done.future.timeout(firstState, onTimeout: () => null);
    } finally {
      sub.close();
    }
  }

  void _watch(String id) {
    if (_watching.containsKey(id)) return;
    _watching[id] = container.listen(deviceStateProvider(id), (_, next) {
      if (next.hasValue) onState?.call(id, next.value);
    }, fireImmediately: true);
  }
}
