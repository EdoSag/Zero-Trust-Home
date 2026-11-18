import 'package:flutter_test/flutter_test.dart';
import 'package:zerotrust_home/model/device.dart';
import 'package:zerotrust_home/model/home.dart';

void main() {
  test('a device survives being saved and read back', () {
    const device = HomeDevice(
      id: 'd1',
      homeId: 'h1',
      roomId: 'r1',
      name: 'Desk lamp',
      type: DeviceType.light,
      adapter: 'matter',
      address: {'node': 12, 'endpoint': 1},
      capabilities: {Capability.onOff, Capability.brightness},
      favourite: true,
      createdAt: 5,
    );
    final back = HomeDevice.fromJson('d1', device.toJson());
    expect(back.homeId, 'h1');
    expect(back.roomId, 'r1');
    expect(back.name, 'Desk lamp');
    expect(back.type, DeviceType.light);
    expect(back.adapter, 'matter');
    expect(back.address, {'node': 12, 'endpoint': 1});
    expect(back.capabilities, {Capability.onOff, Capability.brightness});
    expect(back.favourite, isTrue);
    expect(back.createdAt, 5);
  });

  test('a device from a newer version still reads', () {
    final device = HomeDevice.fromJson('d1', {
      'homeId': 'h1',
      'name': 'Robot',
      'type': 'vacuum',
      'adapter': 'matter',
      'capabilities': ['onOff', 'suction'],
    });
    expect(device.type, DeviceType.other);
    expect(device.capabilities, {Capability.onOff});
    expect(device.roomId, isNull);
  });

  test('moving a device out of its room clears the room', () {
    const device = HomeDevice(
      id: 'd',
      homeId: 'h',
      roomId: 'r',
      name: 'n',
      adapter: 'a',
    );
    expect(device.copyWith(roomId: null).roomId, isNull);
    expect(device.copyWith(name: 'x').roomId, 'r');
  });

  test('rooms and homes survive being saved and read back', () {
    const room = Room(
      id: 'r',
      homeId: 'h',
      name: 'Den',
      kind: RoomKind.office,
      order: 3,
    );
    final back = Room.fromJson('r', room.toJson());
    expect(
      (back.homeId, back.name, back.kind, back.order),
      ('h', 'Den', RoomKind.office, 3),
    );
    expect(Room.fromJson('r', {'kind': 'sauna'}).kind, RoomKind.other);
    final home = Home.fromJson(
      'h',
      const Home(id: 'h', name: 'Flat', createdAt: 9).toJson(),
    );
    expect((home.name, home.createdAt), ('Flat', 9));
  });

  test('only settable capabilities are writable', () {
    expect(Capability.onOff.writable, isTrue);
    expect(Capability.targetTemperature.writable, isTrue);
    expect(Capability.temperature.writable, isFalse);
    expect(Capability.power.writable, isFalse);
  });
}
