import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

import '../adapters/homeassistant/ha_server.dart';
import '../adapters/matter/matter_fabric.dart';
import '../data/home_store.dart';
import 'quick_snapshot.dart';

/// Where the quick controls' copy is kept: a file sealed with a key in the
/// Android Keystore (`QuickVault.kt`). Tests give a fake.
abstract interface class QuickVault {
  Future<void> save(String text);
  Future<String?> load();
  Future<void> clear();
}

class QuickChannelVault implements QuickVault {
  static const _channel = MethodChannel('dev.sagron.zerotrusthome/quick');

  @override
  Future<void> save(String text) =>
      _channel.invokeMethod<void>('save', {'text': text});
  @override
  Future<String?> load() => _channel.invokeMethod<String>('load');
  @override
  Future<void> clear() => _channel.invokeMethod<void>('clear');
}

final quickVaultProvider = Provider<QuickVault>((ref) => QuickChannelVault());

/// Whether devices can be switched from the phone's controls panel without
/// opening the app. On unless the person turns it off.
final quickControlsOnProvider = NotifierProvider<QuickControlsOn, bool>(
  QuickControlsOn.new,
);

class QuickControlsOn extends Notifier<bool> {
  static const _key = 'home.quickControls';

  @override
  bool build() {
    _load();
    return true;
  }

  Future<void> _load() async {
    try {
      final saved = await ref.read(ztPreferencesStoreProvider).read(_key);
      if (saved == 'off') state = false;
    } on Object {
      // On.
    }
  }

  Future<void> set(bool on) async {
    state = on;
    await ref.read(ztPreferencesStoreProvider).write(_key, on ? 'on' : 'off');
  }
}

/// Counts the times the copy was removed (sign-out). A save that began
/// before the latest removal is dropped, so it can't bring the copy back.
final quickClearsProvider = NotifierProvider<QuickClears, int>(QuickClears.new);

class QuickClears extends Notifier<int> {
  @override
  int build() => 0;

  /// Removes the copy, and any save still under way.
  Future<void> clear() {
    state++;
    return ref.read(quickVaultProvider).clear();
  }
}

/// Keeps the quick controls' copy up to date while the app is unlocked,
/// and removes it when they are turned off. Watched by the unlocked app.
final quickSyncProvider = Provider<QuickSync>((ref) {
  final sync = QuickSync(ref);
  ref
    ..listen(homesProvider, (_, _) => sync.changed(), fireImmediately: true)
    ..listen(roomsProvider, (_, _) => sync.changed())
    ..listen(devicesProvider, (_, _) => sync.changed())
    ..listen(scenesProvider, (_, _) => sync.changed())
    ..listen(quickControlsOnProvider, (_, on) {
      // Turned off: removed now, not after a pause.
      if (!on) sync.stop();
      sync.changed();
    })
    ..listen(quickClearsProvider, (_, _) => sync.stop());
  ref.onDispose(sync.dispose);
  return sync;
});

class QuickSync {
  QuickSync(this._ref, {this.wait = const Duration(seconds: 1)});
  final Ref _ref;

  /// Changes coming in a burst (a sync) are saved once.
  final Duration wait;
  Timer? _timer;
  Future<void>? _saving;

  void changed() {
    _timer?.cancel();
    _timer = Timer(wait, () {
      // One at a time, in order: a removal never overtakes a save.
      _saving = (_saving ?? Future<void>.value()).then((_) => _save());
    });
  }

  /// Drops the save waiting to start.
  void stop() => _timer?.cancel();

  /// Waits for a save in progress (tests).
  Future<void> settle() async {
    while (_timer?.isActive ?? false) {
      await Future<void>.delayed(wait);
    }
    await _saving;
  }

  Future<void> _save() async {
    final vault = _ref.read(quickVaultProvider);
    final clears = _ref.read(quickClearsProvider);
    bool stale() =>
        _ref.read(quickClearsProvider) != clears ||
        !_ref.read(quickControlsOnProvider);
    try {
      if (!_ref.read(quickControlsOnProvider)) return await vault.clear();
      final homes = _ref.read(homesProvider).value;
      final rooms = _ref.read(roomsProvider).value;
      final devices = _ref.read(devicesProvider).value;
      final scenes = _ref.read(scenesProvider).value;
      // Not loaded yet: don't replace a good copy with an empty one.
      if (homes == null || rooms == null || devices == null) return;
      final repo = _ref.read(homeRepositoryProvider);
      final haServers = <HaServer>[];
      final fabrics = <MatterFabric>[];
      for (final h in homes) {
        final server = await repo.loadHaServer(h.id);
        if (server != null) haServers.add(server);
        final fabric = await repo.loadFabric(h.id);
        if (fabric != null) fabrics.add(fabric);
      }
      // Signed out or turned off while this was being put together.
      if (stale()) return;
      await vault.save(
        QuickSnapshot(
          homes: homes,
          rooms: rooms,
          devices: devices,
          scenes: scenes ?? const [],
          haServers: haServers,
          fabrics: fabrics,
        ).encode(),
      );
    } on Object {
      // The panel shows what it had; the next change tries again.
    }
  }

  void dispose() => _timer?.cancel();
}
