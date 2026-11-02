import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elecleap/main.dart';
import 'package:elecleap/ui.dart';
import 'package:elecleap/album.dart';

void main() {
  final device = <String, dynamic>{
    'id': 'EL-TEST-000001',
    'name': 'ElecLeap',
    'role': 'owner',
    'online': true,
    'power_source': 'usb',
    'config': {
      'orientation': 'portrait',
      'mode': 'smart',
      'poll_minutes': 15,
      'idle_minutes': 30,
    },
  };
  testWidgets('frame and refresh views fit narrow and modern iPhone screens', (
    t,
  ) async {
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    for (final size in [
      const Size(320, 568),
      const Size(393, 852),
      const Size(430, 932),
    ]) {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      await t.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(seedColor: gold),
          ),
          home: WorkspacePage(
            device: device,
            autoLoad: false,
            initialJob: {'status': 'downloaded', 'progress': 30},
          ),
        ),
      );
      await t.pump(const Duration(milliseconds: 600));
      expect(t.takeException(), isNull);
      expect(find.text('正在刷新画框 30%'), findsOneWidget);
      expect(find.text('相册 0'), findsOneWidget);
    }
    await t.pumpWidget(const SizedBox());
    t.view.resetPhysicalSize();
    t.view.resetDevicePixelRatio();
  });
  testWidgets('login and registration can switch without a server', (t) async {
    await t.pumpWidget(const MaterialApp(home: AuthPage()));
    await t.pump();
    expect(find.text('登录'), findsOneWidget);
    await t.ensureVisible(find.text('还没有账号？注册'));
    await t.tap(find.text('还没有账号？注册'));
    await t.pumpAndSettle();
    expect(find.text('注册并进入'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(3));
    expect(t.takeException(), isNull);
  });
  testWidgets('album grid switches to vertically scrollable large preview', (
    t,
  ) async {
    t.view.physicalSize = const Size(393, 852);
    t.view.devicePixelRatio = 1;
    await t.pumpWidget(
      MaterialApp(
        home: AlbumPage(
          device: device,
          autoLoad: false,
          initialItems: const [],
        ),
      ),
    );
    await t.pump();
    expect(find.text('相册还没有图片'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    t.view.resetPhysicalSize();
    t.view.resetDevicePixelRatio();
  });
  testWidgets('capture real Flutter frame and account UI for local review', (
    t,
  ) async {
    if (!Platform.environment.containsKey('ELECLEAP_SCREENSHOTS')) return;
    t.view.physicalSize = const Size(393, 852);
    t.view.devicePixelRatio = 1;
    await t.runAsync(() async {
      for (final pair in [
        [
          'Roboto',
          '${Platform.environment['ELECLEAP_FONT_DIR']}/Roboto-Regular.ttf',
        ],
        ['CJK', '../assets/DroidSansFallbackFull.ttf'],
        [
          'MaterialIcons',
          '${Platform.environment['ELECLEAP_FONT_DIR']}/MaterialIcons-Regular.otf',
        ],
      ]) {
        final loader = FontLoader(pair[0])
          ..addFont(
            Future.value(ByteData.sublistView(File(pair[1]).readAsBytesSync())),
          );
        await loader.load();
      }
    });
    final key = GlobalKey();
    for (final page in ['frame', 'login']) {
      await t.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            theme: ThemeData(
              fontFamily: 'Roboto',
              fontFamilyFallback: const ['CJK'],
              useMaterial3: true,
              colorScheme: ColorScheme.fromSeed(seedColor: gold),
            ),
            home: page == 'frame'
                ? WorkspacePage(
                    device: device,
                    autoLoad: false,
                    initialJob: {'status': 'downloaded', 'progress': 30},
                  )
                : const AuthPage(),
          ),
        ),
      );
      await t.pumpAndSettle();
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      await t.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        File(
          '../../inspection/ui-ios-$page.png',
        ).writeAsBytesSync(data!.buffer.asUint8List());
        image.dispose();
      });
    }
    await t.pumpWidget(const SizedBox());
    t.view.resetPhysicalSize();
    t.view.resetDevicePixelRatio();
  });
}
