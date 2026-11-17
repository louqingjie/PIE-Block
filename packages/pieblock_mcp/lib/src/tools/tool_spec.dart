/// 工具声明：名字、描述、JSON Schema 与行为提示。
library;

/// 工具行为提示。MCP 用它们让客户端自动放行只读工具。
///
/// 默认值刻意取规范里的保守值：能改配置的工具一律 `readOnlyHint: false`。
class McpToolAnnotations {
  const McpToolAnnotations({
    this.readOnlyHint = false,
    this.destructiveHint = false,
    this.idempotentHint = false,
    this.openWorldHint = false,
  });

  final bool readOnlyHint;
  final bool destructiveHint;
  final bool idempotentHint;
  final bool openWorldHint;

  Map<String, Object?> toJson() => {
    'readOnlyHint': readOnlyHint,
    'destructiveHint': destructiveHint,
    'idempotentHint': idempotentHint,
    'openWorldHint': openWorldHint,
  };
}

/// `tools/list` 里的一项。
///
/// `description` 就是给模型看的 API 文档，写得含糊模型就会乱传参数——
/// 这是整条链路上最值得多写几行字的地方。
class McpToolSpec {
  const McpToolSpec({
    required this.name,
    required this.title,
    required this.description,
    required this.inputSchema,
    this.outputSchema,
    this.annotations = const McpToolAnnotations(),
  });

  final String name;
  final String title;
  final String description;
  final Map<String, Object?> inputSchema;
  final Map<String, Object?>? outputSchema;
  final McpToolAnnotations annotations;

  Map<String, Object?> toJson() => {
    'name': name,
    'title': title,
    'description': description,
    'inputSchema': inputSchema,
    if (outputSchema != null) 'outputSchema': outputSchema,
    'annotations': annotations.toJson(),
  };
}
