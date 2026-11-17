/// Streamable HTTP 传输：只做鉴权、路由与序列化，业务全在 `McpServer` 里。
///
/// 安全上的三条硬约束：
/// 1. 只绑 `127.0.0.1`，不做局域网监听；
/// 2. 每个进程一个随机 token，写操作还要在界面里二次确认；
/// 3. 请求体有大小上限，避免本地进程把内存打满。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../protocol/json_rpc.dart';
import '../server/mcp_server.dart';

/// 本地 MCP 服务。
class McpHttpServer {
  McpHttpServer({
    required this.mcp,
    String? token,
    this.path = '/mcp',
    this.maxBodyBytes = 1024 * 1024,
  }) : token = token ?? _randomToken();

  final McpServer mcp;

  /// 本进程的访问 token；`bridge.json` 里会写一份供客户端读取。
  final String token;

  /// 只认这个路径，其它一律 404，避免被当成通用 HTTP 服务。
  final String path;

  final int maxBodyBytes;

  HttpServer? _http;
  String? _bridgeFile;
  DateTime? _startedAt;

  bool get isRunning => _http != null;

  int? get port => _http?.port;

  /// 客户端要连接的地址；未启动时为 null。
  Uri? get endpoint {
    final value = port;
    return value == null
        ? null
        : Uri.parse('http://127.0.0.1:$value$path');
  }

  /// 写进 `bridge.json` 的内容。不含任何项目数据。
  Map<String, Object?> get bridgeInfo => {
    'schema': 1,
    'app': 'pieblock',
    'path': path,
    'port': port,
    'endpoint': endpoint?.toString(),
    'token': token,
    'pid': pid,
    'startedAt': _startedAt?.toIso8601String(),
  };

  /// 启动监听。[port] 传 0 由系统分配；[bridgeFile] 给了就顺手写一份发现文件。
  Future<void> start({int port = 0, String? bridgeFile}) async {
    if (_http != null) throw StateError('MCP 服务已经启动');
    final http = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    http.autoCompress = false;
    _http = http;
    _startedAt = DateTime.now();
    http.listen(_handle, onError: (Object _) {});
    if (bridgeFile != null) {
      _bridgeFile = bridgeFile;
      await _writeBridge(bridgeFile);
    }
  }

  /// 停服并清掉发现文件。重复调用安全。
  Future<void> stop() async {
    final http = _http;
    _http = null;
    _startedAt = null;
    await http?.close(force: true);
    final bridge = _bridgeFile;
    _bridgeFile = null;
    if (bridge != null) {
      try {
        final file = File(bridge);
        if (file.existsSync()) await file.delete();
      } on FileSystemException {
        // 删除失败不影响停服，下次启动会覆盖。
      }
    }
  }

  Future<void> _writeBridge(String bridgeFile) async {
    final file = File(bridgeFile);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(bridgeInfo)}\n',
      flush: true,
    );
    if (!Platform.isWindows) {
      // POSIX 上尽量收窄权限；失败不阻断启动。
      try {
        await Process.run('chmod', ['600', file.path]);
      } on ProcessException {
        // 没有 chmod 的环境（极少）直接跳过。
      }
    }
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    try {
      if (request.uri.path != path) {
        await _write(response, 404, {'error': 'not_found'});
        return;
      }
      if (request.method != 'POST') {
        response.headers.set(HttpHeaders.allowHeader, 'POST');
        await _write(response, 405, {'error': 'method_not_allowed'});
        return;
      }
      if (!_authorized(request)) {
        response.headers.set(
          HttpHeaders.wwwAuthenticateHeader,
          'Bearer',
        );
        await _write(response, 401, {'error': 'unauthorized'});
        return;
      }
      final body = await _readBody(request);
      if (body == null) {
        await _write(response, 413, {'error': 'payload_too_large'});
        return;
      }
      Object? payload;
      try {
        payload = jsonDecode(body);
      } on FormatException catch (error) {
        await _write(
          response,
          400,
          jsonRpcFailure(
            null,
            JsonRpcException(
              JsonRpcErrorCode.parseError,
              '请求体不是合法 JSON：${error.message}',
            ),
          ),
        );
        return;
      }

      final result = await mcp.handlePayload(payload);
      if (result == null) {
        // 通知：按规范回 202，且不带 body。
        response.statusCode = HttpStatus.accepted;
        await response.close();
        return;
      }
      await _write(response, 200, result);
    } catch (error) {
      try {
        await _write(
          response,
          500,
          jsonRpcFailure(
            null,
            JsonRpcException(
              JsonRpcErrorCode.internalError,
              '请求处理失败：$error',
            ),
          ),
        );
      } catch (_) {
        // 连接已经断了，只能放弃。
      }
    }
  }

  bool _authorized(HttpRequest request) {
    final header = request.headers.value(HttpHeaders.authorizationHeader);
    if (header != null && header == 'Bearer $token') return true;
    // 有的客户端不支持自定义头，允许用查询参数带 token；两者都要能过。
    return request.uri.queryParameters['token'] == token;
  }

  /// 读请求体；超限返回 null。
  ///
  /// 超限后仍然把剩余的 body 读完再返回：中途放弃会在客户端看来像连接被重置，
  /// 413 反而传不回去。
  Future<String?> _readBody(HttpRequest request) async {
    final builder = BytesBuilder(copy: false);
    var overflow = false;
    await for (final chunk in request) {
      if (overflow) continue;
      if (builder.length + chunk.length > maxBodyBytes) {
        overflow = true;
        continue;
      }
      builder.add(chunk);
    }
    if (overflow) return null;
    return utf8.decode(builder.takeBytes(), allowMalformed: true);
  }

  Future<void> _write(
    HttpResponse response,
    int status,
    Object? body,
  ) async {
    response.statusCode = status;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(body));
    await response.close();
  }

  /// 生成一个新的访问令牌。宿主可以把它持久化，避免重启后客户端要重配。
  static String generateToken() => _randomToken();

  static String _randomToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(24, (_) => random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }
}
