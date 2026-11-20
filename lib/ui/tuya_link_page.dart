import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../adapters/tuya/tuya_providers.dart';
import '../adapters/tuya/tuya_share.dart';
import '../l10n/l10n.dart';
import 'common.dart';

/// "Link Smart Life": signs in to Tuya's cloud once with a user code and a
/// QR code approved in the Smart Life app, reads the local keys of the
/// account's devices, and signs out again.
class TuyaLinkPage extends ConsumerStatefulWidget {
  const TuyaLinkPage({super.key});

  @override
  ConsumerState<TuyaLinkPage> createState() => _TuyaLinkPageState();
}

class _TuyaLinkPageState extends ConsumerState<TuyaLinkPage> {
  final _form = GlobalKey<FormState>();
  final _code = TextEditingController();
  var _busy = false;
  var _closed = false;

  /// The sign-in token, while its QR code is shown.
  String? _token;
  String? _error;

  @override
  void dispose() {
    _closed = true;
    _code.dispose();
    super.dispose();
  }

  String _errorText(TuyaShareException e) {
    final l = context.l10n;
    return switch (e.failure) {
      TuyaShareFailure.offline => l.tuyaLinkErrOffline,
      TuyaShareFailure.badUserCode => l.tuyaLinkErrCode,
      TuyaShareFailure.expired => l.tuyaLinkErrExpired,
      TuyaShareFailure.refused => l.tuyaLinkErrRefused(e.detail),
    };
  }

  Future<void> _start() async {
    if (_busy || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final l = context.l10n;
    final share = ref.read(tuyaShareProvider);
    final keys = ref.read(tuyaKeysProvider.notifier);
    final account = keys.account;
    final userCode = _code.text.trim();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final token = await share.start(userCode);
      if (!mounted) return;
      setState(() => _token = token);
      final session = await share.wait(token, userCode, stopped: () => _closed);
      if (session == null) return;
      final List<TuyaSharedDevice> devices;
      try {
        devices = await share.devices(session);
      } finally {
        // Whatever happened, the cloud session ends here.
        await share.signOut(session);
      }
      final updated = await keys.take(devices, account: account);
      if (!mounted) return;
      showSnack(
        context,
        updated == 0
            ? l.tuyaLinkDone(devices.length)
            : l.tuyaLinkDoneUpdated(devices.length, updated),
      );
      Navigator.of(context).pop();
    } on TuyaShareException catch (e) {
      if (!mounted) return;
      setState(() {
        _token = null;
        _error = _errorText(e);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final token = _token;
    return Scaffold(
      appBar: AppBar(title: Text(l.tuyaLinkTitle)),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (token == null) ...[
              Text(l.tuyaLinkIntro),
              const SizedBox(height: 12),
              Text(l.tuyaLinkCloudNote, style: text.bodySmall),
              const SizedBox(height: 16),
              TextFormField(
                controller: _code,
                decoration: InputDecoration(
                  labelText: l.tuyaLinkUserCode,
                  helperText: l.tuyaLinkUserCodeHint,
                  helperMaxLines: 3,
                ),
                autocorrect: false,
                enableSuggestions: false,
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? l.fieldRequired : null,
                onFieldSubmitted: (_) => _start(),
              ),
              const SizedBox(height: 16),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(_error!, style: TextStyle(color: scheme.error)),
                ),
              FilledButton(
                onPressed: _busy ? null : _start,
                child: _busy
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l.tuyaLinkShowCode),
              ),
            ] else ...[
              Text(l.tuyaLinkScan),
              const SizedBox(height: 16),
              Center(
                // Always dark on white, whatever the theme: scanners need it.
                child: Container(
                  key: const Key('tuya-link-qr'),
                  color: Colors.white,
                  padding: const EdgeInsets.all(12),
                  child: QrImageView(
                    data: TuyaShare.qrText(token),
                    size: 240,
                    backgroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(l.tuyaLinkSamePhone, style: text.bodySmall),
              const SizedBox(height: 16),
              Row(
                children: [
                  const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(l.tuyaLinkWaiting)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
