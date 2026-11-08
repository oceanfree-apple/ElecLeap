import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

typedef Json = Map<String, dynamic>;

class Api {
  Api({http.Client? client, this.base = 'https://43.139.37.108:8443'})
    : client = client ?? http.Client();
  final http.Client client;
  final String base;
  final storage = const FlutterSecureStorage();
  String token = '', selected = '';
  Future<void> restore() async {
    token = await storage.read(key: 'elecleap.session') ?? '';
  }

  Map<String, String> get headers => {
    'Authorization': 'Bearer $token',
    'Content-Type': 'application/json',
  };
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Json? data,
  }) async {
    final req = http.Request(method, Uri.parse('$base/api$path'))
      ..headers.addAll(headers);
    if (data != null) req.body = jsonEncode(data);
    final res = await http.Response.fromStream(
      await client.send(req).timeout(const Duration(seconds: 25)),
    );
    dynamic body;
    try {
      body = jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      throw Exception('服务器暂时无法响应，请稍后重试');
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      if (res.statusCode == 401) {
        token = '';
        await storage.delete(key: 'elecleap.session');
      }
      throw Exception(
        body is Map && body['detail'] is String
            ? body['detail']
            : '操作失败，请检查输入后重试',
      );
    }
    return body;
  }

  Future<void> authenticate(String name, String password, bool register) async {
    await setSession(
      await request(
        register ? '/auth/register' : '/auth/password',
        method: 'POST',
        data: {'username': name.trim(), 'password': password},
      ),
    );
  }

  Future<void> setSession(dynamic res) async {
    token = res['token'] as String;
    await storage.write(key: 'elecleap.session', value: token);
  }

  Future<void> logout() async {
    try {
      await request('/auth/logout', method: 'POST');
    } finally {
      token = '';
      selected = '';
      await storage.delete(key: 'elecleap.session');
    }
  }

  Future<Json> upload(Uint8List bytes, String orientation) async {
    final req = http.MultipartRequest('POST', Uri.parse('$base/api/assets'))
      ..headers['Authorization'] = 'Bearer $token'
      ..fields['orientation'] = orientation
      ..files.add(
        http.MultipartFile.fromBytes('image', bytes, filename: 'photo.png'),
      );
    final res = await http.Response.fromStream(
      await client.send(req).timeout(const Duration(seconds: 90)),
    );
    final data = jsonDecode(utf8.decode(res.bodyBytes));
    if (res.statusCode != 200) {
      throw Exception(data['detail'] is String ? data['detail'] : '照片上传失败');
    }
    return Map<String, dynamic>.from(data);
  }

  String image(Json asset) => '$base${asset['picture'] ?? asset['preview']}';
  Future<Json> display(Json asset, {String? key}) async =>
      Map<String, dynamic>.from(
        await request(
          '/devices/$selected/display',
          method: 'POST',
          data: {
            'asset_id': asset['id'],
            'request_key':
                key ??
                'ios:${DateTime.now().microsecondsSinceEpoch}:${asset['id']}',
          },
        ),
      );
}

final api = Api();
