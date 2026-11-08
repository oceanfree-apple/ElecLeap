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

  Future<void> rename(Json a) async {
    final title = await prompt(
      context,
      '修改作品名称',
      value: a['meta']?['title'] ?? '',
      hint: '输入作品名称',
    );
    if (title == null) return;
    if (title.length > 80) {
      notice('作品名称最多80个字符');
      return;
    }
    try {
      await api.request(
        '/devices/${widget.device['id']}/album/${a['id']}/title',
        method: 'PUT',
        data: {'title': title},
      );
      await load();
    } catch (e) {
      notice(e);
    }
  }

  Future<void> tags(Json a) async {
    final controller = TextEditingController(),
        values = List<String>.from(a['tags'] ?? []);
    final result = await showDialog<List<String>>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, update) {
          bool add() {
            final t = controller.text.trim();
            if (t.isEmpty) return true;
            if (t.length > 20 || values.length >= 12) {
              notice('最多12个标签，每个标签最多20个字符');
              return false;
            }
            if (!values.contains(t)) values.add(t);
            controller.clear();
            update(() {});
            return true;
          }

          return Dialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(27),
            ),
            insetPadding: const EdgeInsets.symmetric(horizontal: 30),
            child: Padding(
              padding: const EdgeInsets.all(25),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    '管理标签',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 28),
                  const Text(
                    '图片标签',
                    style: TextStyle(color: gray, fontSize: 14),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      if (values.isEmpty) const Chip(label: Text('暂无')),
                      for (final t in values)
                        InputChip(
                          label: Text(t),
                          onDeleted: () => update(() => values.remove(t)),
                          backgroundColor: const Color(0xfff6f1e5),
                          side: BorderSide.none,
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    '点击添加新标签',
                    style: TextStyle(color: gray, fontSize: 14),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DashedInput(controller: controller, hint: '新标签'),
                      ),
                      const SizedBox(width: 10),
                      Pill('添加', height: 40, fontSize: 14, onTap: add),
                    ],
                  ),
                  const SizedBox(height: 30),
                  Row(
                    children: [
                      Expanded(
                        child: Pill(
                          '取消',
                          height: 44,
                          black: true,
                          onTap: () => Navigator.pop(d),
                        ),
                      ),
                      const SizedBox(width: 15),
                      Expanded(
                        child: Pill(
                          '确定',
                          height: 44,
                          black: true,
                          onTap: () {
                            if (add()) {
                              Navigator.pop(d, List<String>.from(values));
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));
    controller.dispose();
    if (result == null) return;
    try {
      await api.request(
        '/devices/${widget.device['id']}/album/${a['id']}/tags',
        method: 'PUT',
        data: {'tags': result},
      );
      await load();
    } catch (e) {
      notice(e);
    }
  }

  Future<void> remove(Json a) async {
    if (!await confirm(context, '删除图片', '从相框相册移除这张图片？')) return;
    try {
      await api.request(
        '/devices/${widget.device['id']}/album/${a['id']}',
        method: 'DELETE',
      );
      await load();
    } catch (e) {
      notice(e);
    }
  }

  Future<void> publish(Json a) async {
    if (!await confirm(context, '分享作品', '公开到创意广场后，其他用户可以看到这张图片。')) return;
    try {
      await api.request(
        '/community',
        method: 'POST',
        data: {'asset_id': a['id'], 'caption': a['meta']?['title'] ?? ''},
      );
      notice('作品已分享');
    } catch (e) {
      notice(e);
    }
  }

  Future<void> actions(Json a) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: cream,
      showDragHandle: true,
      builder: (d) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final action in [
              (Icons.wallpaper, '显示', () => display(a)),
              (Icons.edit_outlined, '修改作品名称', () => rename(a)),
              (Icons.sell_outlined, '管理标签', () => tags(a)),
              (Icons.download_outlined, '保存到手机', () => savePhoto(a)),
              (Icons.delete_outline, '删除图片', () => remove(a)),
              (Icons.share_outlined, '发布到创意广场', () => publish(a)),
            ])
              ListTile(
                leading: Icon(action.$1),
                title: Text(action.$2),
                onTap: () {
                  Navigator.pop(d);
                  action.$3();
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
                      Text(
                        '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')} ${date.hour}:${date.minute.toString().padLeft(2, '0')}',
                        style: const TextStyle(fontSize: 12, color: gray),
                      ),
                      if ((a['meta']?['title'] ?? '').isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 14),
                          child: Text(
                            a['meta']['title'],
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      if ((a['tags'] as List? ?? []).isNotEmpty)
                        Wrap(
                          spacing: 8,
                          children: [
                            for (final t in a['tags'])
                              Chip(
                                label: Text(t),
                                backgroundColor: const Color(0xfff6f1e5),
                                side: BorderSide.none,
                              ),
                          ],
                        ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(35, 20, 35, 18),
                        child: SizedBox(
                          width: double.infinity,
                          child: Pill(
                            '显示',
                            icon: Icons.check,
                            black: true,
                            height: 43,
                            onTap: busy ? null : () => display(a),
                          ),
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (final action in [
                            (Icons.edit_outlined, '修改作品名称', () => rename(a)),
                            (Icons.sell_outlined, '管理标签', () => tags(a)),
                            (Icons.delete_outline, '删除图片', () => remove(a)),
                            (
                              Icons.download_outlined,
                              '保存到手机',
                              () => savePhoto(a),
                            ),
                          ])
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                              ),
                              child: IconButton.filledTonal(
                                style: IconButton.styleFrom(
                                  backgroundColor: cream,
                                  foregroundColor: ink,
                                ),
                                tooltip: action.$2,
                                onPressed: action.$3,
                                icon: Icon(action.$1, size: 19),
                              ),
                            ),
                        ],
                      ),
                      const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: Text(
                          '●',
                          style: TextStyle(
                            color: Color(0xffd3d1c3),
                            fontSize: 10,
                          ),
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
