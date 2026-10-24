# JSON Schema 说明

本目录下的 `*.schema.json` 由已停用的旧版 Godot CLI 生成，字段结构停留在旧格式（例如配置值仍以字符串描述），与当前 Flutter 版本使用的 `.pieproj` 格式 17 不一致。

当前字段定义以 [Flutter 项目文件格式](../Flutter项目文件格式.md) 与 `packages/pieblock_core` 的模型/校验器为准。待 CLI 恢复生成能力后再整体重生成这些 schema，在此之前不要把这里的内容作为项目文件校验依据。
