import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../adapters/matter/matter_bridge.dart';
import '../adapters/matter/matter_providers.dart';
import '../adapters/matter/matter_setup_code.dart';
import '../data/home_store.dart';
import '../l10n/l10n.dart';
import 'common.dart';

/// Adding a Matter device that is already on the home network: its setup
/// code (typed, or the text of its QR code), a name and a room.
class MatterAddPage extends ConsumerStatefulWidget {
  const MatterAddPage({super.key});

  @override
  ConsumerState<MatterAddPage> createState() => _MatterAddPageState();
}

class _MatterAddPageState extends ConsumerState<MatterAddPage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _code = TextEditingController();
  String? _roomId;
  var _busy = false;
  String? _error;
  var _named = false;

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
    if (_busy) ref.read(matterAdapterProvider).cancelPair().ignore();
    _name.dispose();
    _code.dispose();
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
    try {
      final devices = await ref
          .read(matterAdapterProvider)
          .pair(
            homeId: home.id,
            roomId: _roomId,
            name: name,
            code: _code.text,
            newId: HomeRepository.newId,
          );
      final repo = ref.read(homeRepositoryProvider);
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
      setState(() {
        _error = switch (e.failure) {
          MatterFailure.unsupported => l.matterErrUnsupported,
          MatterFailure.unreachable => l.matterErrNotFound,
          MatterFailure.failed => l.matterErrFailed(e.detail),
        };
      });
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

    return Scaffold(
      appBar: AppBar(title: Text(l.matterAddTitle)),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(l.matterIntro),
            const SizedBox(height: 16),
            TextFormField(
              controller: _code,
              decoration: InputDecoration(
                labelText: l.matterCode,
                hintText: '1234-567-8901',
                helperText: l.matterCodeHint,
                helperMaxLines: 3,
              ),
              // Codes are digits or the Latin text of a QR code, in any
              // language of the app.
              textDirection: TextDirection.ltr,
              autocorrect: false,
              enableSuggestions: false,
              validator: _checkCode,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _name,
              decoration: InputDecoration(labelText: l.name),
              textCapitalization: TextCapitalization.sentences,
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? l.fieldRequired : null,
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
                child: Text(l.matterAdding, style: text.bodySmall),
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
