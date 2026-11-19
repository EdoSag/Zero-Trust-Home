import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

import '../adapters/matter/matter_adapter.dart';
import '../adapters/matter/matter_bridge.dart';
import '../adapters/matter/matter_providers.dart';
import '../adapters/matter/matter_setup_code.dart';
import '../data/home_store.dart';
import '../l10n/l10n.dart';
import 'common.dart';

/// How the device reaches the phone while it is being added.
enum MatterAddKind {
  /// New or reset: found over Bluetooth (or on the Wi-Fi) and given the
  /// home's Wi-Fi.
  newDevice,

  /// Already on the Wi-Fi, set up in another app that shared it.
  shared,
}

/// This phone's last Wi-Fi name given to a device (never the password).
const _wifiNameKey = 'matter.wifi.ssid';

/// Adding a Matter device: its setup code (scanned or typed), for a new
/// device the home's Wi-Fi, then a name and a room.
class MatterAddPage extends ConsumerStatefulWidget {
  const MatterAddPage({super.key});

  @override
  ConsumerState<MatterAddPage> createState() => _MatterAddPageState();
}

class _MatterAddPageState extends ConsumerState<MatterAddPage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _code = TextEditingController();
  final _ssid = TextEditingController();
  final _password = TextEditingController();
  var _kind = MatterAddKind.newDevice;
  String? _roomId;
  var _busy = false;
  var _showPassword = false;
  String? _error;
  var _named = false;
  MatterAdapter? _adapter;

  @override
  void initState() {
    super.initState();
    ref.read(ztPreferencesStoreProvider).read(_wifiNameKey).then((saved) {
      if (mounted && saved != null && _ssid.text.isEmpty) _ssid.text = saved;
    }, onError: (_) {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_named) {
      _named = true;
      _name.text = context.l10n.matterDefaultName;
    }
  }

  @override
  void dispose() {
    // Leaving while a device is being added gives up on it.
    if (_busy) _adapter?.cancelPair().ignore();
    _name.dispose();
    _code.dispose();
    _ssid.dispose();
    _password.dispose();
    super.dispose();
  }

  String? _checkCode(String? value) {
    final l = context.l10n;
    final text = (value ?? '').trim();
    if (text.isEmpty) return l.fieldRequired;
    try {
      MatterSetupCode.parse(text);
      return null;
    } on MatterSetupCodeException catch (e) {
      return switch (e.problem) {
        MatterSetupCodeProblem.checksum => l.matterCodeTypo,
        MatterSetupCodeProblem.version => l.matterCodeTooNew,
        _ => l.matterCodeInvalid,
      };
    }
  }

  Future<void> _scan() async {
    final l = context.l10n;
    setState(() => _error = null);
    final String? text;
    try {
      text = await ref.read(matterBridgeProvider).scanCode();
    } on MatterException catch (e) {
      if (mounted) setState(() => _error = _describe(e));
      return;
    }
    if (!mounted || text == null) return;
    final MatterSetupCode code;
    try {
      code = MatterSetupCode.parse(text);
    } on MatterSetupCodeException {
      setState(() => _error = l.matterScanNotMatter);
      return;
    }
    setState(() {
      _code.text = text!.trim();
      // The QR code says how the device can be reached.
      if (code.bluetooth) {
        _kind = MatterAddKind.newDevice;
      } else if (code.onNetwork) {
        _kind = MatterAddKind.shared;
      }
    });
  }

  String _describe(MatterException e) {
    final l = context.l10n;
    return switch (e.failure) {
      MatterFailure.unsupported => l.matterErrUnsupported,
      MatterFailure.bluetoothOff => l.matterErrBluetoothOff,
      MatterFailure.bluetoothDenied => l.matterErrBluetoothDenied,
      MatterFailure.unreachable =>
        _kind == MatterAddKind.newDevice
            ? l.matterErrNotFoundNew
            : l.matterErrNotFound,
      MatterFailure.failed => l.matterErrFailed(e.detail),
    };
  }

  Future<void> _add() async {
    final l = context.l10n;
    final home = ref.read(currentHomeProvider);
    if (_busy || home == null || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    final name = _name.text.trim();
    final wifi = _kind == MatterAddKind.newDevice
        ? MatterWifi(ssid: _ssid.text.trim(), password: _password.text)
        : null;
    // Taken now: a device that joins after this page was left is still
    // saved, or nothing in the app could remove it from the home.
    final adapter = ref.read(matterAdapterProvider);
    final repo = ref.read(homeRepositoryProvider);
    final preferences = ref.read(ztPreferencesStoreProvider);
    _adapter = adapter;
    try {
      if (wifi != null) {
        preferences.write(_wifiNameKey, wifi.ssid).ignore();
      }
      final devices = await adapter.pair(
        homeId: home.id,
        roomId: _roomId,
        name: name,
        code: _code.text,
        newId: HomeRepository.newId,
        wifi: wifi,
      );
      for (final device in devices) {
        await repo.saveDevice(device);
      }
      if (!mounted) return;
      showSnack(context, l.deviceAdded(name));
      // Back to where "Add a device" was opened from: past this page and
      // the list of ways to connect.
      var pages = 0;
      Navigator.of(context).popUntil((route) => pages++ >= 2 || route.isFirst);
    } on MatterException catch (e) {
      if (!mounted) return;
      setState(() => _error = _describe(e));
    } on MatterFabricNeedsSync {
      if (!mounted) return;
      setState(() => _error = l.matterErrNeedsSync);
    } on MatterFabricUnreadable {
      if (!mounted) return;
      setState(() => _error = l.matterErrKeys);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _error = l.matterErrFailed('$e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final rooms = ref.watch(currentRoomsProvider);
    final isNew = _kind == MatterAddKind.newDevice;
    String? required(String? v) =>
        (v ?? '').trim().isEmpty ? l.fieldRequired : null;

    return Scaffold(
      appBar: AppBar(title: Text(l.matterAddTitle)),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SegmentedButton<MatterAddKind>(
              segments: [
                ButtonSegment(
                  value: MatterAddKind.newDevice,
                  label: Text(l.matterKindNew),
                  icon: const Icon(Icons.bluetooth_searching),
                ),
                ButtonSegment(
                  value: MatterAddKind.shared,
                  label: Text(l.matterKindShared),
                  icon: const Icon(Icons.share_outlined),
                ),
              ],
              selected: {_kind},
              onSelectionChanged: _busy
                  ? null
                  : (picked) => setState(() {
                      _kind = picked.single;
                      _error = null;
                    }),
            ),
            const SizedBox(height: 16),
            Text(isNew ? l.matterIntroNew : l.matterIntro),
            const SizedBox(height: 16),
            TextFormField(
              controller: _code,
              decoration: InputDecoration(
                labelText: l.matterCode,
                hintText: '1234-567-8901',
                helperText: l.matterCodeHint,
                helperMaxLines: 3,
                suffixIcon: IconButton(
                  tooltip: l.matterScan,
                  icon: const Icon(Icons.qr_code_scanner),
                  onPressed: _busy ? null : _scan,
                ),
              ),
              // Codes are digits or the Latin text of a QR code, in any
              // language of the app.
              textDirection: TextDirection.ltr,
              autocorrect: false,
              enableSuggestions: false,
              validator: _checkCode,
            ),
            if (isNew) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _ssid,
                decoration: InputDecoration(
                  labelText: l.matterWifiName,
                  helperText: l.matterWifiHint,
                  helperMaxLines: 3,
                ),
                autocorrect: false,
                enableSuggestions: false,
                validator: required,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _password,
                decoration: InputDecoration(
                  labelText: l.matterWifiPassword,
                  suffixIcon: IconButton(
                    tooltip: _showPassword
                        ? l.matterHidePassword
                        : l.matterShowPassword,
                    icon: Icon(
                      _showPassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                    onPressed: () =>
                        setState(() => _showPassword = !_showPassword),
                  ),
                ),
                obscureText: !_showPassword,
                autocorrect: false,
                enableSuggestions: false,
              ),
            ],
            const SizedBox(height: 12),
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
            const SizedBox(height: 16),
            if (_busy)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  isNew ? l.matterAddingNew : l.matterAdding,
                  style: text.bodySmall,
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_error!, style: TextStyle(color: scheme.error)),
              ),
            FilledButton(
              onPressed: _busy ? null : _add,
              child: _busy
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l.matterAdd),
            ),
          ],
        ),
      ),
    );
  }
}
