# 中文用户名与首次部署导致的两类 SDCC 编译失败

试用反馈里同时出现了两个现场：`C:\Users\吕先生`、`C:\Users\徐瑞杰` 这类中文用户名
下，编译在链接完成后立刻失败；另一台机器上首次使用时内置 SDCC 工具链部署报
「拒绝访问」。两者根因不同，但都发生在“首次编译”这一条链路上，容易混在一起反馈。

## 现象

### 现象一：链接后 MAP 解码失败（中文用户名）

日志在 `ASlink >> -r` 之后直接结束：

```text
[linking] 正在链接 ROBOMASTER_INFANTRY.hex…
[linking] ASlink >> -r
[done] 编译失败：FileSystemException: Failed to decode data using encoding 'utf-8',
       path = 'C:\Users\徐瑞杰\AppData\Local\Temp\builds\…\output\ROBOMASTER_INFANTRY.map'
```

SDCC 的编译、汇编、链接本身都成功了，失败发生在随后的 HEX/MAP 布局校验读 MAP 时。
同一个用户名的警告行在日志里也会显示成 `C:\Users\��\…`（编译器 stdout 是按 UTF-8
宽松解码的，GBK 字节变成了替换字符），属于同一编码问题的外显。

### 现象二：首次部署 `.pending` rename 拒绝访问

```text
[preparing] 首次使用，正在部署内置 SDCC 工具链…
[done] 编译失败：PathAccessException: Rename failed, path =
       'C:\Users\吕先生\AppData\Roaming\com.wpie\PIE-Block\runtime\sdcc\3e36….pending'
       (OS Error: 拒绝访问。, errno = 5)
```

## 根因

### 1. MAP 里的 `Files Linked` 段不是 UTF-8

ASlink 的 `.map` 末尾有一节 `Files Linked`，逐行列出参与链接的 `.rel`/`.lib` 完整路径。
Windows 版 SDCC/ASlink 用**系统 ANSI 代码页**写这些字节；中文用户名或中文临时目录会让
MAP 出现 GBK 字节。仓库里由 SDCC 生成的培训模板 MAP 可直接验证：

```text
C:\Users\louqi\Desktop\program\pie-block\stc32g_sdcc\build\0000.培训模板\common.rel
```

该行中「培训模板」的原始字节是 `C5 E0 D1 B5 C4 A3 B0 E5`（CP936），不是合法 UTF-8。
旧代码 `hex_validator.dart` 用 `File.readAsString()` 严格按 UTF-8 读 MAP，于是抛
`Failed to decode data using encoding 'utf-8'`。HEX 是纯 ASCII，所以能正常解析，
错误看起来像“链接失败”，实际是校验阶段崩溃。

### 2. 固定 `.pending` 目录 + 无重试的 rename

旧部署流程是：

```text
复制数百个文件（约 24 MB）到 <runtime>/sdcc/<fingerprint>.pending
→ 校验 → 写 .ready → 删除目标目录 → rename(.pending → <fingerprint>)
```

`.pending` 路径固定，且删除/rename 都不重试。Windows 上目录 rename 需要目录内没有
其它进程打开的句柄，以下任一情况都会得到 `ERROR_ACCESS_DENIED`（errno 5）：

- 应用内同时有两个 `FirmwareBuilder`：烧录页一个、「生成代码 → 汇编」页一个，共用同一
  `runtimeRoot`，首次使用时可能同时部署，互相复制/删除同一个 `.pending`；
- 杀毒软件、Windows Defender 或搜索索引器正在扫描刚复制出的 `sdcc.exe` 等文件；
- 上一次失败留下的 `.pending` 或半成品目标目录。

`Rename failed` 的异常信息里给的是源路径，所以看到的是 `.pending`。

## 修复

- **工具链文本宽松解码**：新增 `readToolOutputText()`，SDCC MAP、`main_*.rst`
  列表与 Keil 构建日志统一用 `utf8.decode(bytes, allowMalformed: true)` 读取。
  布局校验只依赖 ASCII 的区域名与符号名，非法字节被替换为 `�` 不影响结果。
- **部署指纹与目录不变**：仍使用 `<runtime>/sdcc/<fingerprint>` 与 `.ready`，已有部署
  无需重装。
- **唯一暂存目录**：`<fingerprint>.staging-<pid>-<微秒>`，部署器在进程内串行化，
  两个构建源不会再操作同一个 `.pending`。
- **晋升重试**：rename 遇到占用时退避重试（8 次，约 5 秒），日志提示
  「目录暂时被占用，正在重试…」；每轮先确认目标是否已被另一实例部署好，
  不删除已就绪的部署。
- **可操作报错**：重试仍失败时给出「关闭杀毒实时防护 / 加入白名单 / 删除 runtime\sdcc
  后重试」，而不是只显示裸异常。
- **残留清理**：超过 1 小时的 `*.pending` / `*.staging-*` 在下次部署时清理；
  构建产物缓存写入也加了同样的文件占用重试。

## 验证

旧代码可稳定复现现象一：把临时目录指向中文路径后运行

```powershell
$env:TMP='C:\Users\<用户>\AppData\Local\Temp\pieblock-验证-中文路径'
$env:TEMP=$env:TMP
cd packages/pieblock_toolchain
dart run tool/compile_project.dart debug
```

修复前在链接后抛出上面的 UTF-8 解码异常；修复后同一命令编译成功，且 HEX 与纯英文
临时目录构建逐字节一致（debug 工程 36206 字节，
`hex_sha256 = 210db2181419548e82ecbae0f5ad1da12ae163bebcd41c13d17968c64bc3a263`）。

部署侧由 `test/sdcc_runtime_deployer_test.dart` 覆盖：首次部署、复用、半成品目标重建、
崩溃残留清理、并发收敛、失败提示与暂存清理。
