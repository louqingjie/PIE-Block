# PIE-Block 教材

面向大学生的 PIE-Block 使用教材，用 LaTeX（[ElegantBook](https://github.com/ElegantLaTeX/ElegantBook) v4.7）排版，
输出可印刷的 A4 书籍 PDF。教材与 `docs/` 下的 Markdown 文档分工不同：

- `docs/`：随代码更新的操作指南、规范、排障记录；
- `book/`：按教学顺序组织的教材，强调“从零开始、循序渐进”。

## 当前状态

全部完稿：前言、10 章正文与 3 个附录，共 62 页（A4）。每章配有真实
Widget 树渲染的软件截图、Wikimedia Commons 的 CC 授权实物照片，以及由
内置 SDCC 真实编译产出的代码/HEX 摘录。

## 目录结构

```
book/
├── main.tex              # 主文件：书目信息、封面、章节 include、参考文献
├── elegantbook.cls       # 文类文件（ElegantBook v4.7，已内置）
├── chapters/
│   ├── preface.tex       # 前言（默认未 include）
│   ├── ch01.tex … ch10.tex   # 正文各章（全部完稿）
│   ├── appendix-a.tex    # 附录 A 硬件接口与引脚速查
│   ├── appendix-b.tex    # 附录 B 常见问题（FAQ）
│   └── appendix-c.tex    # 附录 C 术语表
├── examples/            # 全书配套示例工程（.pieproj，可直接导入）
│   ├── mecanum4.pieproj # 四轮麦克纳姆轮工程车
│   ├── omni3.pieproj    # 三轮全向轮工程车
│   ├── arm2dof.pieproj  # 二自由度机械臂
│   └── README.md
├── image/
│   ├── cover.jpg         # 封面横幅：品牌色 + 配置拓扑示意 + 右上角 W.PIE 标识
│   ├── wpie-logo.png     # W.PIE 学生创新实验室标识（封面横幅素材）
│   ├── ch01/…ch10/       # 各章软件截图与实物照片（由 tool/book_screenshots_*.dart 生成）
├── reference.bib         # 参考文献（biblatex / biber）
├── build.ps1             # Windows 编译脚本
├── build.sh              # Linux / macOS 编译脚本
└── README.md
```

## 编译

需要 **TeX Live 2024 及以上**（或 MacTeX），必须使用 **XeLaTeX**，不支持 CTeX 套装。

```powershell
# Windows
.\build.ps1
```

```bash
# Linux / macOS
./build.sh
```

等价命令（在 `book/` 目录下）：

```bash
latexmk -xelatex main.tex
```

手动顺序：`xelatex main.tex` → `biber main` → `xelatex main.tex` → `xelatex main.tex`。

**不想装 TeX**：把 `book/` 目录压缩成 zip，在 Overleaf 里 `New Project → Upload Project`，
然后在 `Menu → Compiler` 选择 **XeLaTeX** 即可。

## 开始写正文

1. 打开 `chapters/ch01.tex`，把 `\chapter{...}` 后面的 `TODO` 注释替换为正文。
2. 新增一章：在 `chapters/` 新建 `ch11.tex`，以 `\chapter{...}` 开头，并在 `main.tex`
   的 `\mainmatter` 之后加一行 `\include{chapters/ch11}`。
3. 需要前言时，取消 `main.tex` 中 `\include{chapters/preface}` 的注释。
4. 图片统一放进 `image/`（建议按章建子目录，如 `image/ch03/`），用相对路径引用。

可用的排版环境（定义、定理、例题、练习、解答、注意、章前导读、章后习题等）及
改封面 / 改配色 / GB/T 7714 参考文献的写法，见模板说明：
<https://github.com/ElegantLaTeX/ElegantBook>

## 示例工程与截图维护

全书示例工程在 `examples/`，可以直接从应用首页“打开项目”导入。示例只做
公式/编译级验证，实机使用前请按正文的安全清单架空、限速、标定。

生成示例 C 并校验（在仓库根目录执行）：

```bash
dart run tool/generate_book_examples.dart   # 输出到 build/book_examples/
flutter test test/book_examples_test.dart     # 校验、生成 C、试算断言
```

重新生成第 5 章软件截图（会覆盖 `image/ch05/*.png`，需要图形环境依赖的字体
资源，但不启动窗口）：

```bash
flutter test tool/book_screenshots_test.dart
```

重新生成第 1、3、4、6、7、8、9、10 章软件截图（会覆盖
`image/ch01…ch10/*.png`）：

```bash
flutter test tool/book_screenshots_chapters_test.dart
```

用内置 SDCC 真实编译部分示例，产出第 9 章引用的 HEX 与 main.rst
（输出到 `build/book_firmware/`）：

```bash
dart run tool/build_book_firmware.dart
```

截图工具不是默认 CI 测试：它们不在 `test/` 下，`flutter test` 不会自动
收集；只有在界面文案或布局改动后才需要手动重跑。截图按 1440 逻辑像素宽
渲染，输出 2078 px 宽，与第 2 章截图一致。

## 写作约定

- 本书正文的中文引号一律使用弯引号 “ ”，不使用「」；后续各章沿用同一约定。

## 真实世界照片来源与授权

第 5 章使用的实物照片均取自 Wikimedia Commons，图注中已注明作者与许可，
此处记录完整来源；替换或新增照片时保持同样的署名要求。

| 文件 | 内容 | 作者 | 许可 | 来源 |
| --- | --- | --- | --- | --- |
| `image/ch05/photo-robomaster.jpg` | RoboMaster 机器人展品（深圳南山博物馆，已裁剪） | Underbar dk | CC BY-SA 4.0 | <https://commons.wikimedia.org/wiki/File:RoboMaster_robot_as_an_exhibit_in_the_Nanshan_Museum.jpg> |
| `image/ch05/photo-mecanum.jpg` | 麦克纳姆轮特写 | Stilfehler | CC BY-SA 4.0 | <https://commons.wikimedia.org/wiki/File:FIRST_Tech_Challenge_%E2%80%93_Parts_%E2%80%93_Mecanum_wheels.jpg> |
| `image/ch05/photo-omni.jpg` | 全向轮特写 | Stilfehler | CC BY-SA 4.0 | <https://commons.wikimedia.org/wiki/File:FIRST_Tech_Challenge_%E2%80%93_Parts_%E2%80%93_Omni_wheels.jpg> |
| `image/ch05/photo-arm-mecanum.jpg` | 麦轮底盘 + 舵机机械臂教学机器人 | Anani A. George | CC0 | <https://commons.wikimedia.org/wiki/File:Mecanum_Wheel_Robot_with_an_Arm.jpg> |
| `image/ch07/7-2-buzzer.jpg` | 压电蜂鸣器剖开外壳特写（已裁剪） | Raimond Spekking | CC BY-SA 4.0 | <https://commons.wikimedia.org/wiki/File:Ideenwelt_EM2862_-_Piezoelectric_buzzer-91799.jpg> |

## 封面与素材来源

- 封面横幅使用应用主题色 `#087F8C` 与“节点-连接”拓扑示意；
- 右上角为 W.PIE（首都师范大学学生创新实验室）标识，素材存于 `image/wpie-logo.png`；
- 封面为中英双语（书名、副标题各配一行英文），不显示软件截图、校名图片以及编著/单位/时间/版本等信息；
- 封面版式：150 mm 横幅 + 4 mm 品牌色饰线 + 20 mm 左右边距 + 底部细线页脚，
  由 `main.tex` 里的自定义 `\maketitle` 排布；
- 文类 `elegantbook.cls` 来自 ElegantBook 项目，遵循 LPPL 1.3c 或更高版本，
  分发时请保留其协议声明与项目地址。

更换封面时替换 `image/cover.jpg`，保持 2400×1714（210×150 mm）即可。
