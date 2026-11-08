import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'api.dart';

const cream = Color(0xfffaf9f6),
    gold = Color(0xffb18a22),
    ink = Color(0xff191a18),
    gray = Color(0xff9a9b92);
final messengerKey = GlobalKey<ScaffoldMessengerState>();
void notice(Object value) {
  messengerKey.currentState?.showSnackBar(
    SnackBar(
      content: Text(value.toString().replaceFirst('Exception: ', '')),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

Future<T?> push<T>(BuildContext context, Widget page) =>
    Navigator.of(context).push<T>(MaterialPageRoute(builder: (_) => page));
Future<bool> confirm(BuildContext context, String title, String text) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: cream,
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('确定'),
          ),
        ],
      ),
    ) ??
    false;
Future<String?> prompt(
  BuildContext context,
  String title, {
  String value = '',
  String hint = '',
  bool secret = false,
}) async {
  final c = TextEditingController(text: value);
  final result = await showDialog<String>(
    context: context,
    builder: (d) => BackdropFilter(
      filter: ui.ImageFilter.blur(sigmaX: 7, sigmaY: 7),
      child: Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(27)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 30, vertical: 24),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(25, 30, 25, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 28),
              DashedInput(controller: c, hint: hint, secret: secret),
              const SizedBox(height: 32),
              Row(
                children: [
                  Expanded(
                    child: Pill(
                      '取消',
                      black: true,
                      height: 44,
                      onTap: () => Navigator.pop(d),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Pill(
                      '确定',
                      black: true,
                      height: 44,
                      onTap: () => Navigator.pop(d, c.text.trim()),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await Future<void>.delayed(const Duration(milliseconds: 200));
  c.dispose();
  return result;
}

class DashedInput extends StatelessWidget {
  const DashedInput({
    super.key,
    required this.controller,
    this.hint = '',
    this.secret = false,
  });
  final TextEditingController controller;
  final String hint;
  final bool secret;
  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _DashedBorder(),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      child: TextField(
        controller: controller,
        obscureText: secret,
        decoration: InputDecoration(
          hintText: hint,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
        ),
        style: const TextStyle(fontSize: 16),
      ),
    ),
  );
}

class _DashedBorder extends CustomPainter {
  @override
  void paint(Canvas c, Size size) {
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(12)),
      );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..color = const Color(0xffd0d0c7);
    for (final m in path.computeMetrics()) {
      for (double x = 0; x < m.length; x += 10) {
        c.drawPath(m.extractPath(x, math.min(x + 5, m.length)), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class Shell extends StatelessWidget {
  const Shell({
    super.key,
    required this.title,
    required this.child,
    this.actions,
    this.footer,
  });
  final String title;
  final Widget child;
  final List<Widget>? actions;
  final Widget? footer;
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: cream,
    appBar: AppBar(
      title: Text(
        title,
        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w500),
      ),
      centerTitle: true,
      backgroundColor: cream,
      surfaceTintColor: Colors.transparent,
      actions: actions,
    ),
    body: SafeArea(
      top: false,
      child: Column(
        children: [
          Expanded(child: child),
          ?footer,
        ],
      ),
    ),
  );
}

class Pill extends StatelessWidget {
  const Pill(
    this.label, {
    super.key,
    this.icon,
    this.onTap,
    this.black = false,
    this.outline = false,
    this.goldStyle = false,
    this.loading = false,
    this.height = 54,
    this.fontSize = 17,
    this.iconSize = 22,
    this.horizontal = 15,
    this.iconTint,
  });
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool black, outline, goldStyle, loading;
  final double height, fontSize, iconSize, horizontal;
  final Color? iconTint;
  @override
  Widget build(BuildContext context) => AnimatedOpacity(
    duration: const Duration(milliseconds: 180),
    opacity: onTap == null && !loading ? 0.4 : 1,
    child: Material(
      color: black
          ? ink
          : goldStyle
          ? const Color(0xfff6f1e5)
          : Colors.white,
      shape: StadiumBorder(
        side: BorderSide(
          color: outline ? ink : const Color(0xffe9e8e2),
          width: outline ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: loading ? null : onTap,
        customBorder: const StadiumBorder(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: height),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: horizontal, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (loading)
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: black ? Colors.white : gold,
                    ),
                  )
                else if (icon != null)
                  Icon(
                    icon,
                    size: iconSize,
                    color:
                        iconTint ??
                        (black
                            ? Colors.white
                            : goldStyle
                            ? gold
                            : ink),
                  ),
                if (label.isNotEmpty && (icon != null || loading))
                  const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: black
                          ? Colors.white
                          : goldStyle
                          ? gold
                          : ink,
                      fontSize: fontSize,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class Paper extends StatelessWidget {
  const Paper({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(22),
  });
  final Widget child;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(30),
      boxShadow: const [
        BoxShadow(
          color: Color(0x05000000),
          blurRadius: 35,
          offset: Offset(0, 16),
        ),
      ],
    ),
    child: child,
  );
}

Widget footer(List<Widget> children) => Container(
  padding: const EdgeInsets.fromLTRB(24, 16, 24, 18),
  decoration: const BoxDecoration(
    color: cream,
    border: Border(top: BorderSide(color: Color(0xffeeede7))),
  ),
  child: Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: children,
  ),
);

class FrameArt extends StatelessWidget {
  const FrameArt({
    super.key,
    this.asset,
    this.portrait = true,
    this.photo,
    this.padding = 21,
  });
  final Json? asset;
  final bool portrait;
  final Widget? photo;
  final double padding;
  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: portrait ? 0.64 : 1.56,
    child: Container(
      padding: EdgeInsets.symmetric(
        horizontal: padding,
        vertical: padding * 1.2,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black, width: 6),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 16,
            offset: Offset(0, 13),
          ),
        ],
      ),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xffc4c9c1)),
        ),
        child:
            photo ??
            (asset == null
                ? const ColoredBox(
                    color: Color(0xfff0efea),
                    child: Center(
                      child: Icon(
                        Icons.add_photo_alternate_outlined,
                        color: gray,
                        size: 42,
                      ),
                    ),
                  )
                : Image.network(
                    api.image(asset!),
                    headers: api.headers,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const Center(
                      child: Icon(Icons.broken_image_outlined, color: gray),
                    ),
                  )),
      ),
    ),
  );
}

class FloatingFrame extends StatefulWidget {
  const FloatingFrame({super.key});
  @override
  State<FloatingFrame> createState() => _FloatingFrameState();
}

class _FloatingFrameState extends State<FloatingFrame>
    with SingleTickerProviderStateMixin {
  late final controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  )..repeat();
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (_, _) => Transform.translate(
      offset: Offset(0, math.sin(controller.value * math.pi * 2) * 8),
      child: SizedBox(
        width: 130,
        height: 175,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              left: 17,
              right: -17,
              child: Transform.rotate(
                angle: .14,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xffeeede7),
                    border: Border.all(color: const Color(0xffd4d2c7)),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: Container(
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: const Color(0xff30312a), width: 3),
                ),
                child: const ColoredBox(
                  color: Color(0xfff0efea),
                  child: Center(
                    child: SizedBox(
                      width: 65,
                      child: Divider(color: Color(0xffcac9bf)),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
