import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';
import 'api.dart';

const native = MethodChannel('elecleap/native');

class ElIdentity {
  ElIdentity(this.id, this.claim, this.key);
  final String id, claim;
  final Uint8List key;
  factory ElIdentity.parse(String text) {
    final u = Uri.parse(text);
    if (u.scheme != 'elecleap' ||
        u.host != 'device' ||
        u.queryParameters['v'] != '1') {
      throw Exception('请扫描 ElecLeap 设备二维码');
    }
    final p = u.queryParameters,
        key = base64Url.decode(base64Url.normalize(p['key'] ?? ''));
    if (key.length != 32 ||
        !(p['id'] ?? '').startsWith('EL-') ||
        (p['claim'] ?? '').length < 16) {
      throw Exception('设备二维码不完整');
    }
    return ElIdentity(p['id']!, p['claim']!, key);
  }
  String get encoded =>
      jsonEncode({'id': id, 'claim': claim, 'key': base64Encode(key)});
  factory ElIdentity.restore(String data) {
    final d = jsonDecode(data);
    return ElIdentity(d['id'], d['claim'], base64Decode(d['key']));
  }
}

String hex(List<int> values) =>
    values.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

class ElSession {
  ElSession(this.identity, {List<int>? clientNonce})
    : cn =
          clientNonce ?? List.generate(16, (_) => Random.secure().nextInt(256));
  final ElIdentity identity;
  final List<int> cn;
  List<int> sn = [];
  SecretKey? tx, rx;
  int sent = 0, received = 0;
  Json hello() => {
    'v': 1,
    'type': 'hello',
    'device_id': identity.id,
    'client_nonce': base64Encode(cn),
  };
  Future<void> challenge(Json msg) async {
    if (msg['v'] != 1 || msg['type'] != 'challenge') {
      throw Exception('设备认证协议不匹配');
    }
    sn = base64Decode(msg['server_nonce']);
    final proof = base64Decode(msg['proof']);
    if (sn.length != 16) throw Exception('设备挑战无效');
    final expected = await Hmac.sha256().calculateMac(
      utf8.encode('EL1|${identity.id}|${hex(cn)}|${hex(sn)}'),
      secretKey: SecretKey(identity.key),
    );
    var difference = expected.bytes.length ^ proof.length;
    for (var i = 0; i < expected.bytes.length && i < proof.length; i++) {
      difference |= expected.bytes[i] ^ proof[i];
    }
    if (difference != 0) throw Exception('设备认证失败，请核对二维码');
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32),
        key = SecretKey(identity.key);
    tx = await hkdf.deriveKey(
      secretKey: key,
      nonce: [...cn, ...sn],
      info: utf8.encode('ElecLeap BLE c2d v1'),
    );
    rx = await hkdf.deriveKey(
      secretKey: key,
      nonce: [...cn, ...sn],
      info: utf8.encode('ElecLeap BLE d2c v1'),
    );
  }

  Uint8List nonce(int seq) {
    final b = Uint8List(12)..setRange(0, 4, sn);
    ByteData.sublistView(b).setUint32(8, seq, Endian.big);
    return b;
  }

  List<int> aad(int seq) =>
      utf8.encode('${identity.id}|${hex(cn)}|${hex(sn)}|$seq');
  Future<Json> seal(Json p) async {
    final seq = ++sent,
        box = await AesGcm.with256bits().encrypt(
          utf8.encode(jsonEncode(p)),
          secretKey: tx!,
          nonce: nonce(seq),
          aad: aad(seq),
        );
    return {
      'v': 1,
      'type': 'encrypted',
      'seq': seq,
      'data': base64Encode([...box.cipherText, ...box.mac.bytes]),
    };
  }

  Future<Json> open(Json msg) async {
    if (msg['v'] != 1 ||
        msg['type'] != 'encrypted' ||
        msg['seq'] != received + 1) {
      throw Exception('设备响应顺序无效');
    }
    final seq = msg['seq'] as int, b = base64Decode(msg['data']);
    if (b.length < 16) throw Exception('设备响应无效');
    final data = await AesGcm.with256bits().decrypt(
      SecretBox(
        b.sublist(0, b.length - 16),
        nonce: nonce(seq),
        mac: Mac(b.sublist(b.length - 16)),
      ),
      secretKey: rx!,
      aad: aad(seq),
    );
    received = seq;
    return Map<String, dynamic>.from(jsonDecode(utf8.decode(data)));
  }
}

class BleLink {
  BleLink() {
    native.setMethodCallHandler((call) async {
      if (call.method == 'bleEvent') {
        final v = Map<String, dynamic>.from(call.arguments as Map);
        events.add(v);
        if (v['type'] == 'disconnected') _fail(Exception('蓝牙连接已断开'));
      } else if (call.method == 'bleBytes') {
        try {
          _feed(List<int>.from(call.arguments));
        } catch (e) {
          _fail(e);
        }
      }
    });
  }
  final events = StreamController<Json>.broadcast();
  final Queue<Completer<Json>> _waiting = Queue();
  final Queue<Json> _messages = Queue();
  List<int> _buffer = [];
  ElSession? session;
  Future<void> scan() => native.invokeMethod<void>('bleScan');
  Future<void> stop() => native.invokeMethod<void>('bleStop');
  Future<void> connect(String id) => native
      .invokeMethod<void>('bleConnect', id)
      .timeout(const Duration(seconds: 20));
  void _fail(Object e) {
    for (final c in _waiting) {
      if (!c.isCompleted) c.completeError(e);
    }
    _waiting.clear();
    session = null;
  }

  void _feed(List<int> b) {
    _buffer.addAll(b);
    while (_buffer.length >= 2) {
      final n = (_buffer[0] << 8) | _buffer[1];
      if (n < 2 || n > 4096) throw Exception('蓝牙数据无效');
      if (_buffer.length < n + 2) break;
      final msg = Map<String, dynamic>.from(
        jsonDecode(utf8.decode(_buffer.sublist(2, n + 2))),
      );
      _buffer = _buffer.sublist(n + 2);
      if (_waiting.isNotEmpty) {
        _waiting.removeFirst().complete(msg);
      } else {
        if (_messages.length >= 20) throw Exception('蓝牙响应过多');
        _messages.add(msg);
      }
    }
  }

  Future<Json> read({int seconds = 25}) {
    if (_messages.isNotEmpty) return Future.value(_messages.removeFirst());
    final c = Completer<Json>();
    _waiting.add(c);
    return c.future.timeout(
      Duration(seconds: seconds),
      onTimeout: () {
        _waiting.remove(c);
        throw TimeoutException('设备响应超时，请重新连接');
      },
    );
  }

  Future<void> write(Json message) async {
    final b = utf8.encode(jsonEncode(message));
    if (b.length > 4096) throw Exception('蓝牙消息过长');
    await native.invokeMethod<void>(
      'bleWrite',
      Uint8List.fromList([b.length >> 8, b.length & 255, ...b]),
    );
  }

  Future<void> authenticate(ElIdentity id) async {
    final s = ElSession(id);
    await write(s.hello());
    await s.challenge(await read());
    session = s;
  }

  Future<Json> command(Json payload, {int timeout = 25}) async {
    if (session == null) throw Exception('请重新连接相框');
    await write(await session!.seal(payload));
    final result = await session!.open(await read(seconds: timeout));
    if (result['status'] == 'error') {
      throw Exception(result['message'] ?? '设备操作失败');
    }
    return result;
  }

  Future<void> wifi(
    String ssid,
    String password,
    void Function(String) status,
  ) async {
    Json p = await command({
      'type': 'wifi_config',
      'ssid': ssid,
      'password': password,
      'api_base': 'https://42.194.237.249/elecleap',
    });
    while (true) {
      status(p['message'] ?? '正在连接网络');
      if (p['status'] == 'connected') return;
      if (p['status'] == 'error') throw Exception(p['message']);
      p = await session!.open(await read(seconds: 45));
    }
  }

  Future<void> image(
    Uint8List bytes,
    String sha,
    void Function(int) progress,
  ) async {
    await command({
      'type': 'image_begin',
      'bytes': bytes.length,
      'sha256': sha,
    });
    for (var offset = 0; offset < bytes.length; offset += 768) {
      final end = min(offset + 768, bytes.length);
      await command({
        'type': 'image_chunk',
        'offset': offset,
        'data': base64Encode(bytes.sublist(offset, end)),
      });
      progress((end / bytes.length * 90).round());
    }
    await command({'type': 'image_end'}, timeout: 90);
    progress(100);
  }

  Future<void> close() async {
    try {
      await native.invokeMethod<void>('bleDisconnect');
    } finally {
      _fail(Exception('连接已关闭'));
      _buffer = [];
      _messages.clear();
      await events.close();
      native.setMethodCallHandler(null);
    }
  }
}
