using System;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using Godot;
using Porta.Pty;
using XTerm;
using XTerm.Options;

namespace PieBlock;

/// <summary>
/// 一个终端会话：ConPTY 子进程（Porta.Pty）+ VT 引擎（XTerm.NET）+ 后台读取线程。
/// 读取线程把子进程输出字节解码后喂给 Terminal 引擎，然后置脏标记；
/// 渲染线程（Godot 主线程）通过 WithTerminal 加锁读取屏幕缓冲。
/// </summary>
public sealed class TerminalSession : IDisposable
{
    private readonly object _lock = new object();
    private readonly IPtyConnection _pty;
    private readonly Terminal _term;
    private readonly Thread _reader;
    private volatile bool _running = true;
    private readonly Action _onUpdate;

    public Terminal Terminal => _term;
    public IPtyConnection Pty => _pty;
    public int ProcessId => _pty.Pid;

    /// <summary>诊断：累计读取的字节数（跨线程可见性用 Interlocked 保证）。</summary>
    public long BytesReceived;

    public TerminalSession(PtyOptions options, Action onUpdate)
    {
        _term = new Terminal(new TerminalOptions
        {
            Cols = options.Cols,
            Rows = options.Rows,
            Scrollback = 5000,
            TermName = "xterm-256color"
        });
        // 子进程发来的终端能力查询（DA/DSR/DECRQM）由引擎应答，转发回 PTY
        _term.DataReceived += (_, e) => WriteRaw(e.Data);
        // 在后台线程 spawn，避免 Godot 主线程 SynchronizationContext 与
        // SpawnAsync 内部 await 死锁（headless 实测会挂起）
        _pty = Task.Run(() => PtyProvider.SpawnAsync(options, CancellationToken.None))
            .GetAwaiter().GetResult();
        GD.Print($"[TerminalSession] spawned pid={_pty.Pid} host={_pty.GetType().Name}");
        Console.WriteLine($"[TerminalSession] spawned pid={_pty.Pid} host={_pty.GetType().Name}");
        _onUpdate = onUpdate;
        _reader = new Thread(ReadLoop) { IsBackground = true, Name = "TerminalReader" };
        _reader.Start();
    }

    private void ReadLoop()
    {
        var buf = new byte[16384];
        Console.WriteLine("[TerminalSession] reader thread started");
        try
        {
            while (_running)
            {
                int n = _pty.ReaderStream.Read(buf, 0, buf.Length);
                if (n <= 0)
                    break;
                BytesReceived += n;
                string text = Encoding.UTF8.GetString(buf, 0, n);
                lock (_lock)
                {
                    _term.Write(text);
                }
                _onUpdate?.Invoke();
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[TerminalSession] reader exception: {ex.Message}");
        }
        finally
        {
            _running = false;
            Console.WriteLine("[TerminalSession] reader thread ended");
        }
    }

    private void WriteRaw(string data)
    {
        byte[] bytes = Encoding.UTF8.GetBytes(data);
        _pty.WriterStream.Write(bytes, 0, bytes.Length);
        _pty.WriterStream.Flush();
    }

    public void Write(string text)
    {
        byte[] bytes = Encoding.UTF8.GetBytes(text);
        _pty.WriterStream.Write(bytes, 0, bytes.Length);
        _pty.WriterStream.Flush();
    }

    /// <summary>在主线程加锁执行对引擎的只读访问（渲染）。</summary>
    public void WithTerminal(Action<Terminal> action)
    {
        lock (_lock)
        {
            action(_term);
        }
    }

    public void Resize(int cols, int rows)
    {
        lock (_lock)
        {
            _term.Resize(cols, rows);
        }
        _pty.Resize(cols, rows);
    }

    public void Dispose()
    {
        _running = false;
        try { _pty?.Dispose(); } catch { }
    }
}