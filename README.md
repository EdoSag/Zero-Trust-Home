# Zero-Trust Home

Private, local-first smart home control. Lights, plugs, locks, thermostats
and sensors are controlled directly over the home network, with no company
cloud in between, and homes, rooms and devices sync end-to-end encrypted to
your other phones. On the phone it is called **ZT Home**; in stores and on
release pages, **Zero-Trust Home**. Same account, settings and look as the
other Zero-Trust apps, built on
[Zero-Trust-Core](https://github.com/EdoSag/Zero-Trust-Core). Part of the
[Zero-Trust suite](https://zerotrust.bz).

## What it does

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
  "Link Smart Life" reads those keys for you: a one-time sign-in to Tuya's
  cloud (user code plus a QR code approved in Smart Life), after which the
  app signs out again. It is the sign-in Tuya made for Home Assistant.
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
- **Controls for every kind of device:** tiles say what each device is
  doing ("Locked", "Open 40%", "On · 19.5°C · set to 21°C"); the details
  sheet dims lights, sets fan speed, moves blinds, locks (unlocking asks
  first) and sets thermostats, and shows sensor readings.
- **Scenes:** one tap sets several devices ("Good night": lights off,
  door locked, blinds closed). Pick what each device does, or copy how
  things are now. Scenes lock doors but never unlock them. Saved as
  encrypted `scene` items and synced.
- **Device Controls panel (Android 11+):** with "Show devices outside the
  app" on in Settings (off by default), the phone's controls panel lists
  every device and scene. Only names and kinds are kept for it, on the
  phone, sealed with a key in the Android Keystore (`QuickVault.kt`);
  addresses, local keys, tokens and Matter keys stay in the vault. A tile
  opens ZT Home (through an activity no other app can start) with the
  tap, which is carried out once the app is
  unlocked (within two minutes): a device switches the other way, a door
  only locks, a scene runs.
- **Home screen widget:** the same names as a resizable grid (favourites,
  scenes, then the other devices), built on the suite's widget kit
  (`HomeWidget.kt`). Same rule as the panel: a tile opens ZT Home with the
  tap. With the switch off it shows no names, only how to turn it on.
- **Matter bridges:** adding a bridge by its Matter code (a Hue Bridge,
  IKEA DIRIGERA, Aqara or SwitchBot hub) brings the lights and plugs
  behind it, each with the name it has on the bridge, and shows one the
  bridge has lost as not reachable while the others keep working.
- **Philips Hue (`lib/adapters/hue`):** lights and smart plugs on a Hue
  Bridge through its local API (CLIP v2) on the home network, with no Hue
  account. Paired once per home with the bridge's button; the key is saved
  as an encrypted `hue-bridge` item. A bridge signs its own certificate,
  so the app remembers the one it saw when pairing and talks to no other.
  State comes live from the bridge's event stream.
- **The adapter interface:** each way of reaching devices (Matter, Home
  Assistant, Hue, Tuya/Smart Life, Shelly, Switcher) is one adapter behind
  `DeviceAdapter`. The ones not built yet are listed under "Add a device"
  as coming soon.

Not built yet: Thread devices, checking devices against the official list
of Matter manufacturers, the Shelly and Switcher adapters, sharing a home
with family, and reaching the home from outside through an encrypted relay
to a hub in the home.

## Privacy

Like every Zero-Trust app, it is zero-knowledge: your data is encrypted on
your device, with keys made from your password, before anything is sent.
The server stores only ciphertext and your password itself is never
sent, so neither we nor anyone who breaks into the server can read your
data. The recovery key shown at sign-up is the only way back in if you
forget the password. How the keys work:
[Zero-Trust-Core](https://github.com/EdoSag/Zero-Trust-Core#key-hierarchy) and
[zerotrust.bz/security](https://zerotrust.bz/security/).

- Homes, rooms, devices, scenes, Matter keys, Tuya local keys, the Hue
  bridge key and the Home Assistant token are encrypted items in the
  account. A device's address is inside the encrypted item.
- Devices are reached on the home network. The one exception is "Link
  Smart Life", a one-time sign-in to Tuya's cloud to read local keys, after
  which the app signs out again.
- The Device Controls panel and the widget are off by default. When on,
  only names and kinds are kept for them on the phone, sealed with a key in
  the Android Keystore; a tap is carried out after the app is unlocked.
- Scenes lock doors but never unlock them, and unlocking always asks first.

## One account, one core

One Zero-Trust account opens every app in the suite. Sign-in, unlock
(fingerprint or face, auto-lock), the recovery key, settings, the look,
sync and languages come from
[Zero-Trust-Core](https://github.com/EdoSag/Zero-Trust-Core), so they work
the same in every app. Accounts made before the core still sign in and
see their data.

## Install

Android: get the latest signed APK from this repository's
[Releases](https://github.com/EdoSag/Zero-Trust-Home/releases/latest),
or from [zerotrust.bz/install](https://zerotrust.bz/install/#home),
which also shows each file's SHA-256, the signing fingerprint and an
Obtainium link. GitHub Releases are the main way the apps are published.

Builds from GitHub check for a newer release themselves (Settings > About,
one anonymous request a day, can be turned off). Every Zero-Trust app is signed
with the same key, and Android only installs an update signed with it.

## Languages

English and Hebrew, with right-to-left layout. Choose under
Settings > Appearance > Language.

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

## Build from source

Flutter 3.47.9, the version CI pins (3.50 deprecates `material.dart` and
fails analyze).

First create a file named `.env` in the project folder. It is not committed
(CI writes its own) and it is bundled into the APK, so it holds public client
values only, never a service-role key:

```
SUPABASE_URL=https://<project>.supabase.co
SUPABASE_ANON_KEY=<publishable key>
```

Then:

```bash
flutter pub get
dart run zt_release_checks --app home   # shared release checks
flutter analyze && flutter test test/
flutter run
```

Never add `cryptography_flutter`: it breaks the core's key derivation and
sign-in fails.

## Branches and releases

Work happens on `Dev`: pull requests target `Dev`, never `main`, and get a
test build. A release is one `Dev` → `main` pull request. Every push to
`main` runs the suite's release checks, builds a signed APK and a Google Play bundle
and publishes them as a GitHub Release named "Zero-Trust Home"
(`.github/workflows/android-apk.yml`). The workflow needs the repository
secrets `ANDROID_KEYSTORE_BASE64` and `ANDROID_KEYSTORE_PASSWORD`, the
keystore shared by all Zero-Trust apps.

## Support and security

- Help centre: [zerotrust.bz/help](https://zerotrust.bz/help/). Questions and
  account deletion: support@zerotrust.bz.
- Security problems: please report them privately to cyber@zerotrust.bz. What
  the encryption does and doesn't protect against is on
  [zerotrust.bz/security](https://zerotrust.bz/security/).
- [Privacy policy](https://zerotrust.bz/privacy/) and
  [terms](https://zerotrust.bz/terms/).

## License

Copyright (C) 2026 Edo Sagron (https://zerotrust.bz)

Zero-Trust is open source under the [GNU Affero General Public License v3.0](LICENSE)
(AGPL-3.0-only), the same licence Signal uses.

- You may use, study, change and share the code, including in your own projects.
- If you share a changed version, or run it for other people over a network, you must
  publish your full source code under the same licence.
- This program comes with no warranty; see the licence for details.

Third-party libraries keep their own licences; the app lists them under
Settings > Open-source licences.

### Name and logo

The AGPL covers the code, not the brand. "Zero-Trust", "ZT", the app names and icons are
reserved. If you publish a fork, give it a different name and icon so nobody mistakes it
for an official Zero-Trust app.

### Servers

The official apps use the Zero-Trust servers. A fork must use its own backend (for
example its own Supabase project) and must not connect to the official servers.

### Contributing

Pull requests are welcome. By sending one you agree that your contribution is licensed
under the AGPL-3.0 and that the copyright holder may also license it under other terms,
including commercially. This keeps the project able to offer paid plans and other licences.
