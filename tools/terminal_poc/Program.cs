using System;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using Porta.Pty;
using XTerm;
using XTerm.Options;

// 独立验证：ConPTY (Porta.Pty) -> XTerm.NET 引擎 -> 屏幕缓冲。
// 不依赖 Godot，快速验证核心管道。交互式 shell 测试输出与输入。

class Program
{
    static async Task<int> Main(string[] args)
    {
        Console.OutputEncoding = Encoding.UTF8;
        Console.WriteLine("=== Terminal POC ===");

        var options = new PtyOptions
        {
            App = "cmd.exe",
            CommandLine = Array.Empty<string>(),
            Cwd = Environment.CurrentDirectory,
            Cols = 80,
            Rows = 24,
            Environment = new System.Collections.Generic.Dictionary<string, string>
            {
                { "TERM", "xterm-256color" }
            }
        };

        var term = new Terminal(new TerminalOptions
        {
            Cols = 80,
            Rows = 24,
            Scrollback = 5000,
            TermName = "xterm-256color"
        });

        Console.WriteLine("Spawning ConPTY...");
        using var pty = await PtyProvider.SpawnAsync(options, CancellationToken.None);
        Console.WriteLine($"Spawned pid={pty.Pid}");

        // 读取线程：输出 -> 引擎
        var t = Task.Run(() =>
        {
            var buf = new byte[16384];
            while (true)
            {
                int n = pty.ReaderStream.Read(buf, 0, buf.Length);
                if (n <= 0) break;
                string text = Encoding.UTF8.GetString(buf, 0, n);
                term.Write(text);
            }
        });

        await Task.Delay(1500);

        // 测试输出：发送命令并检查回显
        Console.WriteLine("=== 测试输出 ===");
        await Send(pty, "echo HELLO_FROM_TERMINAL\r");
        await Task.Delay(1000);
        var lines = term.GetVisibleLines();
        foreach (var l in lines)
            Console.WriteLine("|" + l + "|");
        bool outOk = AnyLine(lines, "HELLO_FROM_TERMINAL");

        // 测试输入：再发一条命令
        Console.WriteLine("=== 测试输入 ===");
        await Send(pty, "echo INPUT_WORKS\r");
        await Task.Delay(1000);
        var lines2 = term.GetVisibleLines();
        bool inputOk = AnyLine(lines2, "INPUT_WORKS");

        // 测试 ANSI 颜色：引擎应解析 31m 红色
        Console.WriteLine("=== 测试 ANSI 颜色 ===");
        await Send(pty, "echo " + "\x1b[31mRED\x1b[0m OK\r");
        await Task.Delay(1000);
        var lines3 = term.GetVisibleLines();
        bool colorOk = AnyLine(lines3, "RED");

        Console.WriteLine($"\n结果: 输出={outOk} 输入={inputOk} 颜色={colorOk}");
        pty.Kill();
        return (outOk && inputOk && colorOk) ? 0 : 1;
    }

    static async Task Send(IPtyConnection pty, string text)
    {
        byte[] bytes = Encoding.UTF8.GetBytes(text);
        await pty.WriterStream.WriteAsync(bytes, 0, bytes.Length);
        await pty.WriterStream.FlushAsync();
    }

    static bool AnyLine(string[] lines, string needle)
    {
        foreach (var l in lines)
            if (l.Contains(needle)) return true;
        return false;
    }
}