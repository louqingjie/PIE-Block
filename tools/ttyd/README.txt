ttyd 1.7.7 (win32) — https://github.com/tsl0922/ttyd
MIT License, Copyright (c) 2016 Shuanglei Tao

用途：把终端通过 WebSocket 暴露成网页（前端 xterm.js），
历史终端 POC 所用。当前 AI 编辑器已改用 XTerm.NET + ConPTY 原生渲染，不再加载此程序。

为什么需要它：Godot 没有 PTY 能力，无法自行渲染 TUI（alternate screen /
光标定位 / 真彩 ANSI）。ttyd 把 PTY 和终端模拟都放在浏览器侧，
我们只提供网页容器，绕开了这个限制。

Windows 上通过 ConPTY 工作，要求 Win10 1809 或更高版本。
