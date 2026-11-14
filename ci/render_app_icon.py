"""Render the 1024x1024 AppIcon.png for FoodLog (食刻): an Apple Fitness/Health inspired macro ring + bowl & leaf emblem."""
from __future__ import annotations

import math
import struct
import zlib
from pathlib import Path


def chunk(tag: bytes, data: bytes) -> bytes:
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)


def encode_png(width: int, height: int, rows: list[bytes]) -> bytes:
    raw = bytearray()
    for row in rows:
        raw.append(0)
        raw.extend(row)
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b"")


def render_icon(size: int = 1024) -> list[bytes]:
    cx = size * 0.5
    cy = size * 0.5
    outer_r = size * 0.34
    inner_r = size * 0.245
    ring_mid = (outer_r + inner_r) * 0.5
    ring_half = (outer_r - inner_r) * 0.5

    rows: list[bytes] = []
    for y in range(size):
        row = bytearray(size * 3)
        ny = y / (size - 1)
        for x in range(size):
            nx = x / (size - 1)
            # Rich dark emerald-slate background gradient
            r = int(12 + 10 * (1.0 - ny) + 6 * nx)
            g = int(24 + 22 * (1.0 - ny))
            b = int(28 + 18 * ny)

            dx = x - cx
            dy = y - cy
            dist = math.hypot(dx, dy)

            # Soft ambient glow behind the ring
            if dist < size * 0.43:
                glow = max(0.0, 1.0 - dist / (size * 0.43))
                r = min(255, int(r + 18 * glow))
                g = min(255, int(g + 56 * glow))
                b = min(255, int(b + 38 * glow))

            # Macro nutrition ring (emerald -> warm amber arc)
            if abs(dist - ring_mid) <= ring_half:
                angle = (math.atan2(dy, dx) + math.pi) / (2.0 * math.pi)
                if angle < 0.68:
                    t = angle / 0.68
                    r = int(38 * (1.0 - t) + 52 * t)
                    g = int(208 * (1.0 - t) + 232 * t)
                    b = int(124 * (1.0 - t) + 168 * t)
                else:
                    t = (angle - 0.68) / 0.32
                    r = int(255 * (1.0 - t) + 246 * t)
                    g = int(179 * (1.0 - t) + 114 * t)
                    b = int(56 * (1.0 - t) + 66 * t)

            # Center warm ivory bowl silhouette in lower half of inner circle
            if dist < inner_r * 0.72 and dy > inner_r * 0.04:
                r, g, b = 244, 248, 245

            # Fresh green leaf above the bowl
            leaf_dx = (x - (cx + size * 0.02)) / (size * 0.085)
            leaf_dy = (y - (cy - size * 0.055)) / (size * 0.055)
            rx = leaf_dx * 0.82 - leaf_dy * 0.57
            ry = leaf_dx * 0.57 + leaf_dy * 0.82
            if rx * rx + (ry * 1.35) ** 2 <= 1.0:
                r, g, b = 58, 224, 138

            idx = x * 3
            row[idx] = r
            row[idx + 1] = g
            row[idx + 2] = b
        rows.append(bytes(row))
    return rows


def main() -> None:
    destination = Path(__file__).resolve().parents[1] / "FoodLog" / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon.png"
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_bytes(encode_png(1024, 1024, render_icon(1024)))
    print(f"Wrote {destination} ({destination.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
