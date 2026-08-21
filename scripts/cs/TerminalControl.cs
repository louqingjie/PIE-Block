using System;
using Godot;
using Porta.Pty;
using XTerm;
using XTerm.Buffer;
using XKey = XTerm.Input.Key;
using XMods = XTerm.Input.KeyModifiers;
using XMouseButton = XTerm.Input.MouseButton;
using XMouseEventType = XTerm.Input.MouseEventType;
using XMouseTrackingMode = XTerm.Input.MouseTrackingMode;
using XSelectionMode = XTerm.Selection.SelectionMode;

namespace PieBlock;

/// <summary>
/// Godot 原生终端控件：渲染 XTerm.NET 引擎的屏幕缓冲，转发键盘输入到 ConPTY。
///
/// 用法（GDScript）：
///   var term = load("res://scripts/cs/TerminalControl.cs").new()
///   add_child(term)
///   term.Command = "powershell.exe"
///   term.Arguments = ["-NoLogo"]
///   term.Start()
/// </summary>
[GlobalClass]
public partial class TerminalControl : Control
{
    // ---- 导出配置 ----
    [Export] public string Command { get; set; } = "powershell.exe";
    [Export] public string[] Arguments { get; set; } = Array.Empty<string>();
    [Export] public string WorkingDirectory { get; set; } = "";
    [Export] public int Columns { get; set; } = 80;
    [Export] public int Rows { get; set; } = 24;
    [Export] public int FontSize { get; set; } = 14;

    // ---- 状态 ----
    private TerminalSession _session;
    private Font _font;
    private float _cellW = 8f;
    private float _cellH = 16f;
    private volatile bool _dirty;
    private int _lastCols = -1;
    private int _lastRows = -1;
    private bool _selecting;
    private Vector2I _lastMouseCell = new Vector2I(-1, -1);
    private Vector2I _lastClickCell = new Vector2I(-1, -1);
    private ulong _lastClickTime;
    private int _clickCount;
    private string _imeText = "";
    private Vector2I _imeSelection = Vector2I.Zero;

    // 主题色
    private static readonly Color Bg = new Color(0.07f, 0.07f, 0.09f);
    private static readonly Color Fg = new Color(0.92f, 0.92f, 0.92f);

    public TerminalSession Session => _session;
    public bool IsRunning => _session != null;

    public override void _Ready()
    {
        FocusMode = FocusModeEnum.All;
        MouseFilter = MouseFilterEnum.Stop;
        _font = new SystemFont
        {
            FontNames = new string[]
            {
                "Cascadia Mono", "Microsoft YaHei UI", "Noto Sans Mono CJK SC",
                "Consolas", "Courier New", "DejaVu Sans Mono"
            }
        };
        _cellW = _font.GetStringSize("M", HorizontalAlignment.Left, -1, FontSize).X;
        _cellH = _font.GetHeight(FontSize);
        SetProcess(true);
    }

    public void Start()
    {
        if (_session != null)
            return;
        try
        {
            var options = new PtyOptions
            {
                App = Command,
                CommandLine = Arguments,
                Cwd = string.IsNullOrEmpty(WorkingDirectory) ? System.Environment.CurrentDirectory : WorkingDirectory,
                Cols = Columns,
                Rows = Rows,
                Environment = new System.Collections.Generic.Dictionary<string, string>
                {
                    { "TERM", "xterm-256color" }
                }
            };
            _session = new TerminalSession(options, () => _dirty = true);
            _lastCols = -1;
            _lastRows = -1;
            if (HasFocus())
            {
                SetImeActive(true);
                UpdateImePosition();
            }
            QueueRedraw();
        }
        catch (Exception ex)
        {
            GD.PrintErr("[TerminalControl] 启动失败: " + ex.Message);
            _session = null;
        }
    }

    public void Stop()
    {
        SetImeActive(false);
        ClearImeComposition();
        if (_session == null)
            return;
        _session.Dispose();
        _session = null;
        QueueRedraw();
    }

    public void Write(string text) => _session?.Write(text);

    public void WriteLine(string text) => _session?.Write(text + "\r");

    public string GetSelectedText()
    {
        return _session?.WithTerminal(t => t.Selection.GetSelectionText()) ?? "";
    }

    public void CopySelection()
    {
        string text = GetSelectedText();
        if (!string.IsNullOrEmpty(text))
            DisplayServer.ClipboardSet(text);
    }

    public void PasteClipboard()
    {
        if (_session == null || !DisplayServer.ClipboardHas())
            return;
        string text = DisplayServer.ClipboardGet();
        if (string.IsNullOrEmpty(text))
            return;
        text = text.Replace("\r\n", "\r").Replace("\n", "\r");
        bool bracketed = _session.WithTerminal(t => t.BracketedPasteMode);
        _session.Write(bracketed ? "\x1b[200~" + text + "\x1b[201~" : text);
    }

    public void SelectAll()
    {
        if (_session == null)
            return;
        _session.WithTerminal(t => t.Selection.SelectAll());
        MarkDirty();
    }

    public void ClearSelection()
    {
        if (_session == null)
            return;
        _session.WithTerminal(t => t.Selection.ClearSelection());
        _selecting = false;
        MarkDirty();
    }

    /// <summary>供 GDScript 读取当前可见行（方法对 GDScript 可见，属性需 [Export]）。</summary>
    public string[] GetVisibleLines()
    {
        if (_session == null)
            return Array.Empty<string>();
        string[] result = null;
        _session.WithTerminal(t => result = t.GetVisibleLines());
        return result ?? Array.Empty<string>();
    }

    public int GetProcessId()
    {
        return _session?.ProcessId ?? -1;
    }

    /// <summary>供测试/脚本采样像素：返回单个格子的宽高（像素）。</summary>
    public float GetCellWidth() => _cellW;

    public float GetCellHeight() => _cellH;

    public long GetBytesReceived()
    {
        return _session?.BytesReceived ?? 0;
    }

    /// <summary>诊断：返回引擎当前状态字符串。</summary>
    public string GetDiagnostics()
    {
        if (_session == null)
            return "no session";
        string info = null;
        _session.WithTerminal(t => info =
            $"rows={t.Rows} cols={t.Cols} bytes={_session.BytesReceived} " +
            $"lines={t.Buffer.Lines.Length} ydisp={t.Buffer.YDisp} ybase={t.Buffer.YBase} " +
            $"cursor=({t.Buffer.X},{t.Buffer.Y})");
        return info ?? "?";
    }

    /// <summary>诊断：统计可见屏幕的渲染内容（非空白 / 调色板色 / 真彩色 / 制表符单元格数）。</summary>
    public string GetRenderStats()
    {
        if (_session == null)
            return "no session";
        string result = null;
        _session.WithTerminal(t =>
        {
            var buffer = t.Buffer;
            int total = 0, nonBlank = 0, palette = 0, rgb = 0, box = 0;
            for (int r = 0; r < t.Rows; r++)
            {
                var line = buffer.Lines[buffer.YDisp + r];
                if (line == null)
                    continue;
                for (int c = 0; c < line.Length; c++)
                {
                    var cell = line[c];
                    total++;
                    if (cell.Width == 0)
                        continue;
                    string content = cell.Content;
                    if (!string.IsNullOrEmpty(content) && content[0] != ' ')
                        nonBlank++;
                    if (cell.Attributes.GetFgColorMode() > 0 || cell.Attributes.GetBgColorMode() > 0)
                        rgb++;
                    else if (cell.Attributes.GetFgColor() < 256 || cell.Attributes.GetBgColor() < 257)
                        palette++;
                    if (content.Length > 0)
                    {
                        char ch = content[0];
                        if (ch >= 0x2500 && ch <= 0x259F) // 制表符/块元素
                            box++;
                    }
                }
            }
            result = $"alt={t.IsAlternateBufferActive} rows={t.Rows} cols={t.Cols} " +
                     $"total={total} nonBlank={nonBlank} palette={palette} rgb={rgb} box={box}";
        });
        return result ?? "?";
    }

    /// <summary>诊断：dump 指定行的每格内容与前景色模式/值。</summary>
    public string DumpLine(int row)
    {
        if (_session == null)
            return "no session";
        string result = null;
        _session.WithTerminal(t =>
        {
            var line = t.Buffer.Lines[t.Buffer.YDisp + row];
            if (line == null)
            {
                result = "(null line)";
                return;
            }
            var sb = new System.Text.StringBuilder();
            for (int c = 0; c < line.Length && c < 40; c++)
            {
                var cell = line[c];
                if (cell.Width == 0)
                    continue;
                sb.Append($"[{c}:{cell.Content}|m{cell.Attributes.GetFgColorMode()}|c{cell.Attributes.GetFgColor()}]");
            }
            result = sb.ToString();
        });
        return result ?? "?";
    }

    public override void _Process(double delta)
    {
        if (_session == null)
            return;
        // 未布局（headless / 尺寸为 0）时跳过 resize，避免把引擎缩成 1x1
        if (Size.X < _cellW || Size.Y < _cellH)
            return;
        // 尺寸变化 -> 重算行列并通知 PTY（ConPTY resize 触发子进程 SIGWINCH 重排）
        int cols = Math.Max(1, (int)(Size.X / _cellW));
        int rows = Math.Max(1, (int)(Size.Y / _cellH));
        if (cols != _lastCols || rows != _lastRows)
        {
            _lastCols = cols;
            _lastRows = rows;
            _session.Resize(cols, rows);
        }
        if (HasFocus())
            UpdateImePosition();
        if (_dirty)
        {
            _dirty = false;
            QueueRedraw();
        }
    }

    public override void _Draw()
    {
        if (_session == null)
        {
            DrawRect(new Rect2(Vector2.Zero, Size), Bg);
            return;
        }
        _session.WithTerminal(term =>
        {
            DrawRect(new Rect2(Vector2.Zero, Size), Bg);
            var buffer = term.Buffer;
            int rows = Math.Min(term.Rows, (int)(Size.Y / _cellH));
            for (int r = 0; r < rows; r++)
            {
                var line = buffer.Lines[buffer.YDisp + r];
                if (line != null)
                    DrawLine(term, line, r);
            }
            DrawCursor(term);
            DrawImeComposition(term);
        });
    }

    private void DrawLine(Terminal term, BufferLine line, int row)
    {
        float y = row * _cellH;
        float ascent = _font.GetAscent(FontSize);
        int cols = Math.Min(line.Length, (int)(Size.X / _cellW));
        for (int c = 0; c < cols; c++)
        {
            BufferCell cell = line[c];
            if (cell.Width == 0)
                continue; // 宽字符的占位格
            var attr = cell.Attributes;
            Color bg = ToColor(attr.GetBgColorMode(), attr.GetBgColor(), Bg);
            Color fg = ToColor(attr.GetFgColorMode(), attr.GetFgColor(), Fg);
            if (attr.IsInverse())
                (fg, bg) = (bg, fg);
            if (attr.IsDim())
                fg = fg.Lerp(Bg, 0.5f);
            bool selected = term.Selection.IsCellSelected(c, row);
            if (selected)
            {
                bg = new Color(0.25f, 0.45f, 0.72f, 0.95f);
                fg = new Color(1f, 1f, 1f);
            }
            if (bg != Bg || selected)
                DrawRect(new Rect2(c * _cellW, y, _cellW * cell.Width, _cellH), bg);
            string glyph = cell.Content;
            float x = c * _cellW;
            DrawString(_font, new Vector2(x, y + ascent), glyph,
                HorizontalAlignment.Left, -1, FontSize, fg);
            if (attr.IsBold())
                DrawString(_font, new Vector2(x + 1f, y + ascent), glyph,
                    HorizontalAlignment.Left, -1, FontSize, fg);
            if (attr.IsUnderline())
                DrawRect(new Rect2(x, y + _cellH - 1.5f, _cellW * cell.Width, 1.5f), fg);
        }
    }

    private void DrawCursor(Terminal term)
    {
        if (!term.CursorVisible)
            return;
        var buffer = term.Buffer;
        int cr = buffer.Y + buffer.YBase - buffer.YDisp;
        int cc = buffer.X;
        if (cr < 0 || cr >= term.Rows)
            return;
        var rect = new Rect2(cc * _cellW, cr * _cellH, _cellW, _cellH);
        DrawRect(rect, new Color(1f, 1f, 1f, 0.35f));
    }

    private void DrawImeComposition(Terminal term)
    {
        if (string.IsNullOrEmpty(_imeText))
            return;
        var buffer = term.Buffer;
        int row = buffer.Y + buffer.YBase - buffer.YDisp;
        if (row < 0 || row >= term.Rows)
            return;
        float x = buffer.X * _cellW;
        float y = row * _cellH;
        float width = Math.Max(_cellW, _font.GetStringSize(
            _imeText, HorizontalAlignment.Left, -1, FontSize).X);
        DrawRect(new Rect2(x, y, width, _cellH), new Color(0.12f, 0.12f, 0.16f, 0.98f));
        DrawString(_font, new Vector2(x, y + _font.GetAscent(FontSize)), _imeText,
            HorizontalAlignment.Left, -1, FontSize, Fg);
        DrawRect(new Rect2(x, y + _cellH - 2f, width, 2f), new Color(0.45f, 0.7f, 1f));

        if (_imeSelection.Y > 0 && _imeSelection.X >= 0)
        {
            int start = CodepointIndexToUtf16(_imeText, _imeSelection.X);
            int end = CodepointIndexToUtf16(_imeText, _imeSelection.X + _imeSelection.Y);
            int length = Math.Max(0, end - start);
            float before = _font.GetStringSize(_imeText[..start],
                HorizontalAlignment.Left, -1, FontSize).X;
            float selected = _font.GetStringSize(_imeText.Substring(start, length),
                HorizontalAlignment.Left, -1, FontSize).X;
            DrawRect(new Rect2(x + before, y, Math.Max(1f, selected), _cellH),
                new Color(0.35f, 0.55f, 0.85f, 0.4f));
        }
    }

    private static int CodepointIndexToUtf16(string text, int codepointIndex)
    {
        int utf16 = 0;
        for (int i = 0; i < codepointIndex && utf16 < text.Length; i++)
            utf16 += char.IsSurrogatePair(text, utf16) ? 2 : 1;
        return Math.Min(utf16, text.Length);
    }

    /// <summary>
    /// XTerm.NET 颜色编码（见 AttributeData.SetFgColor）：
    ///   mode 0 = 256 色索引（0~255；256=默认前景，257=默认背景）
    ///   mode 1 = 真彩 RGB（0xRRGGBB）
    /// </summary>
    private static Color ToColor(int mode, int color, Color fallback)
    {
        switch (mode)
        {
            case 0: // 256 色索引
                if (color >= 256)
                    return fallback;
                return PaletteColor(color);
            case 1: // 真彩 RGB（0xRRGGBB）
                return new Color(
                    ((color >> 16) & 0xFF) / 255f,
                    ((color >> 8) & 0xFF) / 255f,
                    (color & 0xFF) / 255f);
            default:
                return fallback;
        }
    }

    private static readonly Color[] BasicPalette = new Color[]
    {
        new Color(0, 0, 0), new Color(0.8f, 0, 0), new Color(0, 0.8f, 0), new Color(0.8f, 0.8f, 0),
        new Color(0, 0, 0.8f), new Color(0.8f, 0, 0.8f), new Color(0, 0.8f, 0.8f), new Color(0.8f, 0.8f, 0.8f),
        new Color(0.5f, 0.5f, 0.5f), new Color(1, 0, 0), new Color(0, 1, 0), new Color(1, 1, 0),
        new Color(0, 0, 1), new Color(1, 0, 1), new Color(0, 1, 1), new Color(1, 1, 1)
    };

    private static Color PaletteColor(int idx)
    {
        if (idx < 16)
            return BasicPalette[idx];
        if (idx < 232)
        {
            int n = idx - 16;
            int r = n / 36;
            int g = (n / 6) % 6;
            int b = n % 6;
            float R = r == 0 ? 0 : (r * 40 + 55) / 255f;
            float G = g == 0 ? 0 : (g * 40 + 55) / 255f;
            float B = b == 0 ? 0 : (b * 40 + 55) / 255f;
            return new Color(R, G, B);
        }
        int gray = (idx - 232) * 10 + 8;
        float v = gray / 255f;
        return new Color(v, v, v);
    }

    public override void _GuiInput(InputEvent @event)
    {
        if (_session == null)
            return;
        if (@event is InputEventKey key && key.Pressed)
        {
            if (HandleClipboardShortcut(key))
            {
                AcceptEvent();
                return;
            }
            string input = EncodeKey(key);
            if (!string.IsNullOrEmpty(input))
                _session.Write(input);
            AcceptEvent();
            return;
        }
        if (@event is InputEventMouseButton mb)
        {
            HandleMouseButton(mb);
            AcceptEvent();
            return;
        }
        if (@event is InputEventMouseMotion motion)
        {
            HandleMouseMotion(motion);
            AcceptEvent();
        }
    }

    private bool HandleClipboardShortcut(InputEventKey e)
    {
        Godot.Key code = (Godot.Key)((uint)e.Keycode & (uint)KeyModifierMask.CodeMask);
        if (e.CtrlPressed && e.ShiftPressed && code == Godot.Key.C)
        {
            CopySelection();
            return true;
        }
        if (e.CtrlPressed && e.ShiftPressed && code == Godot.Key.V)
        {
            PasteClipboard();
            return true;
        }
        if (e.ShiftPressed && !e.CtrlPressed && code == Godot.Key.Insert)
        {
            PasteClipboard();
            return true;
        }
        return false;
    }

    private string EncodeKey(InputEventKey e)
    {
        XMods mods = ToXTermModifiers(e);
        Godot.Key code = (Godot.Key)((uint)e.Keycode & (uint)KeyModifierMask.CodeMask);

        XKey? k = ToXTermKey(code);
        if (k.HasValue)
            return _session.WithTerminal(t => t.GenerateKeyInput(k.Value, mods));

        if (e.Unicode > 0 && e.Unicode <= 0x10FFFF)
        {
            string unicode = char.ConvertFromUtf32((int)e.Unicode);
            // Unicode is already shifted/localized by Godot. Sending it directly avoids
            // truncating supplementary-plane code points and lets IME commits pass intact.
            if (!e.CtrlPressed && !e.AltPressed)
                return unicode;
            // AltGr is reported as Ctrl+Alt on some layouts. A non-ASCII printable value is
            // text input, not a terminal control chord.
            if (e.CtrlPressed && e.AltPressed && e.Unicode > 0x7F)
                return unicode;
            if (e.Unicode <= 0xFFFF)
                return _session.WithTerminal(t => t.GenerateCharInput((char)e.Unicode, mods));
            return e.AltPressed ? "\x1b" + unicode : unicode;
        }

        char ascii = KeycodeToAscii(code);
        if (ascii != '\0')
            return _session.WithTerminal(t => t.GenerateCharInput(ascii, mods));
        return null;
    }

    private static char KeycodeToAscii(Godot.Key key)
    {
        uint value = (uint)key;
        if (value >= (uint)Godot.Key.A && value <= (uint)Godot.Key.Z)
            return char.ToLowerInvariant((char)value);
        return value >= 0x20 && value <= 0x7E ? (char)value : '\0';
    }

    private static XMods ToXTermModifiers(InputEventWithModifiers e)
    {
        var mods = XMods.None;
        if (e.ShiftPressed) mods |= XMods.Shift;
        if (e.AltPressed) mods |= XMods.Alt;
        if (e.CtrlPressed) mods |= XMods.Control;
        return mods;
    }

    private void HandleMouseButton(InputEventMouseButton e)
    {
        if (e.Pressed)
            GrabFocus();
        Vector2I cell = PositionToCell(e.Position);
        bool tracking = IsMouseTrackingEnabled();
        bool local = e.ShiftPressed || !tracking || _selecting;

        if (e.ButtonIndex is Godot.MouseButton.WheelUp or Godot.MouseButton.WheelDown)
        {
            if (!e.Pressed)
                return;
            int repeats = Math.Max(1, (int)Math.Round(Math.Abs(e.Factor)));
            if (!local)
            {
                XMouseButton button = e.ButtonIndex == Godot.MouseButton.WheelUp
                    ? XMouseButton.WheelUp : XMouseButton.WheelDown;
                XMouseEventType type = e.ButtonIndex == Godot.MouseButton.WheelUp
                    ? XMouseEventType.WheelUp : XMouseEventType.WheelDown;
                for (int i = 0; i < repeats; i++)
                    SendMouse(button, cell, type, ToXTermModifiers(e));
            }
            else
            {
                int lines = (e.ButtonIndex == Godot.MouseButton.WheelUp ? -3 : 3) * repeats;
                _session.WithTerminal(t => t.ScrollLines(lines));
                MarkDirty();
            }
            return;
        }

        if (!local)
        {
            XMouseButton button = ToXTermMouseButton(e.ButtonIndex);
            if (button != XMouseButton.None)
                SendMouse(button, cell, e.Pressed ? XMouseEventType.Down : XMouseEventType.Up,
                    ToXTermModifiers(e));
            return;
        }

        if (e.ButtonIndex != Godot.MouseButton.Left)
            return;
        if (e.Pressed)
        {
            ulong now = Time.GetTicksMsec();
            if (cell == _lastClickCell && now - _lastClickTime <= 500)
                _clickCount = Math.Min(3, _clickCount + 1);
            else
                _clickCount = 1;
            if (e.DoubleClick)
                _clickCount = Math.Max(2, _clickCount);
            _lastClickCell = cell;
            _lastClickTime = now;
            XSelectionMode mode = _clickCount >= 3 ? XSelectionMode.Line
                : _clickCount == 2 ? XSelectionMode.Word : XSelectionMode.Normal;
            _session.WithTerminal(t => t.Selection.StartSelection(cell.X, cell.Y, mode));
            _selecting = true;
            MarkDirty();
        }
        else if (_selecting)
        {
            _session.WithTerminal(t => t.Selection.EndSelection());
            _selecting = false;
            MarkDirty();
        }
    }

    private void HandleMouseMotion(InputEventMouseMotion e)
    {
        Vector2I cell = PositionToCell(e.Position);
        if (cell == _lastMouseCell)
            return;
        _lastMouseCell = cell;
        if (_selecting)
        {
            _session.WithTerminal(t => t.Selection.UpdateSelection(cell.X, cell.Y));
            MarkDirty();
            return;
        }
        if (e.ShiftPressed || !IsMouseTrackingEnabled())
            return;
        XMouseButton button = ButtonMaskToXTerm(e.ButtonMask);
        XMouseEventType type = button == XMouseButton.None ? XMouseEventType.Move : XMouseEventType.Drag;
        SendMouse(button, cell, type, ToXTermModifiers(e));
    }

    private bool IsMouseTrackingEnabled()
    {
        return _session != null &&
            _session.WithTerminal(t => t.MouseTrackingMode != XMouseTrackingMode.None);
    }

    private void SendMouse(XMouseButton button, Vector2I cell, XMouseEventType type, XMods mods)
    {
        string sequence = _session.WithTerminal(t =>
            TerminalMouseEncoder.Generate(t, button, cell.X, cell.Y, type, mods));
        _session.Write(sequence);
    }

    private Vector2I PositionToCell(Vector2 position)
    {
        int maxCols = Math.Max(1, _lastCols > 0 ? _lastCols : Columns);
        int maxRows = Math.Max(1, _lastRows > 0 ? _lastRows : Rows);
        return new Vector2I(
            Math.Clamp((int)(position.X / _cellW), 0, maxCols - 1),
            Math.Clamp((int)(position.Y / _cellH), 0, maxRows - 1));
    }

    private static XMouseButton ToXTermMouseButton(Godot.MouseButton button)
    {
        return button switch
        {
            Godot.MouseButton.Left => XMouseButton.Left,
            Godot.MouseButton.Middle => XMouseButton.Middle,
            Godot.MouseButton.Right => XMouseButton.Right,
            _ => XMouseButton.None
        };
    }

    private static XMouseButton ButtonMaskToXTerm(MouseButtonMask mask)
    {
        if ((mask & MouseButtonMask.Left) != 0) return XMouseButton.Left;
        if ((mask & MouseButtonMask.Middle) != 0) return XMouseButton.Middle;
        if ((mask & MouseButtonMask.Right) != 0) return XMouseButton.Right;
        return XMouseButton.None;
    }

    public override void _Notification(int what)
    {
        if (what == NotificationFocusEnter)
        {
            SetImeActive(true);
            UpdateImePosition();
            SendFocusEvent(true);
        }
        else if (what == NotificationFocusExit)
        {
            SetImeActive(false);
            ClearImeComposition();
            SendFocusEvent(false);
        }
        else if (what == NotificationOsImeUpdate)
        {
            _imeText = DisplayServer.ImeGetText();
            _imeSelection = DisplayServer.ImeGetSelection();
            UpdateImePosition();
            MarkDirty();
        }
    }

    private void SetImeActive(bool active)
    {
        if (!SupportsIme() || GetWindow() == null)
            return;
        GetWindow().SetImeActive(active);
    }

    private void UpdateImePosition()
    {
        if (_session == null || GetWindow() == null || !SupportsIme())
            return;
        Vector2 local = _session.WithTerminal(t =>
        {
            int row = Math.Max(0, t.Buffer.Y + t.Buffer.YBase - t.Buffer.YDisp);
            return new Vector2(t.Buffer.X * _cellW, (row + 1) * _cellH);
        });
        Vector2 windowPosition = GetGlobalTransformWithCanvas() * local;
        GetWindow().SetImePosition(new Vector2I(
            (int)Math.Round(windowPosition.X), (int)Math.Round(windowPosition.Y)));
    }

    private static bool SupportsIme()
    {
        return DisplayServer.GetName() != "headless" &&
            DisplayServer.HasFeature(DisplayServer.Feature.Ime);
    }

    private void ClearImeComposition()
    {
        if (string.IsNullOrEmpty(_imeText) && _imeSelection == Vector2I.Zero)
            return;
        _imeText = "";
        _imeSelection = Vector2I.Zero;
        MarkDirty();
    }

    private void SendFocusEvent(bool focused)
    {
        if (_session == null)
            return;
        string sequence = _session.WithTerminal(t =>
            t.SendFocusEvents ? t.GenerateFocusEvent(focused) : "");
        _session.Write(sequence);
    }

    private void MarkDirty()
    {
        _dirty = true;
        QueueRedraw();
    }

    private static XKey? ToXTermKey(Godot.Key k)
    {
        switch (k)
        {
            case Godot.Key.Enter: return XKey.Enter;
            case Godot.Key.Tab: return XKey.Tab;
            case Godot.Key.Backspace: return XKey.Backspace;
            case Godot.Key.Escape: return XKey.Escape;
            case Godot.Key.Space: return XKey.Space;
            case Godot.Key.Up: return XKey.UpArrow;
            case Godot.Key.Down: return XKey.DownArrow;
            case Godot.Key.Right: return XKey.RightArrow;
            case Godot.Key.Left: return XKey.LeftArrow;
            case Godot.Key.Home: return XKey.Home;
            case Godot.Key.End: return XKey.End;
            case Godot.Key.Pageup: return XKey.PageUp;
            case Godot.Key.Pagedown: return XKey.PageDown;
            case Godot.Key.Insert: return XKey.Insert;
            case Godot.Key.Delete: return XKey.Delete;
            case Godot.Key.F1: return XKey.F1;
            case Godot.Key.F2: return XKey.F2;
            case Godot.Key.F3: return XKey.F3;
            case Godot.Key.F4: return XKey.F4;
            case Godot.Key.F5: return XKey.F5;
            case Godot.Key.F6: return XKey.F6;
            case Godot.Key.F7: return XKey.F7;
            case Godot.Key.F8: return XKey.F8;
            case Godot.Key.F9: return XKey.F9;
            case Godot.Key.F10: return XKey.F10;
            case Godot.Key.F11: return XKey.F11;
            case Godot.Key.F12: return XKey.F12;
            case Godot.Key.Kp0: return XKey.Keypad0;
            case Godot.Key.Kp1: return XKey.Keypad1;
            case Godot.Key.Kp2: return XKey.Keypad2;
            case Godot.Key.Kp3: return XKey.Keypad3;
            case Godot.Key.Kp4: return XKey.Keypad4;
            case Godot.Key.Kp5: return XKey.Keypad5;
            case Godot.Key.Kp6: return XKey.Keypad6;
            case Godot.Key.Kp7: return XKey.Keypad7;
            case Godot.Key.Kp8: return XKey.Keypad8;
            case Godot.Key.Kp9: return XKey.Keypad9;
            case Godot.Key.KpPeriod: return XKey.KeypadDecimal;
            case Godot.Key.KpDivide: return XKey.KeypadDivide;
            case Godot.Key.KpMultiply: return XKey.KeypadMultiply;
            case Godot.Key.KpSubtract: return XKey.KeypadSubtract;
            case Godot.Key.KpAdd: return XKey.KeypadAdd;
            case Godot.Key.KpEnter: return XKey.KeypadEnter;
            default: return null;
        }
    }

    public override void _ExitTree()
    {
        SetImeActive(false);
        Stop();
    }
}
