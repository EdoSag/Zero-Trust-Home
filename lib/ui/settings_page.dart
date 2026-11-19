import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

import '../l10n/l10n.dart';
import '../quick/quick_store.dart';
import 'homes_page.dart';

/// The shared Zero-Trust settings screen, with Home's own rows.
class HomeSettingsPage extends ConsumerWidget {
  const HomeSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    return ZtSettingsPage(
      showSyncStatus: true,
      onSignedOut: () => Navigator.of(context).popUntil((r) => r.isFirst),
      onOpenUrl: (url) => launchUrl(url, mode: LaunchMode.externalApplication),
      privacyPolicyUrl: Uri.parse('https://zerotrust.bz/privacy'),
      termsUrl: Uri.parse('https://zerotrust.bz/terms'),
      supportUrl: Uri.parse('https://zerotrust.bz/support'),
      appSection: [
        ListTile(
          leading: const Icon(Icons.home_work_outlined),
          title: Text(l.manageHomes),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute<void>(builder: (_) => const HomesPage())),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.toggle_on_outlined),
          title: Text(l.quickControls),
          subtitle: Text(l.quickControlsBody),
          value: ref.watch(quickControlsOnProvider),
          onChanged: (on) => ref.read(quickControlsOnProvider.notifier).set(on),
        ),
      ],
    );
  }
}
