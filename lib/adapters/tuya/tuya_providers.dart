import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/home_store.dart';
import 'tuya_adapter.dart';
import 'tuya_codec.dart';
import 'tuya_discovery.dart';

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
