import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/home_store.dart';
import '../../model/device.dart';
import 'tuya_adapter.dart';
import 'tuya_codec.dart';
import 'tuya_discovery.dart';
import 'tuya_share.dart';

/// Android drops broadcast packets for apps that don't hold a multicast
/// lock; MainActivity takes and releases it.
const _network = MethodChannel('dev.sagron.zerotrusthome/network');

/// The one Tuya adapter of the app, with its connections and discovery.
final tuyaAdapterProvider = Provider<TuyaAdapter>((ref) {
  final adapter = TuyaAdapter(
    discovery: TuyaDiscovery(
      onStart: () => _network.invokeMethod<void>('acquireMulticastLock'),
      onStop: () => _network.invokeMethod<void>('releaseMulticastLock'),
    ),
    // The router gave the device another address: save it, so the other
    // phones of the account find it too.
    onMoved: (device, ip) {
      ref
          .read(homeRepositoryProvider)
          .saveDevice(device.copyWith(address: {...device.address, 'ip': ip}))
          .ignore();
    },
  );
  ref.onDispose(adapter.dispose);
  return adapter;
});

/// Tuya devices heard on the network, by device id, while watched.
final tuyaFoundProvider =
    StreamProvider.autoDispose<Map<String, TuyaAnnouncement>>(
      (ref) => ref.watch(tuyaAdapterProvider).discovery.watch(),
    );

/// The one-time sign-in to Tuya's cloud that reads local keys.
final tuyaShareProvider = Provider<TuyaShare>((ref) => TuyaShare());

/// Keys read by "Link Smart Life", by device id. Kept in memory only, until
/// the app closes: a key is saved (encrypted, with its device) once the
/// device is added.
final tuyaKeysProvider =
    NotifierProvider<TuyaKeys, Map<String, TuyaSharedDevice>>(TuyaKeys.new);

class TuyaKeys extends Notifier<Map<String, TuyaSharedDevice>> {
  @override
  Map<String, TuyaSharedDevice> build() => const {};

  /// Takes the account's devices, and gives saved devices whose key
  /// changed (removed and set up again in Smart Life) the new one. Returns
  /// how many saved devices were updated.
  Future<int> take(List<TuyaSharedDevice> devices) async {
    state = {for (final d in devices) d.deviceId: d};
    final repository = ref.read(homeRepositoryProvider);
    var updated = 0;
    final all = ref.read(devicesProvider).value ?? const <HomeDevice>[];
    for (final saved in all) {
      if (saved.adapter != TuyaAdapter.adapterId) continue;
      final fresh = state[saved.address['deviceId']];
      if (fresh == null || tuyaParseLocalKey(fresh.localKey) == null) continue;
      if (saved.address['localKey'] == fresh.localKey) continue;
      await repository.saveDevice(
        saved.copyWith(address: {...saved.address, 'localKey': fresh.localKey}),
      );
      updated++;
    }
    return updated;
  }
}
