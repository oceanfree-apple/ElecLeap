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
  test('reference additive pinch, quarter turns and both image boundaries', () {
    final p = CropPose(1179, 2556, 480, 800);
    p.scale = p.baseScale * .1;
    void spread(double delta, double expected) {
      p.move(Offset.zero, Offset.zero, delta, 1);
      expect(p.scale / p.baseScale, closeTo(expected, 1e-8));
    }

    spread(240, 2.5);
    spread(240, 4.9);
    spread(240, 5);
    p.rotate();
    spread(-180, 3.2);
    spread(-180, 1.4);
    spread(-180, .1);
    spread(40, .5);
    for (final zoom in [.1, .5, 1.0, 3.0, 5.0]) {
      for (var turn = 0; turn < 4; turn++) {
        p.angle = turn * math.pi / 2;
        p.scale = p.baseScale * zoom;
        p.center = const Offset(10000, -10000);
        p.constrain();
        final iw = (turn.isOdd ? p.ih : p.iw) * p.scale,
            ih = (turn.isOdd ? p.iw : p.ih) * p.scale;
        expect(p.center.dx, closeTo((iw - p.w).abs() / 2, 1e-6));
        expect(p.center.dy, closeTo(-(ih - p.h).abs() / 2, 1e-6));
      }
    }
    final scale = p.scale;
    for (var i = 0; i < 4; i++) {
      p.rotate();
      expect(p.scale, scale);
    }
  });
  test(
    'photo export preserves black padding and clockwise quadrants',
    () async {
      final recorder = PictureRecorder();
      final c = Canvas(recorder);
      for (final entry in [
        (const Color(0xffff0000), 0.0, 0.0),
        (const Color(0xff00ff00), 300.0, 0.0),
        (const Color(0xff0000ff), 0.0, 500.0),
        (const Color(0xffffff00), 300.0, 500.0),
      ]) {
        c.drawRect(
          Rect.fromLTWH(entry.$2, entry.$3, 300, 500),
          Paint()..color = entry.$1,
        );
      }
      final picture = recorder.endRecording(),
          image = await picture.toImage(600, 1000);
      final p = CropPose(600, 1000, 480, 800)..scale = .08;
      p.rotate();
      final codec = await instantiateImageCodec(await p.export(image));
      final frame = await codec.getNextFrame();
      final bytes = (await frame.image.toByteData())!.buffer.asUint8List();
      List<int> at(int x, int y) =>
          bytes.sublist((y * 480 + x) * 4, (y * 480 + x) * 4 + 3);
      expect(at(5, 5), [0, 0, 0]);
      expect(at(475, 795), [0, 0, 0]);
      expect(at(220, 388), [0, 0, 255]);
      expect(at(260, 388), [255, 0, 0]);
      expect(at(220, 412), [255, 255, 0]);
      expect(at(260, 412), [0, 255, 0]);
      frame.image.dispose();
      codec.dispose();
      image.dispose();
      picture.dispose();
    },
  );
}
