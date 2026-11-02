import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'api.dart';
import 'ui.dart';

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
  String tab = 'hot';
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
                  itemCount: items.length,
                  itemBuilder: (c, i) {
                    final a = items[i];
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

class WidgetPage extends StatefulWidget {
  const WidgetPage({super.key, required this.device});
  final Json device;
  @override
  State<WidgetPage> createState() => _WidgetState();
}

class _WidgetState extends State<WidgetPage> {
  String kind = 'calendar';
  int city = 0, interval = 180;
  bool enabled = false, background = false, busy = false;
  Json? asset;
  final cities = ['深圳', '上海', '北京', '杭州', '广州', '成都'],
      coordinates = [
        [22.54, 114.06],
        [31.23, 121.47],
        [39.90, 116.40],
        [30.27, 120.15],
        [23.13, 113.26],
        [30.57, 104.07],
      ];
  @override
  void initState() {
    super.initState();
    final cfg = widget.device['config'] as Map,
        w = cfg['widget'] ?? cfg['weather'];
    if (w != null) {
      kind = w['kind'] ?? 'weather';
      city = cities.indexOf(w['city'] ?? '深圳').clamp(0, cities.length - 1);
      enabled = w['enabled'] == true;
      interval = (w['interval_minutes'] ?? 180) as int;
    }
  }

  Json body() => {
    'kind': kind,
    'city': cities[city],
    'latitude': coordinates[city][0],
    'longitude': coordinates[city][1],
    'orientation': widget.device['config']?['orientation'] ?? 'portrait',
  };
  Future<Json> prepare() async {
    final values = body();
    if (background) {
      final jobs =
          await api.request('/devices/${widget.device['id']}/jobs') as List;
      if (jobs.isNotEmpty) values['background_asset'] = jobs.first['asset'];
    }
    return values;
  }

  Future<void> send() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final r = await api.request(
        '/widgets/preview',
        method: 'POST',
        data: await prepare(),
      );
      asset = Map<String, dynamic>.from(r);
      await api.display(asset!);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      notice(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> plan(bool value) async {
    try {
      await api.request(
        '/devices/${widget.device['id']}/widget',
        method: 'PUT',
        data: {
          ...await prepare(),
          'enabled': value,
          'interval_minutes': interval,
        },
      );
      if (mounted) setState(() => enabled = value);
      notice(value ? '自动更新已开启' : '自动更新已关闭');
    } catch (e) {
      notice(e);
    }
  }

  @override
  Widget build(BuildContext context) => Shell(
    title: '小组件',
    footer: footer([
      Expanded(
        child: Pill(
          '设为画面',
          icon: Icons.check,
          black: true,
          onTap: busy ? null : send,
          loading: busy,
        ),
      ),
    ]),
    child: ListView(
      padding: const EdgeInsets.all(25),
      children: [
        const SizedBox(height: 10),
        const Text(
          '把时间和天气，放在喜欢的画面里',
          style: TextStyle(
            fontSize: 23,
            fontWeight: FontWeight.w600,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 30),
        Paper(
          child: RadioGroup<String>(
            groupValue: kind,
            onChanged: (v) => setState(() => kind = v!),
            child: Column(
              children: [
                for (final pair in [
                  ['calendar', '日期'],
                  ['weather', '天气'],
                  ['lunar', '农历'],
                ])
                  RadioListTile<String>(
                    value: pair[0],
                    title: Text(pair[1]),
                    activeColor: gold,
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 22),
        if (kind == 'weather')
          Paper(
            child: DropdownButtonFormField<int>(
              initialValue: city,
              items: [
                for (var i = 0; i < cities.length; i++)
                  DropdownMenuItem(value: i, child: Text(cities[i])),
              ],
              onChanged: (i) => setState(() => city = i!),
              decoration: const InputDecoration(labelText: '城市'),
            ),
          ),
        const SizedBox(height: 22),
        Paper(
          child: Column(
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('叠加在当前画面上'),
                value: background,
                onChanged: (v) => setState(() => background = v),
                activeTrackColor: gold,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('自动更新'),
                subtitle: const Text('设备按联网间隔接收更新'),
                value: enabled,
                onChanged: plan,
                activeTrackColor: gold,
              ),
              DropdownButtonFormField<int>(
                initialValue: [60, 180, 360, 720, 1440].contains(interval)
                    ? interval
                    : 180,
                items: [
                  for (final n in [60, 180, 360, 720, 1440])
                    DropdownMenuItem(value: n, child: Text('每 ${n / 60} 小时')),
                ],
                onChanged: (v) {
                  setState(() => interval = v!);
                  if (enabled) plan(true);
                },
                decoration: const InputDecoration(labelText: '更新间隔'),
              ),
            ],
          ),
        ),
        if (kind == 'weather')
          const Padding(
            padding: EdgeInsets.only(top: 25),
            child: Text(
              'Weather data by Open-Meteo.com (CC BY 4.0)',
              style: TextStyle(fontSize: 12, color: gray),
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
  Future<void> send() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final recorder = ui.PictureRecorder(), canvas = Canvas(recorder);
      _DrawPainter(strokes).paint(canvas, const Size(480, 800));
      final picture = recorder.endRecording(),
          im = await picture.toImage(480, 800),
          data = await im.toByteData(format: ui.ImageByteFormat.png);
      im.dispose();
      picture.dispose();
      final a = await api.upload(
        data!.buffer.asUint8List(),
        widget.device['config']?['orientation'] ?? 'portrait',
      );
      await api.display(a);
      if (mounted) Navigator.pop(context, true);
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
              aspectRatio: .6,
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
