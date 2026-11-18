import 'package:flutter/foundation.dart';

/// A place with rooms and devices: a flat, a house, an office.
@immutable
class Home {
  const Home({required this.id, required this.name, required this.createdAt});

  final String id;
  final String name;

  /// Milliseconds since the epoch; homes are listed oldest first.
  final int createdAt;

  Home copyWith({String? name}) =>
      Home(id: id, name: name ?? this.name, createdAt: createdAt);

  Map<String, dynamic> toJson() => {'name': name, 'createdAt': createdAt};

  static Home fromJson(String id, Map<String, dynamic> json) => Home(
    id: id,
    name: json['name'] as String? ?? '',
    createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
  );
}

/// What a room is, for its icon and its suggested name.
enum RoomKind {
  living,
  kitchen,
  bedroom,
  bathroom,
  office,
  kids,
  hallway,
  balcony,
  garden,
  garage,
  other;

  static RoomKind parse(Object? name) => RoomKind.values.firstWhere(
    (k) => k.name == name,
    orElse: () => RoomKind.other,
  );
}

@immutable
class Room {
  const Room({
    required this.id,
    required this.homeId,
    required this.name,
    this.kind = RoomKind.other,
    this.order = 0,
  });

  final String id;
  final String homeId;
  final String name;
  final RoomKind kind;

  /// Position in the home; lower comes first.
  final int order;

  Room copyWith({String? name, RoomKind? kind, int? order}) => Room(
    id: id,
    homeId: homeId,
    name: name ?? this.name,
    kind: kind ?? this.kind,
    order: order ?? this.order,
  );

  Map<String, dynamic> toJson() => {
    'homeId': homeId,
    'name': name,
    'kind': kind.name,
    'order': order,
  };

  static Room fromJson(String id, Map<String, dynamic> json) => Room(
    id: id,
    homeId: json['homeId'] as String? ?? '',
    name: json['name'] as String? ?? '',
    kind: RoomKind.parse(json['kind']),
    order: (json['order'] as num?)?.toInt() ?? 0,
  );
}
