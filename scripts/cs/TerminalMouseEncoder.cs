using XTerm;
using XTerm.Input;

namespace PieBlock;

/// <summary>
/// XTerm.NET 1.0.15 会把 SGR Drag 固定编码成按钮 3（无按钮移动）。
/// 在保留依赖版本的前提下，仅修正带按钮拖动的 SGR 序列。
/// </summary>
public static class TerminalMouseEncoder
{
    public static string Generate(Terminal terminal, MouseButton button, int x, int y,
        MouseEventType type, KeyModifiers modifiers)
    {
        if (type != MouseEventType.Drag || button == MouseButton.None ||
            terminal.MouseEncoding != MouseEncoding.SGR)
            return terminal.GenerateMouseEvent(button, x, y, type, modifiers);

        int buttonCode = button switch
        {
            MouseButton.Left => 0,
            MouseButton.Middle => 1,
            MouseButton.Right => 2,
            _ => 3
        };
        if ((modifiers & KeyModifiers.Shift) != 0) buttonCode += 4;
        if ((modifiers & KeyModifiers.Alt) != 0) buttonCode += 8;
        if ((modifiers & KeyModifiers.Control) != 0) buttonCode += 16;
        buttonCode += 32;
        return $"\x1b[<{buttonCode};{x + 1};{y + 1}M";
    }
}
