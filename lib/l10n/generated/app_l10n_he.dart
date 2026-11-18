// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_l10n.dart';

// ignore_for_file: type=lint

/// The translations for Hebrew (`he`).
class AppL10nHe extends AppL10n {
  AppL10nHe([String locale = 'he']) : super(locale);

  @override
  String get appTitle => 'ZT Home';

  @override
  String get settings => 'הגדרות';

  @override
  String get cancel => 'ביטול';

  @override
  String get save => 'שמירה';

  @override
  String get delete => 'מחיקה';

  @override
  String get rename => 'שינוי שם';

  @override
  String get add => 'הוספה';

  @override
  String get name => 'שם';

  @override
  String get setupTitle => 'הגדרת הבית';

  @override
  String get setupBody =>
      'נותנים שם לבית ובוחרים את החדרים שבו. אפשר לשנות את שניהם אחר כך.';

  @override
  String get setupStart => 'להגדרת הבית';

  @override
  String get homeName => 'שם הבית';

  @override
  String get defaultHomeName => 'הבית שלי';

  @override
  String get pickRooms => 'אילו חדרים יש בו?';

  @override
  String get createHome => 'יצירת הבית';

  @override
  String get roomLiving => 'סלון';

  @override
  String get roomKitchen => 'מטבח';

  @override
  String get roomBedroom => 'חדר שינה';

  @override
  String get roomBathroom => 'חדר רחצה';

  @override
  String get roomOffice => 'חדר עבודה';

  @override
  String get roomKids => 'חדר ילדים';

  @override
  String get roomHallway => 'מסדרון';

  @override
  String get roomBalcony => 'מרפסת';

  @override
  String get roomGarden => 'גינה';

  @override
  String get roomGarage => 'חניה';

  @override
  String get roomOther => 'חדר אחר';

  @override
  String get addDevice => 'הוספת מכשיר';

  @override
  String get addRoom => 'הוספת חדר';

  @override
  String get roomName => 'שם החדר';

  @override
  String get roomType => 'סוג החדר';

  @override
  String get noDevicesTitle => 'אין עדיין מכשירים';

  @override
  String get noDevicesBody =>
      'אפשר להוסיף תאורה, שקעים וחיישנים ולשלוט בהם מכאן.';

  @override
  String get favourites => 'מועדפים';

  @override
  String get noRoom => 'ללא חדר';

  @override
  String get stateOn => 'פועל';

  @override
  String get stateOff => 'כבוי';

  @override
  String get stateUnreachable => 'לא מגיב';

  @override
  String get stateUnsupported => 'נדרשת גרסה חדשה יותר';

  @override
  String get deviceRoom => 'חדר';

  @override
  String get deviceFavourite => 'הצגה במועדפים';

  @override
  String get removeDevice => 'הסרת המכשיר';

  @override
  String get deleteRoom => 'מחיקת החדר';

  @override
  String get renameRoom => 'שינוי שם החדר';

  @override
  String get roomEmptyTitle => 'אין עדיין מכשירים בחדר';

  @override
  String get roomEmptyBody =>
      'אפשר להוסיף מכשיר, או להעביר לכאן מכשיר קיים דרך הפרטים שלו.';

  @override
  String get homes => 'בתים';

  @override
  String get manageHomes => 'ניהול בתים';

  @override
  String get addHome => 'הוספת בית';

  @override
  String get renameHome => 'שינוי שם הבית';

  @override
  String get deleteHome => 'מחיקת הבית';

  @override
  String get addDeviceIntro =>
      'בוחרים איך המכשיר מתחבר. ZT Home מדבר עם המכשירים ישירות ברשת הביתית בכל מקום שהמכשיר מאפשר זאת.';

  @override
  String get connMatter => 'Matter';

  @override
  String get connMatterBody =>
      'מכשירים עם הלוגו של Matter, מכל יצרן, כולל מכשירים שכבר נמצאים ב-Google Home או ב-Apple Home.';

  @override
  String get connHa => 'Home Assistant';

  @override
  String get connHaBody =>
      'כל מה ש-Home Assistant שלך כבר שולט בו: Zigbee,‏ Z-Wave ועוד.';

  @override
  String get connHue => 'Philips Hue';

  @override
  String get connHueBody => 'תאורה וחיישנים שמחוברים ל-Hue Bridge.';

  @override
  String get connTuya => 'Tuya / Smart Life';

  @override
  String get connTuyaBody =>
      'שקעים, תאורה ומתגים שהוגדרו באפליקציית Smart Life או Tuya.';

  @override
  String get connShelly => 'Shelly';

  @override
  String get connShellyBody => 'ממסרים, שקעים וחיישנים של Shelly.';

  @override
  String get connSwitcher => 'Switcher';

  @override
  String get connSwitcherBody => 'מתגי דוד ושקעים של Switcher.';

  @override
  String get comingSoon => 'בקרוב';

  @override
  String deviceCount(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n מכשירים',
      two: '2 מכשירים',
      one: 'מכשיר אחד',
      zero: 'אין מכשירים',
    );
    return '$_temp0';
  }

  @override
  String commandFailed(String name) {
    return 'אין תגובה מ$name. אפשר לנסות שוב.';
  }

  @override
  String removeDeviceBody(String name) {
    return '$name יוסר מהבית הזה. המכשיר עצמו לא מתאפס.';
  }

  @override
  String deleteRoomBody(String name) {
    return '$name יימחק. המכשירים שבו נשארים בבית, ללא חדר.';
  }

  @override
  String deleteHomeBody(String name) {
    return '$name יימחק עם החדרים והמכשירים שבו, בכל הטלפונים שלך. המכשירים עצמם לא מתאפסים.';
  }
}
