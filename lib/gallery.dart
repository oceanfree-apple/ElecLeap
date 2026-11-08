import 'package:flutter/material.dart';
import 'api.dart';
import 'ui.dart';

class MuseumGalleryPage extends StatefulWidget {
  const MuseumGalleryPage({super.key, required this.device});
  final Json device;
  @override
  State<MuseumGalleryPage> createState() => _MuseumGalleryState();
}

class _MuseumGalleryState extends State<MuseumGalleryPage> {
  List<Json> items = [];
  String category = '推荐';
  int page = 0;
  bool loading = true;
  final countries = const ['推荐', '美国', '中国', '法国', '英国', '荷兰'];
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final r = await api.request('/catalog') as List;
      if (mounted) {
        setState(() {
          items = r.map((x) => Map<String, dynamic>.from(x)).toList();
          loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => loading = false);
        notice(e);
      }
    }
  }

  Widget tile(Json a) => ClipRRect(
    borderRadius: BorderRadius.circular(23),
    child: Material(
      color: Colors.white,
      child: InkWell(
        onTap: () async {
          final changed = await push<bool>(
            context,
            _CollectionPage(device: widget.device, collection: a),
          );
          if (changed == true && mounted) Navigator.pop(context, true);
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              '${api.base}${a['preview']}',
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) =>
                  const Center(child: Icon(Icons.image_outlined, color: gray)),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 30, 14, 13),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0xaa000000)],
                  ),
                ),
                child: Text(
                  a['title'],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final filtered = category == '推荐'
        ? items
        : items.where((a) => a['category'] == category).toList();
    final pages = (filtered.length / 4).ceil().clamp(1, 1000);
    page = page.clamp(0, pages - 1);
    final list = filtered.skip(page * 4).take(4).toList();
    return Shell(
      title: '画廊',
      footer: SizedBox(
        height: 50,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              onPressed: page == 0 ? null : () => setState(() => page--),
              icon: const Icon(Icons.chevron_left),
            ),
            Text(
              '${page + 1} / $pages',
              style: const TextStyle(color: gray, fontSize: 13),
            ),
            IconButton(
              onPressed: page + 1 >= pages
                  ? null
                  : () => setState(() => page++),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 62,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              children: [
                for (final c in countries)
                  Padding(
                    padding: const EdgeInsets.only(right: 9),
                    child: Pill(
                      c,
                      height: 40,
                      fontSize: 14,
                      black: category == c,
                      onTap: () => setState(() {
                        category = c;
                        page = 0;
                      }),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: list.isEmpty
                ? Center(
                    child: Text(
                      loading ? '正在加载' : '这个分类暂时还没有作品',
                      style: const TextStyle(color: gray),
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                    child: list.length == 1
                        ? tile(list[0])
                        : Column(
                            children: [
                              Expanded(
                                flex: 2,
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Expanded(
                                      flex: 3,
                                      child: Column(
                                        children: [
                                          Expanded(child: tile(list[0])),
                                          if (list.length > 2) ...[
                                            const SizedBox(height: 13),
                                            Expanded(child: tile(list[2])),
                                          ],
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 13),
                                    Expanded(flex: 4, child: tile(list[1])),
                                  ],
                                ),
                              ),
                              if (list.length > 3) ...[
                                const SizedBox(height: 13),
                                Expanded(child: tile(list[3])),
                              ],
                            ],
                          ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _CollectionPage extends StatefulWidget {
  const _CollectionPage({required this.device, required this.collection});
  final Json device, collection;
  @override
  State<_CollectionPage> createState() => _CollectionState();
}

class _CollectionState extends State<_CollectionPage> {
  bool busy = false;
  Future<void> add() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final a = Map<String, dynamic>.from(
        await api.request(
          '/catalog/${widget.collection['id']}/import',
          method: 'POST',
          data: {
            'orientation':
                widget.device['config']?['orientation'] ?? 'portrait',
          },
        ),
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
  Widget build(BuildContext context) {
    final a = widget.collection, url = '${api.base}${a['preview']}';
    return Shell(
      title: '画廊',
      child: ListView(
        padding: const EdgeInsets.all(23),
        children: [
          Center(
            child: ClipOval(
              child: Image.network(
                url,
                width: 88,
                height: 88,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    const SizedBox(height: 88, width: 88),
              ),
            ),
          ),
          const SizedBox(height: 22),
          Text(
            a['title'],
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 22),
          Text(
            a['description'] ?? '挑选你喜欢的画面，让光影成为日常的风景。',
            style: const TextStyle(color: gray, height: 1.8, fontSize: 15),
          ),
          const SizedBox(height: 22),
          Paper(
            padding: const EdgeInsets.all(17),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(15),
                  child: Image.network(
                    url,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const SizedBox(
                      height: 250,
                      child: Icon(Icons.image_outlined, color: gray),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  a['title'],
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (a['artist'] != null)
                  Text(a['artist'], style: const TextStyle(color: gray)),
                const SizedBox(height: 23),
                Pill(
                  '添加到画框',
                  icon: Icons.add,
                  black: true,
                  onTap: busy ? null : add,
                  loading: busy,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
