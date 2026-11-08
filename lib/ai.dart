import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'api.dart';
import 'ui.dart';

class AiPage extends StatefulWidget {
  const AiPage({
    super.key,
    required this.device,
    this.voice = false,
    this.referenceAsset,
    this.referenceBytes,
    this.autoLoad = true,
  });
  final Json device;
  final bool voice, autoLoad;
  final Json? referenceAsset;
  final Uint8List? referenceBytes;
  @override
  State<AiPage> createState() => _AiState();
}

class _AiState extends State<AiPage> with WidgetsBindingObserver {
  static const channel = MethodChannel('elecleap/native');
  final prompt = TextEditingController();
  String stage = 'styles',
      style = 'free',
      model = 'flash',
      mode = 'text',
      error = '';
  bool busy = false, recording = false, transcribing = false, active = true;
  int seconds = 0;
  Timer? pollTimer, recordTimer;
  Json? job, result, reference;
  Uint8List? referenceBytes;
  final styles = const [
    ('free', '自由创作'),
    ('oil', '油画风格'),
    ('cubist', '立体主义'),
    ('vangogh', '星空笔触'),
  ];
  String get storageKey => 'elecleap.ai-job.${widget.device['id']}';
  String get orientation =>
      widget.device['config']?['orientation'] ?? 'portrait';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    reference = widget.referenceAsset;
    referenceBytes = widget.referenceBytes;
    if (reference != null) {
      mode = 'doodle';
      stage = 'compose';
      prompt.text = '根据我的涂鸦，创作一幅生动的画。';
    }
    if (widget.voice) stage = 'compose';
    if (widget.autoLoad && reference == null) restore();
  }

  Future<void> restore() async {
    try {
      final id = await api.storage.read(key: storageKey);
      if (id != null && mounted) await observe(id);
    } catch (_) {
      /* A saved generation can also be opened from creation history. */
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    pollTimer?.cancel();
    recordTimer?.cancel();
    if (recording) {
      channel.invokeMethod<void>('audioCancel').catchError((Object _) {});
    }
    prompt.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    active = state == AppLifecycleState.resumed;
    if (!active) {
      pollTimer?.cancel();
      if (recording) stopRecording();
    } else if (job != null && ['queued', 'running'].contains(job!['status'])) {
      observe(job!['id']);
    }
  }

  void schedule() {
    pollTimer?.cancel();
    if (active) {
      pollTimer = Timer(const Duration(seconds: 2), () => observe(job!['id']));
    }
  }

  Future<void> observe(String id) async {
    try {
      final value = Map<String, dynamic>.from(
        await api.request('/ai/jobs/$id'),
      );
      if (!mounted) return;
      setState(() {
        job = value;
        if (reference?['id'] != value['reference']?['id']) {
          referenceBytes = null;
        }
        mode = value['mode'];
        reference = value['reference'] == null
            ? null
            : Map<String, dynamic>.from(value['reference']);
        prompt.text = value['prompt'];
        style = value['style'];
        model = value['model'];
        if (value['status'] == 'succeeded') {
          result = Map<String, dynamic>.from(value['asset']);
          stage = 'result';
          error = '';
        } else if (value['status'] == 'failed') {
          stage = 'compose';
          error = value['error'] ?? '生成失败，请重试';
        } else {
          stage = 'generating';
          error = '';
        }
      });
      if (['queued', 'running'].contains(value['status'])) schedule();
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString().replaceFirst('Exception: ', ''));
        if (job != null && stage == 'generating') schedule();
      }
    }
  }

  Future<void> generate() async {
    if (busy || recording || transcribing) return;
    if (prompt.text.trim().isEmpty) {
      setState(() => error = '先写下或说出你想画的内容');
      return;
    }
    setState(() {
      busy = true;
      error = '';
    });
    try {
      final value = Map<String, dynamic>.from(
        await api.request(
          '/ai/jobs',
          method: 'POST',
          data: {
            'request_key': 'ios-ai:${DateTime.now().microsecondsSinceEpoch}',
            'prompt': prompt.text.trim(),
            'mode': mode,
            'model': model,
            'style': style,
            'orientation': orientation,
            'input_asset': reference?['id'],
          },
        ),
      );
      await api.storage.write(key: storageKey, value: value['id']);
      if (mounted) {
        setState(() {
          job = value;
          if (reference?['id'] != value['reference']?['id']) {
            referenceBytes = null;
          }
          mode = value['mode'];
          reference = value['reference'] == null
              ? null
              : Map<String, dynamic>.from(value['reference']);
          stage = 'generating';
        });
        schedule();
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> pickReference() async {
    if (busy) return;
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1800,
        imageQuality: 93,
      );
      if (picked == null) return;
      if (mounted) setState(() => busy = true);
      final bytes = await picked.readAsBytes();
      final asset = await api.upload(bytes, orientation);
      if (mounted) {
        setState(() {
          reference = asset;
          referenceBytes = bytes;
          mode = 'image';
        });
      }
    } catch (e) {
      notice(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> record() async {
    if (busy || transcribing) return;
    if (recording) {
      await stopRecording();
      return;
    }
    try {
      await channel.invokeMethod<void>('audioStart');
      if (!mounted) {
        await channel.invokeMethod<void>('audioCancel');
        return;
      }
      setState(() {
        recording = true;
        seconds = 0;
        error = '';
      });
      recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => seconds++);
        if (seconds >= 60) stopRecording();
      });
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is PlatformException
              ? (e.message ?? '请允许麦克风权限')
              : '录音未能开始，请重试',
        );
      }
    }
  }

  Future<void> stopRecording() async {
    if (!recording) return;
    recordTimer?.cancel();
    setState(() {
      recording = false;
      transcribing = true;
      error = '';
    });
    try {
      final bytes = await channel.invokeMethod<Uint8List>('audioStop');
      if (bytes == null) throw Exception('没有可用的录音');
      final text = await api.transcribe(bytes);
      if (mounted) setState(() => prompt.text = text);
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => transcribing = false);
    }
  }

  Future<void> display() async {
    if (result == null || busy) return;
    setState(() => busy = true);
    try {
      await api.display(result!, key: 'ai:${job!['id']}');
      await api.storage.delete(key: storageKey);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      notice(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> history() async {
    try {
      final rows = await api.request('/ai/jobs') as List;
      if (!mounted) return;
      final id = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: cream,
        builder: (c) => SafeArea(
          child: rows.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(35),
                  child: Text('还没有作品，开始你的第一幅创作吧'),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: rows.length,
                  itemBuilder: (c, i) => ListTile(
                    leading: const LineIcon('brush', color: gold),
                    title: Text(
                      rows[i]['prompt'],
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      rows[i]['status'] == 'succeeded'
                          ? '创作完成'
                          : rows[i]['status'] == 'failed'
                          ? '生成未完成'
                          : '正在创作',
                    ),
                    onTap: () => Navigator.pop(c, rows[i]['id']),
                  ),
                ),
        ),
      );
      if (id != null) await observe(id);
    } catch (e) {
      notice(e);
    }
  }

  void again() {
    api.storage.delete(key: storageKey);
    setState(() {
      stage = 'compose';
      job = null;
      result = null;
      error = '';
    });
  }

  @override
  Widget build(BuildContext context) => Shell(
    title: mode == 'doodle'
        ? 'AI涂鸦'
        : widget.voice
        ? '语音生图'
        : 'AI绘画',
    actions: [
      IconButton(
        tooltip: '创作记录',
        onPressed: history,
        icon: const Icon(Icons.history, size: 23),
      ),
    ],
    footer: stage == 'styles'
        ? null
        : Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
            child: Row(
              children: [
                Expanded(
                  child: Pill(
                    stage == 'result'
                        ? '再画一张'
                        : stage == 'generating'
                        ? '稍后查看'
                        : '选风格',
                    outline: true,
                    height: 46,
                    onTap: busy || recording
                        ? null
                        : stage == 'result'
                        ? again
                        : stage == 'generating'
                        ? () => Navigator.pop(context)
                        : () => setState(() => stage = 'styles'),
                  ),
                ),
                if (stage != 'generating') ...[
                  const SizedBox(width: 14),
                  Expanded(
                    flex: 2,
                    child: Pill(
                      stage == 'result' ? '显示到画框' : '开始创作',
                      black: true,
                      height: 46,
                      loading: busy,
                      onTap: busy || recording || transcribing
                          ? null
                          : stage == 'result'
                          ? display
                          : generate,
                    ),
                  ),
                ],
              ],
            ),
          ),
    child: Column(
      children: [
        Expanded(
          child: stage == 'styles'
              ? styleGrid()
              : stage == 'compose'
              ? composer()
              : stage == 'result'
              ? resultView()
              : generating(),
        ),
        if (error.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 6, 22, 8),
            child: Text(
              error,
              style: const TextStyle(color: Color(0xffae5b4b), fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ),
      ],
    ),
  );
  Widget styleGrid() => Padding(
    padding: const EdgeInsets.fromLTRB(24, 18, 24, 18),
    child: Column(
      children: [
        Pill(
          '灵感随机选',
          icon: Icons.casino_outlined,
          outline: true,
          height: 44,
          onTap: () {
            prompt.text = '金色夕阳下，鲸鱼跃出蔚蓝大海，温暖而富有想象力的插画';
            setState(() => stage = 'compose');
          },
        ),
        const SizedBox(height: 22),
        Expanded(
          child: GridView.count(
            crossAxisCount: 2,
            crossAxisSpacing: 18,
            mainAxisSpacing: 18,
            childAspectRatio: .86,
            children: [
              for (final s in styles)
                GestureDetector(
                  onTap: () => setState(() {
                    style = s.$1;
                    stage = 'compose';
                    error = '';
                  }),
                  child: Column(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: s.$1 == 'free'
                              ? const ColoredBox(
                                  color: Colors.white,
                                  child: Center(
                                    child: LineIcon('brush', size: 72),
                                  ),
                                )
                              : Image.asset(
                                  'assets/styles/style-${s.$1}.jpg',
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                ),
                        ),
                      ),
                      const SizedBox(height: 9),
                      Text(
                        s.$2,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
  Widget composer() => LayoutBuilder(
    builder: (c, b) => SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 15, 22, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            mode == 'doodle'
                ? '让线条变成一幅画'
                : widget.voice
                ? '说出你的想象'
                : '你想画些什么？',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 7),
          Text(
            widget.voice ? '识别后可以修改文字，再开始创作' : '写下主体、场景和喜欢的氛围',
            style: const TextStyle(color: gray, fontSize: 13),
          ),
          const SizedBox(height: 18),
          if (reference != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  if (referenceBytes != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(
                        referenceBytes!,
                        width: 45,
                        height: 65,
                        fit: BoxFit.contain,
                      ),
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      mode == 'doodle' ? '我的涂鸦' : '参考图片',
                      style: const TextStyle(color: gray),
                    ),
                  ),
                  IconButton(
                    onPressed: () => setState(() {
                      reference = null;
                      referenceBytes = null;
                      mode = 'text';
                    }),
                    icon: const Icon(Icons.close, size: 20),
                  ),
                ],
              ),
            ),
          Container(
            padding: const EdgeInsets.all(17),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              children: [
                SizedBox(
                  height: math.max(
                    95,
                    math.min(
                      205,
                      b.maxHeight - (reference == null ? 275 : 345),
                    ),
                  ),
                  child: TextField(
                    controller: prompt,
                    maxLength: 1200,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    enabled: !busy && !transcribing,
                    decoration: const InputDecoration(
                      hintText: '例如：金色夕阳下，鲸鱼跃出蔚蓝的大海，明亮温暖的插画',
                      border: InputBorder.none,
                      counterText: '',
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: busy || recording ? null : pickReference,
                    icon: const LineIcon('image', size: 18),
                    label: const Text('参考图', style: TextStyle(color: gray)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Pill(
            transcribing
                ? '正在识别…'
                : recording
                ? '点击结束 · $seconds 秒'
                : '点击说出画面',
            glyph: 'mic',
            iconTint: gold,
            goldStyle: recording,
            height: 43,
            onTap: busy || transcribing ? null : record,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  styles.where((s) => s.$1 == style).firstOrNull?.$2 ?? '水彩插画',
                  style: const TextStyle(color: gray, fontSize: 13),
                ),
              ),
              for (final item in [('flash', '快速创作'), ('pro', '精细创作')])
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: ChoiceChip(
                    label: Text(item.$2, style: const TextStyle(fontSize: 12)),
                    selected: model == item.$1,
                    onSelected: busy
                        ? null
                        : (_) => setState(() => model = item.$1),
                    showCheckmark: false,
                    selectedColor: const Color(0xfff6f0df),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            '描述和所选参考图将用于云端创作',
            style: TextStyle(color: gray, fontSize: 11),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
  Widget resultView() => Padding(
    padding: const EdgeInsets.fromLTRB(22, 18, 22, 10),
    child: Column(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x22000000),
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Image.network(
              api.image(result!),
              headers: api.headers,
              fit: BoxFit.contain,
              gaplessPlayback: true,
              errorBuilder: (_, error, stack) =>
                  const Center(child: Text('预览加载失败，请稍后重试')),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          prompt.text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: gray, fontSize: 13),
        ),
        const SizedBox(height: 8),
        const Text('AI 创作', style: TextStyle(color: gray, fontSize: 12)),
      ],
    ),
  );
  Widget generating() => const Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        LineIcon('brush', size: 80, color: gold),
        SizedBox(height: 35),
        Text('正在创作画面', style: TextStyle(fontSize: 22)),
        SizedBox(height: 24),
        SizedBox(
          width: 25,
          height: 25,
          child: CircularProgressIndicator(strokeWidth: 2, color: gold),
        ),
        SizedBox(height: 25),
        Text('可以离开页面，作品会为你保留', style: TextStyle(color: gray, fontSize: 13)),
      ],
    ),
  );
}
