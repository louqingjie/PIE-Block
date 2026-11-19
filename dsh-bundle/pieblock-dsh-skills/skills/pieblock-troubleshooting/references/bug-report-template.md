# 疑似 PIE-Block 缺陷：证据模板

提交 Issue 前先完成 `SKILL.md` 的三方对照；确认是生成器缺陷候选再上报。目标是一次性给出
可复现、可定位的信息，而不是让作者来回问。

## 提交到哪里

- GitHub Issues：<https://github.com/louqingjie/PIE-Block/issues>
- 有 Gitee 镜像时可用镜像的 Issue 区，内容一致。
- 公开前先脱敏：去掉队名、个人信息、与问题无关的工程配置；不要上传完整工程（除非已确认可公开）。

## 模板

```markdown
### 版本与环境
- PIE-Block 版本（安装包/关于页）：
- `pieblock-cli describe` 的 version：
- 操作系统/版本（Windows 10/11、Linux 发行版等）：
- 编译器：内置 SDCC C251 / 本地 Keil C251（含许可证状态）
- 工程类型与格式：infantry / engineer / debug / music，format_version=23
- 是否 Web/Android 版：

### 现象
- 期望行为：
- 实际行为：
- 触发频率（每次/偶发）：
- 是否影响编译 / 烧录 / 运行：

### 复现步骤
1. 新建/打开……（可用模板工程复现时写清用的是哪个模板）
2. 在……页填写……
3. 生成代码 / 编译 / 烧录……
4. 观察……

### 参数与代码对照
| 参数（.pieproj 路径） | 界面值 | 生成代码落点 | 代码里的值 | 一致？ |
| --- | --- | --- | --- | --- |
|  |  |  |  |  |

- 用户从「生成代码」页导出的 main.c 与 `pieblock-cli codegen` 输出是否一致：
- 附：`pieblock-cli validate` 的 JSON（脱敏后）：
- 附：相关生成代码片段（文件 + 行号）：

### 源码定位（可选但很有帮助）
- 怀疑的生成逻辑：按 tag 的 `packages/pieblock_core/lib/src/code_generator.dart` 第 N 行附近（GitHub）
- 对应 tag 的链接（如 `https://github.com/louqingjie/PIE-Block/blob/v1.8.0/...`）

### 已排除
- 版本不一致：是/否
- 用户手改过 main.c：是/否
- 导出的 main.c 与 CLI 输出不一致：是/否
- 硬件/接线/烧录问题：已按 `pieblock-config` Skill 的编译烧录指南检查
- 工程本身存在校验错误：是/否（附 validate 结果）

### 附件
- 最小工程（可复现用，已脱敏）：
- 截图/录屏：
- 构建日志（编译失败时附完整日志）：
```

## 提交前自查

- [ ] 版本、系统、工程类型齐全；
- [ ] 有最小复现步骤，最好能用 `应用内模板` 或 `assets/examples/` 复现；
- [ ] 参数↔代码对照表给出了不一致的具体字段；
- [ ] 说明是否与版本/手改/导出文件不一致有关；
- [ ] 已脱敏，不含隐私与完整工程（除非确认可公开）。

## 不要做

- 不要附上你手改过的 `main.c` 作为"修复"；
- 不要建议作者"直接改生成器"绕过问题；
- 不要在公开 Issue 里贴用户完整工程、个人信息或未脱敏截图。
