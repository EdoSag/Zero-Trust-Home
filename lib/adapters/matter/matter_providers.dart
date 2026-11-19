import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

import '../../data/home_store.dart';
import 'matter_adapter.dart';
import 'matter_bridge.dart';

/// The Matter library of this phone. Tests give a fake.
final matterBridgeProvider = Provider<MatterBridge>(
  (ref) => MatterChannelBridge(),
);

/// The one Matter adapter of the app.
final matterAdapterProvider = Provider<MatterAdapter>((ref) {
  final adapter = MatterAdapter(
    bridge: ref.watch(matterBridgeProvider),
    loadFabric: (homeId) => ref.read(homeRepositoryProvider).loadFabric(homeId),
    makeFabric: (homeId) => ref.read(homeRepositoryProvider).fabricFor(homeId),
    preferences: ref.watch(ztPreferencesStoreProvider),
  );
  ref.onDispose(adapter.dispose);
  return adapter;
});
