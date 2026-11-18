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
}
