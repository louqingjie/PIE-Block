// PIE-Block Windows 单文件便携版启动器。
//
// 由 tools/package_flutter_windows_portable.ps1 在打包时编译：
//   csc /target:winexe /resource:payload.zip,payload.zip
//       /resource:payload.id,payload.id
//       /win32icon:windows\runner\resources\app_icon.ico
//
// 运行时行为：
//   1. 读取内嵌的 payload.id（版本号 + 载荷哈希）；
//   2. 首次运行时把内嵌的 payload.zip 解压到
//      %LOCALAPPDATA%\PIE-Block\portable\app\<payload.id>\（可用环境变量
//      PIEBLOCK_PORTABLE_ROOT 覆盖根目录），并用 .ready 标记完成状态；
//   3. 之后每次启动直接复用已解压目录，再以相同工作目录启动真正的
//      PIE-Block.exe，并把命令行参数原样透传；
//   4. 若设置环境变量 PIEBLOCK_PORTABLE_EXTRACT_ONLY=1，只解压不启动，
//      供打包脚本与 CI 做自检。
//
// 说明：这里只依赖 Windows 自带的 .NET Framework 4.x（Windows 10/11 内置），
// 不引入第三方解压或运行时依赖，因此产出的单 exe 可以在一台干净机器上运行。

using System;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Text;
using System.Threading;
using System.Windows.Forms;

internal static class PortableLauncher
{
    private const string PayloadResource = "payload.zip";
    private const string IdResource = "payload.id";
    private const string AppExecutable = "PIE-Block.exe";
    private const string ReadyMarker = ".ready";
    private const string ExtractOnlyEnv = "PIEBLOCK_PORTABLE_EXTRACT_ONLY";
    private const string RootEnv = "PIEBLOCK_PORTABLE_ROOT";
    private const string LogEnv = "PIEBLOCK_PORTABLE_LOG";

    [STAThread]
    private static int Main(string[] args)
    {
        try
        {
            string payloadId = ReadPayloadId();
            string root = GetRootDirectory();
            string target = Path.Combine(root, payloadId);
            if (!IsReady(target))
            {
                ExtractOnce(root, payloadId, target);
            }
            Log("ready " + target);
            if (IsTruthy(Environment.GetEnvironmentVariable(ExtractOnlyEnv)))
            {
                return 0;
            }
            return Launch(target, args);
        }
        catch (Exception error)
        {
            ShowError(error);
            return 1;
        }
    }

    private static void ShowError(Exception error)
    {
        Log("FAILED " + error);
        // 自检/CI 模式不弹窗：无人值守环境下模态框会一直挂着。
        if (IsTruthy(Environment.GetEnvironmentVariable(ExtractOnlyEnv)))
        {
            return;
        }
        try
        {
            MessageBox.Show(
                "PIE-Block 便携版启动失败：\r\n\r\n" + error.Message +
                "\r\n\r\n如果问题持续存在，可删除目录 " +
                GetRootDirectory() + " 后重试。",
                "PIE-Block",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
        }
        catch
        {
            // 连弹窗都失败时只能返回非零退出码。
        }
    }

    /// <summary>可选诊断日志（PIEBLOCK_PORTABLE_LOG），供打包自检与排障使用。</summary>
    private static void Log(string message)
    {
        try
        {
            string path = Environment.GetEnvironmentVariable(LogEnv);
            if (string.IsNullOrWhiteSpace(path))
            {
                return;
            }
            File.AppendAllText(
                path,
                DateTime.UtcNow.ToString("o") + " " + message + "\r\n");
        }
        catch
        {
            // 日志失败不影响启动。
        }
    }

    private static string ReadPayloadId()
    {
        using (Stream stream = Assembly.GetExecutingAssembly()
                   .GetManifestResourceStream(IdResource))
        {
            if (stream == null)
            {
                throw new InvalidOperationException("安装包损坏：缺少内嵌 payload.id。");
            }
            using (var reader = new StreamReader(stream, Encoding.UTF8))
            {
                string id = reader.ReadToEnd().Trim();
                if (id.Length == 0 || id.Length > 128)
                {
                    throw new InvalidDataException("安装包损坏：payload.id 为空或过长。");
                }
                foreach (char c in id)
                {
                    bool safe = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
                                (c >= '0' && c <= '9') || c == '-' || c == '_' ||
                                c == '.';
                    if (!safe)
                    {
                        throw new InvalidDataException(
                            "安装包损坏：payload.id 含有非法字符。");
                    }
                }
                return id;
            }
        }
    }

    private static string GetRootDirectory()
    {
        string configured = Environment.GetEnvironmentVariable(RootEnv);
        if (!string.IsNullOrWhiteSpace(configured))
        {
            return Path.GetFullPath(configured);
        }
        return Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "PIE-Block",
            "portable",
            "app");
    }

    private static bool IsReady(string target)
    {
        try
        {
            return File.Exists(Path.Combine(target, ReadyMarker)) &&
                   File.Exists(Path.Combine(target, AppExecutable));
        }
        catch (Exception)
        {
            return false;
        }
    }

    private static void ExtractOnce(string root, string payloadId, string target)
    {
        Directory.CreateDirectory(root);
        string mutexName = "Local\\PIE-Block-Portable-" + payloadId;
        using (var mutex = new Mutex(false, mutexName))
        {
            bool owned = false;
            try
            {
                try
                {
                    owned = mutex.WaitOne(TimeSpan.FromMinutes(10));
                }
                catch (AbandonedMutexException)
                {
                    owned = true;
                }
                if (!owned)
                {
                    throw new IOException("等待其它 PIE-Block 实例解压超时。");
                }
                if (IsReady(target))
                {
                    return;
                }
                DeleteStaleStaging(root, payloadId);
                string staging = target + ".staging-" +
                                 Process.GetCurrentProcess().Id.ToString(
                                     CultureInfo.InvariantCulture) + "-" +
                                 DateTime.UtcNow.Ticks.ToString(
                                     CultureInfo.InvariantCulture);
                try
                {
                    ExtractPayload(staging, target);
                }
                finally
                {
                    TryDeleteDirectory(staging);
                }
            }
            finally
            {
                if (owned)
                {
                    mutex.ReleaseMutex();
                }
            }
        }
    }

    /// <summary>解压到 staging，写入 .ready 后晋升为正式目录。</summary>
    private static void ExtractPayload(string staging, string target)
    {
        if (Directory.Exists(staging))
        {
            Directory.Delete(staging, true);
        }
        Directory.CreateDirectory(staging);
        using (Stream stream = Assembly.GetExecutingAssembly()
                   .GetManifestResourceStream(PayloadResource))
        {
            if (stream == null)
            {
                throw new InvalidOperationException("安装包损坏：缺少内嵌 payload.zip。");
            }
            using (var archive = new ZipArchive(stream, ZipArchiveMode.Read))
            {
                string stagingRoot = Path.GetFullPath(
                    staging + Path.DirectorySeparatorChar);
                foreach (ZipArchiveEntry entry in archive.Entries)
                {
                    if (string.IsNullOrEmpty(entry.FullName))
                    {
                        continue;
                    }
                    string relative = entry.FullName.Replace(
                        '/', Path.DirectorySeparatorChar);
                    string path = Path.GetFullPath(Path.Combine(staging, relative));
                    if (!path.StartsWith(stagingRoot, StringComparison.OrdinalIgnoreCase) &&
                        !string.Equals(path, stagingRoot, StringComparison.OrdinalIgnoreCase))
                    {
                        throw new InvalidDataException(
                            "安装包包含非法路径：" + entry.FullName);
                    }
                    if (entry.FullName.EndsWith("/", StringComparison.Ordinal) ||
                        entry.Name.Length == 0)
                    {
                        Directory.CreateDirectory(path);
                        continue;
                    }
                    string parent = Path.GetDirectoryName(path);
                    if (!string.IsNullOrEmpty(parent))
                    {
                        Directory.CreateDirectory(parent);
                    }
                    using (Stream input = entry.Open())
                    using (var output = new FileStream(
                               path, FileMode.Create, FileAccess.Write, FileShare.None))
                    {
                        input.CopyTo(output);
                    }
                }
            }
        }

        File.WriteAllText(Path.Combine(staging, ReadyMarker), target);
        Promote(staging, target);
    }

    /// <summary>staging -> target 的原子替换，失败时退避重试。</summary>
    private static void Promote(string staging, string target)
    {
        for (int attempt = 0; attempt < 25; attempt++)
        {
            if (IsReady(target))
            {
                return;
            }
            try
            {
                if (Directory.Exists(target))
                {
                    Directory.Delete(target, true);
                }
                Directory.Move(staging, target);
                return;
            }
            catch (IOException)
            {
                if (attempt == 24)
                {
                    break;
                }
                Thread.Sleep(200);
            }
            catch (UnauthorizedAccessException)
            {
                if (attempt == 24)
                {
                    break;
                }
                Thread.Sleep(200);
            }
        }
        throw new IOException(
            "无法写入解压目录（可能被其它程序占用或没有写入权限）：" + target);
    }

    private static void DeleteStaleStaging(string root, string payloadId)
    {
        try
        {
            if (!Directory.Exists(root))
            {
                return;
            }
            string prefix = payloadId + ".staging-";
            DateTime cutoff = DateTime.UtcNow.AddDays(-1);
            foreach (string directory in Directory.GetDirectories(root))
            {
                if (!Path.GetFileName(directory).StartsWith(
                        prefix, StringComparison.OrdinalIgnoreCase))
                {
                    continue;
                }
                try
                {
                    if (Directory.GetLastWriteTimeUtc(directory) < cutoff)
                    {
                        Directory.Delete(directory, true);
                    }
                }
                catch (Exception)
                {
                    // 清理残留失败不影响本次解压。
                }
            }
        }
        catch (Exception)
        {
            // 根目录不可枚举时交给后续解压报错。
        }
    }

    private static void TryDeleteDirectory(string path)
    {
        try
        {
            if (Directory.Exists(path))
            {
                Directory.Delete(path, true);
            }
        }
        catch (Exception)
        {
            // 尽力清理，失败留给下一次启动按时间清理。
        }
    }

    private static int Launch(string target, string[] args)
    {
        string executable = Path.Combine(target, AppExecutable);
        if (!File.Exists(executable))
        {
            throw new FileNotFoundException(
                "解压结果缺少主程序，请重新下载便携版。", executable);
        }
        var startInfo = new ProcessStartInfo(executable)
        {
            WorkingDirectory = target,
            UseShellExecute = false,
            Arguments = JoinArguments(args),
        };
        using (Process process = Process.Start(startInfo))
        {
            if (process == null)
            {
                throw new InvalidOperationException("无法启动 PIE-Block.exe。");
            }
            process.WaitForExit();
            return process.ExitCode;
        }
    }

    private static string JoinArguments(string[] args)
    {
        if (args == null || args.Length == 0)
        {
            return string.Empty;
        }
        var builder = new StringBuilder();
        for (int i = 0; i < args.Length; i++)
        {
            if (i > 0)
            {
                builder.Append(' ');
            }
            builder.Append(QuoteArgument(args[i]));
        }
        return builder.ToString();
    }

    /// <summary>按 CommandLineToArgvW 的规则为单个参数加引号。</summary>
    private static string QuoteArgument(string value)
    {
        if (value == null)
        {
            return string.Empty;
        }
        bool needsQuotes = value.Length == 0;
        foreach (char c in value)
        {
            if (c == ' ' || c == '\t' || c == '\n' || c == '\v' || c == '"')
            {
                needsQuotes = true;
                break;
            }
        }
        if (!needsQuotes)
        {
            return value;
        }

        var builder = new StringBuilder("\"");
        int backslashes = 0;
        foreach (char c in value)
        {
            if (c == '\\')
            {
                backslashes++;
                continue;
            }
            if (c == '"')
            {
                builder.Append('\\', backslashes * 2 + 1);
                builder.Append('"');
                backslashes = 0;
                continue;
            }
            if (backslashes > 0)
            {
                builder.Append('\\', backslashes);
                backslashes = 0;
            }
            builder.Append(c);
        }
        if (backslashes > 0)
        {
            builder.Append('\\', backslashes * 2);
        }
        builder.Append('"');
        return builder.ToString();
    }

    private static bool IsTruthy(string value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return false;
        }
        string normalized = value.Trim();
        return normalized == "1" ||
               string.Equals(normalized, "true", StringComparison.OrdinalIgnoreCase) ||
               string.Equals(normalized, "yes", StringComparison.OrdinalIgnoreCase) ||
               string.Equals(normalized, "on", StringComparison.OrdinalIgnoreCase);
    }
}
