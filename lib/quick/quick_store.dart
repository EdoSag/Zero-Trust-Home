import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

import '../data/home_store.dart';
import 'quick_snapshot.dart';

/// A tap in the controls panel or on the widget, waiting for the app to be
/// unlocked: [action] is `toggle` (a device) or `scene`.
typedef QuickTap = ({String action, String id});

/// Where the names for the controls panel and widget are kept: a file
/// sealed with a key in the Android Keystore (`QuickVault.kt`), and the
/// tap that opened the app. Tests give a fake.
abstract interface class QuickVault {
  Future<void> save(String text);
  Future<String?> load();
  Future<void> clear();

  /// The tap that opened the app, once; null when there is none or it is
  /// more than a couple of minutes old.
  Future<QuickTap?> takeTap();

  /// Taps made while the app is open and unlocked.
  Stream<void> get taps;
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

  @override
  Future<QuickTap?> takeTap() async {
    final tap = await _channel.invokeMethod<Map<Object?, Object?>>('takeTap');
    final action = tap?['action'];
    final id = tap?['id'];
    if (action is! String || id is! String) return null;
    return (action: action, id: id);
  }

  static final _taps = StreamController<void>.broadcast();
  static var _listening = false;

  @override
  Stream<void> get taps {
    if (!_listening) {
      _listening = true;
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'tapped') _taps.add(null);
      });
    }
    return _taps.stream;
  }
}

final quickVaultProvider = Provider<QuickVault>((ref) => QuickChannelVault());

/// Whether the controls panel and the home screen widget may show device
/// names. Off unless the person turns it on (the suite's widget privacy
/// rule); off, they only open the app.
final quickControlsOnProvider = NotifierProvider<QuickControlsOn, bool>(
  QuickControlsOn.new,
);

class QuickControlsOn extends Notifier<bool> {
  static const _key = 'home.showOutside';

  @override
  bool build() {
    _load();
    return false;
  }

  Future<void> _load() async {
    try {
      final saved = await ref.read(ztPreferencesStoreProvider).read(_key);
      if (saved == 'on') state = true;
    } on Object {
      // Off.
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
      // Signed out or turned off since this was asked for.
      if (stale()) return;
      await vault.save(
        QuickSnapshot(
          homes: homes,
          rooms: rooms,
          devices: devices,
          scenes: scenes ?? const [],
        ).encode(),
      );
    } on Object {
      // The panel shows what it had; the next change tries again.
    }
  }

  void dispose() => _timer?.cancel();
}
