import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'api.dart';
import 'ui.dart';

const widgetTemplates = <Json>[
  {
    'id': 'calendar-large',
    'kind': 'calendar',
    'template': 'large',
    'title': '大字体日历',
  },
  {
    'id': 'weather-large',
    'kind': 'weather',
    'template': 'large',
    'title': '天气日历',
  },
  {
    'id': 'weather-corner',
    'kind': 'weather',
    'template': 'corner',
    'title': '角落天气',
  },
  {'id': 'lunar-card', 'kind': 'lunar', 'template': 'card', 'title': '农历日历'},
  {'id': 'quote-card', 'kind': 'quote', 'template': 'card', 'title': '每日一句'},
  {
    'id': 'countdown-card',
    'kind': 'countdown',
    'template': 'card',
    'title': '项目倒计时',
  },
  {
    'id': 'countup-card',
    'kind': 'countup',
    'template': 'card',
    'title': '时光正计时',
  },
];
const widgetCities = <Json>[
  {'name': '深圳', 'latitude': 22.54, 'longitude': 114.06},
  {'name': '上海', 'latitude': 31.23, 'longitude': 121.47},
  {'name': '北京', 'latitude': 39.90, 'longitude': 116.40},
  {'name': '杭州', 'latitude': 30.27, 'longitude': 120.16},
  {'name': '广州', 'latitude': 23.13, 'longitude': 113.26},
  {'name': '成都', 'latitude': 30.57, 'longitude': 104.07},
];

class WidgetPage extends StatefulWidget {
  const WidgetPage({super.key, required this.device});
  final Json device;
  @override
  State<WidgetPage> createState() => _WidgetState();
}

class _WidgetState extends State<WidgetPage> {
  late Json device;
  String tab = 'current';
  String? background;
  bool busy = false, loading = true;
  int generation = 0;
  List<Json> cards = [];
  final cache = <String, Json>{};
  final tabs = const [
    ('current', '当前使用'),
    ('recommend', '推荐'),
    ('weather', '天气'),
    ('lunar', '农历'),
    ('daily', '单向历'),
    ('countdown', '倒计时'),
    ('countup', '正计时'),
    ('push', '推送'),
  ];
  Json get plan {
    final c = device['config'] as Map;
    if (c['widget']?['enabled'] == true) {
      return Map<String, dynamic>.from(c['widget']);
    }
    if (c['weather']?['enabled'] == true) {
      return {
        ...Map<String, dynamic>.from(c['weather']),
        'kind': 'weather',
        'template': 'large',
      };
    }
    return Map<String, dynamic>.from(c['widget'] ?? {});
  }

  bool active(Json t) =>
      plan['enabled'] == true &&
      plan['kind'] == t['kind'] &&
      (plan['template'] ?? (plan['kind'] == 'lunar' ? 'card' : 'large')) ==
          t['template'];
  String day(DateTime d) => d.toIso8601String().substring(0, 10);
  @override
  void initState() {
    super.initState();
    device = Map<String, dynamic>.from(widget.device);
    load();
  }

  Future<void> load() async {
    try {
      final devices = await api.request('/devices') as List;
      final matches = devices.where((d) => d['id'] == device['id']);
      if (matches.isNotEmpty) device = Map<String, dynamic>.from(matches.first);
      final album = await api.request('/devices/${device['id']}/album') as List;
      background = plan['background_asset'];
      if (background == null) {
        for (final a in album) {
          if (!['widget', 'weather'].contains(a['meta']?['kind'])) {
            background = a['id'];
            break;
          }
        }
      }
      if (plan['enabled'] != true && tab == 'current') tab = 'recommend';
      await preview();
    } catch (e) {
      if (mounted) {
        setState(() => loading = false);
        notice(e);
      }
    }
  }

  Json body(Json t) => {
    'kind': t['kind'],
    'template': t['template'],
    'city': plan['city'] ?? '深圳',
    'latitude': plan['latitude'] ?? 22.54,
    'longitude': plan['longitude'] ?? 114.06,
    'background_asset': background,
    'orientation': device['config']?['orientation'] ?? 'portrait',
    'event_title': plan['kind'] == t['kind']
        ? (plan['event_title'] ?? '我的目标')
        : '我的目标',
    'target_date': ['countdown', 'countup'].contains(t['kind'])
        ? (plan['kind'] == t['kind']
              ? plan['target_date'] ?? day(DateTime.now())
              : day(DateTime.now()))
        : null,
  };
  Future<Json> render(Json values) async {
    final key = jsonEncode(values);
    if (cache.containsKey(key)) return cache[key]!;
    final a = Map<String, dynamic>.from(
      await api.request('/widgets/preview', method: 'POST', data: values),
    );
    cache[key] = a;
    return a;
  }

  Future<void> preview() async {
    if (!mounted) return;
    final g = ++generation;
    final list = widgetTemplates
        .where(
          (t) => tab == 'current'
              ? active(t)
              : tab == 'recommend'
              ? [
                  'calendar-large',
                  'weather-corner',
                  'lunar-card',
                ].contains(t['id'])
              : (tab == 'daily' || tab == 'push')
              ? t['kind'] == 'quote'
              : t['kind'] == tab,
        )
        .toList();
    setState(() {
      loading = true;
      cards = list.map((t) => {...t, 'loading': true}).toList();
    });
    final result = await Future.wait(
      list.map((t) async {
        try {
          return {...t, 'asset': await render(body(t))};
        } catch (e) {
          return {...t, 'error': '暂时无法加载，点击重试'};
        }
      }),
    );
    if (mounted && g == generation) {
      setState(() {
        cards = result;
        loading = false;
      });
    }
  }

  Future<DateTime?> pickDate(DateTime initial) async {
    var value = initial;
    return showModalBottomSheet<DateTime>(
      context: context,
      backgroundColor: Colors.white,
      builder: (d) => SafeArea(
        child: SizedBox(
          height: 310,
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(d),
                    child: const Text('取消'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(d, value),
                    child: const Text('完成'),
                  ),
                ],
              ),
              Expanded(
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.date,
                  initialDateTime: initial,
                  minimumYear: 1970,
                  maximumYear: 2100,
                  onDateTimeChanged: (v) => value = v,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<Json?> searchCity() async {
    final q = await prompt(context, '选择城市', hint: '输入城市名称');
    if (q == null || q.length < 2) return null;
    try {
      final results =
          await api.request('/locations?city=${Uri.encodeComponent(q)}')
              as List;
      if (!mounted) return null;
      if (results.isEmpty) {
        notice('没有找到该城市，请换一个名称');
        return null;
      }
      return showModalBottomSheet<Json>(
        context: context,
        backgroundColor: Colors.white,
        showDragHandle: true,
        builder: (d) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final c in results)
                ListTile(
                  title: Text(c['name']),
                  subtitle: Text('${c['region']} ${c['country']}'),
                  onTap: () => Navigator.pop(d, Map<String, dynamic>.from(c)),
                ),
            ],
          ),
        ),
      );
    } catch (e) {
      notice(e);
      return null;
    }
  }

  Future<void> configure(Json t) async {
    if (busy || t['asset'] == null) return;
    var city = <String, dynamic>{
      'name': plan['city'] ?? '深圳',
      'latitude': plan['latitude'] ?? 22.54,
      'longitude': plan['longitude'] ?? 114.06,
    };
    final counter = ['countdown', 'countup'].contains(t['kind']),
        controller = TextEditingController(
          text: plan['kind'] == t['kind'] ? plan['event_title'] ?? '' : '',
        );
    DateTime? date = plan['kind'] == t['kind']
        ? DateTime.tryParse(plan['target_date'] ?? '')
        : null;
    final values = await showModalBottomSheet<Json>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (d) => StatefulBuilder(
        builder: (d, update) => Padding(
          padding: EdgeInsets.fromLTRB(
            25,
            8,
            25,
            MediaQuery.viewInsetsOf(d).bottom + 25,
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  t['title'],
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 25),
                if (counter) ...[
                  TextField(
                    controller: controller,
                    maxLength: 40,
                    decoration: const InputDecoration(
                      labelText: '项目名称',
                      hintText: '输入项目名称',
                      counterText: '',
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(t['kind'] == 'countdown' ? '截止时间' : '起始时间'),
                    trailing: Text(
                      date == null ? '请选择' : day(date!),
                      style: const TextStyle(color: gold),
                    ),
                    onTap: () async {
                      final result = await pickDate(date ?? DateTime.now());
                      if (result != null && d.mounted) {
                        update(() => date = result);
                      }
                    },
                  ),
                ] else if (t['kind'] != 'quote') ...[
                  Row(
                    children: [
                      const Text('城市'),
                      const Spacer(),
                      DropdownButton<String>(
                        value:
                            widgetCities.any((c) => c['name'] == city['name'])
                            ? city['name']
                            : null,
                        hint: Text(city['name']),
                        underline: const SizedBox(),
                        items: [
                          for (final c in widgetCities)
                            DropdownMenuItem(
                              value: c['name'] as String,
                              child: Text(
                                c['name'],
                                style: const TextStyle(color: gold),
                              ),
                            ),
                        ],
                        onChanged: (name) => update(
                          () => city = Map<String, dynamic>.from(
                            widgetCities.firstWhere((c) => c['name'] == name),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () async {
                        final c = await searchCity();
                        if (c != null && d.mounted) update(() => city = c);
                      },
                      child: const Text(
                        '选择其他城市',
                        style: TextStyle(color: gray, fontSize: 13),
                      ),
                    ),
                  ),
                ] else
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                      '每天更新一句生活日签，保留你喜欢的照片。',
                      style: TextStyle(color: gray),
                    ),
                  ),
                const SizedBox(height: 25),
                Row(
                  children: [
                    Expanded(
                      child: Pill(
                        '取消',
                        height: 45,
                        onTap: () => Navigator.pop(d),
                      ),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Pill(
                        '确定',
                        black: true,
                        height: 45,
                        onTap: () {
                          if (counter &&
                              (controller.text.trim().isEmpty ||
                                  date == null)) {
                            notice('请输入项目名称并选择日期');
                            return;
                          }
                          Navigator.pop(d, {
                            ...body(t),
                            'city': city['name'],
                            'latitude': city['latitude'],
                            'longitude': city['longitude'],
                            'event_title': controller.text.trim().isEmpty
                                ? '我的目标'
                                : controller.text.trim(),
                            'target_date': counter ? day(date!) : null,
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));
    controller.dispose();
    if (values == null || !mounted) return;
    setState(() => busy = true);
    try {
      final asset = await render(values),
          r = await api.request(
            '/devices/${device['id']}/widget',
            method: 'PUT',
            data: {
              ...values,
              'enabled': true,
              'interval_minutes': plan['interval_minutes'] ?? 180,
            },
          );
      device = {...device, 'config': r['config']};
      await api.display(asset);
      await preview();
      notice('已应用到相框');
    } catch (e) {
      notice(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> disable() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final p = plan,
          r = await api.request(
            '/devices/${device['id']}/widget',
            method: 'PUT',
            data: {
              ...p,
              'enabled': false,
              'interval_minutes': p['interval_minutes'] ?? 180,
            },
          );
      device = {...device, 'config': r['config']};
      if (p['background_asset'] != null) {
        await api.display({'id': p['background_asset']});
      }
      await preview();
      notice('已停用小组件');
    } catch (e) {
      notice(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Shell(
    title: '小组件',
    footer: SizedBox(
      height: 62,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Row(
          children: [
            for (final t in tabs)
              Padding(
                padding: const EdgeInsets.only(right: 7),
                child: InkWell(
                  borderRadius: BorderRadius.circular(30),
                  onTap: busy
                      ? null
                      : () {
                          tab = t.$1;
                          preview();
                        },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 15,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: tab == t.$1 ? ink : Colors.transparent,
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Text(
                      t.$2,
                      style: TextStyle(
                        color: tab == t.$1 ? Colors.white : gray,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
    child: cards.isEmpty
        ? Center(
            child: loading
                ? const CircularProgressIndicator(color: gold)
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('暂未使用小组件', style: TextStyle(color: gray)),
                      const SizedBox(height: 22),
                      Pill(
                        '挑选小组件',
                        black: true,
                        onTap: () {
                          tab = 'recommend';
                          preview();
                        },
                      ),
                    ],
                  ),
          )
        : ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: cards.length,
            separatorBuilder: (_, _) => const SizedBox(height: 20),
            itemBuilder: (d, i) {
              final t = cards[i], isActive = active(t);
              return Paper(
                child: Column(
                  children: [
                    FrameArt(
                      asset: t['asset'] as Json?,
                      portrait: device['config']?['orientation'] != 'landscape',
                      photo: t['error'] != null
                          ? Center(
                              child: TextButton(
                                onPressed: preview,
                                child: Text(t['error']),
                              ),
                            )
                          : t['loading'] == true
                          ? const Center(
                              child: CircularProgressIndicator(color: gold),
                            )
                          : null,
                    ),
                    const SizedBox(height: 25),
                    Text(
                      t['title'],
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (isActive)
                          const Padding(
                            padding: EdgeInsets.only(right: 10),
                            child: Text('●', style: TextStyle(color: gold)),
                          ),
                        Pill(
                          isActive ? '× 不使用' : '使用',
                          icon: isActive ? null : Icons.check,
                          black: !isActive,
                          height: 42,
                          fontSize: 16,
                          onTap: busy
                              ? null
                              : isActive
                              ? disable
                              : () => configure(t),
                        ),
                        if (isActive) ...[
                          const SizedBox(width: 12),
                          Pill(
                            '设置',
                            icon: Icons.settings_outlined,
                            height: 42,
                            fontSize: 16,
                            onTap: busy ? null : () => configure(t),
                          ),
                        ],
                      ],
                    ),
                    if (t['kind'] == 'weather')
                      const Padding(
                        padding: EdgeInsets.only(top: 15),
                        child: Text(
                          '天气数据 · Open-Meteo',
                          style: TextStyle(fontSize: 10, color: gray),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
  );
}
