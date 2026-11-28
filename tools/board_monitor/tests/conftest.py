"""pytest 公共配置：把工具目录加入 sys.path，并强制 Qt 使用 offscreen。"""
from __future__ import annotations

import os
import sys
from pathlib import Path

TOOL_ROOT = Path(__file__).resolve().parents[1]
if str(TOOL_ROOT) not in sys.path:
    sys.path.insert(0, str(TOOL_ROOT))

# 必须在任何 PySide6 导入之前设置，否则 Windows 上会尝试连桌面显示。
os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_LOGGING_RULES", "qt.qpa.*=false")
