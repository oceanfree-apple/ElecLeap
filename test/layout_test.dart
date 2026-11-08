import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elecleap/main.dart';
import 'package:elecleap/ui.dart';
import 'package:elecleap/album.dart';
import 'package:elecleap/ai.dart';

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
  testWidgets(
    'idle preview and frame taps switch between large and small views',
    (t) async {
      t.view.physicalSize = const Size(393, 852);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(
        MaterialApp(
          home: WorkspacePage(
            device: device,
            autoLoad: false,
            previewPhoto: const ColoredBox(color: Colors.blue),
            initialJob: const {'status': 'displayed'},
          ),
        ),
      );
      await t.pumpAndSettle();
      final frame = find.byType(FrameArt),
          tools = find.byKey(const ValueKey('frame-tools'));
      final enlarged = t.getSize(frame).width;
      expect(t.getSize(tools).height, 0);
      expect(
        t.getRect(frame).bottom,
        lessThan(t.getRect(find.widgetWithText(Pill, 'AI 绘画')).top),
      );
      await t.tap(frame);
      await t.pumpAndSettle();
      final before = t.getSize(frame).width;
      expect(enlarged, greaterThan(before));
      expect(t.getSize(tools).height, greaterThan(40));
      await t.pump(const Duration(seconds: 13));
      expect(t.getSize(tools).height, greaterThan(40));
      await t.pump(const Duration(seconds: 2));
      await t.pumpAndSettle();
      expect(t.getSize(tools).height, 0);
      expect(t.getSize(frame).width, greaterThan(before));
      await t.tap(frame);
      await t.pumpAndSettle();
      expect(t.getSize(tools).height, greaterThan(40));
      expect(t.getSize(frame).width, closeTo(before, 1));
      expect(find.byTooltip('放大预览'), findsNothing);
      await t.tap(frame);
      await t.pumpAndSettle();
      expect(t.getSize(tools).height, 0);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets('orientation changes only the small preview before refresh', (
    t,
  ) async {
    t.view.physicalSize = const Size(393, 852);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      MaterialApp(
        home: WorkspacePage(
          device: device,
          autoLoad: false,
          previewPhoto: const ColoredBox(color: Colors.blue),
          initialJob: const {'id': 'existing-job', 'status': 'displayed'},
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('纵向'));
    await t.pumpAndSettle();
    final frame = find.byType(FrameArt);
    expect(find.text('横向'), findsOneWidget);
    expect(t.getSize(frame).width, greaterThan(t.getSize(frame).height));
    expect(
      t.getSize(find.byKey(const ValueKey('frame-tools'))).height,
      greaterThan(40),
    );
    expect(t.widget<FrameArt>(frame).quarterTurns, 1);
    expect(device['config']['orientation'], 'portrait');
    expect(find.textContaining('正在刷新画框'), findsNothing);
    await t.tap(frame);
    await t.pumpAndSettle();
    expect(t.getSize(find.byKey(const ValueKey('frame-tools'))).height, 0);
    await t.tap(find.text('横向'));
    await t.pumpAndSettle();
    expect(find.text('纵向'), findsOneWidget);
    expect(t.widget<FrameArt>(frame).quarterTurns, 0);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets(
    'landscape frame stays centered with tools and refresh progress',
    (t) async {
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      t.view.devicePixelRatio = 1;
      for (final size in [const Size(320, 568), const Size(393, 852)]) {
        t.view.physicalSize = size;
        for (final refreshing in [false, true]) {
          await t.pumpWidget(
            MaterialApp(
              home: WorkspacePage(
                key: ValueKey('$size-$refreshing'),
                device: {
                  ...device,
                  'config': {...device['config'], 'orientation': 'landscape'},
                },
                autoLoad: false,
                previewPhoto: const ColoredBox(color: Colors.blue),
                initialJob: {
                  'status': refreshing ? 'downloaded' : 'displayed',
                  'progress': 30,
                },
              ),
            ),
          );
          await t.pumpAndSettle();
          if (!refreshing) {
            await t.tap(find.byType(FrameArt));
            await t.pumpAndSettle();
          }
          final positioned = find.byKey(const ValueKey('frame-position'));
          final region = find
              .ancestor(of: positioned, matching: find.byType(Stack))
              .first;
          expect(
            t.getCenter(find.byType(FrameArt)).dy,
            closeTo(t.getCenter(region).dy, 1),
          );
          expect(t.takeException(), isNull);
        }
      }
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets('AI styles, voice prompt and doodle prompt fit small phones', (
    t,
  ) async {
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    t.view.devicePixelRatio = 1;
    for (final width in [320.0, 393.0]) {
      t.view.physicalSize = Size(width, width == 320 ? 568 : 852);
      for (final mode in ['styles', 'voice', 'doodle']) {
        await t.pumpWidget(
          MaterialApp(
            home: AiPage(
              key: ValueKey('$width-$mode'),
              device: device,
              autoLoad: false,
              voice: mode == 'voice',
              referenceAsset: mode == 'doodle' ? {'id': 'test-sketch'} : null,
            ),
          ),
        );
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        if (mode == 'voice') {
          await t.tap(find.text('开始创作'));
          await t.pumpAndSettle();
          expect(find.text('先写下或说出你想画的内容'), findsOneWidget);
        }
      }
    }
    await t.pumpWidget(const SizedBox());
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
    final oldShadows = debugDisableShadows;
    debugDisableShadows = false;
    addTearDown(() => debugDisableShadows = oldShadows);
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
    final photo = MemoryImage(
      File('../miniprogram/assets/reference-flight.jpg').readAsBytesSync(),
    );
    final key = GlobalKey();
    for (final page in [
      'frame',
      'frame-controls',
      'frame-preview',
      'login',
      'ai',
      'voice',
      'doodle',
    ]) {
      await t.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                padding: const EdgeInsets.only(top: 59, bottom: 34),
                viewPadding: const EdgeInsets.only(top: 59, bottom: 34),
              ),
              child: child!,
            ),
            theme: ThemeData(
              fontFamily: 'Roboto',
              fontFamilyFallback: const ['CJK'],
              useMaterial3: true,
              colorScheme: ColorScheme.fromSeed(seedColor: gold),
            ),
            home: page.startsWith('frame')
                ? WorkspacePage(
                    key: ValueKey(page),
                    device: device,
                    autoLoad: false,
                    previewPhoto: Image(image: photo, fit: BoxFit.cover),
                    initialJob: page == 'frame'
                        ? {'status': 'downloaded', 'progress': 30}
                        : {'status': 'displayed'},
                  )
                : page == 'login'
                ? const AuthPage()
                : AiPage(
                    key: ValueKey(page),
                    device: device,
                    autoLoad: false,
                    voice: page == 'voice',
                    referenceAsset: page == 'doodle'
                        ? {'id': 'test-sketch'}
                        : null,
                  ),
          ),
        ),
      );
      await t.pumpAndSettle();
      if (page.startsWith('frame')) {
        await t.runAsync(
          () => precacheImage(photo, t.element(find.byType(FrameArt))),
        );
        await t.pumpAndSettle();
      }
      if (page == 'frame-controls') {
        await t.tap(find.byType(FrameArt));
        await t.pumpAndSettle();
      }
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
    debugDisableShadows = oldShadows;
    await t.pumpWidget(const SizedBox());
    t.view.resetPhysicalSize();
    t.view.resetDevicePixelRatio();
  });
}
