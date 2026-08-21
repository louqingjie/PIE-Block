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
    private readonly object _terminalLock = new object();
    private readonly object _writerLock = new object();
    private readonly IPtyConnection _pty;
    private readonly Terminal _term;
    private readonly Thread _reader;
    private volatile bool _running = true;
    private readonly Action _onUpdate;
    private long _bytesReceived;

    public IPtyConnection Pty => _pty;
    public int ProcessId => _pty.Pid;

    /// <summary>诊断：累计读取的字节数（跨线程可见性用 Interlocked 保证）。</summary>
    public long BytesReceived => Interlocked.Read(ref _bytesReceived);

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
        var decoder = new StreamingUtf8Decoder();
        Console.WriteLine("[TerminalSession] reader thread started");
        try
        {
            while (_running)
            {
                int n = _pty.ReaderStream.Read(buf, 0, buf.Length);
                if (n <= 0)
                    break;
                Interlocked.Add(ref _bytesReceived, n);
                string text = decoder.Decode(buf, n);
                if (text.Length == 0)
                    continue;
                lock (_terminalLock)
                {
                    _term.Write(text);
                }
                _onUpdate?.Invoke();
            }

            // Flush any incomplete sequence once EOF is reached. Invalid trailing bytes are
            // represented by the decoder fallback instead of being silently discarded.
            string remaining = decoder.Decode(Array.Empty<byte>(), 0, true);
            if (remaining.Length > 0)
            {
                lock (_terminalLock)
                {
                    _term.Write(remaining);
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
        WriteBytes(Encoding.UTF8.GetBytes(data));
    }

    public void Write(string text)
    {
        if (string.IsNullOrEmpty(text))
            return;
        WriteBytes(Encoding.UTF8.GetBytes(text));
    }

    private void WriteBytes(byte[] bytes)
    {
        lock (_writerLock)
        {
            if (!_running)
                return;
            _pty.WriterStream.Write(bytes, 0, bytes.Length);
            _pty.WriterStream.Flush();
        }
    }

    /// <summary>在主线程加锁执行对引擎的只读访问（渲染）。</summary>
    public void WithTerminal(Action<Terminal> action)
    {
        lock (_terminalLock)
        {
            action(_term);
        }
    }

    public T WithTerminal<T>(Func<Terminal, T> action)
    {
        lock (_terminalLock)
        {
            return action(_term);
        }
    }

    public void Resize(int cols, int rows)
    {
        lock (_terminalLock)
        {
            _term.Resize(cols, rows);
        }
        if (_running)
            _pty.Resize(cols, rows);
    }

    public void Dispose()
    {
        _running = false;
        lock (_writerLock)
        {
            try { _pty?.Dispose(); } catch { }
        }
        if (Thread.CurrentThread != _reader && _reader.IsAlive)
            _reader.Join(1000);
    }
}
