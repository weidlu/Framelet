#!/usr/bin/env python3
"""Ensure Xcode and direct-download builds use the same generated artwork."""
import json
from pathlib import Path
import struct
import sys

root = Path(__file__).resolve().parents[1] / "Resources"
catalog = root / "Assets.xcassets" / "AppIcon.appiconset"
failures = []
entries = json.loads((catalog / "Contents.json").read_text())["images"]
for entry in entries:
    name = entry["filename"]
    source = root / "AppIcon.iconset" / name
    target = catalog / name
    if not source.is_file() or not target.is_file():
        failures.append(f"缺少图标尺寸：{name}")
        continue
    content = target.read_bytes()
    if source.read_bytes() != content:
        failures.append(f"App Store 图标与新版源图不一致：{name}")
    size = int(entry["size"].split("x")[0]) * int(entry["scale"].removesuffix("x"))
    if content[:8] != b"\x89PNG\r\n\x1a\n" or len(content) < 24:
        failures.append(f"图标不是 PNG：{name}")
    elif struct.unpack(">II", content[16:24]) != (size, size):
        failures.append(f"图标尺寸错误：{name}")
if (root / "AppIcon.png").read_bytes() != (root / "AppIcon.iconset" / "icon_512x512@2x.png").read_bytes():
    failures.append("主图标与 1024px 图标不一致")
if failures:
    print("\n".join(failures), file=sys.stderr)
    sys.exit(1)
print(f"图标检查通过：App Store 与直接下载版的 {len(entries)} 个尺寸一致。")
