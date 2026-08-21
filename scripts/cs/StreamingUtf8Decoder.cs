using System;
using System.Text;

namespace PieBlock;

/// <summary>保留跨 PTY 读取块的 UTF-8 解码状态，避免多字节字符被拆坏。</summary>
public sealed class StreamingUtf8Decoder
{
    private readonly Decoder _decoder = Encoding.UTF8.GetDecoder();
    private char[] _chars = new char[4096];

    public string Decode(byte[] bytes, int count, bool flush = false)
    {
        if (count < 0 || count > bytes.Length)
            throw new ArgumentOutOfRangeException(nameof(count));
        if (_chars.Length < Math.Max(1, count))
            _chars = new char[count];
        int charCount = _decoder.GetChars(bytes, 0, count, _chars, 0, flush);
        return charCount == 0 ? "" : new string(_chars, 0, charCount);
    }
}
