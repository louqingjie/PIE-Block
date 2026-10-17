# OLED 五线谱显示方案（第一版 · 模拟稿）

> 本文件记录 128×64 单色 OLED 上滚动五线谱的第一版版面/字形/滚动规范，
> 由离线模拟器 `tool/render_oled_staff.dart` 渲染验证后再进入固件实现。

## 1. 范围

- **本轮只做模拟器**：不写固件、不改 app 配置；目标是先确认谱号、调号、符头/符干/
  符尾、加线、小节线、滚动方式是否“规范”、在 128×64 上是否可读。
- 模拟器输出的是**精确 1bit 帧**（8 页 × 128 列，共 1024 字节），字节序与后续
  SSD1306 页寻址完全相同，固件可以逐字节照抄。
- 模拟器复用 `MusicTimeline.soundingSpans(config)`，画面与蜂鸣器听到的音符/休止
  严格同源。

## 2. 屏幕与约束（代码事实）

- 屏是 `stc32g_sdcc/libraries/boards/src/LCD.c` 驱动的 **128×64 单色 OLED**
  （SSD1306 类），软件 SPI 位操作：`CS=P2.2、D1=P2.3、RST=P2.4、CLK=P2.5、DC=P2.6`。
- 现有 API 只有 `LCD_Init/LCD_CLS/LCD_P6x8Str/LCD_P8x16Str/LCD_PrintU16/LCD_PrintFloat`；
  `LCD_WrCmd/LCD_WrDat/LCD_Set_Pos` 未在头文件声明。显示五线谱需要自带帧缓冲并整屏刷写。
- 帧缓冲 1024 字节，SDCC 链接参数已给 8KB XRAM（`--xram-size 0x2000`），放得下。
- 音乐固件工程 `BUZZER_MUSIC_GENERATED` 目前只链接 `pwm` 组；固件阶段需要把 `lcd`
  组（`LCD.c/Font.c/CNU_PIE_GPIO.c`）加进 `build_manifest.json` 的工程依赖。

## 3. 版面参数（默认值，可在模拟器里调）

| 参数 | 默认 | 说明 |
| --- | --- | --- |
| 屏幕 | 128×64 | 1bit，白=1 |
| 五线谱线距 `space` | 6px | 5 条 1px 线，谱表高 24px |
| 谱表顶线 `staffTop` | 14 | 线在 y=14/20/26/32/38 |
| 左端固定区 | 25px（C 调）+ 6px 隔离带 | 谱号 13 + 调号每个升降号 6 + 拍号 7；隔离带内只有谱线 |
| 横向比例 `pxPerQuarter` | 16px | 4/4 下一小节 64px，约 1.7 小节可见 |
| 音符最小间距 | 6px | 防止 16 分音符符头重叠 |
| 当前音符位置 | 滚动区 30% | `noteAreaStart = panelWidth+6`，`cursorX = noteAreaStart + (128-noteAreaStart)*0.30` |
| 符干长度 | 8px | 1.3 个线距，兼顾屏幕高度 |
| 符头 | 4×3 | 实心（四分及更短）/空心（二分、全音符） |

`space=5/6/7` 与 `pxPerQuarter=10/12/13` 的对比图见模拟器输出；默认取 6/16：
space=7 时 C6 会顶出屏幕上沿，space=5 时字形过小；pxPerQuarter 取 12 时八分音符只有 6px，容易挤在一起。

## 4. 音高与符号

### 4.1 音高 → 纵坐标

- 全音阶序号：`diatonicIndex(p) = (p ~/ 12 - 1) * 7 + [C,D,E,F,G,A,B 的字母步进]`。
- 符头中心：`y = (staffTop + 4*space) - (diatonicIndex(p) - 谱号底线) * space ~/ 2`。
  - 高音谱号底线 = E4（diatonic 30）；低音谱号底线 = G2（diatonic 18）。
  - **位置按调号拼写后的音名计算**：同一 MIDI 音高在 C 调记 G#4（G 线）、在 F 调记 Ab4
    （A 间），Bb 记在 B 线而不是 A# 的 A 间；否则降号调的音符会被画到错线/错间上。
- 加线：超出五线谱范围时，按线位置逐条画 1px 短线（长度 = 符头宽 + 2px）。
- 符干方向：音符在中线以下 → 向上；中线及以上 → 向下。
- 临时记号画在符头左侧 7px 处（3×5 或 4×7 手绘点阵）。

### 4.2 时值

`beats = durationTicks / ticksPerQuarter` → 最近的标准时值：

| beats | 时值 |
| --- | --- |
| 4 | 全音符（空心，无符干） |
| 3 | 附点二分 |
| 2 | 二分（空心 + 符干） |
| 1.5 | 附点四分 |
| 1 | 四分 |
| 0.75 | 附点八分 |
| 0.5 | 八分（1 条符尾） |
| 0.375 | 附点十六分 |
| 0.25 | 十六分（2 条符尾） |

其它时值取最近标准值并在 `spec.json` 里可查（三连音等暂不画括号/连杠）。

### 4.3 调号、临时记号、拍号、小节线

- 调号来自音乐工程的 `keySignatureFifths`（编辑器下拉 / 项目 JSON / MIDI 调号 meta），
  模拟器 `--key` 可临时覆盖。按标准顺序画在固定区：
  - 升号顺序 F C G D A E B；降号顺序 B E A D G C F；
  - 高音、低音谱号各一套标准线/间位置（`trebleSharpSteps` 等表）；
  - 调号里每个升降号占 6px（5px 字形 + 1px 间距）。
- 临时记号按小节维护状态：调号之外才画 ♯/♭；同音高在本小节内延续，跨小节复位，
  取消升降时画还原号。
- **升号必须完整可辨**：字形 5×7（两根竖线 + 两根横线，见第 7 节）；绘制时先擦掉
  字形包围盒内的谱线像素再落点阵，否则压在谱线上的升号其中心空洞会被谱线填成实心，
  看起来像“工/日”。还原号同理，并画成紧凑 ♮ 形状（左竖线偏上、右竖线偏下、两根横线，3×7，中间只留 1px 空洞）。
- 拍号取工程第一个 `TimeSignatureEvent`（默认 4/4），数字 7×8 点阵上下排列（跨第 1–2 线 / 第 3–4 线）。
- 小节线为 1px 竖线，按 `ticksPerQuarter*4/denominator*numerator` 从 tick 0 计算。

## 5. 自动谱号（单谱表）

- 按音符顺序分配谱号（每个音符的谱号固定，不随播放位置改变），规则：
  - 初始谱号取第一个音符在高/低音谱号下“最大加线数”较小者；
  - 遇到新音符时，若换谱号能让「当前音符起后续 3 个音符」的最大加线数至少少 2 条，
    则从该音符起换谱号（迟滞，避免来回跳）。
- 左端固定区显示当前播放位置的谱号；滚动区在换谱号处画一个小谱号变更符号
  （被固定区挡住时不画）。
- `--clef treble|bass` 可强制单谱号。

## 6. 滚动模型

- 当前播放事件（音符或休止）固定在 `cursorX`；每播放完一个事件，整幅左移一个步进。
- x 按 tick 比例：`x = cursorX + (event.startTick - playTick) * pxPerQuarter/ticksPerQuarter`；
  当前音符之后的音符再按最小间距 5px 排开，避免 16 分音符符头粘连。
- 已播放音符向左滚出固定区；当前播放位置用谱表上方的 ▼ 三角标记（不再给音符套方框，
  避免遮住符头/符干）。
- **左端固定区（谱号/调号/拍号）是禁区**：固定区外再留 6px 隔离带（`noteAreaStart =
  panelWidth + 6`）。每帧先画滚动内容，再清空 `[0, noteAreaStart)` 并重绘谱线和固定内容。
  音符/休止符不做半颗截断：字形会进入隔离带时整颗不画（在禁区外消失），
  隔离带里只有 5 条谱线。`test/staff_preview_test.dart` 有“固定区+隔离带各帧一致”的回归断言。

## 7. 字形清单（1bit 点阵）

| 字形 | 尺寸 | 来源 |
| --- | --- | --- |
| 高音谱号 | 13×28 | 系统音乐符号字体离线栅格化后修补 |
| 低音谱号 | 12×13 | 同上 |
| 升/降/还原号 | 5×7 / 4×7 / 3×7 | 手绘 |
| 拍号数字 0–9 | 7×8 | 离线栅格化 |
| 符头实心/空心 | 4×3 | 手绘 |
| 休止符（全/二分/四分/八分/十六分） | 2–5×3–7 | 手绘 |
| 符尾 | 由代码按符干方向画 | 代码 |

仓库只提交点阵数据，不包含字体文件。模拟器 `--emit-spec` 会输出全部点阵的十六进制/
字符串形式，供固件阶段生成 C 数组。

## 8. 模拟器用法

```powershell
# 内置示例：twinkle/wide/bass/mixed/chromatic/accidentals/flats/rests/sevenSharps
dart run tool/render_oled_staff.dart --demo twinkle --out tmp/staff_preview/twinkle
dart run tool/render_oled_staff.dart --demo wide
dart run tool/render_oled_staff.dart --demo bass

# 临时升/降/还原号特写（压在顶线、需要谱线遮罩的场景）
dart run tool/render_oled_staff.dart --demo accidentals --out tmp/staff_preview/accidentals
dart run tool/render_oled_staff.dart --demo flats --out tmp/staff_preview/flats

# 真实工程：默认用工程的 keySignatureFifths，--key 可临时覆盖
dart run tool/render_oled_staff.dart --project path/to/music.pieproj
dart run tool/render_oled_staff.dart --project path/to/music.pieproj --key G

# 自检 / 输出字形与几何规格
dart run tool/render_oled_staff.dart --self-check
dart run tool/render_oled_staff.dart --demo wide --emit-spec
```

输出：`frame_*.png`（128×64 原始帧）、`detail.png`（放大 8 倍单帧）、
`sheet.png`（4 列滚动对比图）、`spec.json`（几何 + 字形点阵 + 事件表）。

版面参数（`--space`/`--px-per-quarter`/`--min-note-gap`/`--cursor`）现在与固件
共用整数版面，只接受标准值（6 / 16 / 6 / 0.30），传其它值会直接报错——这是
“模拟器帧与固件帧逐字节一致”的前提。

## 9. 已知限制

- 暂不画跨音符连杠（beaming），八分/十六分都用独立符尾；需要时可在下一轮加。
- 三连音等非标准时值按最近标准时值近似，不画连音符数字/括号。
- 只处理一个拍号（取第一个事件）；中途变拍号未实现。
- 单谱表自动换谱号时，过渡窗口中已滚出的旧谱号音符仍按旧谱号显示（记谱正确，
  但固定区显示的是当前谱号）。
- 模拟器不模拟 OLED 软 SPI 的刷屏耗时；按 1024 字节整屏估算量级为数毫秒到十几毫秒，
  步进式滚动够用，固件阶段再实测。
- 7 个升降号时固定区会很挤（每个 6px），实际曲目按 0–4 个升降号使用。

## 10. 固件接入（代码生成器）

固件阶段已把本方案的模拟器逻辑原样搬进 `stc32g_sdcc`：音乐工程生成 `main.c` 时，
`pieblock_core` 会把乐谱预先算成紧凑的显示事件数据表，并随 main.c 一起发射字形点阵；
固件运行时只做几何绘制和整屏刷新。

### 10.1 数据流

```
MusicConfig → buildStaffSong()（pieblock_core）
  · soundingSpans 裁决 + 休止拆分
  · 按调号拼写的音名 → step、自动谱号、临时记号、时值编码、毫秒时长
  · 调号纵向步数（高/低音各一套）、拍号
→ main.c 内 `#if defined(__SDCC)` 分支：
  · staffGlyphRows/staffGlyphDescs/staffGlyphSet（字形点阵）
  · staffTickDurations/staffDurationsMs/staffPitches/staffSteps/staffFlags
  · staffKeyStepsTreble/staffKeyStepsBass
  · staffSong（指向上述表的只读结构体）
→ 固件循环：OLEDStaff_Show(&staffSong, i) → 发声/停 → Music_Wait(durationsMs[i])
```

- 事件表用 SoA（避免结构体对齐浪费 flash），事件首尾相接，C 侧累加
  `tickDurations` 得到 `startTick`。
- 渲染器 `StaffRender.c` 是纯 C（只依赖 `stdint.h`/`string.h`），可在 PC 上用 gcc
  编译，和 Dart 模拟器逐帧对拍；板级胶水 `OLED_Staff.c` 负责 XRAM 帧缓冲与
  `LCD_WriteFrame`（新增文件实现软件 SPI 整屏写，不修改厂商 `LCD.c`）。
- 版面常量与 `pieblock_core/lib/src/staff_layout.dart` 完全一致（整数像素），
  禁区/隔离带/整颗音符不截断/临时记号遮罩等规则不变。

### 10.2 构建与验证

- `build_manifest.json` 新增 `staff` 源组；三个音乐工程的 `library_groups` 为
  `["pwm","lcd","staff"]`。Android/Windows/Linux 的资源打包会自动带上
  `libraries/**`，不需要改打包脚本。
- 本地重新生成并构建：

```powershell
dart run tool/generate_firmware_main.dart --project assets/templates/music.pieproj `
  --out stc32g_sdcc/projects/BUZZER_MUSIC_GENERATED/src/main.c

pwsh stc32g_sdcc/build.ps1 -Project BUZZER_MUSIC_GENERATED `
  -Sdcc vendor\sdcc-toolchain\bin\sdcc.exe `
  -LibDir vendor\sdcc-toolchain\lib\mcs251-large-stack-auto `
  -StdInclude vendor\sdcc-toolchain\include
```

- 主机对拍：`tool/emit_staff_fixtures.dart` 生成 fixture（6 个场景的 C 数据 + golden
  帧），`stc32g_sdcc/tests/test_staff_render_host.py` 用 gcc 编译
  `StaffRender.c` 逐帧比较，并用 SDCC `-c` 检查 C251 兼容性。
- 生成器测试：`packages/pieblock_core/test/staff_notation_test.dart` 覆盖调号拼写、
  自动谱号、临时记号、休止拆分、MIDI 调号往返与 main.c 分支结构。

### 10.3 限制

- 只有 SDCC 构建包含五线谱显示；Keil 音乐构建保持原蜂鸣器播放（main.c 用
  `#if defined(__SDCC)` 隔离，部署页会提示）。
- 只显示第一个拍号事件；中途变拍号仍按第一拍号画小节线。
- 整屏软件 SPI 刷新在每事件开头统一增加数毫秒延迟，节奏整体平移但不改变相对时值；
  若实机明显需要优化，再做按页差量刷新。
- 曲目过长时五线谱数据可能逼近 64KB 代码区，校验器会给出预算告警。

## 11. 后续可选

1. 连杠（beaming）、三连音数字/括号。
2. Keil 音乐工程也接入 OLED 显示（需要改 Keil 工程文件与库）。
3. 多拍号/多调号事件与更平滑的滚动。
