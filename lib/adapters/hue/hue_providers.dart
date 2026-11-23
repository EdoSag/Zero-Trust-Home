import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/home_store.dart';
import 'hue_adapter.dart';

/// The one Philips Hue adapter of the app.
final hueAdapterProvider = Provider<HueAdapter>((ref) {
  final adapter = HueAdapter(
    loadBridge: (homeId) =>
        ref.read(homeRepositoryProvider).loadHueBridge(homeId),
  );
  ref.onDispose(adapter.dispose);
  return adapter;
});
