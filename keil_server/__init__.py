# -*- coding: utf-8 -*-
"""云端 Keil C251 编译服务。

上传 Keil 工程 zip -> 服务端用安装的 Keil C251 原生编译 -> 返回 HEX + 日志。
本目录先在本机搭建（本机也装完整正版 Keil），之后可原样部署到云服务器。

模块：
    config.py          配置（Keil 路径、并发、超时、大小限制、任务 TTL）
    safe_unzip.py      安全解压（防 zip-slip / zip bomb）
    tools_ini.py       TOOLS.INI [C251] 段解析与修复
    keil_detect.py     Keil 安装探测与校验
    compiler.py        编译核心（uVision.com -r、日志解析、hex 定位）
    task_manager.py    任务状态机 + 并发 + TTL 清理
    server.py          FastAPI 入口（/health /compile /tasks/...）
    make_fixture.py    生成自包含工程 zip 夹具（测试/演示用）
"""

__version__ = "0.1.0"
