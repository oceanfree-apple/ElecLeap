import 'dart:async';
import 'package:flutter/material.dart';
import 'api.dart';
import 'ui.dart';
import 'ble.dart';

class ProvisionPage extends StatefulWidget {
  const ProvisionPage({super.key, this.device, this.upload = false});
  final Json? device;
  final bool upload;
  @override
  State<ProvisionPage> createState() => _ProvisionState();
}

class _ProvisionState extends State<ProvisionPage> {
  late final BleLink link;
  StreamSubscription<Json>? listener;
  ElIdentity? identity;
  List<Json> devices = [], networks = [];
  int step = 1, progress = 0;
  bool scanning = false, busy = false, open = false, failed = false;
  String ssid = '', status = '';
  Json info = {};
  final password = TextEditingController();
  Timer? scanTimer;
  @override
  void initState() {
    super.initState();
    link = BleLink();
    listener = link.events.stream.listen((e) {
      if (!mounted) return;
      if (e['type'] == 'devices') {
        setState(
          () => devices = (e['devices'] as List)
              .map((r) => Map<String, dynamic>.from(r))
              .toList(),
        );
      }
      if (e['type'] == 'disconnected' && step < 5) {
        setState(() {
          step = 1;
          scanning = false;
          status = '蓝牙连接已断开，请重新连接';
        });
      }
    });
    scan();
  }

  @override
  void dispose() {
    listener?.cancel();
    scanTimer?.cancel();
    link.close();
    password.dispose();
    super.dispose();
  }

  Future<void> scan() async {
    if (scanning) return;
    setState(() {
      scanning = true;
      devices = [];
      status = '';
    });
    try {
      await link.scan();
      scanTimer?.cancel();
      scanTimer = Timer(const Duration(seconds: 15), () {
        link.stop();
        if (mounted) setState(() => scanning = false);
      });
    } catch (e) {
      if (mounted) setState(() => scanning = false);
      notice(e);
    }
  }

  Future<void> connect(Json d) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await link.stop();
      String? stored = widget.device == null
          ? null
          : await api.storage.read(key: 'elecleap.ble.${widget.device!['id']}');
      if (stored != null) {
        identity = ElIdentity.restore(stored);
      } else {
        final result = await native.invokeMethod<String>('scanQr');
        if (result == null) throw Exception('需要设备二维码完成安全认证');
        identity = ElIdentity.parse(result);
        await api.storage.write(
          key: 'elecleap.ble.${identity!.id}',
          value: identity!.encoded,
        );
      }
      final owned = await api.request('/devices') as List;
      if (!owned.any((e) => e['id'] == identity!.id)) {
        String claim = identity!.claim;
        try {
          await api.request(
            '/devices/bind',
            method: 'POST',
            data: {'device_id': identity!.id, 'claim_code': claim},
          );
        } catch (e) {
          if (!mounted) return;
          final v = await prompt(context, '输入新的绑定码', hint: '解除绑定后生成的绑定码');
          if (v == null) rethrow;
          claim = v;
          await api.request(
            '/devices/bind',
            method: 'POST',
            data: {'device_id': identity!.id, 'claim_code': claim},
          );
        }
      }
      api.selected = identity!.id;
      await link.connect(d['id']);
      await link.authenticate(identity!);
      final data = await link.command({'type': 'device_info'});
      if (mounted) {
        setState(() {
          info = data;
          step = 2;
          scanning = false;
        });
      }
      if (widget.upload) await upload();
    } catch (e) {
      notice(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> wifiScan() async {
    setState(() {
      step = 3;
      scanning = true;
      networks = [];
      status = '';
    });
    try {
      final r = await link.command({'type': 'wifi_scan'});
      if (mounted) {
        setState(
          () => networks = (r['networks'] as List)
              .map((e) => Map<String, dynamic>.from(e))
              .toList(),
        );
      }
    } catch (e) {
      notice(e);
    } finally {
      if (mounted) setState(() => scanning = false);
    }
  }

  Future<void> provision() async {
    setState(() {
      busy = true;
      step = 5;
      failed = false;
    });
    try {
      await link.wifi(ssid, open ? '' : password.text, (s) {
        if (mounted) setState(() => status = s);
      });
      if (mounted) {
        setState(() {
          step = 6;
          status = '相框已联网';
        });
      }
      password.clear();
    } catch (e) {
      if (mounted) {
        setState(() {
          failed = true;
          status = e.toString().replaceFirst('Exception: ', '');
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> upload() async {
    try {
      final jobs = await api.request('/devices/${api.selected}/jobs') as List;
      if (jobs.isEmpty) {
        notice('请先在相册中选择一张画面');
        return;
      }
      final photos =
          await api.request('/devices/${api.selected}/album') as List;
      final a = photos.where((a) => a['id'] == jobs.first['asset']).firstOrNull;
      if (a == null) {
        notice('当前画面不在相册中');
        return;
      }
      final bytes = await api.client.get(
        Uri.parse('${api.base}/api/assets/${a['id']}/panel'),
        headers: api.headers,
      );
      if (bytes.statusCode != 200) throw Exception('图片读取失败');
      if (mounted) {
        setState(() {
          step = 7;
          progress = 0;
        });
      }
      await link.image(bytes.bodyBytes, a['sha256'], (p) {
        if (mounted) setState(() => progress = p);
      });
      if (mounted) {
        setState(() {
          step = 6;
          status = '图片已通过蓝牙刷新到相框';
        });
      }
    } catch (e) {
      notice(e);
      if (mounted) setState(() => step = 2);
    }
  }

  @override
  Widget build(BuildContext context) => Shell(
    title: step < 5 ? '连接设备' : '画框',
    child: step >= 5
        ? Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(25),
              child: Column(
                children: [
                  const FloatingFrame(),
                  const SizedBox(height: 75),
                  Text(
                    step == 6
                        ? '连接完成'
                        : step == 7
                        ? '正在上传图片'
                        : failed
                        ? '连接未完成'
                        : '正在连接网络',
                    style: const TextStyle(fontSize: 25, letterSpacing: 3),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    step == 7
                        ? '$progress%'
                        : step == 6
                        ? status
                        : failed
                        ? status
                        : '大约需要几十秒',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: gray, fontSize: 16),
                  ),
                  const SizedBox(height: 25),
                  if (step != 6 && !failed)
                    const Text(
                      '· · ·',
                      style: TextStyle(fontSize: 25, color: gray),
                    ),
                  const SizedBox(height: 25),
                  const Text(
                    '长时间无法连接，请重新连接设备配置网络',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: gray, fontSize: 13),
                  ),
                  const SizedBox(height: 30),
                  if (failed)
                    Pill(
                      '重新配置',
                      black: true,
                      onTap: () => setState(() => step = 4),
                    ),
                  if (step == 6)
                    Pill(
                      '完成',
                      black: true,
                      onTap: () => Navigator.pop(context, true),
                    ),
                  const SizedBox(height: 45),
                  const Text(
                    'ElecLeap',
                    style: TextStyle(color: gray, letterSpacing: 2),
                  ),
                ],
              ),
            ),
          )
        : Padding(
            padding: const EdgeInsets.fromLTRB(25, 28, 25, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  step == 1
                      ? '通过蓝牙连接设备'
                      : step == 2
                      ? '设备信息'
                      : step == 3
                      ? '设置 WiFi'
                      : '设置 WiFi 密码',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 42),
                if (step == 1) ...[
                  Pill(
                    scanning ? '扫描中' : '重新扫描',
                    black: true,
                    icon: scanning ? null : Icons.refresh,
                    loading: scanning,
                    onTap: scan,
                    height: 62,
                  ),
                  const SizedBox(height: 25),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final d in devices)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 15),
                            child: Paper(
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      d['name'],
                                      style: const TextStyle(fontSize: 18),
                                    ),
                                  ),
                                  Pill(
                                    '连接',
                                    goldStyle: true,
                                    onTap: busy ? null : () => connect(d),
                                    height: 42,
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 30),
                  hint('请确保设备已经开机，并且手机打开了蓝牙。如果搜索不到设备，请长按配网键 3 秒后重试。'),
                  const SizedBox(height: 25),
                  hint('连接设备需要在 iPhone 系统设置中为 ElecLeap 打开蓝牙权限。'),
                  if (status.isNotEmpty) hint(status),
                ] else if (step == 2) ...[
                  Paper(
                    child: Column(
                      children: [
                        infoRow('型号', info['model'] ?? 'ElecLeap-7.3-inch'),
                        infoRow('固件', info['firmware'] ?? ''),
                        infoRow('序列号', info['device_id'] ?? ''),
                        infoRow('状态', '已激活', goldText: true),
                      ],
                    ),
                  ),
                  const SizedBox(height: 30),
                  hint('为设备设置 WiFi 网络，确保设备可以连接到互联网。'),
                  const SizedBox(height: 35),
                  Pill(
                    '设置 WiFi',
                    black: true,
                    icon: Icons.wifi,
                    onTap: wifiScan,
                    height: 62,
                  ),
                  if (widget.upload)
                    TextButton(
                      onPressed: upload,
                      child: const Text('通过蓝牙上传当前画面'),
                    ),
                ] else if (step == 3) ...[
                  Pill(
                    scanning ? '扫描中' : '刷新',
                    black: true,
                    loading: scanning,
                    icon: Icons.refresh,
                    onTap: wifiScan,
                    height: 62,
                  ),
                  const SizedBox(height: 25),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(30),
                      child: ColoredBox(
                        color: Colors.white,
                        child: ListView(
                          children: [
                            for (final n in networks)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                ),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 18,
                                  ),
                                  decoration: const BoxDecoration(
                                    border: Border(
                                      bottom: BorderSide(
                                        color: Color(0xfff2f1ec),
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          n['ssid'],
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 18),
                                        ),
                                      ),
                                      const SizedBox(width: 15),
                                      Pill(
                                        '选择',
                                        goldStyle: true,
                                        height: 42,
                                        onTap: () => setState(() {
                                          ssid = n['ssid'];
                                          open = n['open'] == true;
                                          password.clear();
                                          step = 4;
                                        }),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      final v = await prompt(
                        context,
                        '手动输入 WiFi',
                        hint: '隐藏网络的名称',
                      );
                      if (v != null && v.isNotEmpty) {
                        setState(() {
                          ssid = v;
                          step = 4;
                          open = false;
                        });
                      }
                    },
                    child: const Text(
                      '找不到网络？手动输入',
                      style: TextStyle(color: gray, fontSize: 13),
                    ),
                  ),
                  hint('设备只支持 2.4GHz 频率的 WiFi'),
                  const SizedBox(height: 20),
                  hint('如果连接手机热点，请打开“最大兼容性”选项'),
                ] else ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 16,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xfff3eedf),
                        borderRadius: BorderRadius.circular(40),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.wifi, color: gold),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              ssid,
                              style: const TextStyle(color: gold, fontSize: 18),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  Paper(
                    child: TextField(
                      controller: password,
                      obscureText: true,
                      enabled: !open,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(hintText: 'WiFi 密码'),
                    ),
                  ),
                  const SizedBox(height: 25),
                  Paper(
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            '连接到公共 WiFi，没有密码',
                            style: TextStyle(fontSize: 16),
                          ),
                        ),
                        Switch(
                          value: open,
                          activeTrackColor: gold,
                          onChanged: (v) => setState(() {
                            open = v;
                            password.clear();
                          }),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),
                  Pill(
                    '确定',
                    black: true,
                    icon: Icons.check,
                    onTap: open || password.text.length >= 8 ? provision : null,
                    height: 62,
                  ),
                ],
              ],
            ),
          ),
  );
  Widget hint(String s) => Text(
    s,
    textAlign: TextAlign.center,
    style: const TextStyle(color: gray, fontSize: 14, height: 1.8),
  );
  Widget infoRow(String label, String value, {bool goldText = false}) =>
      Container(
        constraints: const BoxConstraints(minHeight: 65),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xfff3f2ed))),
        ),
        child: Row(
          children: [
            Text(
              label,
              style: const TextStyle(color: Color(0xff878980), fontSize: 16),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: TextStyle(color: goldText ? gold : ink, fontSize: 16),
              ),
            ),
          ],
        ),
      );
}
