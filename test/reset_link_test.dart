import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:zerotrust_home/app/auth_providers.dart';
import 'package:zerotrust_home/app/email_links.dart';

void main() {
  tearDown(() => EmailLinks.recoveryPending = false);

  ProviderContainer container() {
    final c = ProviderContainer(
      overrides: [
        authStateChangesProvider.overrideWith(
          (ref) => const Stream<AuthState>.empty(),
        ),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('no reset link: not in recovery', () {
    expect(container().read(passwordRecoveryProvider), isFalse);
  });

  test('a reset link that signed in before the gate listened still opens '
      'the reset screen, until it is done', () {
    // What the link handler sets once the link's sign-in succeeded.
    EmailLinks.recoveryPending = true;
    final c = container();
    expect(c.read(passwordRecoveryProvider), isTrue);
    c.read(passwordRecoveryProvider.notifier).done();
    expect(c.read(passwordRecoveryProvider), isFalse);
    expect(EmailLinks.recoveryPending, isFalse);
    // A later start of the gate doesn't reopen it.
    expect(container().read(passwordRecoveryProvider), isFalse);
  });
}
