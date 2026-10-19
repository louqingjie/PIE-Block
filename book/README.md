# PIE-Block 教材

面向大学生的 PIE-Block 使用教材，用 LaTeX（[ElegantBook](https://github.com/ElegantLaTeX/ElegantBook) v4.7）排版，
输出可印刷的 A4 书籍 PDF。教材与 `docs/` 下的 Markdown 文档分工不同：

- `docs/`：随代码更新的操作指南、规范、排障记录；
- `book/`：按教学顺序组织的教材，强调「从零开始、循序渐进」。

## 当前状态

模板骨架已完成：封面、目录、10 章正文与 3 个附录的标题、参考文献占位都已排好，
**正文内容尚未编写**。每章文件里只保留 `\chapter{...}` 和一条 `TODO` 注释。

## 目录结构

```
book/
├── main.tex              # 主文件：书目信息、封面、章节 include、参考文献
├── elegantbook.cls       # 文类文件（ElegantBook v4.7，已内置）
├── chapters/
│   ├── preface.tex       # 前言（默认未 include）
│   ├── ch01.tex … ch10.tex   # 正文各章（仅章标题占位）
│   ├── appendix-a.tex    # 附录 A 硬件接口与引脚速查
│   ├── appendix-b.tex    # 附录 B 常见问题（FAQ）
│   └── appendix-c.tex    # 附录 C 术语表
├── image/
│   ├── cover.jpg         # 封面横幅：品牌色 + 配置拓扑示意 + 右上角 W.PIE 标识
│   └── wpie-logo.png     # W.PIE 学生创新实验室标识（封面横幅素材）
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

## 封面与素材来源

- 封面横幅使用应用主题色 `#087F8C` 与「节点-连接」拓扑示意；
- 右上角为 W.PIE（首都师范大学学生创新实验室）标识，素材存于 `image/wpie-logo.png`；
- 封面保留书名与副标题，不显示软件截图、校名图片以及编著/单位/时间/版本等信息；
- 文类 `elegantbook.cls` 来自 ElegantBook 项目，遵循 LPPL 1.3c 或更高版本，
  分发时请保留其协议声明与项目地址。

更换封面时替换 `image/cover.jpg`，保持 2400×1920（5:4 横版）即可。
