// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_l10n.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppL10nEn extends AppL10n {
  AppL10nEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'ZT Home';

  @override
  String get settings => 'Settings';

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get delete => 'Delete';

  @override
  String get rename => 'Rename';

  @override
  String get add => 'Add';

  @override
  String get name => 'Name';

  @override
  String get setupTitle => 'Set up your home';

  @override
  String get setupBody =>
      'Name your home and pick its rooms. You can change both later.';

  @override
  String get setupStart => 'Set up my home';

  @override
  String get homeName => 'Home name';

  @override
  String get defaultHomeName => 'My home';

  @override
  String get pickRooms => 'Which rooms does it have?';

  @override
  String get createHome => 'Create home';

  @override
  String get roomLiving => 'Living room';

  @override
  String get roomKitchen => 'Kitchen';

  @override
  String get roomBedroom => 'Bedroom';

  @override
  String get roomBathroom => 'Bathroom';

  @override
  String get roomOffice => 'Office';

  @override
  String get roomKids => 'Kids\' room';

  @override
  String get roomHallway => 'Hallway';

  @override
  String get roomBalcony => 'Balcony';

  @override
  String get roomGarden => 'Garden';

  @override
  String get roomGarage => 'Garage';

  @override
  String get roomOther => 'Other room';

  @override
  String get addDevice => 'Add a device';

  @override
  String get addRoom => 'Add a room';

  @override
  String get roomName => 'Room name';

  @override
  String get roomType => 'Type of room';

  @override
  String get noDevicesTitle => 'No devices yet';

  @override
  String get noDevicesBody =>
      'Add your lights, plugs and sensors to control them from here.';

  @override
  String get favourites => 'Favourites';

  @override
  String get noRoom => 'Not in a room';

  @override
  String get stateOn => 'On';

  @override
  String get stateOff => 'Off';

  @override
  String get stateUnreachable => 'Not responding';

  @override
  String get stateUnsupported => 'Needs a newer ZT Home';

  @override
  String get deviceRoom => 'Room';

  @override
  String get deviceFavourite => 'Show in Favourites';

  @override
  String get removeDevice => 'Remove device';

  @override
  String get deleteRoom => 'Delete room';

  @override
  String get renameRoom => 'Rename room';

  @override
  String get roomEmptyTitle => 'Nothing in this room yet';

  @override
  String get roomEmptyBody =>
      'Add a device, or move one here from its details.';

  @override
  String get homes => 'Homes';

  @override
  String get manageHomes => 'Manage homes';

  @override
  String get addHome => 'Add a home';

  @override
  String get renameHome => 'Rename home';

  @override
  String get deleteHome => 'Delete home';

  @override
  String get addDeviceIntro =>
      'Pick how the device connects. ZT Home talks to devices directly over your home network wherever the device allows it.';

  @override
  String get connMatter => 'Matter';

  @override
  String get connMatterBody =>
      'Devices with the Matter logo, from any brand, including ones already in Google Home or Apple Home.';

  @override
  String get connHa => 'Home Assistant';

  @override
  String get connHaBody =>
      'Everything your Home Assistant already controls: Zigbee, Z-Wave and more.';

  @override
  String get connHue => 'Philips Hue';

  @override
  String get connHueBody => 'Lights and sensors on a Hue Bridge.';

  @override
  String get connTuya => 'Tuya / Smart Life';

  @override
  String get connTuyaBody =>
      'Plugs, lights and switches set up with the Smart Life or Tuya app.';

  @override
  String get connShelly => 'Shelly';

  @override
  String get connShellyBody => 'Shelly relays, plugs and sensors.';

  @override
  String get connSwitcher => 'Switcher';

  @override
  String get connSwitcherBody => 'Switcher water heater switches and plugs.';

  @override
  String get comingSoon => 'Coming soon';

  @override
  String deviceCount(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n devices',
      one: '1 device',
      zero: 'No devices',
    );
    return '$_temp0';
  }

  @override
  String commandFailed(String name) {
    return '$name didn\'t respond. Try again.';
  }

  @override
  String removeDeviceBody(String name) {
    return '$name is removed from this home. The device itself isn\'t reset.';
  }

  @override
  String deleteRoomBody(String name) {
    return '$name is deleted. Its devices stay in the home, without a room.';
  }

  @override
  String deleteHomeBody(String name) {
    return '$name is deleted with its rooms and devices, on all your phones. Matter devices are let go so they can be added again; other devices aren\'t reset.';
  }

  @override
  String get copy => 'Copy';

  @override
  String get copied => 'Copied';

  @override
  String get powerNow => 'Power now';

  @override
  String get tuyaIntro =>
      'Devices that are set up in the Smart Life or Tuya app. ZT Home then talks to them directly over your Wi-Fi, without Tuya\'s servers.';

  @override
  String get tuyaSearching => 'Looking for devices on your Wi-Fi…';

  @override
  String get tuyaSearchHint =>
      'The phone has to be on the same Wi-Fi as the device. A device can take up to 10 seconds to show up.';

  @override
  String get tuyaAlreadyAdded => 'Already added';

  @override
  String get tuyaManual => 'Enter the address by hand';

  @override
  String get tuyaPairTitle => 'Connect the device';

  @override
  String get tuyaDefaultName => 'Smart plug';

  @override
  String get tuyaIp => 'IP address';

  @override
  String get tuyaDeviceId => 'Device ID';

  @override
  String get tuyaVersion => 'Protocol version';

  @override
  String get tuyaLocalKey => 'Local key';

  @override
  String get tuyaLocalKeyHelp => 'Where do I find the local key?';

  @override
  String get tuyaKeyLength => 'A local key has 16 characters.';

  @override
  String get fieldRequired => 'Required';

  @override
  String get tuyaConnect => 'Connect';

  @override
  String get tuyaErrKey =>
      'The device didn\'t accept this key. Check the key, and the protocol version if you entered it by hand. The key changes when a device is removed and set up again in Smart Life.';

  @override
  String get tuyaKeyHelpTitle => 'Finding the local key';

  @override
  String get tuyaKeyHelpBody =>
      'Each device has a secret local key, given to it when it is set up in the Smart Life app. ZT Home needs it once, to talk to the device directly. Tuya only shows it on its developer site:\n\n1. Sign up for free at iot.tuya.com and create a cloud project.\n2. In the project, open Devices, choose Link App Account and scan the code with the Smart Life app.\n3. In API Explorer, run \"Query Device Details\" with the Device ID below, and copy \"local_key\" from the answer.\n\nThe key is saved encrypted in your ZT account. It never leaves your devices unencrypted.';

  @override
  String get close => 'Close';

  @override
  String get showKey => 'Show the key';

  @override
  String get hideKey => 'Hide the key';

  @override
  String stateWithPower(String state, String watts) {
    return '$state · $watts W';
  }

  @override
  String watts(String watts) {
    return '$watts W';
  }

  @override
  String tuyaFound(String ip) {
    return 'Device at $ip';
  }

  @override
  String tuyaFoundDetails(String tail, String version) {
    return 'ID ending in $tail · protocol $version';
  }

  @override
  String tuyaTooOld(String version) {
    return 'Protocol $version isn\'t supported yet';
  }

  @override
  String tuyaErrUnreachable(String ip) {
    return 'No answer from $ip. Check that the device is plugged in and on the same Wi-Fi as this phone.';
  }

  @override
  String deviceAdded(String name) {
    return '$name added';
  }

  @override
  String get matterAddTitle => 'Add a Matter device';

  @override
  String get matterIntro =>
      'A device already set up in another app (its own app, Google Home or Apple Home): there, choose to share it with another app or to turn on pairing mode, and enter the code you get. The phone has to be on the same Wi-Fi as the device.';

  @override
  String get matterCode => 'Setup code';

  @override
  String get matterCodeHint =>
      'The 11 or 21 digits, or the text of the QR code (it starts with MT:).';

  @override
  String get matterCodeInvalid =>
      'This isn\'t a Matter setup code. It is 11 or 21 digits, or text that starts with MT:';

  @override
  String get matterCodeTypo =>
      'One of the digits is wrong. Check the code and type it again.';

  @override
  String get matterCodeTooNew =>
      'This code is from a newer kind of Matter device that this version can\'t add yet.';

  @override
  String get matterDefaultName => 'Matter device';

  @override
  String get matterAdd => 'Add';

  @override
  String get matterAdding =>
      'Looking for the device and adding it to your home. This can take up to a minute.';

  @override
  String get matterErrUnsupported =>
      'This phone can\'t run Matter. It needs a 64-bit ARM phone, which most phones from recent years are.';

  @override
  String get matterErrNotFound =>
      'The device wasn\'t found. Check that it is in pairing mode, that the code is the one it gave now (codes expire after a few minutes), and that this phone is on the same Wi-Fi.';

  @override
  String matterErrFailed(String detail) {
    return 'The device couldn\'t be added. $detail';
  }

  @override
  String get matterErrNeedsSync =>
      'Connect to the internet and try again. The home\'s Matter keys are saved to your account before the first device is added, so your other phones get the same ones.';

  @override
  String get matterErrKeys =>
      'The home\'s Matter keys couldn\'t be read. Sync this phone and try again.';

  @override
  String get matterKindNew => 'New device';

  @override
  String get matterKindShared => 'Already set up';

  @override
  String get matterIntroNew =>
      'A new device, or one that was reset: plug it in so it is in pairing mode, keep the phone close to it, and scan the QR code on the device or its box. The phone finds it over Bluetooth and gives it your Wi-Fi. Devices that use Thread instead of Wi-Fi can\'t be added yet.';

  @override
  String get matterScan => 'Scan the QR code';

  @override
  String get matterScanNotMatter =>
      'That QR code isn\'t a Matter code. The Matter one is usually next to the Matter logo, on the device or its box.';

  @override
  String get matterWifiName => 'Wi-Fi name';

  @override
  String get matterWifiHint =>
      'The device joins this Wi-Fi. Most devices need a 2.4 GHz network. The password is only given to the device, never saved.';

  @override
  String get matterWifiPassword => 'Wi-Fi password';

  @override
  String get matterShowPassword => 'Show the password';

  @override
  String get matterHidePassword => 'Hide the password';

  @override
  String get matterAddingNew =>
      'Looking for the device, giving it the Wi-Fi and adding it to your home. This can take up to two minutes. Keep the phone close to it.';

  @override
  String get matterErrBluetoothOff =>
      'Turn on Bluetooth to add a new device, then try again.';

  @override
  String get matterErrBluetoothDenied =>
      'ZT Home needs the Nearby devices permission to find a new device over Bluetooth. Allow it in the app\'s settings, then try again.';

  @override
  String get matterErrLocationOff =>
      'Turn on Location to add a new device. On this version of Android, phones can only find Bluetooth devices while Location is on.';

  @override
  String get matterErrNotFoundNew =>
      'The device wasn\'t found. Check that it is in pairing mode (often: just plugged in, or its button held until it blinks), keep the phone close to it, and check the Wi-Fi name and password.';

  @override
  String get tryAgain => 'Try again';

  @override
  String get haIntro =>
      'Connect your Home Assistant once, and pick which of its devices to show here. The app talks to it on your home network; the token is encrypted with the rest of your home.';

  @override
  String get haAddress => 'Home Assistant address';

  @override
  String get haAddressHint =>
      'Use its IP address if homeassistant.local doesn\'t work on this phone.';

  @override
  String get haAddressBad => 'Enter an address like http://192.168.1.10:8123';

  @override
  String get haToken => 'Long-lived access token';

  @override
  String get haTokenHint =>
      'In Home Assistant, open your profile, then Security, and create a long-lived access token at the bottom of the page. Paste it here.';

  @override
  String get haConnect => 'Connect';

  @override
  String get haChangeServer => 'Change address or token';

  @override
  String haConnectedTo(String url) {
    return 'Connected to $url. Pick the devices to show in this home.';
  }

  @override
  String get haNothing =>
      'Home Assistant has no lights, switches, sensors or other devices this app can show yet.';

  @override
  String get haAlreadyAdded => 'Already in this home';

  @override
  String haAdd(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: 'Add $n devices',
      one: 'Add 1 device',
      zero: 'Add devices',
    );
    return '$_temp0';
  }

  @override
  String haAdded(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n devices added',
      one: '1 device added',
    );
    return '$_temp0';
  }

  @override
  String get haErrUnreachable =>
      'Home Assistant didn\'t answer at that address. Check that this phone is on your home Wi-Fi and the address is right.';

  @override
  String get haErrToken =>
      'Home Assistant didn\'t accept the token. Create a new one and paste all of it.';

  @override
  String get haErrNotHa =>
      'Something answered at that address, but it isn\'t Home Assistant. Check the address and port (usually 8123).';

  @override
  String haErrFailed(String detail) {
    return 'Home Assistant refused: $detail';
  }

  @override
  String get stateLocked => 'Locked';

  @override
  String get stateUnlocked => 'Unlocked';

  @override
  String get stateOpen => 'Open';

  @override
  String get stateClosed => 'Closed';

  @override
  String stateOpenPercent(int n) {
    return 'Open $n%';
  }

  @override
  String get stateMotion => 'Motion';

  @override
  String get stateNoMotion => 'No motion';

  @override
  String degrees(String value) {
    return '$value°C';
  }

  @override
  String setTo(String value) {
    return 'set to $value';
  }

  @override
  String percent(int n) {
    return '$n%';
  }

  @override
  String batteryLevel(int n) {
    return 'Battery $n%';
  }

  @override
  String get brightness => 'Brightness';

  @override
  String get fanSpeed => 'Speed';

  @override
  String get position => 'Position';

  @override
  String get open => 'Open';

  @override
  String get lock => 'Lock';

  @override
  String get unlock => 'Unlock';

  @override
  String unlockTitle(String name) {
    return 'Unlock $name?';
  }

  @override
  String get unlockBody =>
      'The door can then be opened by anyone who is there.';

  @override
  String get targetTemperature => 'Set to';

  @override
  String get colder => 'Colder';

  @override
  String get warmer => 'Warmer';

  @override
  String get temperatureNow => 'Temperature';

  @override
  String get humidity => 'Humidity';

  @override
  String get contact => 'Door or window';

  @override
  String get motion => 'Motion';

  @override
  String get energy => 'Energy used';

  @override
  String kwh(String value) {
    return '$value kWh';
  }

  @override
  String get battery => 'Battery';

  @override
  String get scenes => 'Scenes';

  @override
  String get addScene => 'Add scene';

  @override
  String get newScene => 'New scene';

  @override
  String get editScene => 'Edit scene';

  @override
  String get sceneName => 'Scene name';

  @override
  String get sceneNameHint => 'Like Good night or Movie';

  @override
  String get sceneCopyNow => 'Copy how things are now';

  @override
  String get sceneDontChange => 'Don\'t change';

  @override
  String get scenePartOpen => 'Part open';

  @override
  String get sceneSetTemperature => 'Set temperature';

  @override
  String get sceneNeedsName => 'Give the scene a name.';

  @override
  String get sceneNeedsDevice => 'Pick at least one device to change.';

  @override
  String get sceneNoUnlock => 'A scene can lock a door but never unlocks one.';

  @override
  String get sceneEditHint => 'Touch and hold a scene to change it.';

  @override
  String get deleteSceneBody => 'Your devices stay as they are.';

  @override
  String sceneDone(String name) {
    return '$name is set.';
  }

  @override
  String sceneFailed(String name, String devices) {
    return '$name: no answer from $devices.';
  }

  @override
  String deleteSceneTitle(String name) {
    return 'Delete $name?';
  }

  @override
  String get quickControls => 'Controls without opening the app';

  @override
  String get quickControlsBody =>
      'Switch lights, plugs and scenes from the phone\'s device controls. A copy of your devices and their keys stays on this phone only, sealed by Android.';
}
