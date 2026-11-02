import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'api.dart';
import 'ui.dart';

class SharingPage extends StatefulWidget {
  const SharingPage({super.key, this.accept = false, this.device});
  final bool accept;
  final Json? device;
  @override
  State<SharingPage> createState() => _SharingState();
}

class _SharingState extends State<SharingPage> {
  final code = TextEditingController();
  String invite = '';
  List<Json> members = [];
  bool busy = false;
  @override
  void initState() {
    super.initState();
    if (!widget.accept && widget.device?['role'] == 'owner') load();
  }

  @override
  void dispose() {
    code.dispose();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final rows = await api.request('/devices/${widget.device!['id']}/shares');
      if (mounted) {
        setState(
          () => members = (rows as List)
              .map((r) => Map<String, dynamic>.from(r))
              .toList(),
        );
      }
    } catch (e) {
      notice(e);
    }
  }

  Future<void> generate() async {
    setState(() => busy = true);
    try {
      final r = await api.request(
        '/devices/${widget.device!['id']}/share',
        method: 'POST',
        data: {},
      );
      if (mounted) setState(() => invite = r['code']);
    } catch (e) {
      notice(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> accept() async {
    setState(() => busy = true);
    try {
      final r = await api.request(
        '/shares/accept',
        method: 'POST',
        data: {'code': code.text.trim().toUpperCase()},
      );
      api.selected = r['device_id'];
      notice('分享设备已添加');
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      notice(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Shell(
    title: widget.accept ? '添加分享设备' : '分享设备',
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 25, 22, 35),
      child: widget.accept
          ? Column(
              children: [
                const SizedBox(height: 15),
                _symbol(Icons.link),
                const SizedBox(height: 40),
                const Text(
                  '输入设备的分享码，即可添加设备',
                  style: TextStyle(color: Color(0xff6f7067), fontSize: 17),
                ),
                const SizedBox(height: 40),
                Paper(
                  child: Row(
                    children: [
                      const Icon(Icons.qr_code, color: gray),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextField(
                          controller: code,
                          autocorrect: false,
                          maxLength: 12,
                          decoration: const InputDecoration(
                            hintText: '请输入分享码',
                            counterText: '',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 30),
                SizedBox(
                  width: double.infinity,
                  child: Pill(
                    '添加',
                    icon: Icons.add,
                    black: true,
                    onTap: busy ? null : accept,
                    loading: busy,
                  ),
                ),
              ],
            )
          : widget.device?['role'] == 'member'
          ? Column(
              children: [
                _symbol(Icons.share_outlined),
                const SizedBox(height: 25),
                const Text('这是与你分享的相框'),
                const SizedBox(height: 30),
                Pill(
                  '退出共享',
                  black: true,
                  onTap: () async {
                    if (!await confirm(context, '退出共享', '确定不再使用这台分享设备？')) {
                      return;
                    }
                    try {
                      await api.request(
                        '/devices/${widget.device!['id']}/membership',
                        method: 'DELETE',
                      );
                      if (context.mounted) Navigator.pop(context, true);
                    } catch (e) {
                      notice(e);
                    }
                  },
                ),
              ],
            )
          : Column(
              children: [
                Paper(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    children: [
                      _symbol(Icons.reply_outlined),
                      const SizedBox(height: 24),
                      const Text(
                        '分享码用于将设备分享给他人。其他用户在添加设备时，选择“通过分享码添加”，输入分享码即可添加',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 18,
                          height: 1.7,
                          color: Color(0xff6f7067),
                        ),
                      ),
                      const SizedBox(height: 28),
                      SizedBox(
                        width: double.infinity,
                        child: Pill(
                          '生成分享码',
                          icon: Icons.refresh,
                          black: true,
                          onTap: busy ? null : generate,
                          loading: busy,
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 30),
                        child: Divider(color: Color(0xffeeeeea)),
                      ),
                      InkWell(
                        onTap: invite.isEmpty
                            ? null
                            : () {
                                Clipboard.setData(ClipboardData(text: invite));
                                notice('分享码已复制');
                              },
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 22),
                          decoration: BoxDecoration(
                            color: const Color(0xfff5f5f4),
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Flexible(
                                child: Text(
                                  invite.isEmpty ? '— — — —' : invite,
                                  style: const TextStyle(
                                    fontSize: 34,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 5,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              const Icon(Icons.copy, color: gray, size: 20),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        '分享码 24 小时内有效，添加一次后失效。复制给亲友，即可一起管理相框。',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: gray, height: 1.7),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                if (members.isNotEmpty)
                  Paper(
                    child: Column(
                      children: [
                        const Text(
                          '共享成员',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        for (final m in members)
                          ListTile(
                            title: Text(m['name']),
                            trailing: TextButton(
                              onPressed: () async {
                                if (!await confirm(
                                  context,
                                  '移除成员',
                                  '移除后对方将无法控制此相框。',
                                )) {
                                  return;
                                }
                                try {
                                  await api.request(
                                    '/devices/${widget.device!['id']}/shares/${m['handle']}',
                                    method: 'DELETE',
                                  );
                                  load();
                                } catch (e) {
                                  notice(e);
                                }
                              },
                              child: const Text('移除'),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
    ),
  );
  Widget _symbol(IconData icon) => Container(
    width: 88,
    height: 88,
    decoration: const BoxDecoration(
      shape: BoxShape.circle,
      color: Color(0xfff8f4e9),
    ),
    child: Icon(icon, color: gold, size: 42),
  );
}
