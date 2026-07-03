import 'package:flutter_test/flutter_test.dart';
import 'package:field_tracker/models/location_point.dart';
import 'package:field_tracker/models/user.dart';

void main() {
  group('LocationPoint — 序列化/反序列化', () {
    test('全字段 toJson/fromJson 往返一致', () {
      final original = LocationPoint(
        userId: 'u001',
        latitude: 39.909,
        longitude: 116.397,
        accuracy: 10.5,
        speed: 1.2,
        altitude: 50.0,
        bearing: 180.0,
        battery: 0.85,
        timestamp: DateTime.parse('2026-07-03T10:00:00.000Z'),
      );
      final json = original.toJson();
      final restored = LocationPoint.fromJson(json);
      expect(restored.userId, 'u001');
      expect(restored.latitude, 39.909);
      expect(restored.longitude, 116.397);
      expect(restored.accuracy, 10.5);
      expect(restored.speed, 1.2);
      expect(restored.altitude, 50.0);
      expect(restored.bearing, 180.0);
      expect(restored.battery, 0.85);
      expect(restored.timestamp.toIso8601String(), '2026-07-03T10:00:00.000Z');
    });

    test('所有可选字段缺失（fromJson）', () {
      final json = {
        'userId': 'u002',
        'lat': 30.0,
        'lng': 120.0,
      };
      final point = LocationPoint.fromJson(json);
      expect(point.userId, 'u002');
      expect(point.latitude, 30.0);
      expect(point.longitude, 120.0);
      expect(point.accuracy, isNull);
      expect(point.speed, isNull);
      expect(point.altitude, isNull);
      expect(point.bearing, isNull);
      expect(point.battery, isNull);
      expect(point.timestamp, isNotNull); // 默认值为 DateTime.now()
    });

    test('fromJson 处理 null 字段', () {
      final json = {
        'userId': 'u003',
        'lat': 30.0,
        'lng': 120.0,
        'accuracy': null,
        'speed': null,
        'altitude': null,
        'bearing': null,
        'battery': null,
        'timestamp': null,
      };
      final point = LocationPoint.fromJson(json);
      expect(point.accuracy, isNull);
      expect(point.timestamp, isNotNull); // null timestamp → DateTime.now()
    });

    test('经纬度边界值 — 南极点/本初子午线', () {
      final point = LocationPoint(
        userId: 'u_border_1',
        latitude: -90.0,
        longitude: 0.0,
      );
      expect(point.latitude, -90.0);
      expect(point.longitude, 0.0);
      final json = point.toJson();
      expect(json['lat'], -90.0);
      expect(json['lng'], 0.0);
    });

    test('经纬度边界值 — 北极点/180度', () {
      final point = LocationPoint(
        userId: 'u_border_2',
        latitude: 90.0,
        longitude: 180.0,
      );
      expect(point.latitude, 90.0);
      expect(point.longitude, 180.0);
      final json = point.toJson();
      expect(json['lat'], 90.0);
      expect(json['lng'], 180.0);
    });

    test('fromJson 处理字符串数值', () {
      // 某些定位 SDK 可能返回字符串类型
      final json = {
        'userId': 'u_str',
        'lat': '39.909',
        'lng': '116.397',
        'accuracy': '10.5',
      };
      final point = LocationPoint.fromJson(json);
      expect(point.latitude, 39.909);
      expect(point.longitude, 116.397);
      expect(point.accuracy, 10.5);
    });

    test('超大数值精度不丢失', () {
      final point = LocationPoint(
        userId: 'u_precise',
        latitude: 39.9087654321,
        longitude: 116.397654321,
        accuracy: 0.0001,
        speed: 0.000001,
      );
      final json = point.toJson();
      final restored = LocationPoint.fromJson(json);
      // double 精度 15 位可靠
      expect(restored.latitude, closeTo(39.9087654321, 1e-12));
      expect(restored.longitude, closeTo(116.397654321, 1e-12));
      expect(restored.accuracy, closeTo(0.0001, 1e-12));
      expect(restored.speed, closeTo(0.000001, 1e-12));
    });

    test('fromJson 处理空字符串 userId', () {
      final json = {
        'userId': '',
        'lat': 0,
        'lng': 0,
      };
      final point = LocationPoint.fromJson(json);
      expect(point.userId, isEmpty);
    });

    test('fromJson 处理无效时间戳 — 回退到 DateTime.now()', () {
      final json = {
        'userId': 'u_bad_ts',
        'lat': 30.0,
        'lng': 120.0,
        'timestamp': 'not-a-date',
      };
      final point = LocationPoint.fromJson(json);
      expect(point.timestamp, isNotNull);
      // 应该是接近当前时间
      final diff = DateTime.now().difference(point.timestamp);
      expect(diff.inSeconds, lessThan(5));
    });
  });

  group('LocationPoint — toDbMap', () {
    test('包含 uploaded=0 标记', () {
      final point = LocationPoint(userId: 'u1', latitude: 30.0, longitude: 120.0);
      final dbMap = point.toDbMap();
      expect(dbMap['uploaded'], 0);
      expect(dbMap['user_id'], 'u1');
      expect(dbMap['latitude'], 30.0);
      expect(dbMap['longitude'], 120.0);
      expect(dbMap['recorded_at'], isA<String>());
    });

    test('不包含 id/uploaded 外部字段', () {
      final point = LocationPoint(userId: 'u1', latitude: 30.0, longitude: 120.0);
      final dbMap = point.toDbMap();
      expect(dbMap.containsKey('id'), false); // autoincrement
    });
  });

  group('LocationPoint — toString', () {
    test('包含经纬度格式', () {
      final point = LocationPoint(userId: 'u1', latitude: 39.909, longitude: 116.397);
      final str = point.toString();
      expect(str, contains('39.909'));
      expect(str, contains('116.397'));
      expect(str, startsWith('LocationPoint('));
    });

    test('精度保留6位小数', () {
      final point = LocationPoint(userId: 'u1', latitude: 39.123456789, longitude: 116.987654321);
      final str = point.toString();
      // toStringAsFixed(6) 四舍五入到6位
      expect(str, 'LocationPoint(39.123457, 116.987654)');
    });
  });

  group('User — 序列化/反序列化', () {
    test('全字段 fromJson', () {
      final json = {
        'id': 'a0001',
        'name': '张三',
        'phone': '13800138000',
        'role': 'employee',
        'departmentName': '销售部',
      };
      final user = User.fromJson(json);
      expect(user.id, 'a0001');
      expect(user.name, '张三');
      expect(user.phone, '13800138000');
      expect(user.role, 'employee');
      expect(user.departmentName, '销售部');
    });

    test('可选字段缺失', () {
      final json = {'id': 'u1', 'name': 'test', 'phone': '123'};
      final user = User.fromJson(json);
      expect(user.id, 'u1');
      expect(user.name, 'test');
      expect(user.phone, '123');
      expect(user.role, isNull);
      expect(user.departmentName, isNull);
    });

    test('空字段处理', () {
      final json = {'id': '', 'name': '', 'phone': ''};
      final user = User.fromJson(json);
      expect(user.id, isEmpty);
      expect(user.name, isEmpty);
      expect(user.phone, isEmpty);
    });

    test('toJson 往返一致', () {
      final original = User(
        id: 'u1',
        name: '管理员',
        phone: '13900000001',
        departmentName: '技术部',
        role: 'admin',
      );
      final json = original.toJson();
      final restored = User.fromJson(json);
      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.phone, original.phone);
      expect(restored.role, original.role);
      expect(restored.departmentName, original.departmentName);
    });

    test('unmask 角色字符串', () {
      final user = User(id: 'u1', name: 'test', phone: '123', role: 'employee');
      expect(user.role, 'employee');
    });

    test('null 角色', () {
      final user = User(id: 'u1', name: 'test', phone: '123');
      expect(user.role, isNull);
    });

    test('Unicode 用户名', () {
      final json = {
        'id': 'u_unicode',
        'name': '测试用户😊🌍❤️',
        'phone': '123',
        'role': 'admin',
      };
      final user = User.fromJson(json);
      expect(user.name, '测试用户😊🌍❤️');
      // toJson 往返
      expect(user.toJson()['name'], '测试用户😊🌍❤️');
    });
  });
}
