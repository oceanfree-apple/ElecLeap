import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'api.dart';
import 'ui.dart';

Future<void> savePhoto(Json a) async {
  try {
    final res = await api.client.get(
      Uri.parse(api.image(a)),
      headers: api.headers,
    );
    if (res.statusCode != 200) throw Exception('图片读取失败');
    await const MethodChannel(
      'elecleap/native',
    ).invokeMethod<void>('savePhoto', Uint8List.fromList(res.bodyBytes));
    notice('已保存到手机相册');
  } catch (e) {
    notice('保存失败，请在系统设置中允许添加照片');
  }
}

class AlbumPage extends StatefulWidget {
  const AlbumPage({
    super.key,
    required this.device,
    this.initialItems,
    this.autoLoad = true,
  });
  final Json device;
  final List<Json>? initialItems;
  final bool autoLoad;
  @override
  State<AlbumPage> createState() => _AlbumState();
}

class _AlbumState extends State<AlbumPage> {
  List<Json> items = [];
  bool grid = true, busy = false;
  int page = 0;
  final scroll = ScrollController();
  @override
  void initState() {
    super.initState();
    items = widget.initialItems ?? [];
    if (widget.autoLoad) load();
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final rows = await api.request('/devices/${widget.device['id']}/album');
      if (mounted) {
        setState(
          () => items = (rows as List)
              .map((e) => Map<String, dynamic>.from(e))
              .toList(),
        );
      }
    } catch (e) {
      notice(e);
    }
  }

  Future<void> display(Json a) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await api.display(a);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      notice(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> actions(Json a) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: cream,
      showDragHandle: true,
      builder: (c) => Padding(
        padding: const EdgeInsets.only(bottom: 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.wallpaper),
              title: const Text('设为画面'),
              onTap: () {
                Navigator.pop(c);
                display(a);
              },
            ),
            ListTile(
              leading: const Icon(Icons.label_outline),
              title: const Text('编辑标签'),
              onTap: () async {
                Navigator.pop(c);
                final value = await prompt(
                  context,
                  '图片标签',
                  value: (a['tags'] as List? ?? []).join(','),
                  hint: '用逗号分隔，如：家人,旅行',
                );
                if (value == null) return;
                try {
                  await api.request(
                    '/devices/${widget.device['id']}/album/${a['id']}/tags',
                    method: 'PUT',
                    data: {
                      'tags': value
                          .split(RegExp('[,，]'))
                          .map((x) => x.trim())
                          .where((x) => x.isNotEmpty)
                          .toList(),
                    },
                  );
                  load();
                } catch (e) {
                  notice(e);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.download_outlined),
              title: const Text('保存到手机'),
              onTap: () {
                Navigator.pop(c);
                savePhoto(a);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('删除图片'),
              onTap: () async {
                Navigator.pop(c);
                if (!await confirm(context, '删除图片', '从相框相册移除这张图片？')) return;
                try {
                  await api.request(
                    '/devices/${widget.device['id']}/album/${a['id']}',
                    method: 'DELETE',
                  );
                  load();
                } catch (e) {
                  notice(e);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> clear() async {
    if (items.isEmpty || !await confirm(context, '清空相册', '清空全部图片？相框会保留当前画面。')) {
      return;
    }
    try {
      await api.request(
        '/devices/${widget.device['id']}/album',
        method: 'DELETE',
      );
      await load();
    } catch (e) {
      notice(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = (items.length / 24).ceil().clamp(1, 10000);
    page = page.clamp(0, pages - 1);
    final visible = items.skip(page * 24).take(24).toList();
    return Shell(
      title: '相册',
      footer: footer([
        IconButton(
          onPressed: page == 0
              ? null
              : () => setState(() {
                  page--;
                  scroll.jumpTo(0);
                }),
          icon: const Icon(Icons.arrow_back, size: 19),
        ),
        Text(
          '${page + 1}/$pages',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        IconButton(
          onPressed: page == pages - 1
              ? null
              : () => setState(() {
                  page++;
                  scroll.jumpTo(0);
                }),
          icon: const Icon(Icons.arrow_forward, size: 19),
        ),
        Text('${items.length}', style: const TextStyle(color: gray)),
        const Spacer(),
        IconButton.filledTonal(
          style: IconButton.styleFrom(backgroundColor: Colors.white),
          onPressed: () => setState(() => grid = !grid),
          icon: Icon(
            grid ? Icons.view_list_outlined : Icons.grid_view_outlined,
            size: 22,
          ),
        ),
        const SizedBox(width: 10),
        Pill('清空', icon: Icons.delete_outline, onTap: clear, height: 42),
      ]),
      child: items.isEmpty
          ? const Center(
              child: Text('相册还没有图片', style: TextStyle(color: gray)),
            )
          : grid
          ? GridView.builder(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(20, 15, 20, 30),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 14,
                crossAxisSpacing: 14,
                childAspectRatio: .6,
              ),
              itemCount: visible.length,
              itemBuilder: (c, i) {
                final a = visible[i];
                return GestureDetector(
                  onTap: () => display(a),
                  onLongPress: () => actions(a),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Image.network(
                      api.image(a),
                      headers: api.headers,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const ColoredBox(
                        color: Color(0xffeeede6),
                        child: Icon(Icons.image_outlined, color: gray),
                      ),
                    ),
                  ),
                );
              },
            )
          : ListView.separated(
              controller: scroll,
              padding: const EdgeInsets.all(20),
              itemCount: visible.length,
              separatorBuilder: (_, _) => const SizedBox(height: 20),
              itemBuilder: (c, i) {
                final a = visible[i],
                    date = DateTime.fromMillisecondsSinceEpoch(
                      ((a['created'] ?? 0) * 1000).toInt(),
                    ).toLocal();
                return Paper(
                  child: Column(
                    children: [
                      GestureDetector(
                        onTap: () => display(a),
                        onLongPress: () => actions(a),
                        child: FrameArt(
                          asset: a,
                          portrait: a['meta']?['orientation'] != 'landscape',
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Flexible(
                            child: Text(
                              '${date.year}/${date.month}/${date.day}  ${date.hour}:${date.minute.toString().padLeft(2, '0')}',
                              style: const TextStyle(fontSize: 12, color: gray),
                            ),
                          ),
                          const SizedBox(width: 12),
                          TextButton.icon(
                            onPressed: () async {
                              final text = await prompt(
                                context,
                                '反馈',
                                hint: '描述你遇到的问题',
                              );
                              if (text == null || text.isEmpty) return;
                              try {
                                await api.request(
                                  '/feedback',
                                  method: 'POST',
                                  data: {'asset_id': a['id'], 'text': text},
                                );
                                notice('反馈已收到');
                              } catch (e) {
                                notice(e);
                              }
                            },
                            icon: const Icon(
                              Icons.assignment_outlined,
                              size: 16,
                            ),
                            label: const Text('反馈'),
                          ),
                        ],
                      ),
                      Text(
                        a['meta']?['title'] ?? '生活记录',
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final t in a['tags'] ?? [])
                            Chip(
                              label: Text(t),
                              backgroundColor: const Color(0xfff6f1e5),
                              side: BorderSide.none,
                            ),
                        ],
                      ),
                      TextButton(
                        onPressed: () => actions(a),
                        child: const Text(
                          '设置画面 · 标签 · 保存',
                          style: TextStyle(color: gray, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
