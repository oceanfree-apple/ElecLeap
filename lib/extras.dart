import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'api.dart';
import 'ui.dart';
import 'ai.dart';
export 'widgets.dart';

class CatalogPage extends StatefulWidget {
  const CatalogPage({super.key, required this.device, this.community = false});
  final Json device;
  final bool community;
  @override
  State<CatalogPage> createState() => _CatalogState();
}

class _CatalogState extends State<CatalogPage> {
  List<Json> items = [];
  int page = 0, pages = 1;
  String tab = 'hot', category = '全部';
  List<Json> get visible => widget.community || category == '全部'
      ? items
      : items.where((a) => a['category'] == category).toList();
  bool busy = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final r = await api.request(
        widget.community ? '/community?sort=$tab&page=$page' : '/catalog',
      );
      if (mounted) {
        setState(() {
          items = ((widget.community ? r['items'] : r) as List)
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          pages = widget.community ? r['pages'] : 1;
        });
      }
    } catch (e) {
      notice(e);
    }
  }

  Future<void> use(Json a) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final r = await api.request(
        widget.community
            ? '/community/${a['id']}/save'
            : '/catalog/${a['id']}/import',
        method: 'POST',
        data: widget.community
            ? {}
            : {
                'orientation':
                    widget.device['config']?['orientation'] ?? 'portrait',
              },
      );
      await api.display(Map<String, dynamic>.from(r));
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      notice(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Shell(
    title: widget.community ? '创意广场' : '画廊',
    footer: widget.community
        ? footer([
            TextButton(
              onPressed: page == 0
                  ? null
                  : () {
                      setState(() => page--);
                      load();
                    },
              child: const Text('上一页'),
            ),
            Text('${page + 1}/$pages'),
            TextButton(
              onPressed: page + 1 >= pages
                  ? null
                  : () {
                      setState(() => page++);
                      load();
                    },
              child: const Text('下一页'),
            ),
          ])
        : null,
    child: Column(
      children: [
        if (!widget.community)
          SizedBox(
            height: 55,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: [
                for (final name in [
                  '全部',
                  ...items.map((a) => a['category'] as String).toSet(),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: ChoiceChip(
                      label: Text(name),
                      selected: category == name,
                      onSelected: (_) => setState(() => category = name),
                      selectedColor: const Color(0xfff0e8d3),
                      backgroundColor: Colors.white,
                      side: BorderSide.none,
                    ),
                  ),
              ],
            ),
          ),
        if (widget.community)
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'hot', label: Text('热门')),
              ButtonSegment(value: 'new', label: Text('最新')),
              ButtonSegment(value: 'mine', label: Text('我的')),
            ],
            selected: {tab},
            onSelectionChanged: (v) {
              setState(() {
                tab = v.first;
                page = 0;
              });
              load();
            },
          ),
        Expanded(
          child: items.isEmpty
              ? Center(
                  child: Text(
                    widget.community ? '还没有分享作品，去记录生活吧' : '正在打开画廊…',
                    style: const TextStyle(color: gray),
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(20),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: .52,
                    mainAxisSpacing: 18,
                    crossAxisSpacing: 15,
                  ),
                  itemCount: visible.length,
                  itemBuilder: (c, i) {
                    final a = visible[i];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: busy ? null : () => use(a),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(22),
                              child: Image.network(
                                '${api.base}${widget.community ? a['picture'] ?? a['preview'] : a['preview']}',
                                headers: api.headers,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => const Center(
                                  child: Icon(
                                    Icons.image_outlined,
                                    color: gray,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(
                            a['title'] ?? a['caption'] ?? '生活记录',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                        if (widget.community)
                          Row(
                            children: [
                              TextButton.icon(
                                onPressed: () async {
                                  try {
                                    await api.request(
                                      '/community/${a['id']}/like',
                                      method: 'PUT',
                                    );
                                    load();
                                  } catch (e) {
                                    notice(e);
                                  }
                                },
                                icon: Icon(
                                  a['liked'] == true
                                      ? Icons.favorite
                                      : Icons.favorite_outline,
                                  size: 17,
                                ),
                                label: Text('${a['likes']}'),
                              ),
                              const Spacer(),
                              if (a['mine'] == true)
                                IconButton(
                                  onPressed: () async {
                                    if (!await confirm(
                                      context,
                                      '取消分享',
                                      '从创意广场移除这张作品？',
                                    )) {
                                      return;
                                    }
                                    try {
                                      await api.request(
                                        '/community/${a['id']}',
                                        method: 'DELETE',
                                      );
                                      load();
                                    } catch (e) {
                                      notice(e);
                                    }
                                  },
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    size: 19,
                                  ),
                                ),
                            ],
                          ),
                      ],
                    );
                  },
                ),
        ),
      ],
    ),
  );
}

class DrawPage extends StatefulWidget {
  const DrawPage({super.key, required this.device});
  final Json device;
  @override
  State<DrawPage> createState() => _DrawState();
}

class Stroke {
  Stroke(this.color, this.width);
  final Color color;
  final double width;
  final List<Offset> points = [];
}

class _DrawState extends State<DrawPage> {
  final strokes = <Stroke>[];
  Color color = Colors.black;
  double width = 5;
  bool busy = false;
  Future<void> send({bool useAi = false}) async {
    if (busy) return;
    if (useAi && strokes.isEmpty) {
      notice('先画下你的想法吧');
      return;
    }
    setState(() => busy = true);
    try {
      final recorder = ui.PictureRecorder(), canvas = Canvas(recorder);
      final landscape = widget.device['config']?['orientation'] == 'landscape';
      final size = landscape ? const Size(800, 480) : const Size(480, 800);
      _DrawPainter(strokes).paint(canvas, size);
      final picture = recorder.endRecording(),
          im = await picture.toImage(size.width.toInt(), size.height.toInt()),
          data = await im.toByteData(format: ui.ImageByteFormat.png);
      im.dispose();
      picture.dispose();
      final a = await api.upload(
        data!.buffer.asUint8List(),
        widget.device['config']?['orientation'] ?? 'portrait',
      );
      if (useAi) {
        if (!mounted) return;
        final displayed = await push<bool>(
          context,
          AiPage(
            device: widget.device,
            referenceAsset: a,
            referenceBytes: data.buffer.asUint8List(),
          ),
        );
        if (displayed == true && mounted) Navigator.pop(context, true);
      } else {
        await api.display(a);
        if (mounted) Navigator.pop(context, true);
      }
    } catch (e) {
      notice(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Shell(
    title: '自由涂鸦',
    footer: footer([
      IconButton(
        onPressed: strokes.isEmpty
            ? null
            : () => setState(() => strokes.removeLast()),
        icon: const Icon(Icons.undo),
      ),
      IconButton(
        onPressed: () => setState(() => color = Colors.white),
        icon: const Icon(Icons.auto_fix_normal),
      ),
      const Spacer(),
      Pill(
        'AI 创作',
        glyph: 'brush',
        outline: true,
        height: 44,
        fontSize: 14,
        onTap: busy ? null : () => send(useAi: true),
      ),
      const SizedBox(width: 8),
      Pill('确定', black: true, onTap: busy ? null : send, loading: busy),
    ]),
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(15),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (final c in [
                Colors.black,
                const Color(0xfffce000),
                const Color(0xffe03020),
                const Color(0xff0060e0),
                const Color(0xff20a060),
              ])
                GestureDetector(
                  onTap: () => setState(() => color = c),
                  child: Container(
                    width: 31,
                    height: 31,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(
                        width: color == c ? 3 : 1,
                        color: color == c ? gold : Colors.white,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio:
                  widget.device['config']?['orientation'] == 'landscape'
                  ? 800 / 480
                  : .6,
              child: LayoutBuilder(
                builder: (c, b) => GestureDetector(
                  onPanStart: busy
                      ? null
                      : (d) => setState(
                          () => strokes.add(
                            Stroke(color, width)
                              ..points.add(
                                Offset(
                                  d.localPosition.dx / b.maxWidth,
                                  d.localPosition.dy / b.maxHeight,
                                ),
                              ),
                          ),
                        ),
                  onPanUpdate: busy
                      ? null
                      : (d) => setState(
                          () => strokes.last.points.add(
                            Offset(
                              d.localPosition.dx / b.maxWidth,
                              d.localPosition.dy / b.maxHeight,
                            ),
                          ),
                        ),
                  child: ClipRect(
                    child: CustomPaint(
                      painter: _DrawPainter(strokes),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Slider(
          value: width,
          min: 2,
          max: 25,
          activeColor: gold,
          onChanged: (v) => setState(() => width = v),
        ),
      ],
    ),
  );
}

class _DrawPainter extends CustomPainter {
  _DrawPainter(this.strokes);
  final List<Stroke> strokes;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(Colors.white, BlendMode.src);
    for (final s in strokes) {
      final p = Paint()
        ..color = s.color
        ..strokeWidth = s.width * size.width / 480
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      for (var i = 1; i < s.points.length; i++) {
        final a = s.points[i - 1], b = s.points[i];
        canvas.drawLine(
          Offset(a.dx * size.width, a.dy * size.height),
          Offset(b.dx * size.width, b.dy * size.height),
          p,
        );
      }
      if (s.points.length == 1) {
        canvas.drawCircle(
          Offset(
            s.points.first.dx * size.width,
            s.points.first.dy * size.height,
          ),
          p.strokeWidth / 2,
          p,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DrawPainter old) => true;
}
