# Zero-Trust Home

Private, local-first smart home control (on the phone: **ZT Home**). Same
account, settings and look as the other Zero-Trust apps, built on
[Zero-Trust-Core](https://github.com/EdoSag/Zero-Trust-Core), and end-to-end
encrypted like them.

The goal: add lights, plugs, locks, thermostats and sensors from any brand,
control them directly over the home network with no company cloud in
between, share the home with family, and reach it from outside through an
encrypted relay to a hub in the home.

## Where it stands

This is the foundation (phase H0 of the plan). It has:

- **Account, lock, settings and sync** from the shared core, in English and
  Hebrew.
- **Homes and rooms:** set up a home with its rooms, add, rename and delete
  rooms, keep several homes and switch between them. Synced to your other
  phones, end-to-end encrypted.
- **The device model:** one kind of device for every brand, described by
  what it can do (on/off, brightness, lock, temperature, power...). The home
  screen, the tiles and the details sheet are built on it.
- **The adapter interface:** each way of reaching devices (Matter, Home
  Assistant, Hue, Tuya/Smart Life, Shelly, Switcher) is one adapter behind
  `DeviceAdapter`. None is in yet, so "Add a device" lists them as coming
  soon.

Next: the Matter adapter (phase H1), so real devices can be added and
controlled.

## How it is built

- `lib/model/`: `Home`, `Room`, `HomeDevice` (with its `Capability` set),
  and `DeviceState` / `DeviceCommand`, which are never stored: state is read
  from the device.
- `lib/adapters/device_adapter.dart`: `DeviceAdapter`, the registry
  (`deviceAdaptersProvider`), live state per device (`deviceStateProvider`)
  and `DeviceControl` for sending commands.
- `lib/data/home_store.dart`: items in the shared `vault_items` table,
  sealed with the Home app key (`app = 'home'`): kinds `home`, `room` and
  `device`. No database change was needed. A device's address (node id, IP,
  local key) is inside the encrypted item.
- The home picked on a phone is kept on that phone, not synced.
- A device saved by a newer version (an adapter, type or capability this
  version doesn't know) still loads and is shown as needing a newer version.

## Build

```bash
# .env (not committed; CI writes its own)
SUPABASE_URL=https://<project>.supabase.co
SUPABASE_ANON_KEY=<publishable key>

flutter pub get
dart run zt_release_checks --app home   # shared release checks
flutter analyze && flutter test test/
flutter run
```

Flutter 3.47.9 (3.50 deprecates `material.dart` and fails analyze).

Pushing to `main` builds a signed APK and a Play bundle and publishes them as
a GitHub Release (`.github/workflows/android-apk.yml`). It needs the
repository secrets `ANDROID_KEYSTORE_BASE64` and `ANDROID_KEYSTORE_PASSWORD`,
the same keystore as the other Zero-Trust apps. Pull requests target `Dev`;
releases are one `Dev` → `main` pull request.

## License

AGPL-3.0. See [LICENSE](LICENSE).
