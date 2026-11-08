import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'api.dart';
import 'ui.dart';

class CropPose {
  CropPose(this.iw, this.ih, this.w, this.h) {
    scale = baseScale;
    constrain();
  }
  final double iw, ih, w, h;
  double scale = 0, angle = 0;
  Offset center = Offset.zero;
  double get baseScale => math.max(w / iw, h / ih);
  double get minimumScale => baseScale * .1;
  double get maximumScale => baseScale * 5;
  void constrain() {
    scale = scale.clamp(minimumScale, maximumScale);
    final c = math.cos(angle).abs(), s = math.sin(angle).abs();
    final mx = ((iw * c + ih * s) * scale - w).abs() / 2;
    final my = ((iw * s + ih * c) * scale - h).abs() / 2;
    center = Offset(center.dx.clamp(-mx, mx), center.dy.clamp(-my, my));
  }

  void rotate() {
    angle = (angle + math.pi / 2) % (math.pi * 2);
    constrain();
  }

  // Focal points are relative to the crop centre in logical screen points.
  void move(Offset oldFocal, Offset newFocal, double spreadDelta, double k) {
    final next = (scale + baseScale * spreadDelta / 100).clamp(
      minimumScale,
      maximumScale,
    );
    final ratio = next / scale;
    center = newFocal * k - (oldFocal * k - center) * ratio;
    scale = next;
    constrain();
  }

  void paint(
    Canvas canvas,
    ui.Image image,
    Size size, {
    bool clip = true,
    bool dim = false,
  }) {
    canvas.save();
    if (clip) canvas.clipRect(Offset.zero & size);
    canvas.scale(size.width / w);
    canvas.translate(w / 2 + center.dx, h / 2 + center.dy);
    canvas.rotate(angle);
    canvas.scale(scale);
    final paint = Paint()..filterQuality = FilterQuality.high;
    if (dim) {
      paint.colorFilter = const ColorFilter.matrix([
        .36,
        0,
        0,
        0,
        0,
        0,
        .36,
        0,
        0,
        0,
        0,
        0,
        .36,
        0,
        0,
        0,
        0,
        0,
        1,
        0,
      ]);
    }
    canvas.drawImage(image, Offset(-iw / 2, -ih / 2), paint);
    canvas.restore();
  }

  Future<Uint8List> export(ui.Image image) async {
    final recorder = ui.PictureRecorder();
    // Use one picture for both the black padding and the preview transform.
    final canvas = Canvas(recorder);
    canvas.drawColor(Colors.black, BlendMode.src);
    paint(canvas, image, Size(w, h));
    final picture = recorder.endRecording(),
        im = await picture.toImage(w.toInt(), h.toInt());
    final bytes = await im.toByteData(format: ui.ImageByteFormat.png);
    im.dispose();
    picture.dispose();
    return bytes!.buffer.asUint8List();
  }
}

class PhotoEditor extends StatefulWidget {
  const PhotoEditor({super.key, required this.device, this.camera = false});
  final Json device;
  final bool camera;
  @override
  State<PhotoEditor> createState() => _PhotoEditorState();
}

class _PhotoEditorState extends State<PhotoEditor> {
  ui.Image? image;
  CropPose? pose;
  bool busy = false;
  final pointers = <int, Offset>{};
  String? requestKey;
  Json? uploaded;
  bool get landscape => widget.device['config']?['orientation'] == 'landscape';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => choose());
  }

  @override
  void dispose() {
    image?.dispose();
    super.dispose();
  }

  void invalidate() {
    uploaded = null;
    requestKey = null;
  }

  Future<void> choose() async {
    try {
      final f = await ImagePicker().pickImage(
        source: widget.camera ? ImageSource.camera : ImageSource.gallery,
        maxWidth: 4096,
        maxHeight: 4096,
        imageQuality: 100,
        requestFullMetadata: false,
      );
      if (f == null) return;
      final codec = await ui.instantiateImageCodec(await f.readAsBytes());
      final frame = await codec.getNextFrame();
      codec.dispose();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      image?.dispose();
      setState(() {
        image = frame.image;
        pose = CropPose(
          image!.width.toDouble(),
          image!.height.toDouble(),
          landscape ? 800 : 480,
          landscape ? 480 : 800,
        );
        pointers.clear();
        invalidate();
      });
    } catch (e) {
      notice('无法打开照片，请允许访问相册后重试');
    }
  }

  Future<void> submit() async {
    if (busy || pose == null) return;
    setState(() => busy = true);
    try {
      uploaded ??= await api.upload(
        await pose!.export(image!),
        landscape ? 'landscape' : 'portrait',
      );
      requestKey ??=
          'ios:${DateTime.now().microsecondsSinceEpoch}:${uploaded!['id']}';
      await api.display(uploaded!, key: requestKey);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      notice(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void move(PointerMoveEvent e, Size stage, double cropWidth) {
    if (busy || pose == null || !pointers.containsKey(e.pointer)) return;
    final old = pointers.values.take(2).toList();
    pointers[e.pointer] = e.localPosition;
    final next = pointers.values.take(2).toList();
    Offset focal(List<Offset> p) => p.length > 1 ? (p[0] + p[1]) / 2 : p[0];
    double span(List<Offset> p) => p.length > 1 ? (p[0] - p[1]).distance : 0;
    final origin = Offset(stage.width / 2, stage.height / 2);
    setState(() {
      pose!.move(
        focal(old) - origin,
        focal(next) - origin,
        span(next) - span(old),
        pose!.w / cropWidth,
      );
      invalidate();
    });
  }

  @override
  Widget build(BuildContext context) => Shell(
    title: '画框',
    footer: Padding(
      padding: EdgeInsets.fromLTRB(
        MediaQuery.sizeOf(context).width * .134,
        7,
        MediaQuery.sizeOf(context).width * .134,
        12,
      ),
      child: Row(
        children: [
          Expanded(
            child: Pill(
              '重新选择',
              height: 40,
              fontSize: 16,
              onTap: busy ? null : choose,
            ),
          ),
          SizedBox(width: MediaQuery.sizeOf(context).width * .122),
          Expanded(
            child: Pill(
              '确定',
              height: 40,
              fontSize: 16,
              onTap: busy || image == null ? null : submit,
              loading: busy,
            ),
          ),
        ],
      ),
    ),
    child: ColoredBox(
      color: const Color(0xff282828),
      child: LayoutBuilder(
        builder: (context, box) {
          final ratio = landscape ? 800 / 480 : 480 / 800;
          final width = math.min(
            box.maxWidth * (landscape ? .82 : .55),
            box.maxHeight * .82 * ratio,
          );
          final height = width / ratio,
              stage = Size(box.maxWidth, box.maxHeight);
          return Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned.fill(
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (e) {
                    if (!busy) pointers[e.pointer] = e.localPosition;
                  },
                  onPointerMove: (e) => move(e, stage, width),
                  onPointerUp: (e) => pointers.remove(e.pointer),
                  onPointerCancel: (e) => pointers.remove(e.pointer),
                  child: Center(
                    child: SizedBox(
                      width: width,
                      height: height,
                      child: CustomPaint(painter: _CropPainter(image, pose)),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 1,
                bottom: 2,
                child: IconButton(
                  tooltip: '顺时针旋转90°',
                  icon: const Icon(
                    Icons.rotate_90_degrees_cw_outlined,
                    color: Colors.white,
                    size: 29,
                  ),
                  onPressed: busy || pose == null
                      ? null
                      : () {
                          setState(() {
                            pose!.rotate();
                            pointers.clear();
                            invalidate();
                          });
                        },
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}

class _CropPainter extends CustomPainter {
  _CropPainter(this.image, this.pose);
  final ui.Image? image;
  final CropPose? pose;
  @override
  void paint(Canvas c, Size size) {
    if (image != null && pose != null) {
      pose!.paint(c, image!, size, clip: false, dim: true);
    }
    c.drawRect(Offset.zero & size, Paint()..color = Colors.black);
    if (image != null && pose != null) pose!.paint(c, image!, size);
    final p = Paint()
      ..color = Colors.white.withValues(alpha: .42)
      ..strokeWidth = .6;
    for (var i = 1; i < 3; i++) {
      for (double y = 0; y < size.height; y += 8) {
        c.drawLine(
          Offset(size.width * i / 3, y),
          Offset(size.width * i / 3, math.min(y + 4, size.height)),
          p,
        );
      }
      for (double x = 0; x < size.width; x += 8) {
        c.drawLine(
          Offset(x, size.height * i / 3),
          Offset(math.min(x + 4, size.width), size.height * i / 3),
          p,
        );
      }
    }
    c.drawRect(
      Offset.zero & size,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = Colors.white,
    );
    final corner = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.6;
    for (final x in [0.0, size.width]) {
      for (final y in [0.0, size.height]) {
        c.drawLine(Offset(x, y), Offset(x + (x == 0 ? 20 : -20), y), corner);
        c.drawLine(Offset(x, y), Offset(x, y + (y == 0 ? 20 : -20)), corner);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CropPainter old) => true;
}
