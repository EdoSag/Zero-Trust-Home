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

Phase H0 (the foundation) and the first part of H1 (real devices) are in:

- **Account, lock, settings and sync** from the shared core, in English and
  Hebrew.
- **Homes and rooms:** set up a home with its rooms, add, rename and delete
  rooms, keep several homes and switch between them. Synced to your other
  phones, end-to-end encrypted.
- **The device model:** one kind of device for every brand, described by
  what it can do (on/off, brightness, lock, temperature, power...). The home
  screen, the tiles and the details sheet are built on it.
- **Tuya / Smart Life devices, locally:** plugs, switches and lights set up
  in the Smart Life or Tuya app are found on the Wi-Fi, added with their
  local key, switched, and show their state and power draw live. The app
  talks to them directly (protocol 3.3, 3.4 and 3.5); Tuya's servers are not
  involved. The local key is stored in the encrypted device item.
- **Matter devices:** a new device is found over Bluetooth from its QR
  code (scanned with the camera, ZXing, no Google code) and given the
  home's Wi-Fi; one already set up in another app joins from the code that
  app shares. Each home
  has its own Matter fabric: its keys are made on the phone and saved
  encrypted in the account, so every phone of the account controls the
  same devices, and each phone has its own key in the Android Keystore.
  Plugs, switches and lights switch and dim, with live state; a power
  strip shows one device per socket. This uses the open Matter SDK (see
  `matter/README.md`), not Google Play services. 64-bit ARM phones only.
- **Home Assistant:** connect a home's Home Assistant once with its
  address and a long-lived access token, then pick its lights, switches,
  plugs, fans, blinds, locks, thermostats and sensors. One WebSocket
  connection per home, on the home network, open while its devices are on
  screen; live state follows Home Assistant's `state_changed` events. The
  token is saved in the home's encrypted `ha-server` item.
- **The adapter interface:** each way of reaching devices (Matter, Home
  Assistant, Hue, Tuya/Smart Life, Shelly, Switcher) is one adapter behind
  `DeviceAdapter`. The ones not built yet are listed under "Add a device"
  as coming soon.

Next: Thread devices, and checking devices against the official list of
Matter manufacturers.

## How it is built

- `lib/model/`: `Home`, `Room`, `HomeDevice` (with its `Capability` set),
  and `DeviceState` / `DeviceCommand`, which are never stored: state is read
  from the device.
- `lib/adapters/device_adapter.dart`: `DeviceAdapter`, the registry
  (`deviceAdaptersProvider`), live state per device (`deviceStateProvider`)
  and `DeviceControl` for sending commands.
- `lib/adapters/tuya/`: the Tuya local protocol. `tuya_codec.dart` is the
  wire format (no network, tested against frames made by the open-source
  tinytuya library), `tuya_link.dart` one connection to one device,
  `tuya_discovery.dart` the UDP announcements, `tuya_adapter.dart` the
  `DeviceAdapter` (pairing, reconnecting, following a device to a new
  address).
- `lib/adapters/homeassistant/`: `ha_client.dart` the WebSocket API
  (sign-in, states, events, service calls), `ha_entities.dart` what each
  entity becomes (type, capabilities, values, service calls),
  `ha_adapter.dart` the shared connection per home with reconnecting.
- `lib/data/home_store.dart`: items in the shared `vault_items` table,
  sealed with the Home app key (`app = 'home'`): kinds `home`, `room`,
  `device`, `fabric` (Matter keys) and `ha-server` (Home Assistant address
  and token). No database change was needed. A device's address (node id, IP,
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
