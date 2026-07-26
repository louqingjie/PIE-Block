ttyd 1.7.7 (win32) — https://github.com/tsl0922/ttyd
MIT License, Copyright (c) 2016 Shuanglei Tao

用途：把终端通过 WebSocket 暴露成网页（前端 xterm.js），
供 Godot 侧的 WRY WebView 加载，从而在程序内嵌入真实终端跑 AI Agent 的 TUI。

为什么需要它：Godot 没有 PTY 能力，无法自行渲染 TUI（alternate screen /
光标定位 / 真彩 ANSI）。ttyd 把 PTY 和终端模拟都放在浏览器侧，
我们只提供网页容器，绕开了这个限制。

Windows 上通过 ConPTY 工作，要求 Win10 1809 或更高版本。
