import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'api.dart';
import 'ui.dart';
import 'crop.dart';
import 'album.dart';
import 'settings.dart';
import 'sharing.dart';
import 'provision.dart';
import 'extras.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
  await api.restore();
  runApp(const ElecLeapApp());
}

class ElecLeapApp extends StatelessWidget {
  const ElecLeapApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'ElecLeap',
    debugShowCheckedModeBanner: false,
    scaffoldMessengerKey: messengerKey,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: gold, surface: cream),
      scaffoldBackgroundColor: cream,
      textTheme: const TextTheme(bodyMedium: TextStyle(color: ink)),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xfff8f8f7),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xffe4e4e8)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xffe4e4e8), width: 2),
        ),
      ),
    ),
    home: api.token.isEmpty ? const AuthPage() : const DeviceList(),
  );
}

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});
  @override
  State<AuthPage> createState() => _AuthState();
}

class _AuthState extends State<AuthPage> {
  final name = TextEditingController(),
      password = TextEditingController(),
      repeat = TextEditingController();
  bool register = false, busy = false, show = false, agreed = false;
  @override
  void dispose() {
    name.dispose();
    password.dispose();
    repeat.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (busy) return;
    if (!agreed) {
      notice('请先阅读并同意用户协议与隐私政策');
      return;
    }
    if (name.text.trim().length < 4 || password.text.length < 8) {
      notice('账号至少4位，密码至少8位');
      return;
    }
    if (register && password.text != repeat.text) {
      notice('两次输入的密码不一致');
      return;
    }
    setState(() => busy = true);
    try {
      await api.authenticate(name.text, password.text, register);
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const DeviceList()),
          (_) => false,
        );
      }
    } catch (e) {
      notice(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Shell(
    title: '',
    child: SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 30),
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 30),
            Center(
              child: Image.asset('assets/ElecLeap.png', width: 85, height: 85),
            ),
            const SizedBox(height: 24),
            const Text(
              'ElecLeap',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 31,
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              register ? '开启你的画框生活' : '让喜欢的瞬间，留在眼前',
              textAlign: TextAlign.center,
              style: const TextStyle(color: gray, fontSize: 16),
            ),
            const SizedBox(height: 45),
            Paper(
              child: Column(
                children: [
                  TextField(
                    controller: name,
                    autofillHints: const [AutofillHints.username],
                    autocorrect: false,
                    decoration: const InputDecoration(
                      hintText: '账号 / 邮箱',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: password,
                    autofillHints: [
                      register
                          ? AutofillHints.newPassword
                          : AutofillHints.password,
                    ],
                    obscureText: !show,
                    decoration: InputDecoration(
                      hintText: '密码（至少8位）',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => show = !show),
                        icon: Icon(
                          show
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                      ),
                    ),
                  ),
                  if (register) ...[
                    const SizedBox(height: 18),
                    TextField(
                      controller: repeat,
                      obscureText: !show,
                      decoration: const InputDecoration(
                        hintText: '再次输入密码',
                        prefixIcon: Icon(Icons.lock_outline),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 26),
            Pill(
              register ? '注册并进入' : '登录',
              black: true,
              onTap: busy ? null : submit,
              loading: busy,
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => setState(() => register = !register),
              child: Text(register ? '已有账号，去登录' : '还没有账号？注册'),
            ),
            Row(
              children: [
                Checkbox(
                  value: agreed,
                  activeColor: gold,
                  onChanged: (v) => setState(() => agreed = v ?? false),
                ),
                const Flexible(
                  child: Text(
                    '我已阅读并同意',
                    style: TextStyle(fontSize: 12, color: gray),
                  ),
                ),
                TextButton(
                  onPressed: () => push(context, const LegalPage()),
                  child: const Text(
                    '用户协议与隐私政策',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 15),
          ],
        ),
      ),
    ),
  );
}

class DeviceList extends StatefulWidget {
  const DeviceList({super.key});
  @override
  State<DeviceList> createState() => _DeviceListState();
}

class _DeviceListState extends State<DeviceList> {
  List<Json> devices = [];
  bool loading = true, polling = false;
  Timer? timer;
  @override
  void initState() {
    super.initState();
    load();
    timer = Timer.periodic(const Duration(seconds: 12), (_) => load());
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> load() async {
    if (polling) return;
    polling = true;
    try {
      final rows = await api.request('/devices');
      if (mounted) {
        setState(() {
          devices = (rows as List)
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => loading = false);
        if (api.token.isEmpty) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const AuthPage()),
            (_) => false,
          );
        } else {
          notice(e);
        }
      }
    } finally {
      polling = false;
    }
  }

  Future<void> add() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: cream,
      showDragHandle: true,
      builder: (c) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 35),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '添加相框',
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 22),
            ListTile(
              leading: const Icon(Icons.bluetooth, color: gold),
              title: const Text('通过蓝牙连接设备'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.pop(c);
                push(context, const ProvisionPage()).then((_) => load());
              },
            ),
            ListTile(
              leading: const Icon(Icons.link, color: gold),
              title: const Text('通过分享码添加'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.pop(c);
                push(
                  context,
                  const SharingPage(accept: true),
                ).then((_) => load());
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Shell(
    title: 'ElecLeap',
    actions: [
      IconButton(
        onPressed: () => push(context, const AccountPage()).then((_) => load()),
        icon: const Icon(Icons.person_outline),
      ),
    ],
    footer: footer([
      const Text('留住每一个值得看见的瞬间', style: TextStyle(color: gray, fontSize: 12)),
      Pill('添加', icon: Icons.add, onTap: add),
    ]),
    child: loading
        ? const Center(child: CircularProgressIndicator(color: gold))
        : devices.isEmpty
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const FloatingFrame(),
                const SizedBox(height: 45),
                const Text('把你的第一幅画，放进相框', style: TextStyle(color: gray)),
                const SizedBox(height: 26),
                Pill('添加相框', black: true, onTap: add),
              ],
            ),
          )
        : RefreshIndicator(
            color: gold,
            onRefresh: load,
            child: ListView.separated(
              padding: const EdgeInsets.all(24),
              itemCount: devices.length,
              separatorBuilder: (_, _) => const SizedBox(height: 22),
              itemBuilder: (c, i) {
                final d = devices[i];
                return InkWell(
                  borderRadius: BorderRadius.circular(30),
                  onTap: () async {
                    api.selected = d['id'];
                    await push(context, WorkspacePage(device: d));
                    load();
                  },
                  child: Paper(
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 68,
                          height: 108,
                          child: FrameArt(padding: 8),
                        ),
                        const SizedBox(width: 25),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                d['name'],
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '7.3 inch  ·  ${d['online'] == true
                                    ? 'Online'
                                    : d['sleeping'] == true
                                    ? 'Sleeping'
                                    : 'Offline'}',
                                style: const TextStyle(color: gray),
                              ),
                              const SizedBox(height: 18),
                              Row(
                                children: [
                                  Icon(
                                    d['online'] == true
                                        ? Icons.wifi
                                        : Icons.wifi_off,
                                    size: 19,
                                  ),
                                  const SizedBox(width: 15),
                                  Icon(
                                    d['power_source'] == 'usb'
                                        ? Icons.usb
                                        : Icons.battery_std,
                                    size: 20,
                                  ),
                                  if (d['battery'] != null)
                                    Text(' ${d['battery']}%'),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right, color: gray),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
  );
}

class WorkspacePage extends StatefulWidget {
  const WorkspacePage({
    super.key,
    required this.device,
    this.initialAsset,
    this.autoLoad = true,
    this.initialJob,
  });
  final Json device;
  final Json? initialAsset, initialJob;
  final bool autoLoad;
  @override
  State<WorkspacePage> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<WorkspacePage> {
  late Json device;
  Json? asset, job;
  int count = 0;
  bool busy = false, polling = false;
  Timer? timer;
  @override
  void initState() {
    super.initState();
    device = widget.device;
    asset = widget.initialAsset;
    job = widget.initialJob;
    if (widget.autoLoad) {
      load();
      timer = Timer.periodic(const Duration(milliseconds: 2300), (_) => load());
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> load() async {
    if (polling) return;
    polling = true;
    try {
      final ds = await api.request('/devices'),
          list = await api.request('/devices/${api.selected}/album'),
          jobs = await api.request('/devices/${api.selected}/jobs');
      final d = (ds as List).where((d) => d['id'] == api.selected).firstOrNull;
      if (d == null) {
        if (mounted) Navigator.pop(context);
        return;
      }
      final j = (jobs as List).firstOrNull;
      Json? a;
      if (j != null) {
        final found = (list as List)
            .where((a) => a['id'] == j['asset'])
            .firstOrNull;
        a = found == null
            ? {
                'id': j['asset'],
                'preview': '/api/assets/${j['asset']}/preview',
                'picture': '/api/assets/${j['asset']}/picture',
              }
            : Map<String, dynamic>.from(found);
      }
      if (mounted) {
        setState(() {
          device = Map<String, dynamic>.from(d);
          job = j == null ? null : Map<String, dynamic>.from(j);
          asset = a;
          count = (list as List).length;
        });
      }
    } catch (e) {
      if (mounted && api.token.isEmpty) notice('登录已过期，请返回重新登录');
    } finally {
      polling = false;
    }
  }

  Future<void> action(Future<void> Function() f) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await f();
      await load();
    } catch (e) {
      notice(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void photo() =>
      push(context, PhotoEditor(device: device)).then((_) => load());
  void ai() => notice('AI 功能暂未开通');
  @override
  Widget build(BuildContext context) {
    final portrait = device['config']?['orientation'] != 'landscape',
        refreshing =
            job != null && ['queued', 'downloaded'].contains(job!['status']),
        progress = (job?['progress'] ?? 4) as int;
    return Shell(
      title: '画框',
      footer: footer([
        TextButton.icon(
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            textStyle: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontSize: 14),
          ),
          onPressed: busy || device['role'] != 'owner'
              ? null
              : () => action(() async {
                  await api.request(
                    '/devices/${api.selected}/orientation',
                    method: 'POST',
                    data: {'orientation': portrait ? 'landscape' : 'portrait'},
                  );
                }),
          icon: const Icon(Icons.screen_rotation_outlined, size: 20),
          label: Text(portrait ? '纵向' : '横向'),
        ),
        TextButton.icon(
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            textStyle: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontSize: 14),
          ),
          onPressed: () =>
              push(context, SettingsPage(device: device)).then((_) => load()),
          icon: const Icon(Icons.settings_outlined, size: 20),
          label: const Text('设置'),
        ),
        const Spacer(),
        TextButton.icon(
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            textStyle: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontSize: 14),
          ),
          onPressed: () =>
              push(context, AlbumPage(device: device)).then((_) => load()),
          icon: const Icon(Icons.image_outlined, size: 20),
          label: Text('相册 $count'),
        ),
      ]),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      device['name'] ?? 'ElecLeap',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Icon(Icons.monetization_on_outlined, size: 20),
                  const Text(' 0   '),
                  Icon(
                    device['online'] == true ? Icons.wifi : Icons.wifi_off,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Icon(
                    device['power_source'] == 'usb'
                        ? Icons.usb
                        : Icons.battery_std,
                    size: 23,
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 65,
              child: refreshing
                  ? Center(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(40),
                        child: SizedBox(
                          width: 225,
                          height: 42,
                          child: Stack(
                            children: [
                              const Positioned.fill(
                                child: ColoredBox(color: Colors.white),
                              ),
                              AnimatedFractionallySizedBox(
                                duration: const Duration(seconds: 1),
                                widthFactor: progress / 100,
                                heightFactor: 1,
                                child: const ColoredBox(
                                  color: Color(0xff646660),
                                ),
                              ),
                              Center(
                                child: Text(
                                  '正在刷新画框 $progress%',
                                  style: const TextStyle(
                                    color: gold,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _round(
                          Icons.skip_next_outlined,
                          () => action(() async {
                            await api.request(
                              '/devices/${api.selected}/next',
                              method: 'POST',
                              data: {},
                            );
                          }),
                        ),
                        _round(
                          Icons.download_outlined,
                          asset == null ? null : () => savePhoto(asset!),
                        ),
                        _round(
                          Icons.delete_outline,
                          asset == null
                              ? null
                              : () => action(() async {
                                  if (!await confirm(
                                    context,
                                    '删除图片',
                                    '从相框相册移除当前图片？',
                                  )) {
                                    return;
                                  }
                                  await api.request(
                                    '/devices/${api.selected}/album/${asset!['id']}',
                                    method: 'DELETE',
                                  );
                                }),
                        ),
                        _round(
                          Icons.share_outlined,
                          asset == null
                              ? null
                              : () => action(() async {
                                  if (!await confirm(
                                    context,
                                    '分享作品',
                                    '公开到创意广场，其他用户将可以看到这张图片。',
                                  )) {
                                    return;
                                  }
                                  await api.request(
                                    '/community',
                                    method: 'POST',
                                    data: {
                                      'asset_id': asset!['id'],
                                      'caption': '',
                                    },
                                  );
                                  notice('作品已分享');
                                }),
                        ),
                      ],
                    ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (c, b) {
                  final ratio = portrait ? 0.64 : 1.56;
                  return Center(
                    child: SizedBox(
                      width: (b.maxHeight - 12) * ratio > b.maxWidth - 35
                          ? b.maxWidth - 35
                          : (b.maxHeight - 12) * ratio,
                      child: GestureDetector(
                        onTap: asset == null ? photo : null,
                        child: FrameArt(asset: asset, portrait: portrait),
                      ),
                    ),
                  );
                },
              ),
            ),
            if (job?['status'] == 'failed')
              TextButton(
                onPressed: () => action(() async {
                  if (asset != null) await api.display(asset!);
                }),
                child: const Text(
                  '刷新未完成，点击重试',
                  style: TextStyle(color: Color(0xffb24e3e)),
                ),
              ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: Pill(
                    'AI 绘画',
                    icon: Icons.camera_outlined,
                    outline: true,
                    onTap: ai,
                    height: 48,
                    fontSize: 16,
                    horizontal: 8,
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 62,
                  child: Pill(
                    '',
                    icon: Icons.mic_none_outlined,
                    outline: true,
                    onTap: ai,
                    height: 48,
                    fontSize: 16,
                    horizontal: 8,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Pill(
                    'AI 涂鸦',
                    icon: Icons.brush_outlined,
                    outline: true,
                    onTap: () => push(context, DrawPage(device: device)),
                    height: 48,
                    fontSize: 16,
                    horizontal: 8,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _tool(
                  '创意',
                  Icons.share_outlined,
                  () => push(
                    context,
                    CatalogPage(device: device, community: true),
                  ),
                ),
                _tool(
                  '画廊',
                  Icons.image_outlined,
                  () => push(context, CatalogPage(device: device)),
                ),
                _tool('图片', Icons.add, photo),
                _tool(
                  '小组件',
                  Icons.calendar_today_outlined,
                  () => push(
                    context,
                    WidgetPage(device: device),
                  ).then((_) => load()),
                ),
              ],
            ),
            const SizedBox(height: 23),
          ],
        ),
      ),
    );
  }

  Widget _round(IconData icon, VoidCallback? tap) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: IconButton.filledTonal(
      onPressed: tap,
      style: IconButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: ink,
        fixedSize: const Size(43, 43),
      ),
      icon: Icon(icon, size: 23),
    ),
  );
  Widget _tool(String label, IconData icon, VoidCallback tap) => Expanded(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Pill(
        label,
        icon: icon,
        onTap: tap,
        outline: true,
        height: 38,
        fontSize: 14,
        iconSize: 17,
        horizontal: 7,
      ),
    ),
  );
}
