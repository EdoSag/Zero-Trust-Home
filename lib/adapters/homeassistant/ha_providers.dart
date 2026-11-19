import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/home_store.dart';
import 'ha_adapter.dart';

/// The one Home Assistant adapter of the app.
final haAdapterProvider = Provider<HomeAssistantAdapter>((ref) {
  final adapter = HomeAssistantAdapter(
    loadServer: (homeId) =>
        ref.read(homeRepositoryProvider).loadHaServer(homeId),
  );
  ref.onDispose(adapter.dispose);
  return adapter;
});
