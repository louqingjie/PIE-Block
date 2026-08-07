using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using Windows.Devices.Radios;

namespace BtCtl;

/// <summary>
/// btctl —— 经典蓝牙 (SPP) 扫描 / 配对伴生工具。
/// 第一阶段只做 --scan（扫描），后续阶段再做 --pair。
///
/// 发现 / 已配对列表走 Win32 bluetoothapis.dll 的 BluetoothFindFirstDevice：
///   这是 Windows「设置 → 蓝牙 → 添加设备」用的同一套查询，fIssueInquiry 保证
///   发起真实查询（约 cTimeoutMultiplier * 1.28s），不会像 WinRT AEP 那样在
///   无设备时秒返回空、漏掉配对模式里的 HC-05/06。
/// 适配器开关状态走 WinRT Radio（简单可靠）。
/// 后续 --pair 走 WinRT DevicePairing（按 MAC 从 BluetoothDevice 发起），
/// 与本文件的 Win32 发现结果天然衔接。
///
/// 输出：一律 JSON。既打 stdout，也支持 --out &lt;路径&gt; 写 UTF-8 文件
/// （Godot 在中文 Windows 下读文件比解析 OS.execute 的 stdout 可靠）。
/// 退出码：0=成功 1=运行时错误 2=用法错误。
/// </summary>
internal static class Program
{
    /// <summary>真实查询时长倍数：8 * 1.28s ≈ 10s（1..48 有效）。</summary>
    private const byte InquiryTimeoutMultiplier = 8;

    private static readonly JsonSerializerOptions JsonOpts = new()
    {
        WriteIndented = true,
        Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    };

    private static readonly string HelpText =
        "btctl —— 经典蓝牙 (SPP) 扫描 / 配对伴生工具\n" +
        "\n" +
        "用法:\n" +
        "  btctl --scan [--multiplier <1..48>] [--verbose] [--out <json文件>]\n" +
        "  btctl --pair <MAC> [--pin <pin>] [--system-dialog] [--enable-spp] [--verbose] [--out <json文件>]\n" +
        "\n" +
        "  --scan          扫描：列出蓝牙适配器、可发现设备（真实查询）、已配对设备\n" +
        "  --multiplier    查询时长倍数（1..48，每倍约 1.28s，默认 8≈10s）。测试可调小\n" +
        "  --pair <MAC>    与指定地址配对（MAC 形如 AA:BB:CC:DD:EE:FF）\n" +
        "  --pin <pin>     先尝试用该 PIN 静默配对（HC-05/06 固定 1234）；失败则弹系统对话框\n" +
        "  --system-dialog 直接弹系统配对对话框（不尝试静默 PIN）\n" +
        "  --enable-spp    配对成功后启用 SPP 串口服务（让虚拟串口出现）\n" +
        "  --verbose       附加诊断信息（异常堆栈）\n" +
        "  --out           把 JSON 额外写入指定文件（UTF-8，供 Godot 读取）\n" +
        "\n" +
        "退出码: 0=成功  1=运行时错误  2=用法错误";

    private static async Task<int> Main(string[] args)
    {
        var argv = args.ToList();
        string? outPath = TakeOption(argv, "--out");
        bool verbose = argv.RemoveAll(x => string.Equals(x, "--verbose", StringComparison.OrdinalIgnoreCase)) > 0;
        byte multiplier = ParseMultiplier(argv);

        // --pair 参数：--pair 后紧跟 MAC
        string? pairMac = null;
        int pairIdx = argv.FindIndex(x => string.Equals(x, "--pair", StringComparison.OrdinalIgnoreCase));
        if (pairIdx >= 0)
        {
            if (pairIdx + 1 < argv.Count)
            {
                pairMac = argv[pairIdx + 1];
            }
            argv.RemoveRange(pairIdx, pairMac != null ? 2 : 1);
        }
        string? pin = TakeOption(argv, "--pin");
        bool systemDialog = argv.RemoveAll(x => string.Equals(x, "--system-dialog", StringComparison.OrdinalIgnoreCase)) > 0;
        bool enableSpp = argv.RemoveAll(x => string.Equals(x, "--enable-spp", StringComparison.OrdinalIgnoreCase)) > 0;

        bool doScan = argv.Any(x => string.Equals(x, "--scan", StringComparison.OrdinalIgnoreCase));
        if (!doScan && pairMac == null)
        {
            Console.WriteLine(HelpText);
            return 2;
        }

        try
        {
            object payload = pairMac != null
                ? RunPair(pairMac, pin, systemDialog, enableSpp)
                : await RunScanAsync(verbose, multiplier).ConfigureAwait(false);
            return Emit(payload, outPath);
        }
        catch (Exception ex)
        {
            var err = new { ok = false, error = ex.Message, stack = verbose ? ex.ToString() : null };
            return Emit(err, outPath);
        }
    }

    private static async Task<object> RunScanAsync(bool verbose, byte inquiryMultiplier)
    {
        var sw = Stopwatch.StartNew();

        var radios = await GetBluetoothRadiosAsync().ConfigureAwait(false);
        bool radioReady = radios.Any(r => string.Equals(r.State, "on", StringComparison.OrdinalIgnoreCase));

        // 可发现设备：认证 + 记住 + 未知 + 已连接，并发起真实查询。
        var discoverable = EnumerateDevices(
            includeAuthenticated: true,
            includeRemembered: true,
            includeUnknown: true,
            issueInquiry: true,
            inquiryMultiplier);

        // 已配对设备：只查缓存（认证过的），不再查询。
        var paired = EnumerateDevices(
            includeAuthenticated: true,
            includeRemembered: true,
            includeUnknown: false,
            issueInquiry: false,
            inquiryMultiplier);

        return new
        {
            ok = true,
            scan = new
            {
                radio_ready = radioReady,
                radios,
                discoverable,
                paired,
                discovery_ms = sw.ElapsedMilliseconds,
            },
        };
    }

    // ---------------------------------------------------------------- 配对

    private static object RunPair(string mac, string? pin, bool systemDialog, bool enableSpp)
    {
        var sw = Stopwatch.StartNew();
        var p = new BLUETOOTH_FIND_RADIO_PARAMS
        {
            dwSize = (uint)Marshal.SizeOf<BLUETOOTH_FIND_RADIO_PARAMS>(),
        };
        // 返回值 = 搜索句柄（BluetoothFindRadioClose 关它）；出参 = 电台句柄（配对用）。
        IntPtr hFind = BluetoothFindFirstRadio(ref p, out IntPtr hRadio);
        if (hFind == IntPtr.Zero)
        {
            throw new Exception("未找到可用的蓝牙适配器（或已被禁用）");
        }

        try
        {
            var info = new BLUETOOTH_DEVICE_INFO
            {
                dwSize = (uint)Marshal.SizeOf<BLUETOOTH_DEVICE_INFO>(),
                Address = ParseBthAddr(mac),
            };

            string method;
            string? error = null;
            bool ok = TryAuthenticate(hRadio, ref info, pin, systemDialog, out method, out error);

            // 静默 PIN 失败：回退到系统配对对话框，让用户手动输 PIN（或点完成）。
            if (!ok && !systemDialog && !string.IsNullOrEmpty(pin))
            {
                ok = TryAuthenticate(hRadio, ref info, null, true, out method, out error);
                method = "pin_fallback_dialog";
            }

            if (ok && enableSpp)
            {
                var sppGuid = SerialPortGuid;
                BluetoothSetServiceState(hRadio, ref info, ref sppGuid, BluetoothServiceEnable);
            }

            return new
            {
                ok,
                paired = ok,
                method,
                mac,
                enable_spp = enableSpp,
                error,
                pair_ms = sw.ElapsedMilliseconds,
            };
        }
        finally
        {
            BluetoothFindRadioClose(hFind);
            CloseHandle(hRadio);
        }
    }

    private static bool TryAuthenticate(IntPtr hRadio, ref BLUETOOTH_DEVICE_INFO info,
        string? pin, bool forceDialog, out string method, out string? error)
    {
        error = null;
        if (forceDialog || string.IsNullOrEmpty(pin))
        {
            method = "dialog";
            if (BluetoothAuthenticateDevice(IntPtr.Zero, hRadio, ref info, null, 0))
            {
                return true;
            }
            error = $"系统配对失败（Win32 错误 {Marshal.GetLastWin32Error()}）";
            return false;
        }

        method = "pin";
        if (BluetoothAuthenticateDevice(IntPtr.Zero, hRadio, ref info, pin, (uint)pin.Length))
        {
            return true;
        }
        error = $"静默 PIN 配对失败（Win32 错误 {Marshal.GetLastWin32Error()}）";
        return false;
    }

    /// <summary>"AA:BB:CC:DD:EE:FF" → BTH_ADDR（ULONGLONG）。</summary>
    private static ulong ParseBthAddr(string mac)
    {
        var parts = mac.Trim().Split(':');
        if (parts.Length != 6)
        {
            throw new FormatException($"无效 MAC 地址: {mac}");
        }
        ulong addr = 0;
        for (int i = 0; i < 6; i++)
        {
            if (!byte.TryParse(parts[i], System.Globalization.NumberStyles.HexNumber, null, out byte b))
            {
                throw new FormatException($"无效 MAC 地址: {mac}");
            }
            addr |= (ulong)b << (8 * (5 - i));
        }
        return addr;
    }

    // ---------------------------------------------------------------- 适配器

    private static async Task<List<RadioInfo>> GetBluetoothRadiosAsync()
    {
        var result = new List<RadioInfo>();
        try
        {
            var radios = await Task.Run(async () => await Radio.GetRadiosAsync()).ConfigureAwait(false);
            foreach (var r in radios.Where(r => r.Kind == RadioKind.Bluetooth))
            {
                result.Add(new RadioInfo { Name = r.Name, State = r.State.ToString().ToLowerInvariant() });
            }
        }
        catch (Exception ex)
        {
            result.Add(new RadioInfo { Name = "(枚举失败)", State = "error", Error = ex.Message });
        }
        return result;
    }

    // ---------------------------------------------------------------- 设备（Win32）

    private static List<DeviceInfo> EnumerateDevices(
        bool includeAuthenticated, bool includeRemembered, bool includeUnknown, bool issueInquiry, byte multiplier)
    {
        var search = new BLUETOOTH_DEVICE_SEARCH_PARAMS
        {
            dwSize = (uint)Marshal.SizeOf<BLUETOOTH_DEVICE_SEARCH_PARAMS>(),
            fReturnAuthenticated = includeAuthenticated ? 1u : 0u,
            fReturnRemembered = includeRemembered ? 1u : 0u,
            fReturnUnknown = includeUnknown ? 1u : 0u,
            fReturnConnected = 1u,
            fIssueInquiry = issueInquiry ? 1u : 0u,
            cTimeoutMultiplier = issueInquiry ? multiplier : (byte)0,
            hRadio = IntPtr.Zero, // 搜所有适配器
        };

        var info = new BLUETOOTH_DEVICE_INFO
        {
            dwSize = (uint)Marshal.SizeOf<BLUETOOTH_DEVICE_INFO>(),
        };

        var results = new List<DeviceInfo>();
        IntPtr hFind = BluetoothFindFirstDevice(ref search, ref info);
        if (hFind == IntPtr.Zero)
        {
            return results; // 无设备 / 适配器不可用，均视为空
        }

        try
        {
            AddUnique(results, ToDeviceInfo(info));
            while (BluetoothFindNextDevice(hFind, ref info))
            {
                AddUnique(results, ToDeviceInfo(info));
            }
        }
        finally
        {
            BluetoothFindDeviceClose(hFind);
        }

        return results
            .OrderByDescending(x => x.Connected)
            .ThenBy(x => x.Name, StringComparer.OrdinalIgnoreCase)
            .ToList();
    }

    private static void AddUnique(List<DeviceInfo> list, DeviceInfo d)
    {
        if (string.IsNullOrEmpty(d.Address) || list.Any(x => x.Address == d.Address))
        {
            return;
        }
        list.Add(d);
    }

    private static DeviceInfo ToDeviceInfo(BLUETOOTH_DEVICE_INFO info)
    {
        return new DeviceInfo
        {
            Name = info.szName?.Trim() ?? "",
            Address = FormatBthAddr(info.Address),
            Paired = info.fAuthenticated != 0,
            Connected = info.fConnected != 0,
        };
    }

    /// <summary>BTH_ADDR（ULONGLONG）→ "AA:BB:CC:DD:EE:FF"。</summary>
    private static string FormatBthAddr(ulong addr)
    {
        var b = new byte[6];
        for (int i = 0; i < 6; i++)
        {
            b[i] = (byte)((addr >> (8 * (5 - i))) & 0xFF);
        }
        return string.Join(":", b.Select(x => x.ToString("X2")));
    }

    // ---------------------------------------------------------------- P/Invoke

    [DllImport("bluetoothapis.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern IntPtr BluetoothFindFirstDevice(
        ref BLUETOOTH_DEVICE_SEARCH_PARAMS pbtsp,
        ref BLUETOOTH_DEVICE_INFO pbtdi);

    [DllImport("bluetoothapis.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool BluetoothFindNextDevice(IntPtr hFind, ref BLUETOOTH_DEVICE_INFO pbtdi);

    [DllImport("bluetoothapis.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool BluetoothFindDeviceClose(IntPtr hFind);

    [StructLayout(LayoutKind.Sequential)]
    private struct BLUETOOTH_DEVICE_SEARCH_PARAMS
    {
        public uint dwSize;
        public uint fReturnAuthenticated;
        public uint fReturnRemembered;
        public uint fReturnUnknown;
        public uint fReturnConnected;
        public uint fIssueInquiry;
        public byte cTimeoutMultiplier;
        public IntPtr hRadio;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct BLUETOOTH_DEVICE_INFO
    {
        public uint dwSize;
        public ulong Address;
        public uint ulClassofDevice;
        public uint fConnected;
        public uint fRemembered;
        public uint fAuthenticated;
        public SYSTEMTIME stLastSeen;
        public SYSTEMTIME stLastUsed;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 248)]
        public string szName;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct SYSTEMTIME
    {
        public ushort wYear;
        public ushort wMonth;
        public ushort wDayOfWeek;
        public ushort wDay;
        public ushort wHour;
        public ushort wMinute;
        public ushort wSecond;
        public ushort wMilliseconds;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct BLUETOOTH_FIND_RADIO_PARAMS
    {
        public uint dwSize;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct GUID
    {
        public uint Data1;
        public ushort Data2;
        public ushort Data3;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 8)]
        public byte[] Data4;
    }

    private const uint BluetoothServiceEnable = 1;

    /// <summary>GUID_SERIALPORT：00001101-0000-1000-8000-00805F9B34FB（SPP 串口服务）。</summary>
    private static readonly GUID SerialPortGuid = new()
    {
        Data1 = 0x00001101,
        Data2 = 0x0000,
        Data3 = 0x1000,
        Data4 = new byte[] { 0x80, 0x00, 0x00, 0x80, 0x5F, 0x9B, 0x34, 0xFB },
    };

    [DllImport("bluetoothapis.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool BluetoothAuthenticateDevice(
        IntPtr hwnd,
        IntPtr hRadio,
        ref BLUETOOTH_DEVICE_INFO pbtdi,
        [MarshalAs(UnmanagedType.LPWStr)] string? pszPin,
        uint ulPasskeyLength);

    [DllImport("bluetoothapis.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool BluetoothSetServiceState(
        IntPtr hRadio,
        ref BLUETOOTH_DEVICE_INFO pbtdi,
        ref GUID pGuidService,
        uint dwServiceFlags);

    [DllImport("bluetoothapis.dll", SetLastError = true)]
    private static extern IntPtr BluetoothFindFirstRadio(
        ref BLUETOOTH_FIND_RADIO_PARAMS pbtfrp,
        out IntPtr phRadio);

    [DllImport("bluetoothapis.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool BluetoothFindRadioClose(IntPtr hFind);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CloseHandle(IntPtr hObject);

    // ---------------------------------------------------------------- 参数 / 输出

    private static string? TakeOption(List<string> argv, string flag)
    {
        int i = argv.FindIndex(x => string.Equals(x, flag, StringComparison.OrdinalIgnoreCase));
        if (i < 0 || i + 1 >= argv.Count)
        {
            return null;
        }
        var v = argv[i + 1];
        argv.RemoveRange(i, 2);
        return v;
    }

    private static byte ParseMultiplier(List<string> argv)
    {
        string? v = TakeOption(argv, "--multiplier");
        if (int.TryParse(v, out int m) && m >= 1 && m <= 48)
        {
            return (byte)m;
        }
        return InquiryTimeoutMultiplier;
    }

    private static int Emit(object payload, string? outPath)
    {
        string json = JsonSerializer.Serialize(payload, JsonOpts);
        Console.OutputEncoding = Encoding.UTF8;
        Console.WriteLine(json);

        if (!string.IsNullOrWhiteSpace(outPath))
        {
            try
            {
                var dir = Path.GetDirectoryName(Path.GetFullPath(outPath));
                if (!string.IsNullOrEmpty(dir))
                {
                    Directory.CreateDirectory(dir);
                }
                File.WriteAllText(outPath, json, new UTF8Encoding(false));
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine($"[warn] 写入 --out 失败: {ex.Message}");
            }
        }
        return 0;
    }

    // ---------------------------------------------------------------- DTO

    internal sealed class RadioInfo
    {
        public string Name { get; set; } = "";
        public string State { get; set; } = "";
        [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
        public string? Error { get; set; }
    }

    internal sealed class DeviceInfo
    {
        public string Name { get; set; } = "";
        [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
        public string? Address { get; set; }
        [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
        public int? Rssi { get; set; }
        public bool Paired { get; set; }
        public bool Connected { get; set; }
    }
}
