import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'api.dart';
import 'ui.dart';
import 'sharing.dart';
import 'provision.dart';
import 'main.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.device});
  final Json device;
  @override
  State<SettingsPage> createState() => _SettingsState();
}

class _SettingsState extends State<SettingsPage> {
  late Json device;
  String integrationKey = '';
  bool busy = false;
  Json get cfg => Map<String, dynamic>.from(device['config']);
  bool get owner => device['role'] == 'owner';
  @override
  void initState() {
    super.initState();
    device = widget.device;
  }

  Future<void> reload() async {
    final ds = await api.request('/devices');
    final d = (ds as List).where((d) => d['id'] == device['id']).firstOrNull;
    if (d != null && mounted) {
      setState(() => device = Map<String, dynamic>.from(d));
    }
  }

  Future<void> patch(Json values) async {
    if (!owner) return;
    try {
      await api.request(
        '/devices/${device['id']}/config',
        method: 'PATCH',
        data: {'mode': cfg['mode'] ?? 'smart', ...values},
      );
      await reload();
    } catch (e) {
      notice(e);
    }
  }

  Future<int?> select(String title, List<String> options) async =>
      showModalBottomSheet<int>(
        context: context,
        backgroundColor: cream,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (c) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(c).height * .7,
            ),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 25),
              children: [
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                for (var i = 0; i < options.length; i++)
                  ListTile(
                    title: Text(options[i]),
                    trailing: const Icon(Icons.chevron_right, color: gray),
                    onTap: () => Navigator.pop(c, i),
                  ),
              ],
            ),
          ),
        ),
      );
  Future<void> modes() async {
    final mode = await select('运行模式', ['智能模式', '快速模式', '节能模式']);
    if (mode == null) return;
    Json values = {
      'mode': ['smart', 'fast', 'eco'][mode],
    };
    if (mode == 0 && mounted) {
      final idle = await prompt(
        context,
        '无操作多久后进入节能（分钟）',
        value: '${cfg['idle_minutes'] ?? 30}',
      );
      if (idle == null) return;
      values['idle_minutes'] = int.tryParse(idle) ?? 0;
    }
    if (mode != 1 && mounted) {
      final p = await prompt(
        context,
        '节能联网间隔（分钟）',
        value: '${cfg['poll_minutes'] ?? 15}',
      );
      if (p == null) return;
      values['poll_minutes'] = int.tryParse(p) ?? 0;
    }
    await patch(values);
  }

  Future<void> transfer() async {
    try {
      final ds = (await api.request('/devices') as List)
          .where((d) => d['id'] != device['id'])
          .toList();
      if (ds.isEmpty) {
        notice('先添加另一台相框，就可以转移图片');
        return;
      }
      if (!mounted) return;
      final i = await select(
        '复制图片到',
        ds.map((d) => d['name'] as String).toList(),
      );
      if (i == null) return;
      final photos =
          await api.request('/devices/${device['id']}/album') as List;
      if (photos.isEmpty) {
        notice('相册还没有图片');
        return;
      }
      await api.request(
        '/devices/${device['id']}/album/transfer',
        method: 'POST',
        data: {
          'target_device': ds[i]['id'],
          'asset_ids': photos.map((a) => a['id']).toList(),
          'move': false,
        },
      );
      notice('图片已复制');
    } catch (e) {
      notice(e);
    }
  }

  Widget row(
    String name,
    String value, {
    VoidCallback? tap,
    bool copy = false,
  }) => InkWell(
    onTap: tap,
    child: Container(
      constraints: const BoxConstraints(minHeight: 67),
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xfff5f4f0))),
      ),
      child: Row(
        children: [
          Text(name, style: const TextStyle(color: Color(0xff6d6f65))),
          const SizedBox(width: 20),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 14,
                color: name == 'API Key' ? gray : ink,
              ),
            ),
          ),
          if (tap != null) ...[
            const SizedBox(width: 6),
            Icon(
              copy ? Icons.content_copy : Icons.chevron_right,
              size: 17,
              color: copy ? gold : const Color(0xffcbccc3),
            ),
          ],
        ],
      ),
    ),
  );
  Widget group(List<Widget> rows) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Paper(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 3),
      child: Column(children: rows),
    ),
  );
  Widget label(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 5, 0, 16),
    child: Text(text, style: const TextStyle(color: gray, fontSize: 13)),
  );
  @override
  Widget build(BuildContext context) {
    final telemetry = device['telemetry'] ?? {},
        minutes = cfg['slideshow_minutes'] ?? 0,
        mode = cfg['mode'] ?? 'smart';
    return Shell(
      title: '画框设置',
      child: ListView(
        padding: const EdgeInsets.all(22),
        children: [
          group([
            row(
              '名称',
              device['name'],
              tap: !owner
                  ? null
                  : () async {
                      final v = await prompt(
                        context,
                        '相框名称',
                        value: device['name'],
                      );
                      if (v == null || v.isEmpty) return;
                      try {
                        await api.request(
                          '/devices/${device['id']}/name',
                          method: 'PATCH',
                          data: {'name': v},
                        );
                        reload();
                      } catch (e) {
                        notice(e);
                      }
                    },
            ),
            row(
              '分享设备',
              '',
              tap: () => push(context, SharingPage(device: device)),
            ),
            row(
              '时区',
              (cfg['timezone'] ?? 'Asia/Shanghai')
                  .toString()
                  .replaceFirst('Asia/', '亚洲/')
                  .replaceFirst('Shanghai', '上海'),
              tap: !owner
                  ? null
                  : () async {
                      const values = [
                        'Asia/Shanghai',
                        'Asia/Hong_Kong',
                        'Asia/Tokyo',
                        'Europe/London',
                        'America/New_York',
                        'America/Los_Angeles',
                        'UTC',
                      ];
                      final i = await select('时区', [
                        '亚洲/上海',
                        '亚洲/香港',
                        '亚洲/东京',
                        '欧洲/伦敦',
                        '美洲/纽约',
                        '美洲/洛杉矶',
                        'UTC',
                      ]);
                      if (i != null) patch({'timezone': values[i]});
                    },
            ),
          ]),
          if (!owner)
            const Padding(
              padding: EdgeInsets.only(bottom: 24),
              child: Text(
                '此设备是与你共享的设备，你不是设备的主账号',
                textAlign: TextAlign.center,
                style: TextStyle(color: gray),
              ),
            ),
          group([
            row(
              '摆放方向',
              cfg['orientation'] == 'landscape' ? '横向' : '纵向',
              tap: !owner
                  ? null
                  : () async {
                      try {
                        await api.request(
                          '/devices/${device['id']}/orientation',
                          method: 'POST',
                          data: {
                            'orientation': cfg['orientation'] == 'landscape'
                                ? 'portrait'
                                : 'landscape',
                          },
                        );
                        reload();
                      } catch (e) {
                        notice(e);
                      }
                    },
            ),
            row(
              '轮播方式',
              cfg['slideshow_order'] == 'random' ? '随机' : '顺序',
              tap: !owner
                  ? null
                  : () async {
                      final i = await select('轮播方式', ['顺序', '随机']);
                      if (i != null) {
                        patch({
                          'slideshow_order': i == 0 ? 'sequence' : 'random',
                        });
                      }
                    },
            ),
            row(
              '轮播间隔',
              minutes == 0
                  ? '不轮播'
                  : minutes < 60
                  ? '$minutes 分钟'
                  : '${minutes / 60} 小时',
              tap: !owner
                  ? null
                  : () async {
                      final i = await select('轮播间隔', [
                        '不轮播',
                        '5分钟（续航非常短）',
                        '1小时（续航非常短）',
                        '6小时',
                        '12小时',
                        '24小时',
                        '48小时',
                        '每周',
                      ]);
                      if (i != null) {
                        patch({
                          'slideshow_minutes': [
                            0,
                            5,
                            60,
                            360,
                            720,
                            1440,
                            2880,
                            10080,
                          ][i],
                        });
                      }
                    },
            ),
            row(
              '轮播标签',
              (cfg['slideshow_tags'] as List? ?? []).isEmpty
                  ? '全部标签'
                  : (cfg['slideshow_tags'] as List).join(', '),
              tap: !owner
                  ? null
                  : () async {
                      try {
                        final photos =
                                await api.request(
                                      '/devices/${device['id']}/album',
                                    )
                                    as List,
                            tags = photos
                                .expand((a) => a['tags'] as List? ?? [])
                                .toSet()
                                .map((e) => e.toString())
                                .toList();
                        if (!mounted) return;
                        final i = await select('轮播标签', ['全部标签', ...tags]);
                        if (i != null) {
                          patch({
                            'slideshow_tags': i == 0 ? [] : [tags[i - 1]],
                          });
                        }
                      } catch (e) {
                        notice(e);
                      }
                    },
            ),
          ]),
          const Padding(
            padding: EdgeInsets.fromLTRB(10, 0, 10, 25),
            child: Text(
              '建议将轮播间隔设置为 12 小时以上，频繁切换图片会降低相框续航',
              style: TextStyle(fontSize: 13, color: gray, height: 1.7),
            ),
          ),
          label('用户设置'),
          group([
            row('积分', '0', tap: () => notice('开发版暂不使用积分，创作使用已配置的云端服务')),
            row('转移图片', '', tap: transfer),
          ]),
          label('蓝牙连接'),
          group([
            row(
              '通过蓝牙上传图片',
              '',
              tap: () =>
                  push(context, ProvisionPage(device: device, upload: true)),
            ),
            row(
              '重新配置 WiFi',
              '',
              tap: owner
                  ? () => push(context, ProvisionPage(device: device))
                  : null,
            ),
          ]),
          label('设备信息'),
          group([
            row(
              '休眠间隔',
              '${mode == 'smart'
                  ? '智能模式'
                  : mode == 'fast'
                  ? '快速模式'
                  : '节能模式'} ${mode == 'fast' ? '5秒' : '${cfg['poll_minutes']}分钟'}',
              tap: owner ? modes : null,
            ),
            row(
              '最后联网',
              device['last_seen'] == 0
                  ? '尚未连接'
                  : DateTime.fromMillisecondsSinceEpoch(
                      ((device['last_seen'] ?? 0) * 1000).toInt(),
                    ).toLocal().toString().substring(0, 16),
            ),
            row('分辨率', '800 × 480'),
            row('WiFi', telemetry['ssid'] ?? '等待设备上报'),
            row(
              'SD',
              telemetry['sd_present'] == false
                  ? '无 SD 卡（测试板）'
                  : telemetry['sd_present'] == true
                  ? '${telemetry['sd_used_mb'] ?? 0} / ${telemetry['sd_total_mb'] ?? 0} MB'
                  : '等待设备上报',
            ),
            row(
              '序列号',
              device['id'],
              copy: true,
              tap: () {
                Clipboard.setData(ClipboardData(text: device['id']));
                notice('序列号已复制');
              },
            ),
            row(
              '固件',
              telemetry['firmware'] ?? '等待设备上报',
              tap: () => notice('固件升级由开发版维护流程提供'),
            ),
            row('语言', '简体中文'),
            if (owner) ...[
              row(
                'API Key',
                integrationKey.isEmpty ? '点击下方生成' : integrationKey,
                copy: true,
                tap: integrationKey.isEmpty
                    ? null
                    : () {
                        Clipboard.setData(ClipboardData(text: integrationKey));
                        notice('API Key 已复制');
                      },
              ),
              Padding(
                padding: const EdgeInsets.only(left: 70, bottom: 18),
                child: Pill(
                  'Refresh API Key',
                  black: true,
                  height: 30,
                  onTap: () async {
                    if (!await confirm(
                      context,
                      '刷新 API Key',
                      '旧 Key 将立即失效，新 Key 只在此页显示。',
                    )) {
                      return;
                    }
                    try {
                      final r = await api.request(
                        '/devices/${device['id']}/api-key',
                        method: 'POST',
                        data: {},
                      );
                      if (mounted) setState(() => integrationKey = r['key']);
                    } catch (e) {
                      notice(e);
                    }
                  },
                ),
              ),
            ],
          ]),
          if (owner) ...[
            const SizedBox(height: 10),
            Pill(
              '恢复出厂设置',
              black: true,
              onTap: () async {
                if (!await confirm(
                  context,
                  '恢复出厂设置',
                  '重置运行设置并清除 WiFi，需要重新配网。云端相册和绑定关系保留。',
                )) {
                  return;
                }
                try {
                  await api.request(
                    '/devices/${device['id']}/reset',
                    method: 'POST',
                    data: {},
                  );
                  notice('相框下次联网时执行重置');
                  reload();
                } catch (e) {
                  notice(e);
                }
              },
            ),
            const SizedBox(height: 14),
          ],
          Pill(
            owner ? '解除绑定' : '退出共享',
            black: true,
            onTap: () async {
              if (!owner) {
                push(context, SharingPage(device: device));
                return;
              }
              if (!await confirm(
                context,
                '解除绑定',
                '共享成员也会失去访问权限，请保存随后生成的新绑定码。',
              )) {
                return;
              }
              try {
                final r = await api.request(
                  '/devices/${device['id']}/binding',
                  method: 'DELETE',
                );
                await Clipboard.setData(ClipboardData(text: r['claim_code']));
                if (!context.mounted) return;
                await showDialog<void>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: const Text('请保存新绑定码'),
                    content: SelectableText(r['claim_code']),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(c),
                        child: const Text('已复制，完成'),
                      ),
                    ],
                  ),
                );
                if (context.mounted) {
                  Navigator.popUntil(context, (r) => r.isFirst);
                }
              } catch (e) {
                notice(e);
              }
            },
          ),
          const Padding(
            padding: EdgeInsets.all(30),
            child: Text(
              'ElecLeap',
              textAlign: TextAlign.center,
              style: TextStyle(color: gray, letterSpacing: 2),
            ),
          ),
        ],
      ),
    );
  }
}

class AccountPage extends StatelessWidget {
  const AccountPage({super.key});
  @override
  Widget build(BuildContext context) => Shell(
    title: '我的',
    child: ListView(
      padding: const EdgeInsets.all(25),
      children: [
        Center(
          child: Image.asset('assets/ElecLeap.png', width: 80, height: 80),
        ),
        const SizedBox(height: 25),
        const Center(
          child: Text(
            'ElecLeap',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 35),
        Paper(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.link),
                title: const Text('关联小程序账号'),
                subtitle: const Text('同步已有相框、相册和控制权限'),
                onTap: () async {
                  final code = await prompt(
                    context,
                    '输入小程序关联码',
                    hint: '在小程序“我的”中生成12位关联码',
                  );
                  if (code == null) return;
                  try {
                    final r = await api.request(
                      '/account/link',
                      method: 'POST',
                      data: {'code': code},
                    );
                    await api.setSession(r);
                    notice('账号已关联');
                    if (context.mounted) Navigator.pop(context);
                  } catch (e) {
                    notice(e);
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.add_link),
                title: const Text('添加分享设备'),
                onTap: () => push(context, const SharingPage(accept: true)),
              ),
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: const Text('用户协议与隐私政策'),
                onTap: () => push(context, const LegalPage()),
              ),
              const ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('关于 ElecLeap'),
                trailing: Text('0.4.0'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 25),
        Pill(
          '退出登录',
          black: true,
          onTap: () async {
            try {
              await api.logout();
            } catch (_) {}
            if (context.mounted) {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const AuthPage()),
                (_) => false,
              );
            }
          },
        ),
        const SizedBox(height: 25),
        TextButton(
          onPressed: () async {
            if (!await confirm(
              context,
              '删除账号',
              '账号将停用并撤销登录，个人图库和公开作品将移除。请先解除自有相框绑定。',
            )) {
              return;
            }
            try {
              await api.request('/account', method: 'DELETE');
              await api.logout();
              if (context.mounted) {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const AuthPage()),
                  (_) => false,
                );
              }
            } catch (e) {
              notice(e);
            }
          },
          child: const Text('删除账号', style: TextStyle(color: gray)),
        ),
      ],
    ),
  );
}

class LegalPage extends StatelessWidget {
  const LegalPage({super.key});
  @override
  Widget build(BuildContext context) => const Shell(
    title: '用户协议与隐私政策',
    child: SingleChildScrollView(
      padding: EdgeInsets.all(28),
      child: Text(
        'ElecLeap 开发版\n\n照片与设备\n你选择的照片经过裁剪后上传至项目的腾讯云服务器，仅你的账号和与你共享设备的成员可访问。只有你主动选择“分享作品”时，作品才会公开。请仅上传你有权使用的内容。\n\n账号\n账号密码使用随机盐与迭代哈希保存在服务器。会话凭据保存在 iOS Keychain，退出登录后清除。你可以在“我的”删除账号；有自有设备时，需先解除绑定。删除操作会撤销会话并隐藏个人图库及作品；已共享到其他设备的图片和故障恢复备份可能继续保留，开发阶段如需彻底清除请联系项目维护者。\n\n权限\n相册和相机仅用于你主动选择或拍摄照片；蓝牙用于发现相框、加密配网和传图。WiFi 密码通过相框二维码密钥认证和加密后直达设备，不发送给业务服务器。\n\n第三方服务\n天气使用 Open-Meteo.com，天气数据遵循 CC BY 4.0。语音识别和图像生成使用火山引擎服务。仅在你主动录音或点击创作时，将录音、描述及所选参考图发送给相应服务。业务服务器不持久保存录音；生成的作品按账号保存，确认显示后加入相册。\n\n开发状态\n这是用于原型调测的开发版。软件保留必要的异常与任务状态用于排查，设备可在不同网络下通过云端通信。',
        style: TextStyle(fontSize: 16, height: 1.8),
      ),
    ),
  );
}
