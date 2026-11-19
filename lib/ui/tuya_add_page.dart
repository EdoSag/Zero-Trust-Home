import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../adapters/tuya/tuya_adapter.dart';
import '../adapters/tuya/tuya_codec.dart';
import '../adapters/tuya/tuya_link.dart';
import '../adapters/tuya/tuya_providers.dart';
import '../data/home_store.dart';
import '../l10n/l10n.dart';
import 'common.dart';

/// Adding a Tuya / Smart Life device: the ones heard on the Wi-Fi are
/// listed; picking one (or entering an address by hand) opens
/// [TuyaPairPage].
class TuyaAddPage extends ConsumerWidget {
  const TuyaAddPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final text = Theme.of(context).textTheme;
    final found =
        (ref.watch(tuyaFoundProvider).value ?? const {}).values.toList()
          ..sort((a, b) => a.ip.compareTo(b.ip));
    final added = {
      for (final d in ref.watch(devicesProvider).value ?? const [])
        if (d.adapter == TuyaAdapter.adapterId) d.address['deviceId'],
    };

    void open(TuyaAnnouncement? device) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => TuyaPairPage(found: device)),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(l.connTuya)),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(l.tuyaIntro),
          ),
          for (final device in found)
            _FoundRow(
              device: device,
              added: added.contains(device.deviceId),
              onTap: () => open(device),
            ),
          ListTile(
            leading: const SizedBox.square(
              dimension: 24,
              child: Padding(
                padding: EdgeInsets.all(2),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            title: Text(l.tuyaSearching),
            subtitle: Text(l.tuyaSearchHint, style: text.bodySmall),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: Text(l.tuyaManual),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => open(null),
          ),
        ],
      ),
    );
  }
}

class _FoundRow extends StatelessWidget {
  const _FoundRow({
    required this.device,
    required this.added,
    required this.onTap,
  });
  final TuyaAnnouncement device;
  final bool added;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final supported = device.version != null;
    final id = device.deviceId;
    final tail = id.length > 4 ? id.substring(id.length - 4) : id;
    final String details;
    if (added) {
      details = l.tuyaAlreadyAdded;
    } else if (!supported) {
      details = l.tuyaTooOld(device.versionText);
    } else {
      details = l.tuyaFoundDetails(tail, device.versionText);
    }
    return ListTile(
      enabled: supported && !added,
      leading: const Icon(Icons.power_outlined),
      title: Text(l.tuyaFound(device.ip)),
      subtitle: Text(details),
      trailing: supported && !added ? const Icon(Icons.chevron_right) : null,
      onTap: onTap,
    );
  }
}

/// Name, room and local key of one device, then "Connect": the device is
/// reached with the key, asked what it can do, and saved.
class TuyaPairPage extends ConsumerStatefulWidget {
  const TuyaPairPage({super.key, this.found});

  /// The device picked from the list. Null to enter everything by hand.
  final TuyaAnnouncement? found;

  @override
  ConsumerState<TuyaPairPage> createState() => _TuyaPairPageState();
}

class _TuyaPairPageState extends ConsumerState<TuyaPairPage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _ip = TextEditingController();
  final _deviceId = TextEditingController();
  final _key = TextEditingController();
  var _version = TuyaVersion.v34;
  String? _roomId;
  var _showKey = false;
  var _busy = false;
  String? _error;
  var _named = false;

  @override
  void initState() {
    super.initState();
    final found = widget.found;
    if (found != null) {
      _ip.text = found.ip;
      _deviceId.text = found.deviceId;
      _version = found.version ?? _version;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_named) {
      _named = true;
      _name.text = context.l10n.tuyaDefaultName;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _ip.dispose();
    _deviceId.dispose();
    _key.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final l = context.l10n;
    final home = ref.read(currentHomeProvider);
    if (_busy || home == null || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    final ip = _ip.text.trim();
    final name = _name.text.trim();
    try {
      final device = await ref
          .read(tuyaAdapterProvider)
          .pair(
            id: HomeRepository.newId(),
            homeId: home.id,
            roomId: _roomId,
            name: name,
            deviceId: _deviceId.text.trim(),
            ip: ip,
            version: _version,
            localKey: _key.text,
          );
      await ref.read(homeRepositoryProvider).saveDevice(device);
      if (!mounted) return;
      showSnack(context, l.deviceAdded(name));
      // Back to where "Add a device" was opened from: past this page, the
      // list of found devices and the list of ways to connect.
      var pages = 0;
      Navigator.of(context).popUntil((route) => pages++ >= 3 || route.isFirst);
    } on TuyaException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = switch (e.failure) {
          TuyaFailure.unreachable => l.tuyaErrUnreachable(ip),
          TuyaFailure.keyRejected => l.tuyaErrKey,
        };
      });
    } on Object {
      if (!mounted) return;
      setState(() => _error = l.tuyaErrUnreachable(ip));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final manual = widget.found == null;
    final rooms = ref.watch(currentRoomsProvider);
    String? required(String? v) =>
        (v ?? '').trim().isEmpty ? l.fieldRequired : null;

    return Scaffold(
      appBar: AppBar(title: Text(l.tuyaPairTitle)),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              decoration: InputDecoration(labelText: l.name),
              textCapitalization: TextCapitalization.sentences,
              validator: required,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: _roomId,
              decoration: InputDecoration(labelText: l.deviceRoom),
              items: [
                DropdownMenuItem(value: null, child: Text(l.noRoom)),
                for (final r in rooms)
                  DropdownMenuItem(value: r.id, child: Text(r.name)),
              ],
              onChanged: (id) => _roomId = id,
            ),
            const SizedBox(height: 12),
            if (manual) ...[
              TextFormField(
                controller: _ip,
                decoration: InputDecoration(
                  labelText: l.tuyaIp,
                  hintText: '192.168.1.50',
                ),
                keyboardType: TextInputType.url,
                autocorrect: false,
                validator: required,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _deviceId,
                decoration: InputDecoration(labelText: l.tuyaDeviceId),
                autocorrect: false,
                enableSuggestions: false,
                validator: required,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<TuyaVersion>(
                initialValue: _version,
                decoration: InputDecoration(labelText: l.tuyaVersion),
                items: [
                  for (final v in TuyaVersion.values)
                    DropdownMenuItem(value: v, child: Text(v.text)),
                ],
                onChanged: (v) => _version = v ?? _version,
              ),
              const SizedBox(height: 12),
            ],
            TextFormField(
              controller: _key,
              decoration: InputDecoration(
                labelText: l.tuyaLocalKey,
                suffixIcon: IconButton(
                  tooltip: _showKey ? l.hideKey : l.showKey,
                  icon: Icon(
                    _showKey
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                  onPressed: () => setState(() => _showKey = !_showKey),
                ),
              ),
              obscureText: !_showKey,
              autocorrect: false,
              enableSuggestions: false,
              validator: (v) =>
                  tuyaParseLocalKey(v ?? '') == null ? l.tuyaKeyLength : null,
              onFieldSubmitted: (_) => _connect(),
            ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: () =>
                    showTuyaKeyHelp(context, deviceId: _deviceId.text.trim()),
                child: Text(l.tuyaLocalKeyHelp),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_error!, style: TextStyle(color: scheme.error)),
              ),
            FilledButton(
              onPressed: _busy ? null : _connect,
              child: _busy
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l.tuyaConnect),
            ),
          ],
        ),
      ),
    );
  }
}

/// How to get a device's local key, with its Device ID ready to copy.
Future<void> showTuyaKeyHelp(BuildContext context, {required String deviceId}) {
  final l = context.l10n;
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l.tuyaKeyHelpTitle),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.tuyaKeyHelpBody),
            if (deviceId.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(l.tuyaDeviceId, style: Theme.of(ctx).textTheme.labelMedium),
              Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      deviceId,
                      textDirection: TextDirection.ltr,
                    ),
                  ),
                  IconButton(
                    tooltip: l.copy,
                    icon: const Icon(Icons.copy_outlined),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: deviceId));
                      if (ctx.mounted) showSnack(ctx, l.copied);
                    },
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l.close)),
      ],
    ),
  );
}
