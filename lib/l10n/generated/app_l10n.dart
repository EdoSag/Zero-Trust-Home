import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_l10n_en.dart';
import 'app_l10n_he.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppL10n
/// returned by `AppL10n.of(context)`.
///
/// Applications need to include `AppL10n.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_l10n.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppL10n.localizationsDelegates,
///   supportedLocales: AppL10n.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppL10n.supportedLocales
/// property.
abstract class AppL10n {
  AppL10n(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppL10n of(BuildContext context) {
    return Localizations.of<AppL10n>(context, AppL10n)!;
  }

  static const LocalizationsDelegate<AppL10n> delegate = _AppL10nDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('he'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'ZT Home'**
  String get appTitle;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @rename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get rename;

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @name.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get name;

  /// No description provided for @setupTitle.
  ///
  /// In en, this message translates to:
  /// **'Set up your home'**
  String get setupTitle;

  /// No description provided for @setupBody.
  ///
  /// In en, this message translates to:
  /// **'Name your home and pick its rooms. You can change both later.'**
  String get setupBody;

  /// No description provided for @setupStart.
  ///
  /// In en, this message translates to:
  /// **'Set up my home'**
  String get setupStart;

  /// No description provided for @homeName.
  ///
  /// In en, this message translates to:
  /// **'Home name'**
  String get homeName;

  /// No description provided for @defaultHomeName.
  ///
  /// In en, this message translates to:
  /// **'My home'**
  String get defaultHomeName;

  /// No description provided for @pickRooms.
  ///
  /// In en, this message translates to:
  /// **'Which rooms does it have?'**
  String get pickRooms;

  /// No description provided for @createHome.
  ///
  /// In en, this message translates to:
  /// **'Create home'**
  String get createHome;

  /// No description provided for @roomLiving.
  ///
  /// In en, this message translates to:
  /// **'Living room'**
  String get roomLiving;

  /// No description provided for @roomKitchen.
  ///
  /// In en, this message translates to:
  /// **'Kitchen'**
  String get roomKitchen;

  /// No description provided for @roomBedroom.
  ///
  /// In en, this message translates to:
  /// **'Bedroom'**
  String get roomBedroom;

  /// No description provided for @roomBathroom.
  ///
  /// In en, this message translates to:
  /// **'Bathroom'**
  String get roomBathroom;

  /// No description provided for @roomOffice.
  ///
  /// In en, this message translates to:
  /// **'Office'**
  String get roomOffice;

  /// No description provided for @roomKids.
  ///
  /// In en, this message translates to:
  /// **'Kids\' room'**
  String get roomKids;

  /// No description provided for @roomHallway.
  ///
  /// In en, this message translates to:
  /// **'Hallway'**
  String get roomHallway;

  /// No description provided for @roomBalcony.
  ///
  /// In en, this message translates to:
  /// **'Balcony'**
  String get roomBalcony;

  /// No description provided for @roomGarden.
  ///
  /// In en, this message translates to:
  /// **'Garden'**
  String get roomGarden;

  /// No description provided for @roomGarage.
  ///
  /// In en, this message translates to:
  /// **'Garage'**
  String get roomGarage;

  /// No description provided for @roomOther.
  ///
  /// In en, this message translates to:
  /// **'Other room'**
  String get roomOther;

  /// No description provided for @addDevice.
  ///
  /// In en, this message translates to:
  /// **'Add a device'**
  String get addDevice;

  /// No description provided for @addRoom.
  ///
  /// In en, this message translates to:
  /// **'Add a room'**
  String get addRoom;

  /// No description provided for @roomName.
  ///
  /// In en, this message translates to:
  /// **'Room name'**
  String get roomName;

  /// No description provided for @roomType.
  ///
  /// In en, this message translates to:
  /// **'Type of room'**
  String get roomType;

  /// No description provided for @noDevicesTitle.
  ///
  /// In en, this message translates to:
  /// **'No devices yet'**
  String get noDevicesTitle;

  /// No description provided for @noDevicesBody.
  ///
  /// In en, this message translates to:
  /// **'Add your lights, plugs and sensors to control them from here.'**
  String get noDevicesBody;

  /// No description provided for @favourites.
  ///
  /// In en, this message translates to:
  /// **'Favourites'**
  String get favourites;

  /// No description provided for @noRoom.
  ///
  /// In en, this message translates to:
  /// **'Not in a room'**
  String get noRoom;

  /// No description provided for @stateOn.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get stateOn;

  /// No description provided for @stateOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get stateOff;

  /// No description provided for @stateUnreachable.
  ///
  /// In en, this message translates to:
  /// **'Not responding'**
  String get stateUnreachable;

  /// No description provided for @stateUnsupported.
  ///
  /// In en, this message translates to:
  /// **'Needs a newer ZT Home'**
  String get stateUnsupported;

  /// No description provided for @deviceRoom.
  ///
  /// In en, this message translates to:
  /// **'Room'**
  String get deviceRoom;

  /// No description provided for @deviceFavourite.
  ///
  /// In en, this message translates to:
  /// **'Show in Favourites'**
  String get deviceFavourite;

  /// No description provided for @removeDevice.
  ///
  /// In en, this message translates to:
  /// **'Remove device'**
  String get removeDevice;

  /// No description provided for @deleteRoom.
  ///
  /// In en, this message translates to:
  /// **'Delete room'**
  String get deleteRoom;

  /// No description provided for @renameRoom.
  ///
  /// In en, this message translates to:
  /// **'Rename room'**
  String get renameRoom;

  /// No description provided for @roomEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing in this room yet'**
  String get roomEmptyTitle;

  /// No description provided for @roomEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Add a device, or move one here from its details.'**
  String get roomEmptyBody;

  /// No description provided for @homes.
  ///
  /// In en, this message translates to:
  /// **'Homes'**
  String get homes;

  /// No description provided for @manageHomes.
  ///
  /// In en, this message translates to:
  /// **'Manage homes'**
  String get manageHomes;

  /// No description provided for @addHome.
  ///
  /// In en, this message translates to:
  /// **'Add a home'**
  String get addHome;

  /// No description provided for @renameHome.
  ///
  /// In en, this message translates to:
  /// **'Rename home'**
  String get renameHome;

  /// No description provided for @deleteHome.
  ///
  /// In en, this message translates to:
  /// **'Delete home'**
  String get deleteHome;

  /// No description provided for @addDeviceIntro.
  ///
  /// In en, this message translates to:
  /// **'Pick how the device connects. ZT Home talks to devices directly over your home network wherever the device allows it.'**
  String get addDeviceIntro;

  /// No description provided for @connMatter.
  ///
  /// In en, this message translates to:
  /// **'Matter'**
  String get connMatter;

  /// No description provided for @connMatterBody.
  ///
  /// In en, this message translates to:
  /// **'Devices with the Matter logo, from any brand, including ones already in Google Home or Apple Home.'**
  String get connMatterBody;

  /// No description provided for @connHa.
  ///
  /// In en, this message translates to:
  /// **'Home Assistant'**
  String get connHa;

  /// No description provided for @connHaBody.
  ///
  /// In en, this message translates to:
  /// **'Everything your Home Assistant already controls: Zigbee, Z-Wave and more.'**
  String get connHaBody;

  /// No description provided for @connHue.
  ///
  /// In en, this message translates to:
  /// **'Philips Hue'**
  String get connHue;

  /// No description provided for @connHueBody.
  ///
  /// In en, this message translates to:
  /// **'Lights and sensors on a Hue Bridge.'**
  String get connHueBody;

  /// No description provided for @connTuya.
  ///
  /// In en, this message translates to:
  /// **'Tuya / Smart Life'**
  String get connTuya;

  /// No description provided for @connTuyaBody.
  ///
  /// In en, this message translates to:
  /// **'Plugs, lights and switches set up with the Smart Life or Tuya app.'**
  String get connTuyaBody;

  /// No description provided for @connShelly.
  ///
  /// In en, this message translates to:
  /// **'Shelly'**
  String get connShelly;

  /// No description provided for @connShellyBody.
  ///
  /// In en, this message translates to:
  /// **'Shelly relays, plugs and sensors.'**
  String get connShellyBody;

  /// No description provided for @connSwitcher.
  ///
  /// In en, this message translates to:
  /// **'Switcher'**
  String get connSwitcher;

  /// No description provided for @connSwitcherBody.
  ///
  /// In en, this message translates to:
  /// **'Switcher water heater switches and plugs.'**
  String get connSwitcherBody;

  /// No description provided for @comingSoon.
  ///
  /// In en, this message translates to:
  /// **'Coming soon'**
  String get comingSoon;

  /// No description provided for @deviceCount.
  ///
  /// In en, this message translates to:
  /// **'{n, plural, =0{No devices} =1{1 device} other{{n} devices}}'**
  String deviceCount(int n);

  /// No description provided for @commandFailed.
  ///
  /// In en, this message translates to:
  /// **'{name} didn\'t respond. Try again.'**
  String commandFailed(String name);

  /// No description provided for @removeDeviceBody.
  ///
  /// In en, this message translates to:
  /// **'{name} is removed from this home. The device itself isn\'t reset.'**
  String removeDeviceBody(String name);

  /// No description provided for @deleteRoomBody.
  ///
  /// In en, this message translates to:
  /// **'{name} is deleted. Its devices stay in the home, without a room.'**
  String deleteRoomBody(String name);

  /// No description provided for @deleteHomeBody.
  ///
  /// In en, this message translates to:
  /// **'{name} is deleted with its rooms and devices, on all your phones. The devices themselves aren\'t reset.'**
  String deleteHomeBody(String name);
}

class _AppL10nDelegate extends LocalizationsDelegate<AppL10n> {
  const _AppL10nDelegate();

  @override
  Future<AppL10n> load(Locale locale) {
    return SynchronousFuture<AppL10n>(lookupAppL10n(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'he'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppL10nDelegate old) => false;
}

AppL10n lookupAppL10n(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppL10nEn();
    case 'he':
      return AppL10nHe();
  }

  throw FlutterError(
    'AppL10n.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
