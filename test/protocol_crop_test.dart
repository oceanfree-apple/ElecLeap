import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:elecleap/ble.dart';
import 'package:elecleap/crop.dart';

void main() {
  test(
    'Dart matches existing mini-program EL1 HMAC HKDF AES-GCM wire vector',
    () async {
      final v = jsonDecode(
            File('test/fixtures/el1-vector.json').readAsStringSync(),
          ),
          session = ElSession(
            ElIdentity(v['id'], 'fixture-claim-code', base64Decode(v['key'])),
            clientNonce: base64Decode(v['cn']),
          );
      await session.challenge(Map<String, dynamic>.from(v['challenge']));
      expect(
        await session.seal(Map<String, dynamic>.from(v['payload'])),
        v['tx'],
      );
      expect(
        (await session.open(Map<String, dynamic>.from(v['rx'])))['status'],
        'connected',
      );
      await expectLater(
        session.open(Map<String, dynamic>.from(v['rx'])),
        throwsException,
      );
    },
  );
  test('arbitrary rotation and drag never expose empty corners', () {
    for (final size in [
      const Size(600, 1000),
      const Size(4000, 1800),
      const Size(1200, 1200),
    ]) {
      for (var deg = -180; deg <= 180; deg += 3) {
        final p = CropPose(size.width, size.height, 480, 800)
          ..angle = deg * math.pi / 180
          ..center = const Offset(10000, -10000);
        p.constrain();
        final c = math.cos(p.angle), s = math.sin(p.angle);
        for (final x in [-240.0, 240.0]) {
          for (final y in [-400.0, 400.0]) {
            expect(
              ((x - p.center.dx) * c + (y - p.center.dy) * s).abs() / p.scale,
              lessThanOrEqualTo(p.iw / 2 + 1e-6),
            );
            expect(
              (-(x - p.center.dx) * s + (y - p.center.dy) * c).abs() / p.scale,
              lessThanOrEqualTo(p.ih / 2 + 1e-6),
            );
          }
        }
      }
    }
  });
}
