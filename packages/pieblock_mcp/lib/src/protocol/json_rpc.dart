/// JSON-RPC 2.0 编解码：只覆盖 MCP 实际用到的子集。
///
/// 不引第三方包有两个原因：协议本身很小；「`id` 缺失即通知，不回包」「批量
/// 请求里任何一条结构不合法就整体报错」这类语义自己写更容易测清楚。
library;

/// JSON-RPC 2.0 标准错误码，外加实现自定义的 -32000 段。
abstract final class JsonRpcErrorCode {
  static const parseError = -32700;
  static const invalidRequest = -32600;
  static const methodNotFound = -32601;
  static const invalidParams = -32602;
  static const internalError = -32603;

  /// -32000 ~ -32099 是实现保留区间。
  static const serverError = -32000;
}

/// 协议级错误：直接映射成 JSON-RPC 的 `error` 对象。
///
/// 工具内部的业务失败不要用这个——那要走 `tools/call` 的 `isError`
/// （见 `mcp_message.dart` 的 `McpToolResult`）。协议级错误只意味着
/// 「这条 JSON-RPC 消息本身不成立」。
class JsonRpcException implements Exception {
  const JsonRpcException(this.code, this.message, {this.data});

  final int code;
  final String message;
  final Object? data;

  Map<String, Object?> toJson() => {
    'code': code,
    'message': message,
    if (data != null) 'data': data,
  };

  @override
  String toString() => 'JsonRpcException($code): $message';
}

/// 一条 JSON-RPC 请求。
///
/// `id == null` 视为通知：服务器处理完不回包。MCP 的
/// `notifications/initialized`、`notifications/cancelled` 都走这条路。
class JsonRpcRequest {
  const JsonRpcRequest({required this.method, this.id, this.params});

  final String method;
  final Object? id;
  final Map<String, Object?>? params;

  bool get isNotification => id == null;

  /// 解析单条请求或批量请求。
  ///
  /// 批量请求里任何一条不合法都会抛异常——按规范整个批量都要以 invalid
  /// request 应答，不做「部分成功」。
  static List<JsonRpcRequest> parseBatch(Object? payload) {
    if (payload is List) {
      if (payload.isEmpty) {
        throw const JsonRpcException(
          JsonRpcErrorCode.invalidRequest,
          '批量请求不能是空数组',
        );
      }
      return [for (final item in payload) parse(item)];
    }
    return [parse(payload)];
  }

  static JsonRpcRequest parse(Object? payload) {
    if (payload is! Map) {
      throw const JsonRpcException(
        JsonRpcErrorCode.invalidRequest,
        '请求必须是 JSON 对象',
      );
    }
    final json = Map<String, Object?>.from(payload);
    if (json['jsonrpc'] != '2.0') {
      throw const JsonRpcException(
        JsonRpcErrorCode.invalidRequest,
        '缺少 "jsonrpc": "2.0"',
      );
    }
    final method = json['method'];
    if (method is! String || method.isEmpty) {
      throw const JsonRpcException(
        JsonRpcErrorCode.invalidRequest,
        'method 必须是非空字符串',
      );
    }
    final id = json['id'];
    if (id != null && id is! String && id is! num) {
      throw const JsonRpcException(
        JsonRpcErrorCode.invalidRequest,
        'id 必须是字符串或数字',
      );
    }
    final rawParams = json['params'];
    final Map<String, Object?>? params;
    if (rawParams == null) {
      params = null;
    } else if (rawParams is Map) {
      params = Map<String, Object?>.from(rawParams);
    } else {
      throw const JsonRpcException(
        JsonRpcErrorCode.invalidParams,
        'params 必须是 JSON 对象',
      );
    }
    return JsonRpcRequest(method: method, id: id, params: params);
  }

  /// 取必填字符串参数，缺失或类型不对按 invalid params 处理。
  String requireString(String key) {
    final value = params?[key];
    if (value is String && value.isNotEmpty) return value;
    throw JsonRpcException(
      JsonRpcErrorCode.invalidParams,
      '缺少参数 $key（应为非空字符串）',
    );
  }
}

/// 成功应答。
Map<String, Object?> jsonRpcSuccess(Object? id, Object? result) => {
  'jsonrpc': '2.0',
  'id': id,
  'result': result,
};

/// 失败应答。
Map<String, Object?> jsonRpcFailure(Object? id, JsonRpcException error) => {
  'jsonrpc': '2.0',
  'id': id,
  'error': error.toJson(),
};
