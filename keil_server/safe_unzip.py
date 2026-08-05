# -*- coding: utf-8 -*-
"""安全解压模块。

防护两类攻击：
  - zip-slip：恶意条目用 `../` 或绝对路径写出解压目录，覆盖任意文件
  - zip bomb：解压后总量 / 单文件 / 文件数异常庞大，拖垮磁盘与内存

所有解压路径都被限定在 dest_dir 内，任何越界条目直接抛 UnzipError。
"""
from __future__ import annotations

import zipfile
from pathlib import Path


class UnzipError(Exception):
    """解压失败（路径穿越 / 超限 / 非法 zip 等）。"""


def safe_extract(
    zip_path: Path,
    dest_dir: Path,
    max_total_size: int,
    max_files: int,
    max_file_size: int,
) -> int:
    """把 zip 安全解压到 dest_dir，返回实际解压的文件数。

    参数：
      max_total_size  解压后所有文件累计字节数上限
      max_files       文件数上限
      max_file_size   单个文件字节数上限
    """
    dest_dir = dest_dir.resolve()
    dest_dir.mkdir(parents=True, exist_ok=True)

    total = 0
    count = 0
    with zipfile.ZipFile(zip_path) as zf:
        for info in zf.infolist():
            # 统一用正斜杠：Windows 打包工具常写反斜杠
            name = info.filename.replace("\\", "/")
            # 目录条目跳过
            if name.endswith("/") or name == "":
                continue
            # zip-slip 检查：规范化后必须仍位于 dest_dir 内
            target = (dest_dir / name).resolve()
            try:
                target.relative_to(dest_dir)
            except ValueError:
                raise UnzipError(f"zip 条目路径穿越被拒绝: {info.filename}")

            # zip bomb 检查
            size = info.file_size
            if size > max_file_size:
                raise UnzipError(
                    f"单文件超过上限 {max_file_size} 字节: {info.filename}"
                )
            total += size
            if total > max_total_size:
                raise UnzipError(
                    f"解压总量超过上限 {max_total_size} 字节（疑似 zip bomb）"
                )
            count += 1
            if count > max_files:
                raise UnzipError(f"文件数超过上限 {max_files}")

            # 逐块写出，避免一次性读入大文件
            target.parent.mkdir(parents=True, exist_ok=True)
            with zf.open(info) as src, open(target, "wb") as dst:
                while True:
                    chunk = src.read(1024 * 1024)
                    if not chunk:
                        break
                    dst.write(chunk)
    return count
