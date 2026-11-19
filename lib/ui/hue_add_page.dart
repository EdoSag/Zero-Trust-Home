import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../adapters/hue/hue_adapter.dart';
import '../adapters/hue/hue_bridge.dart';
import '../adapters/hue/hue_lights.dart';
import '../adapters/hue/hue_link.dart';
import '../adapters/hue/hue_providers.dart';
import '../data/home_store.dart';
import '../l10n/l10n.dart';
import '../model/home.dart';
import 'common.dart';

/// Adding lights from a Philips Hue Bridge: the home's bridge is paired
/// once (its address, then its round button), then its lights and plugs
/// are listed to pick from.
class HueAddPage extends ConsumerStatefulWidget {
  const HueAddPage({super.key});

  @override
  ConsumerState<HueAddPage> createState() => _HueAddPageState();
}

class _HueAddPageState extends ConsumerState<HueAddPage> {
  final _form = GlobalKey<FormState>();
  final _host = TextEditingController();
  var _loading = true;
  var _busy = false;
  var _editing = false;
  String? _error;
  HueBridge? _bridge;
  List<HueLight>? _lights;
  final _picked = <String>{};
  String? _roomId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _host.dispose();
    super.dispose();
  }

  Home? get _home => ref.read(currentHomeProvider);

  Future<void> _load() async {
    try {
      await ref.read(homesProvider.future);
    } on Object {
      // No homes to read: the form is shown.
    }
    if (!mounted) return;
    final home = _home;
    final bridge = home == null
        ? null
        : await ref.read(homeRepositoryProvider).loadHueBridge(home.id);
    if (!mounted) return;
    setState(() {
      _bridge = bridge;
      _loading = false;
      if (bridge != null) _host.text = bridge.host;
    });
    if (bridge != null) await _list(bridge);
  }

  String _describe(HueException e) {
    final l = context.l10n;
    return switch (e.failure) {
      HueFailure.unreachable => l.hueErrUnreachable,
      HueFailure.pressButton => l.hueErrButton,
      HueFailure.badKey => l.hueErrKey,
      HueFailure.notHue => l.hueErrNotHue,
      HueFailure.changed => l.hueErrChanged,
      HueFailure.failed => l.hueErrFailed(e.detail),
    };
  }

  Future<void> _list(HueBridge bridge) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final lights = await ref.read(hueAdapterProvider).lights(bridge);
      if (!mounted) return;
      setState(() => _lights = lights);
    } on HueException catch (e) {
      if (!mounted) return;
      setState(() => _error = _describe(e));
    } on Object {
      if (!mounted) return;
      setState(() => _error = context.l10n.hueErrUnreachable);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connect() async {
    final home = _home;
    if (_busy || home == null || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final adapter = ref.read(hueAdapterProvider);
      final bridge = await adapter.pair(
        homeId: home.id,
        host: HueBridge.normalizeHost(_host.text)!,
      );
      final lights = await adapter.lights(bridge);
      // Saved only once it worked: a typo never replaces a key that did.
      await ref.read(homeRepositoryProvider).saveHueBridge(bridge);
      if (!mounted) return;
      setState(() {
        _bridge = bridge;
        _lights = lights;
        _editing = false;
      });
    } on HueException catch (e) {
      if (!mounted) return;
      setState(() => _error = _describe(e));
    } on Object {
      if (!mounted) return;
      setState(() => _error = context.l10n.hueErrUnreachable);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add() async {
    final home = _home;
    final lights = _lights;
    if (_busy || home == null || lights == null || _picked.isEmpty) return;
    setState(() => _busy = true);
    final adapter = ref.read(hueAdapterProvider);
    final repo = ref.read(homeRepositoryProvider);
    for (final light in lights) {
      if (!_picked.contains(light.id)) continue;
      await repo.saveDevice(
        adapter.deviceFor(
          id: HomeRepository.newId(),
          homeId: home.id,
          light: light,
          roomId: _roomId,
        ),
      );
    }
    if (!mounted) return;
    showSnack(context, context.l10n.haAdded(_picked.length));
    // Back past this page and the list of ways to connect.
    var pages = 0;
    Navigator.of(context).popUntil((route) => pages++ >= 2 || route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    // Kept up to date while the page is open, for the buttons to read.
    ref.watch(currentHomeProvider);
    final bridge = _bridge;
    final Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (bridge == null || _editing) {
      body = _pairForm(context);
    } else {
      body = _lightList(context);
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(l.connHue),
        actions: [
          if (bridge != null && !_editing)
            IconButton(
              tooltip: l.huePairAgain,
              icon: const Icon(Icons.key_outlined),
              onPressed: () => setState(() {
                _editing = true;
                _error = null;
              }),
            ),
        ],
      ),
      body: body,
    );
  }

  Widget _pairForm(BuildContext context) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(l.hueIntro),
          const SizedBox(height: 16),
          TextFormField(
            controller: _host,
            decoration: InputDecoration(
              labelText: l.hueAddress,
              hintText: '192.168.1.20',
              helperText: l.hueAddressHint,
              helperMaxLines: 4,
            ),
            keyboardType: TextInputType.url,
            autocorrect: false,
            enableSuggestions: false,
            validator: (v) => HueBridge.normalizeHost(v ?? '') == null
                ? l.hueAddressBad
                : null,
            onFieldSubmitted: (_) => _connect(),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.radio_button_checked, color: scheme.primary),
              const SizedBox(width: 12),
              Expanded(child: Text(l.huePressButton)),
            ],
          ),
          const SizedBox(height: 16),
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
                : Text(l.haConnect),
          ),
        ],
      ),
    );
  }

  Widget _lightList(BuildContext context) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final home = ref.watch(currentHomeProvider);
    final rooms = ref.watch(currentRoomsProvider);
    final added = {
      for (final d in ref.watch(devicesProvider).value ?? const [])
        if (d.adapter == HueAdapter.adapterId && d.homeId == home?.id)
          HueAddress.parse(d.address)?.lightId,
    };
    final lights = _lights;
    return Column(
      children: [
        Expanded(
          child: ListView(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Text(l.hueConnectedTo(_bridge!.host)),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(_error!, style: TextStyle(color: scheme.error)),
                ),
              if (_busy && lights == null)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (lights != null && lights.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(l.hueNothing),
                ),
              if (lights == null && !_busy)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: OutlinedButton(
                    onPressed: () => _list(_bridge!),
                    child: Text(l.tryAgain),
                  ),
                ),
              for (final light in lights ?? const <HueLight>[])
                CheckboxListTile(
                  secondary: Icon(deviceIcon(light.type)),
                  title: Text(light.name),
                  subtitle: added.contains(light.id)
                      ? Text(l.haAlreadyAdded)
                      : null,
                  value: added.contains(light.id) || _picked.contains(light.id),
                  onChanged: added.contains(light.id)
                      ? null
                      : (on) => setState(
                          () => on == true
                              ? _picked.add(light.id)
                              : _picked.remove(light.id),
                        ),
                ),
            ],
          ),
        ),
        if (lights != null && lights.isNotEmpty)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
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
                  FilledButton(
                    onPressed: _busy || _picked.isEmpty ? null : _add,
                    child: Text(l.haAdd(_picked.length)),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
