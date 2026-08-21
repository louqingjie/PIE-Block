using System;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using Porta.Pty;
using PieBlock;
using XTerm;
using XTerm.Input;
using XTerm.Options;
using XTerm.Selection;

// 独立验证：ConPTY (Porta.Pty) -> XTerm.NET 引擎 -> 屏幕缓冲。
// 不依赖 Godot，快速验证核心管道。交互式 shell 测试输出与输入。

class Program
{
    static int failures;

    static async Task<int> Main(string[] args)
    {
        Console.OutputEncoding = Encoding.UTF8;
        Console.WriteLine("=== Terminal POC ===");
        RunEngineInteractionTests();

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
            var decoder = new StreamingUtf8Decoder();
            while (true)
            {
                int n = pty.ReaderStream.Read(buf, 0, buf.Length);
                if (n <= 0) break;
                string text = decoder.Decode(buf, n);
                if (text.Length > 0)
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

        Check("ConPTY 输出", outOk);
        Check("ConPTY 输入", inputOk);
        Check("ANSI 颜色解析", colorOk);
        Console.WriteLine($"\n结果: failures={failures}");
        pty.Kill();
        return failures == 0 ? 0 : 1;
    }

    static void RunEngineInteractionTests()
    {
        Console.WriteLine("=== 引擎交互测试 ===");
        var term = new Terminal(new TerminalOptions
        {
            Cols = 20,
            Rows = 4,
            Scrollback = 20,
            TermName = "xterm-256color"
        });

        Check("Ctrl+C", term.GenerateCharInput('c', KeyModifiers.Control) == "\x03");
        Check("Ctrl+S", term.GenerateCharInput('s', KeyModifiers.Control) == "\x13");
        Check("Ctrl+Z", term.GenerateCharInput('z', KeyModifiers.Control) == "\x1a");
        Check("Ctrl+L", term.GenerateCharInput('l', KeyModifiers.Control) == "\x0c");
        Check("Ctrl+W", term.GenerateCharInput('w', KeyModifiers.Control) == "\x17");
        Check("Alt 字符", term.GenerateCharInput('x', KeyModifiers.Alt) == "\x1bx");
        Check("方向键", term.GenerateKeyInput(Key.UpArrow, KeyModifiers.None) == "\x1b[A");
        Check("按键重复编码稳定",
            term.GenerateCharInput('a', KeyModifiers.None) ==
            term.GenerateCharInput('a', KeyModifiers.None));

        term.Write("\x1b[?1002h\x1b[?1006h");
        Check("SGR 鼠标按下", TerminalMouseEncoder.Generate(term, MouseButton.Left, 2, 1,
            MouseEventType.Down, KeyModifiers.None) == "\x1b[<0;3;2M");
        Check("SGR 鼠标释放", TerminalMouseEncoder.Generate(term, MouseButton.Left, 2, 1,
            MouseEventType.Up, KeyModifiers.None) == "\x1b[<0;3;2m");
        Check("SGR 鼠标拖动", TerminalMouseEncoder.Generate(term, MouseButton.Left, 2, 1,
            MouseEventType.Drag, KeyModifiers.None) == "\x1b[<32;3;2M");
        Check("SGR 鼠标滚轮", TerminalMouseEncoder.Generate(term, MouseButton.WheelUp, 2, 1,
            MouseEventType.WheelUp, KeyModifiers.None) == "\x1b[<64;3;2M");

        var selectionTerm = new Terminal(new TerminalOptions { Cols = 20, Rows = 3 });
        selectionTerm.Write("alpha beta");
        selectionTerm.Selection.StartSelection(0, 0, SelectionMode.Normal);
        selectionTerm.Selection.UpdateSelection(4, 0);
        selectionTerm.Selection.EndSelection();
        Check("本地文本选择", selectionTerm.Selection.GetSelectionText() == "alpha");
        selectionTerm.Selection.StartSelection(7, 0, SelectionMode.Word);
        selectionTerm.Selection.EndSelection();
        Check("双击选词", selectionTerm.Selection.GetSelectionText() == "beta");
        selectionTerm.Selection.StartSelection(2, 0, SelectionMode.Line);
        selectionTerm.Selection.EndSelection();
        Check("三击选行", selectionTerm.Selection.GetSelectionText().StartsWith("alpha beta"));

        var scrollTerm = new Terminal(new TerminalOptions { Cols = 8, Rows = 2, Scrollback = 20 });
        scrollTerm.Write("1\r\n2\r\n3\r\n4");
        int bottom = scrollTerm.Buffer.YDisp;
        scrollTerm.ScrollLines(-3);
        Check("历史滚动三行", scrollTerm.Buffer.YDisp == Math.Max(0, bottom - 3));

        byte[] unicode = Encoding.UTF8.GetBytes("中文😀补充面");
        var decoder = new StreamingUtf8Decoder();
        var decoded = new StringBuilder();
        for (int i = 0; i < unicode.Length; i++)
            decoded.Append(decoder.Decode(new[] { unicode[i] }, 1));
        decoded.Append(decoder.Decode(Array.Empty<byte>(), 0, true));
        Check("跨读取块 UTF-8 与补充平面", decoded.ToString() == "中文😀补充面");
    }

    static void Check(string label, bool ok)
    {
        Console.WriteLine($"[{(ok ? "PASS" : "FAIL")}] {label}");
        if (!ok) failures++;
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
