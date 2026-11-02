import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'api.dart';
import 'ui.dart';

class CropPose {
  CropPose(this.iw, this.ih, this.w, this.h) {
    constrain();
  }
  final double iw, ih, w, h;
  double scale = 0, angle = 0;
  Offset center = Offset.zero;
  double get minimumScale => math.max(
    (w * math.cos(angle).abs() + h * math.sin(angle).abs()) / iw,
    (w * math.sin(angle).abs() + h * math.cos(angle).abs()) / ih,
  );
  void constrain() {
    scale = scale.clamp(minimumScale, minimumScale * 8);
    final c = math.cos(angle),
        s = math.sin(angle),
        mx = math.max(0.0, iw * scale / 2 - (w * c.abs() + h * s.abs()) / 2),
        my = math.max(0.0, ih * scale / 2 - (w * s.abs() + h * c.abs()) / 2);
    final x = (center.dx * c + center.dy * s).clamp(-mx, mx),
        y = (-center.dx * s + center.dy * c).clamp(-my, my);
    center = Offset(c * x - s * y, s * x + c * y);
  }

  void paint(
    Canvas canvas,
    ui.Image image,
    Size size, {
    bool clip = true,
    double opacity = 1,
  }) {
    canvas.save();
    if (clip) canvas.clipRect(Offset.zero & size);
    canvas.scale(size.width / w);
    canvas.translate(w / 2 + center.dx, h / 2 + center.dy);
    canvas.rotate(angle);
    canvas.scale(scale);
    canvas.drawImage(
      image,
      Offset(-iw / 2, -ih / 2),
      Paint()
        ..filterQuality = FilterQuality.high
        ..color = Colors.white.withValues(alpha: opacity),
    );
    canvas.restore();
  }

  Future<Uint8List> export(ui.Image image) async {
    final recorder = ui.PictureRecorder();
    final c = Canvas(recorder);
    c.drawColor(Colors.white, BlendMode.src);
    paint(c, image, Size(w, h));
    final picture = recorder.endRecording(),
        im = await picture.toImage(w.toInt(), h.toInt());
    final b = await im.toByteData(format: ui.ImageByteFormat.png);
    im.dispose();
    picture.dispose();
    return b!.buffer.asUint8List();
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
  double startScale = 1, startAngle = 0;
  Offset focal = Offset.zero, startCenter = Offset.zero;
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
        uploaded = null;
        requestKey = null;
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

  @override
  Widget build(BuildContext context) => Shell(
    title: '画框',
    footer: footer([
      Pill('重新选择', onTap: busy ? null : choose),
      Pill('确定', onTap: busy || image == null ? null : submit, loading: busy),
    ]),
    child: ColoredBox(
      color: const Color(0xff282928),
      child: LayoutBuilder(
        builder: (context, box) {
          final ratio = landscape ? 800 / 480 : 480 / 800,
              width = math.min(
                box.maxWidth * .73,
                (box.maxHeight - 65) * .85 * ratio,
              ),
              height = width / ratio,
              k = (landscape ? 800 : 480) / width;
          return Stack(
            children: [
              Center(
                child: GestureDetector(
                  onScaleStart: busy
                      ? null
                      : (d) {
                          startScale = pose?.scale ?? 1;
                          startAngle = pose?.angle ?? 0;
                          focal = d.localFocalPoint;
                          startCenter = pose?.center ?? Offset.zero;
                        },
                  onScaleUpdate: busy
                      ? null
                      : (d) {
                          if (pose == null) return;
                          final a = d.rotation,
                              c = math.cos(a),
                              s = math.sin(a),
                              old =
                                  (focal - Offset(width / 2, height / 2)) * k -
                                  startCenter;
                          setState(() {
                            pose!.angle = startAngle + a;
                            pose!.scale = startScale * d.scale;
                            pose!.center =
                                (d.localFocalPoint -
                                        Offset(width / 2, height / 2)) *
                                    k -
                                Offset(
                                      c * old.dx - s * old.dy,
                                      s * old.dx + c * old.dy,
                                    ) *
                                    d.scale;
                            pose!.constrain();
                            uploaded = null;
                            requestKey = null;
                          });
                        },
                  child: SizedBox(
                    width: width,
                    height: height,
                    child: CustomPaint(
                      painter: _CropPainter(image, pose),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ),
              const Positioned(
                bottom: 17,
                left: 16,
                right: 16,
                child: Text(
                  '双指旋转、缩放，拖动调整构图',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xffc1c1b8), fontSize: 12),
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
      pose!.paint(c, image!, size, clip: false, opacity: .25);
      pose!.paint(c, image!, size);
    }
    final p = Paint()
      ..color = Colors.white.withValues(alpha: .45)
      ..strokeWidth = .6;
    for (var i = 1; i < 3; i++) {
      c.drawLine(
        Offset(size.width * i / 3, 0),
        Offset(size.width * i / 3, size.height),
        p,
      );
      c.drawLine(
        Offset(0, size.height * i / 3),
        Offset(size.width, size.height * i / 3),
        p,
      );
    }
    c.drawRect(
      Offset.zero & size,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant _CropPainter old) => true;
}
