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
    return '$name is deleted with its rooms and devices, on all your phones. The devices themselves aren\'t reset.';
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
      'For now the device has to be on your Wi-Fi already: set it up in its own app, or in Google Home or Apple Home. There, choose to connect it to another app or to turn on pairing mode, and you get a setup code. Brand-new devices, straight out of the box, come in a later version.';

  @override
  String get matterCode => 'Setup code';

  @override
  String get matterCodeHint =>
      'The 11 or 21 digits, or the text of the QR code (it starts with MT:). The phone has to be on the same Wi-Fi as the device.';

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
}
