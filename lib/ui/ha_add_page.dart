import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../adapters/homeassistant/ha_adapter.dart';
import '../adapters/homeassistant/ha_client.dart';
import '../adapters/homeassistant/ha_entities.dart';
import '../adapters/homeassistant/ha_providers.dart';
import '../adapters/homeassistant/ha_server.dart';
import '../data/home_store.dart';
import '../l10n/l10n.dart';
import '../model/home.dart';
import 'common.dart';

/// Adding devices from Home Assistant: the home's server is connected once
/// (address and token), then its lights, switches, sensors and the rest
/// are listed to pick from.
class HaAddPage extends ConsumerStatefulWidget {
  const HaAddPage({super.key});

  @override
  ConsumerState<HaAddPage> createState() => _HaAddPageState();
}

class _HaAddPageState extends ConsumerState<HaAddPage> {
  final _form = GlobalKey<FormState>();
  final _url = TextEditingController();
  final _token = TextEditingController();
  var _showToken = false;
  var _loading = true;
  var _busy = false;
  var _editing = false;
  String? _error;
  HaServer? _server;
  List<HaEntity>? _entities;
  final _picked = <String>{};
  String? _roomId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
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
    final server = home == null
        ? null
        : await ref.read(homeRepositoryProvider).loadHaServer(home.id);
    if (!mounted) return;
    setState(() {
      _server = server;
      _loading = false;
      if (server != null) _url.text = server.url;
    });
    if (server != null) await _list(server);
  }

  String _describe(HaException e) {
    final l = context.l10n;
    return switch (e.failure) {
      HaFailure.unreachable => l.haErrUnreachable,
      HaFailure.badToken => l.haErrToken,
      HaFailure.notHomeAssistant => l.haErrNotHa,
      HaFailure.failed => l.haErrFailed(e.detail),
    };
  }

  Future<void> _list(HaServer server) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final entities = await ref.read(haAdapterProvider).entities(server);
      if (!mounted) return;
      setState(() => _entities = entities);
    } on HaException catch (e) {
      if (!mounted) return;
      setState(() => _error = _describe(e));
    } on Object {
      if (!mounted) return;
      setState(() => _error = context.l10n.haErrUnreachable);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connect() async {
    final home = _home;
    if (_busy || home == null || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final server = HaServer(
      homeId: home.id,
      url: HaServer.normalizeUrl(_url.text)!,
      token: _token.text.trim(),
    );
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final entities = await ref.read(haAdapterProvider).entities(server);
      // Saved only once it worked: a typo never replaces a token that did.
      await ref.read(homeRepositoryProvider).saveHaServer(server);
      if (!mounted) return;
      setState(() {
        _server = server;
        _entities = entities;
        _editing = false;
        _token.clear();
      });
    } on HaException catch (e) {
      if (!mounted) return;
      setState(() => _error = _describe(e));
    } on Object {
      if (!mounted) return;
      setState(() => _error = context.l10n.haErrUnreachable);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add() async {
    final home = _home;
    final entities = _entities;
    if (_busy || home == null || entities == null || _picked.isEmpty) return;
    setState(() => _busy = true);
    final adapter = ref.read(haAdapterProvider);
    final repo = ref.read(homeRepositoryProvider);
    for (final entity in entities) {
      if (!_picked.contains(entity.id)) continue;
      await repo.saveDevice(
        adapter.deviceFor(
          id: HomeRepository.newId(),
          homeId: home.id,
          entity: entity,
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
    final server = _server;
    final Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (server == null || _editing) {
      body = _connectForm(context);
    } else {
      body = _entityList(context);
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(l.connHa),
        actions: [
          if (server != null && !_editing)
            IconButton(
              tooltip: l.haChangeServer,
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

  Widget _connectForm(BuildContext context) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(l.haIntro),
          const SizedBox(height: 16),
          TextFormField(
            controller: _url,
            decoration: InputDecoration(
              labelText: l.haAddress,
              hintText: 'http://192.168.1.10:8123',
              helperText: l.haAddressHint,
              helperMaxLines: 3,
            ),
            keyboardType: TextInputType.url,
            autocorrect: false,
            enableSuggestions: false,
            validator: (v) =>
                HaServer.normalizeUrl(v ?? '') == null ? l.haAddressBad : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _token,
            decoration: InputDecoration(
              labelText: l.haToken,
              helperText: l.haTokenHint,
              helperMaxLines: 4,
              suffixIcon: IconButton(
                tooltip: _showToken ? l.hideKey : l.showKey,
                icon: Icon(
                  _showToken
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
                onPressed: () => setState(() => _showToken = !_showToken),
              ),
            ),
            obscureText: !_showToken,
            autocorrect: false,
            enableSuggestions: false,
            validator: (v) => (v ?? '').trim().isEmpty ? l.fieldRequired : null,
            onFieldSubmitted: (_) => _connect(),
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

  Widget _entityList(BuildContext context) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final home = ref.watch(currentHomeProvider);
    final rooms = ref.watch(currentRoomsProvider);
    final added = {
      for (final d in ref.watch(devicesProvider).value ?? const [])
        if (d.adapter == HomeAssistantAdapter.adapterId && d.homeId == home?.id)
          HaAddress.parse(d.address)?.entityId,
    };
    final entities = _entities;
    return Column(
      children: [
        Expanded(
          child: ListView(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Text(l.haConnectedTo(_server!.url)),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(_error!, style: TextStyle(color: scheme.error)),
                ),
              if (_busy && entities == null)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (entities != null && entities.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(l.haNothing),
                ),
              if (entities == null && !_busy)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: OutlinedButton(
                    onPressed: () => _list(_server!),
                    child: Text(l.tryAgain),
                  ),
                ),
              for (final e in entities ?? const <HaEntity>[])
                CheckboxListTile(
                  secondary: Icon(deviceIcon(e.type)),
                  title: Text(e.name),
                  subtitle: Text(
                    added.contains(e.id) ? l.haAlreadyAdded : e.id,
                    textDirection: added.contains(e.id)
                        ? null
                        : TextDirection.ltr,
                  ),
                  value: added.contains(e.id) || _picked.contains(e.id),
                  onChanged: added.contains(e.id)
                      ? null
                      : (on) => setState(
                          () => on == true
                              ? _picked.add(e.id)
                              : _picked.remove(e.id),
                        ),
                ),
            ],
          ),
        ),
        if (entities != null && entities.isNotEmpty)
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
