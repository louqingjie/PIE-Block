# -*- coding: utf-8 -*-
"""keil_server 编译服务配置。

所有配置都可通过环境变量覆盖，方便云服务器部署时调整，无需改代码。
取值优先级：环境变量 > 默认值。
"""
from __future__ import annotations

import os
from pathlib import Path

# 服务根目录（本文件所在目录）
SERVICE_ROOT = Path(__file__).resolve().parent
# 项目根目录（keil_server 的上一级）
PROJECT_ROOT = SERVICE_ROOT.parent

# ------------------------------------------------------------------ 数据目录
# 任务存储根（上传 zip、解压目录、日志、元数据、部署的工具链副本都放这里）
DATA_DIR = Path(os.environ.get("KEIL_SERVER_DATA_DIR", str(SERVICE_ROOT / "data")))

# ------------------------------------------------------------------ 鉴权
# 管理员主 key（环境变量 KEIL_API_KEY）。永远有效，管理接口（增删用户 key）用它。
# 未设置时，开放模式判断会退化为"也没有任何用户 key"才开放。
API_KEY = os.environ.get("KEIL_API_KEY", "").strip()

# 普通用户 key 表：JSON 文件（默认 data/api_keys.json，可动态增删/吊销）
KEYS_FILE = Path(os.environ.get(
    "KEIL_API_KEYS_FILE", str(DATA_DIR / "api_keys.json"),
))

# 初始用户 key（环境变量 KEIL_API_KEYS，格式 user:key,user:key），
# 服务启动/读取时并入 key 表（文件里已有的不覆盖）。便于脚本/一键部署注入。
API_KEYS_CSV = os.environ.get("KEIL_API_KEYS", "").strip()

# 编译降权用户（KEIL_BUILD_USER / KEIL_BUILD_PASSWORD）。
# 服务本身可以 SYSTEM 运行，但编译子进程（uVision）用此低权限账户启动：
# 恶意工程即使打穿 uVision 也只拿到普通用户权限，无法触碰 SYSTEM 资源。
# 留空则退化为当前账户直接启动（降权不可用）。
BUILD_USER = os.environ.get("KEIL_BUILD_USER", "").strip()
BUILD_PASSWORD = os.environ.get("KEIL_BUILD_PASSWORD", "").strip()


# ------------------------------------------------------------------ Keil 安装
# 手动指定 Keil 根目录（完整正版安装位置），优先级最高。
# 未设置时按 KEIL_CANDIDATE_PATHS 自动探测。
KEIL_PATH = os.environ.get("KEIL_PATH", "").strip()

# 自动探测候选路径（按顺序）：
#   1. 常见完整版安装位置（C251 与 MDK 同装在 Keil_v5）
#   2. %LOCALAPPDATA%\Keil_v5 —— Keil「仅当前用户」安装的位置（本机即在此）
#   3. 项目内分发的精简工具链（开发/冒烟用，结构一致；会被部署副本后使用）
_keil_candidates: list[str] = [r"C:\Keil_v5"]
_local_appdata = os.environ.get("LOCALAPPDATA", "").strip()
if _local_appdata:
    _keil_candidates.append(str(Path(_local_appdata) / "Keil_v5"))
_keil_candidates += [
    r"C:\Keil",
    str(PROJECT_ROOT / "stc32g" / "toolchain" / "Keil_noarm"),
]
KEIL_CANDIDATE_PATHS: list[str] = _keil_candidates

# ------------------------------------------------------------------ 编译
# 最大并发编译数。Keil 共享 TOOLS.INI 且为 CPU 密集任务，默认 1 最稳。
# 云服务器核多时可实测调高。
MAX_CONCURRENT_BUILDS = int(os.environ.get("KEIL_MAX_CONCURRENT", "1"))
# 单次编译超时（秒）
BUILD_TIMEOUT = int(os.environ.get("KEIL_BUILD_TIMEOUT", "120"))

# ------------------------------------------------------------------ 上传与解压限制
# 上传 zip 大小上限（默认 50MB）
UPLOAD_MAX_SIZE = int(os.environ.get("KEIL_UPLOAD_MAX_SIZE", str(50 * 1024 * 1024)))
# 解压后总大小上限（防 zip bomb，默认 300MB）
EXTRACT_MAX_SIZE = int(os.environ.get("KEIL_EXTRACT_MAX_SIZE", str(300 * 1024 * 1024)))
# 解压最大文件数
EXTRACT_MAX_FILES = int(os.environ.get("KEIL_EXTRACT_MAX_FILES", "2000"))
# 单文件解压上限（默认 50MB）
EXTRACT_MAX_FILE_SIZE = int(os.environ.get("KEIL_EXTRACT_MAX_FILE_SIZE", str(50 * 1024 * 1024)))

# ------------------------------------------------------------------ 任务生命周期
# 已完成任务保留时长（秒，默认 1 小时），超时被清理
TASK_TTL = int(os.environ.get("KEIL_TASK_TTL", str(3600)))
