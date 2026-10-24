part of '../wizard_screen.dart';

/// 网页版的「烧录」：功能不存在，但也不能留一个空页——
/// 说清楚为什么、以及要去哪里完成，顺带把下载链接给出去。
class _WebDeployNotice extends StatelessWidget {
  const _WebDeployNotice();

  static const _downloadUrl =
      'https://github.com/louqingjie/PIE-Block/releases';

  @override
  Widget build(BuildContext context) => _PageFrame(
    title: '烧录',
    subtitle: '网页版负责配置与生成代码，汇编对照与烧录请在桌面版完成。',
    child: _Section(
      title: '这一步需要本机环境',
      children: [
        const _InfoBanner(
          '汇编对照要用本机的内置 SDCC 工具链编译，烧录要直接访问 USB-HID 设备，'
          '浏览器里都做不到。项目配置与生成的 C 代码不受影响，可以照常导出。',
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton.icon(
              onPressed: () async {
                await Clipboard.setData(
                  const ClipboardData(text: _downloadUrl),
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('下载链接已复制')));
                }
              },
              icon: const Icon(Icons.copy_all_outlined),
              label: const Text('复制桌面版下载链接'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SelectableText(
          _downloadUrl,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
  );
}

class _DeployPage extends ConsumerStatefulWidget {
  const _DeployPage();

  @override
  ConsumerState<_DeployPage> createState() => _DeployPageState();
}

class _DeployPageState extends ConsumerState<_DeployPage> {
  Timer? _deviceTimer;

  final ScrollController _logScroll = ScrollController();
  final GlobalKey _logSectionKey = GlobalKey();
  ProviderSubscription<List<String>>? _logEventsSub;

  /// 日志区是否跟随最新一行。用户手动上滑时会暂停，滚回底部再自动恢复。
  bool _logFollow = false;

  @override
  void initState() {
    super.initState();
    _logScroll.addListener(_onLogScroll);
    // 只在 events 变化时触发：每秒的 refreshDevices 不会改动 events 引用，
    // 因此不会误触发滚动。
    _logEventsSub = ref.listenManual<List<String>>(
      deployControllerProvider.select((s) => s.events),
      (previous, next) => _followLogToBottom(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 进入页面时重新检查 udev 规则是否已安装（用户可能在应用外装过）。
      ref.read(udevRuleControllerProvider.notifier).refresh();
      _prepare();
    });
    // 安卓同样需要周期检测：UsbHidBridge 检测到板子的瞬间会自动授权并
    // 打开保持（防止 STC ISP 固件因总线空闲跳回用户程序）。
    _deviceTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => ref.read(deployControllerProvider.notifier).refreshDevices(),
    );
  }

  @override
  void dispose() {
    _deviceTimer?.cancel();
    _logEventsSub?.close();
    _logScroll
      ..removeListener(_onLogScroll)
      ..dispose();
    super.dispose();
  }

  void _onLogScroll() {
    if (!_logScroll.hasClients) return;
    // 留一点容差，滚到底部附近就算「在底部」，避免差几个像素就误判。
    final atBottom = _logScroll.position.extentAfter <= 24;
    if (atBottom != _logFollow) setState(() => _logFollow = atBottom);
  }

  /// 新日志追加后跟到最后一行。内容变长要等这一帧布局完才能拿到新的
  /// maxScrollExtent，所以放到 post-frame 里做。日志逐行刷得很快，用
  /// jumpTo 而不是 animateTo，避免动画互相打断。
  void _followLogToBottom() {
    if (!_logFollow) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_logScroll.hasClients) return;
      _logScroll.jumpTo(_logScroll.position.maxScrollExtent);
    });
  }

  /// 点击编译/烧录类按钮时调用：开启跟随、把日志区滚入视野、并立刻跟到底。
  void _startLogFollow() {
    setState(() => _logFollow = true);
    final context = _logSectionKey.currentContext;
    if (context != null) {
      Scrollable.ensureVisible(
        context,
        duration: m3Duration(context, Durations.medium2),
        alignment: .28,
      );
    }
    _followLogToBottom();
  }

  Future<void> _prepare() async {
    var app = ref.read(appControllerProvider);
    if (_isAndroid && app.compiler != CompilerKind.sdcc) {
      ref.read(appControllerProvider.notifier).setCompiler(CompilerKind.sdcc);
      app = ref.read(appControllerProvider);
    }
    if (app.compiler == CompilerKind.keil && app.keilPath == null) {
      final installation = await const ToolchainDiscovery().resolveKeil();
      if (installation != null && mounted) {
        ref.read(appControllerProvider.notifier).setKeilPath(installation.root);
        app = ref.read(appControllerProvider);
      }
    }
    await ref
        .read(deployControllerProvider.notifier)
        .prepare(app.document!.config, app.compiler, keilRoot: app.keilPath);
  }

  Future<void> _chooseKeil() async {
    final selected = await getDirectoryPath(confirmButtonText: '选择 Keil 目录');
    if (selected == null) return;
    final installation = await const ToolchainDiscovery().validateKeil(
      selected,
    );
    if (!mounted) return;
    if (installation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('所选目录缺少 UV4/uVision.com 或 C251/BIN/C251.EXE'),
        ),
      );
      return;
    }
    ref.read(appControllerProvider.notifier).setKeilPath(installation.root);
    await _prepare();
  }

  Future<bool> _build() async {
    _startLogFollow();
    final appController = ref.read(appControllerProvider.notifier);
    await appController.saveNow();
    final app = ref.read(appControllerProvider);
    if (app.saveStatus == SaveStatus.failed) return false;
    if (app.compiler == CompilerKind.keil && app.keilPath == null) {
      await _chooseKeil();
      if (ref.read(appControllerProvider).keilPath == null) return false;
    }
    final current = ref.read(appControllerProvider);
    return ref
        .read(deployControllerProvider.notifier)
        .buildFirmware(
          current.document!.config,
          current.compiler,
          keilRoot: current.keilPath,
        );
  }

  Future<bool> _confirmFlashSafety() async {
    final app = ref.read(appControllerProvider);
    if (app.suppressFlashGuide) return true;
    var suppress = false;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('烧录主控板前请确认'),
          content: SizedBox(
            // Android 手机上给正文明确的最大高度，避免两张说明图和
            // 内层滚动视图把 AlertDialog 推出屏幕，只剩下遮罩层。
            width: double.maxFinite,
            height: MediaQuery.sizeOf(context).height * 0.52,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '只能烧录主控板，绝不能向机械扩展板烧录程序。烧录前请关闭以下四个开关，避免无法识别或电流倒灌。',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Builder(
                    builder: (context) {
                      const main = _SafetyImage(
                        asset: 'assets/images/switch_main.png',
                        caption: '主控板：关闭 SERVO、POWER',
                      );
                      const expansion = _SafetyImage(
                        asset: 'assets/images/switch_expend.png',
                        caption: '扩展板：关闭 POWER、BOOSTER',
                      );
                      if (_isCompact(context)) {
                        return const Column(
                          children: [main, SizedBox(height: 16), expansion],
                        );
                      }
                      return const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: main),
                          SizedBox(width: 16),
                          Expanded(child: expansion),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  const Text('主控板必须通过断电后重新上电进入 ISP。烧录完成会自动复位；再次烧录前需要重新断电上电。'),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: suppress,
                    onChanged: (value) =>
                        setDialogState(() => suppress = value ?? false),
                    title: const Text('以后不再显示此提示'),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('已关闭开关，继续烧录'),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true && suppress) {
      ref.read(appControllerProvider.notifier).suppressFlashGuide();
    }
    return confirmed == true;
  }

  Future<void> _primaryAction() async {
    _startLogFollow();
    var artifact = ref.read(deployControllerProvider).artifact;
    if (artifact == null) {
      if (!await _build()) return;
      artifact = ref.read(deployControllerProvider).artifact;
      if (artifact == null) return;
    }
    if (!await _confirmFlashSafety()) return;
    await ref.read(deployControllerProvider.notifier).flashFirmware();
  }

  Future<void> _exportHex() async {
    if (_isAndroid) {
      await ref.read(deployControllerProvider.notifier).exportHexOnAndroid();
      return;
    }
    final location = await getSaveLocation(
      suggestedName: 'firmware.hex',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'HEX 固件', extensions: ['hex']),
      ],
    );
    if (location == null) return;
    await ref.read(deployControllerProvider.notifier).exportHex(location.path);
  }

  /// 通过 pkexec 弹出系统授权对话框安装 udev 规则（Linux 桌面版）。
  Future<void> _installUdevRule() async {
    if (ref.read(udevRuleControllerProvider).installing) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('安装 udev 规则'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: const Text(
            '将把 hidraw 设备授权规则写入 /etc/udev/rules.d/70-pieblock-hid.rules 并重载 udev。'
            '接下来会弹出系统授权对话框，请输入管理员密码确认；应用不会接触或保存密码。',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('安装'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final result = await ref
        .read(udevRuleControllerProvider.notifier)
        .install();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(_udevResultMessage(result))));
    if (result.ok) {
      await ref.read(deployControllerProvider.notifier).refreshDevices();
    }
  }

  String _udevResultMessage(UdevInstallResult result) {
    return switch (result.outcome) {
      UdevInstallOutcome.success =>
        'udev 规则已安装。若主控板已插上，请拔出后重新插入（或断电重新上电进 ISP）再检测。',
      UdevInstallOutcome.installedNoUdevadm =>
        '规则已安装，但未找到 udevadm（可能是非 systemd 环境）。请手动重载 udev 或重新插拔设备。',
      UdevInstallOutcome.canceled => '已取消安装（未通过系统授权）。',
      UdevInstallOutcome.notAuthorized => '系统授权失败或不可用：可能缺少 polkit 认证代理，或在无图形会话中运行。可改用命令行：sudo tools/install_udev_rules.sh',
      UdevInstallOutcome.pkexecMissing => '未找到 pkexec，无法弹出系统授权对话框。请安装 polkit，或改用命令行：sudo tools/install_udev_rules.sh',
      UdevInstallOutcome.timedOut => '系统授权超时，未安装 udev 规则。',
      UdevInstallOutcome.failed =>
        result.exitCode != null
            ? '安装 udev 规则失败（退出码 ${result.exitCode}）：${result.stderrText}'
            : '安装 udev 规则失败：${result.stderrText}',
    };
  }

  Future<void> _applyLicense() async {
    final key = TextEditingController();
    final submitted = await showDialog<String>(
      context: context,
      builder: (context) => AppDialog(
        title: const Text('应用 Keil C251 许可证'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '密钥只写入 Keil 的 TOOLS.INI，不会保存到 PIE-Block 设置或构建日志。写入前会创建 .pieblock.bak 备份。',
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: key,
                  decoration: const InputDecoration(labelText: 'C251 许可证密钥'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, key.text.trim()),
            child: const Text('应用许可证'),
          ),
        ],
      ),
    );
    if (submitted == null || submitted.isEmpty) return;
    final path = ref.read(appControllerProvider).keilPath;
    final installation = await const ToolchainDiscovery().validateKeil(
      path ?? '',
    );
    if (installation == null) return;
    try {
      await const ToolchainDiscovery().applyKeilLicense(
        installation,
        submitted,
      );
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('许可证已应用，请重新编译')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('写入许可证失败：$error。请改用 Keil License Management。'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 网页版没有本地编译器，也没有 USB-HID，这一页整块换引导。
    if (kIsWeb) return const _WebDeployNotice();
    final app = ref.watch(appControllerProvider);
    final deploy = ref.watch(deployControllerProvider);
    final udev = ref.watch(udevRuleControllerProvider);
    final artifact = deploy.artifact;
    final deviceText = switch (deploy.deviceCount) {
      0 => '未检测到 ISP 主控板',
      1 => '已检测到 1 块 ISP 主控板',
      _ => '检测到 ${deploy.deviceCount} 块主控板，请只保留一块',
    };
    return _PageFrame(
      title: '烧录',
      subtitle: _isAndroid
          ? deploy.compilerAvailable
                ? '使用内置 SDCC 离线编译 STC32G12K128 固件，并通过 OTG USB-HID 写入主控板。'
                : '当前安装包未启用 Android 原生编译；项目配置与代码生成仍可正常使用。'
          : '将当前配置编译为 STC32G12K128 固件，并通过免驱 USB-HID 写入主控板。',
      child: Column(
        children: [
          _Section(
            title: '编译器',
            subtitle: _isAndroid
                ? deploy.compilerAvailable
                      ? 'Android 使用随应用发布的原生 SDCC C251，不需要联网。'
                      : '原生编译安全门禁尚未通过，编译入口已禁用。'
                : '内置 SDCC 可完全离线使用；Keil 使用本机已安装的 C251。',
            children: [
              if (_isAndroid)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    deploy.compilerAvailable
                        ? Icons.memory_outlined
                        : Icons.warning_amber_rounded,
                    color: deploy.compilerAvailable
                        ? null
                        : Theme.of(context).colorScheme.error,
                  ),
                  title: const Text('内置 SDCC C251'),
                  subtitle: Text(
                    deploy.compilerAvailable
                        ? 'NDK 原生库 · arm64-v8a / x86_64'
                        : '当前安装包未包含可用的原生编译流水线',
                  ),
                )
              else ...[
                _AdaptiveRow(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<CompilerKind>(
                        initialValue: app.compiler,
                        decoration: const InputDecoration(labelText: '本地编译器'),
                        items: const [
                          DropdownMenuItem(
                            value: CompilerKind.sdcc,
                            child: Text('内置 SDCC C251'),
                          ),
                          DropdownMenuItem(
                            value: CompilerKind.keil,
                            child: Text('本地 Keil C251'),
                          ),
                        ],
                        onChanged: deploy.busy
                            ? null
                            : (value) async {
                                if (value == null) return;
                                ref
                                    .read(appControllerProvider.notifier)
                                    .setCompiler(value);
                                await _prepare();
                              },
                      ),
                    ),
                    if (app.compiler == CompilerKind.keil) ...[
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed: deploy.busy ? null : _chooseKeil,
                        icon: const Icon(Icons.folder_open),
                        label: const Text('选择 Keil 目录'),
                      ),
                    ],
                  ],
                ),
                if (app.compiler == CompilerKind.keil) ...[
                  const SizedBox(height: 10),
                  Text(app.keilPath ?? '尚未指定 Keil 安装目录'),
                ],
                if (app.document?.config.kind == ProjectKind.music &&
                    app.compiler == CompilerKind.keil) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Keil 音乐构建只播放声音，不包含 OLED 五线谱显示；'
                    '需要屏幕显示请切换为内置 SDCC C251。',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ],
          ),
          const SizedBox(height: 16),
          _Section(
            title: '构建产物',
            children: [
              Row(
                children: [
                  Icon(
                    artifact == null
                        ? Icons.pending_outlined
                        : Icons.verified_outlined,
                    color: artifact == null
                        ? Theme.of(context).colorScheme.onSurfaceVariant
                        : AppStatusColors.ok(Theme.of(context).brightness),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      artifact == null
                          ? '当前编译器没有与配置完全匹配的固件'
                          : '${artifact.byteCount} 字节 · ${artifact.warningCount} 条警告 · ${artifact.builtAt.toLocal()}',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  if (_supportsFlashing)
                    FilledButton.icon(
                      onPressed: deploy.busy ? null : _primaryAction,
                      icon: Icon(
                        artifact == null
                            ? Icons.rocket_launch_outlined
                            : Icons.system_update_alt,
                      ),
                      label: Text(artifact == null ? '编译并烧录' : '烧录当前固件'),
                    ),
                  (_isAndroid ? FilledButton.icon : OutlinedButton.icon)(
                    onPressed:
                        deploy.busy || (_isAndroid && !deploy.compilerAvailable)
                        ? null
                        : _build,
                    icon: const Icon(Icons.build_outlined),
                    label: const Text('仅编译'),
                  ),
                  OutlinedButton.icon(
                    onPressed: deploy.busy || artifact == null
                        ? null
                        : _exportHex,
                    icon: const Icon(Icons.save_alt),
                    label: const Text('导出 HEX'),
                  ),
                  if (deploy.busy)
                    TextButton.icon(
                      onPressed: ref
                          .read(deployControllerProvider.notifier)
                          .cancelAll,
                      icon: const Icon(Icons.stop_circle_outlined),
                      label: const Text('取消任务'),
                    ),
                  if (_isWindows && deploy.licenseFailure)
                    TextButton.icon(
                      onPressed: _applyLicense,
                      icon: const Icon(Icons.key_outlined),
                      label: const Text('应用 Keil 许可证'),
                    ),
                ],
              ),
            ],
          ),
          if (_supportsFlashing) ...[
            const SizedBox(height: 16),
            _Section(
              title: '主控板 USB-HID',
              children: [
                Row(
                  children: [
                    Icon(
                      deploy.deviceCount == 1 ? Icons.usb : Icons.usb_off,
                      color: deploy.deviceCount == 1
                          ? AppStatusColors.ok(Theme.of(context).brightness)
                          : deploy.deviceCount > 1
                          ? Theme.of(context).colorScheme.error
                          : null,
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text('$deviceText（VID 34BF / PID 1001）')),
                    IconButton(
                      tooltip: '重新检测',
                      onPressed: deploy.busy
                          ? null
                          : () {
                              ref
                                  .read(deployControllerProvider.notifier)
                                  .refreshDevices();
                              ref
                                  .read(udevRuleControllerProvider.notifier)
                                  .refresh();
                            },
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _InfoBanner(
                  _isAndroid
                      ? '通过 OTG 转接线连接主控板；首次烧录会请求 USB 权限。请先将主控板断电再重新上电进入 ISP 模式；烧录成功后 HID 设备自动消失是正常现象。'
                      : _isLinux
                      ? (udev.installed
                            ? '已安装 udev 规则。未检测到时，请关闭四个供电开关，将主控板断电后重新连接 USB；烧录成功后 HID 设备自动消失是正常现象。'
                            : '尚未安装 udev 规则，应用无法访问 hidraw 设备。请点击下方「安装 udev 规则」，通过系统授权对话框完成安装（等价于 sudo tools/install_udev_rules.sh，详见烧录指南）。')
                      : '未检测到时，请关闭四个供电开关，将主控板断电后重新连接 USB。烧录成功后 HID 设备自动消失是正常现象。',
                ),
                if (_isLinux && !udev.installed) ...[
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: udev.installing ? null : _installUdevRule,
                      icon: const Icon(Icons.shield_outlined),
                      label: Text(udev.installing ? '正在安装…' : '安装 udev 规则'),
                    ),
                  ),
                ],
              ],
            ),
          ],
          const SizedBox(height: 16),
          _Section(
            key: _logSectionKey,
            title: '进度与日志',
            children: [
              // 栏目高度恒定：进度条与消息行常驻占位，日志框固定 360px。
              SizedBox(
                height: 16,
                child: deploy.progress != null
                    ? WavyProgressIndicator(
                        value: deploy.progress,
                        semanticLabel: '烧录进度',
                      )
                    : deploy.busy
                    ? const WavyProgressIndicator(semanticLabel: '烧录进度')
                    : const SizedBox.shrink(),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 20,
                child: Text(
                  deploy.message ?? ' ',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                height: 360,
                padding: const EdgeInsets.all(14),
                decoration: ShapeDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  shape: AppShape.lg,
                ),
                child: SingleChildScrollView(
                  controller: _logScroll,
                  child: SelectableText(
                    deploy.events.isEmpty ? '等待操作…' : deploy.events.join('\n'),
                    style: const TextStyle(
                      fontFamily: 'PieBlockMono',
                      fontSize: 12.5,
                      height: 1.45,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SafetyImage extends StatelessWidget {
  const _SafetyImage({required this.asset, required this.caption});
  final String asset;
  final String caption;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(AppCorner.lg),
        child: Image.asset(
          asset,
          height: 190,
          width: double.infinity,
          fit: BoxFit.contain,
        ),
      ),
      const SizedBox(height: 6),
      Text(caption, textAlign: TextAlign.center),
    ],
  );
}
