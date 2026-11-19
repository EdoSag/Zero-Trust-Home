import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../adapters/device_adapter.dart';
import '../data/home_store.dart';
import '../l10n/l10n.dart';
import '../model/device.dart';
import '../model/home.dart';
import 'common.dart';
import 'setup_home_page.dart';

/// Every home of the account: switch, rename, delete, add.
class HomesPage extends ConsumerWidget {
  const HomesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final homes = ref.watch(homesProvider).value ?? const <Home>[];
    final current = ref.watch(currentHomeProvider);
    final devices = ref.watch(devicesProvider).value ?? const <HomeDevice>[];
    final repo = ref.read(homeRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l.homes)),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: Text(l.addHome),
        onPressed: () => Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => const SetupHomePage())),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 88),
        children: [
          for (final home in homes)
            ListTile(
              leading: Icon(
                home.id == current?.id
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: home.id == current?.id
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
              title: Text(home.name),
              subtitle: Text(
                l.deviceCount(devices.where((d) => d.homeId == home.id).length),
              ),
              onTap: () =>
                  ref.read(selectedHomeIdProvider.notifier).select(home.id),
              trailing: PopupMenuButton<String>(
                onSelected: (action) async {
                  if (action == 'rename') {
                    final name = await askName(
                      context,
                      title: l.renameHome,
                      label: l.homeName,
                      initial: home.name,
                    );
                    if (name != null) {
                      await repo.saveHome(home.copyWith(name: name));
                    }
                  } else {
                    final ok = await confirm(
                      context,
                      title: l.deleteHome,
                      body: l.deleteHomeBody(home.name),
                      action: l.delete,
                      destructive: true,
                    );
                    if (!ok) return;
                    // Before the home's keys go: Matter devices are let go
                    // while this phone can still speak to them.
                    final devices =
                        ref.read(devicesProvider).value ?? const <HomeDevice>[];
                    await ref
                        .read(deviceControlProvider)
                        .forgetAll([
                          for (final d in devices)
                            if (d.homeId == home.id) d,
                        ])
                        .timeout(const Duration(seconds: 30), onTimeout: () {});
                    await repo.deleteHome(home.id);
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'rename', child: Text(l.rename)),
                  PopupMenuItem(value: 'delete', child: Text(l.delete)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
