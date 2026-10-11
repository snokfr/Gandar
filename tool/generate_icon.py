#!/usr/bin/env python3
"""Generates the Windows window/taskbar icon for Gandar.

The mark is the one the app already shows in its sidebar: a rounded square
filled with the accent gradient, holding a small equaliser glyph. Drawing it
here rather than shipping a binary blob means the icon can be re-tuned by
editing numbers, and stays in step with the theme.

Usage
-----
    python tool/generate_icon.py                 # draw the built-in mark
    python tool/generate_icon.py --png art.png   # convert your own square PNG
    python tool/generate_icon.py --preview       # also write a PNG/HTML proof

Only the standard library is used (no Pillow, no ImageMagick), so it runs on a
bare Python 3 install.

Sizes written: 16, 20, 24, 32, 40, 48, 64, 128, 256. Windows needs several:
the 16 is the title bar, the 32 the taskbar, the 256 the large Explorer view,
and it picks the closest match rather than scaling a single bitmap.
"""

from __future__ import annotations

import argparse
import base64
import struct
import sys
import zlib
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
DEFAULT_ICO = REPO / "windows" / "runner" / "resources" / "app_icon.ico"

# The default theme's accent pair (spotify_classic in theme_presets.dart) and
# the far-background colour, which is what the in-app glyph is drawn in.
ACCENT = (0x1D, 0xB9, 0x54)
ACCENT_ALT = (0x1E, 0xD7, 0x60)
GLYPH = (0x12, 0x12, 0x12)

SIZES = (16, 20, 24, 32, 40, 48, 64, 128, 256)

# Supersampling factor: each output pixel is averaged from SS x SS samples.
# Four is enough to keep the 16 px frame from looking chewed.
SS = 4


# ---------------------------------------------------------------------------
# Geometry
# ---------------------------------------------------------------------------


def _inside_rounded_rect(x: float, y: float, x0: float, y0: float, x1: float, y1: float, r: float) -> bool:
    """Point-in-rounded-rectangle test, used for the tile and each bar."""
    cx = min(max(x, x0 + r), x1 - r)
    cy = min(max(y, y0 + r), y1 - r)
    if x0 <= x <= x1 and y0 <= y <= y1:
        return (x - cx) ** 2 + (y - cy) ** 2 <= r * r
    return False


def _lerp(a: int, b: int, t: float) -> int:
    return int(round(a + (b - a) * t))


def _tile_colour(x: float, y: float, pad: float, side: float) -> tuple[int, int, int]:
    """Diagonal gradient across the rounded square, matching GandarLogo."""
    t = ((x - pad) / side + (y - pad) / side) / 2
    t = min(max(t, 0.0), 1.0)
    return tuple(_lerp(ACCENT[i], ACCENT_ALT[i], t) for i in range(3))  # type: ignore[return-value]


def _bars(size: int) -> list[tuple[float, float]]:
    """Relative (height, vertical centre) of each equaliser bar.

    Two bars at 16 px: three would leave sub-pixel gaps and read as a smudge.
    """
    if size <= 20:
        # Two wide bars: three would be sub-pixel and read as a smudge.
        return [(0.62, 0.58), (0.92, 0.44)]
    return [(0.52, 0.60), (0.80, 0.42), (0.62, 0.54)]


def render_mark(size: int) -> list[bytearray]:
    """Draws the icon mark at [size] px and returns RGBA scanlines."""
    # Small icons are given no breathing room; they are already tiny.
    pad = 0.0 if size <= 24 else round(size * 0.05)
    side = size - 2 * pad
    radius = side * 0.22

    glyph_box = side * (0.72 if size <= 20 else 0.60)
    glyph_left = pad + (side - glyph_box) / 2
    bar_w = glyph_box * (0.30 if size <= 20 else 0.19)
    gap = bar_w * (0.42 if size <= 20 else 0.48)
    rows = _bars(size)
    span = len(rows) * bar_w + (len(rows) - 1) * gap
    first_left = glyph_left + (glyph_box - span) / 2

    bars: list[tuple[float, float, float, float]] = []
    for index, (height, centre) in enumerate(rows):
        bar_h = glyph_box * height
        x0 = first_left + index * (bar_w + gap)
        y0 = pad + (side - bar_h) / 2 + (centre - 0.5) * glyph_box * 0.5
        bars.append((x0, y0, x0 + bar_w, y0 + bar_h))

    step = 1.0 / SS
    rows_out: list[bytearray] = []
    for py in range(size):
        row = bytearray()
        for px in range(size):
            r = g = b = a = 0.0
            for sy in range(SS):
                y = py + (sy + 0.5) * step
                for sx in range(SS):
                    x = px + (sx + 0.5) * step
                    if not _inside_rounded_rect(x, y, pad, pad, pad + side, pad + side, radius):
                        continue
                    colour = _tile_colour(x, y, pad, side)
                    for (bx0, by0, bx1, by1) in bars:
                        if _inside_rounded_rect(x, y, bx0, by0, bx1, by1, bar_w / 2):
                            colour = GLYPH
                            break
                    r += colour[0]
                    g += colour[1]
                    b += colour[2]
                    a += 255.0
            samples = SS * SS
            if a == 0:
                row += b"\x00\x00\x00\x00"
            else:
                # Straight (unpremultiplied) alpha: colour is the mean of the
                # covered samples only, so edges do not darken.
                covered = a / 255.0
                row += bytes(
                    (
                        int(round(r / covered)),
                        int(round(g / covered)),
                        int(round(b / covered)),
                        int(round(a / samples)),
                    )
                )
        rows_out.append(row)
    return rows_out


# ---------------------------------------------------------------------------
# PNG
# ---------------------------------------------------------------------------


# ---------------------------------------------------------------------------
# Discord art assets
# ---------------------------------------------------------------------------

# Discord shows Rich Presence art in two places: a large image (the app mark)
# and a small circular badge next to it. All three are square PNGs; the badge is
# drawn as a filled circle rather than a bare glyph because Discord crops small
# images to a circle, and a glyph floating on transparency gets its corners cut
# off by that crop.
DISCORD_SIZES = {
    "gandar": 512,
    "playing": 512,
    "paused": 512,
}


def _inside_circle(x: float, y: float, cx: float, cy: float, r: float) -> bool:
    return (x - cx) ** 2 + (y - cy) ** 2 <= r * r


def _inside_triangle(
    x: float,
    y: float,
    a: tuple[float, float],
    b: tuple[float, float],
    c: tuple[float, float],
) -> bool:
    def side(p, q) -> float:
        return (p[0] - x) * (q[1] - y) - (q[0] - x) * (p[1] - y)

    d1, d2, d3 = side(a, b), side(b, c), side(c, a)
    negative = d1 < 0 or d2 < 0 or d3 < 0
    positive = d1 > 0 or d2 > 0 or d3 > 0
    return not (negative and positive)


def render_badge(size: int, kind: str) -> list[bytearray]:
    """Draws a play or pause badge: the accent disc with the glyph cut into it."""
    centre = size / 2
    radius = size / 2 - 1
    glyph = GLYPH

    if kind == "playing":
        # A right-pointing triangle, optically centred: a triangle's visual
        # centre sits left of its bounding box, so it is nudged right slightly.
        height = size * 0.46
        width = size * 0.40
        left = centre - width / 2 - size * 0.01
        top = centre - height / 2
        # Named v0..v2, not a..c: those two names are already the pixel
        # accumulators below, and shadowing them turns the triangle into a
        # float.
        v0 = (left, top)
        v1 = (left + width, centre)
        v2 = (left, top + height)
    else:
        bar_w = size * 0.13
        bar_h = size * 0.46
        gap = size * 0.10
        top = centre - bar_h / 2
        left = centre - gap / 2 - bar_w
        right = centre + gap / 2

    step = 1.0 / SS
    rows_out: list[bytearray] = []
    for py in range(size):
        row = bytearray()
        for px in range(size):
            r = g = b = a = 0.0
            for sy in range(SS):
                y = py + (sy + 0.5) * step
                for sx in range(SS):
                    x = px + (sx + 0.5) * step
                    if not _inside_circle(x, y, centre, centre, radius):
                        continue
                    if kind == "playing":
                        ink = _inside_triangle(x, y, v0, v1, v2)
                    else:
                        ink = (
                            left <= x <= left + bar_w or right <= x <= right + bar_w
                        ) and top <= y <= top + bar_h
                    colour = glyph if ink else _tile_colour(
                        x, y, size * 0.08, size * 0.84
                    )
                    r += colour[0]
                    g += colour[1]
                    b += colour[2]
                    a += 255.0
            samples = SS * SS
            if a == 0:
                row += b"\x00\x00\x00\x00"
            else:
                covered = a / 255.0
                row += bytes(
                    (
                        int(round(r / covered)),
                        int(round(g / covered)),
                        int(round(b / covered)),
                        int(round(a / samples)),
                    )
                )
        rows_out.append(row)
    return rows_out


def write_discord_assets(directory: Path) -> list[tuple[str, Path]]:
    """Writes the three asset names the Discord application expects.

    The names are the contract: `lib/data/discord/discord_presence.dart`
    refers to `gandar`, `playing` and `paused`, and Discord matches them
    exactly. Uploading these files under those names is all that is left.
    """
    written: list[tuple[str, Path]] = []
    directory.mkdir(parents=True, exist_ok=True)
    for name, size in DISCORD_SIZES.items():
        rows = render_mark(size) if name == "gandar" else render_badge(size, name)
        path = directory / f"{name}.png"
        path.write_bytes(encode_png(size, size, rows))
        written.append((name, path))
    return written


def encode_png(width: int, height: int, rows: list[bytearray]) -> bytes:
    """Writes 8-bit RGBA, filter type 0 on every row."""
    raw = bytearray()
    for row in rows:
        raw.append(0)
        raw += row

    def chunk(tag: bytes, payload: bytes) -> bytes:
        return (
            struct.pack(">I", len(payload))
            + tag
            + payload
            + struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF)
        )

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + chunk(b"IEND", b"")
    )


def _paeth(a: int, b: int, c: int) -> int:
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    if pb <= pc:
        return b
    return c


def decode_png(data: bytes) -> tuple[int, int, list[bytearray]]:
    """Decodes the PNG subset a hand-made icon needs: 8-bit RGB or RGBA."""
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not a PNG file")
    pos = 8
    width = height = 0
    colour_type = 0
    compressed = bytearray()
    while pos + 8 <= len(data):
        length, tag = struct.unpack(">I4s", data[pos : pos + 8])
        payload = data[pos + 8 : pos + 8 + length]
        pos += 12 + length
        if tag == b"IHDR":
            width, height, depth, colour_type, comp, filt, interlace = struct.unpack(
                ">IIBBBBB", payload
            )
            if depth != 8 or colour_type not in (2, 6) or interlace != 0:
                raise ValueError(
                    "only 8-bit, non-interlaced RGB/RGBA PNGs are supported "
                    f"(got depth={depth}, colour_type={colour_type}, interlace={interlace})"
                )
        elif tag == b"IDAT":
            compressed += payload
        elif tag == b"IEND":
            break

    channels = 4 if colour_type == 6 else 3
    stride = width * channels
    raw = zlib.decompress(bytes(compressed))

    rows: list[bytearray] = []
    previous = bytearray(stride)
    offset = 0
    for _ in range(height):
        filter_type = raw[offset]
        offset += 1
        line = bytearray(raw[offset : offset + stride])
        offset += stride
        for i in range(stride):
            a = line[i - channels] if i >= channels else 0
            b = previous[i]
            c = previous[i - channels] if i >= channels else 0
            if filter_type == 1:
                line[i] = (line[i] + a) & 0xFF
            elif filter_type == 2:
                line[i] = (line[i] + b) & 0xFF
            elif filter_type == 3:
                line[i] = (line[i] + (a + b) // 2) & 0xFF
            elif filter_type == 4:
                line[i] = (line[i] + _paeth(a, b, c)) & 0xFF
            elif filter_type != 0:
                raise ValueError(f"unknown PNG filter {filter_type}")
        if channels == 3:
            expanded = bytearray()
            for x in range(width):
                expanded += line[x * 3 : x * 3 + 3]
                expanded.append(255)
            line = expanded
        rows.append(line)
        previous = line
    return width, height, rows


def resize_rgba(width: int, height: int, rows: list[bytearray], target: int) -> list[bytearray]:
    """Area-average resample, premultiplied so edges do not fringe."""
    scale = width / target
    out: list[bytearray] = []
    for ty in range(target):
        row = bytearray()
        y0, y1 = ty * scale, (ty + 1) * scale
        for tx in range(target):
            x0, x1 = tx * scale, (tx + 1) * scale
            sr = sg = sb = sa = weight = 0.0
            for sy in range(int(y0), min(int(y1) + 1, height)):
                wy = min(y1, sy + 1) - max(y0, sy)
                if wy <= 0:
                    continue
                line = rows[sy]
                for sx in range(int(x0), min(int(x1) + 1, width)):
                    wx = min(x1, sx + 1) - max(x0, sx)
                    if wx <= 0:
                        continue
                    w = wx * wy
                    i = sx * 4
                    alpha = line[i + 3] / 255.0
                    sr += line[i] * alpha * w
                    sg += line[i + 1] * alpha * w
                    sb += line[i + 2] * alpha * w
                    sa += line[i + 3] * w
                    weight += w
            if weight == 0 or sa == 0:
                row += b"\x00\x00\x00\x00"
                continue
            covered = sa / 255.0
            row += bytes(
                (
                    int(round(sr / covered)),
                    int(round(sg / covered)),
                    int(round(sb / covered)),
                    int(round(sa / weight)),
                )
            )
        out.append(row)
    return out


# ---------------------------------------------------------------------------
# ICO
# ---------------------------------------------------------------------------


def write_ico(path: Path, images: list[tuple[int, bytes]]) -> None:
    """Writes an ICO whose entries are PNG payloads (Vista and later)."""
    images = sorted(images)
    header = struct.pack("<HHH", 0, 1, len(images))
    offset = 6 + 16 * len(images)
    directory = bytearray()
    for size, payload in images:
        directory += struct.pack(
            "<BBBBHHII",
            size if size < 256 else 0,
            size if size < 256 else 0,
            0,
            0,
            1,
            32,
            len(payload),
            offset,
        )
        offset += len(payload)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("wb") as handle:
        handle.write(header)
        handle.write(directory)
        for _, payload in images:
            handle.write(payload)


PROOF_SHEET = """<!doctype html>
<meta charset="utf-8">
<title>Gandar icon proof sheet</title>
<style>
 body {{ margin:0; font:13px/1.5 system-ui, sans-serif; background:#202020; color:#e8e8e8 }}
 section {{ padding:14px 18px }}
 h2 {{ font-size:13px; font-weight:600; margin:0 0 10px; opacity:.7 }}
 .row {{ display:flex; align-items:flex-end; gap:14px; flex-wrap:wrap }}
 figure {{ margin:0; text-align:center }}
 figcaption {{ font-size:11px; opacity:.55; margin-top:4px }}
 img {{ display:block }}
 .light {{ background:#f4f4f4; color:#222 }}
 .bar {{ display:flex; align-items:center; gap:10px; width:max-content;
        background:#f3f3f3; color:#111; padding:6px 12px; border-radius:6px }}
 .title {{ display:flex; align-items:center; gap:8px; width:max-content;
          background:#2b2b2b; color:#ddd; padding:4px 10px; border-radius:6px 6px 0 0 }}
</style>
{body}
"""


def write_proof_sheet(path: Path, images: list[tuple[int, bytes]]) -> None:
    """A self-contained HTML proof sheet, so the icon can be eyeballed.

    Each PNG is embedded inline: the file can be opened from anywhere, with no
    sibling assets to lose.
    """
    by_size = dict(images)
    largest = max(by_size)
    biggest = f"data:image/png;base64,{base64.b64encode(by_size[largest]).decode()}"

    def img(size: int) -> str:
        return f"data:image/png;base64,{base64.b64encode(by_size[size]).decode()}"

    real = "".join(
        f'<figure><img src="{img(size)}" width="{size}" height="{size}">'
        f"<figcaption>{size}</figcaption></figure>"
        for size in sorted(by_size)
        if size <= 128
    )
    body = f"""
<section><h2>Each packaged size, drawn at its real pixel size</h2>
  <div class="row">{real}</div></section>
<section><h2>The {largest} px master, shown at 128</h2>
  <div class="row"><figure><img src="{biggest}" width="128" height="128">
  </figure><figure><img src="{biggest}" width="32" height="32">
  </figure><figure><img src="{biggest}" width="16" height="16"></figure></div></section>
<section class="light"><h2>On a light surface</h2>
  <div class="row"><figure><img src="{biggest}" width="96" height="96">
  </figure><figure><img src="{biggest}" width="16" height="16"></figure></div></section>
<section><h2>In context</h2>
  <div class="title"><img src="{biggest}" width="16" height="16"> Gandar</div>
  <div style="height:8px"></div>
  <div class="bar"><img src="{biggest}" width="24" height="24"> Gandar \u2014 Liked Songs</div>
</section>
"""
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(PROOF_SHEET.format(body=body), encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate Gandar's window icon")
    parser.add_argument(
        "--png",
        type=Path,
        help="use this square PNG as the artwork instead of the built-in mark",
    )
    parser.add_argument(
        "--out",
        type=Path,
        default=DEFAULT_ICO,
        help=f"where to write the .ico (default {DEFAULT_ICO})",
    )
    parser.add_argument(
        "--preview",
        type=Path,
        help="also write a PNG to this path, to eyeball the result",
    )
    parser.add_argument(
        "--proof",
        type=Path,
        help="also write a self-contained HTML proof sheet to this path",
    )
    parser.add_argument(
        "--discord-assets",
        type=Path,
        help="write gandar.png, playing.png and paused.png for Discord here",
    )
    args = parser.parse_args()

    if args.png:
        source = args.png.read_bytes()
        width, height, rows = decode_png(source)
        if width != height:
            print(
                f"warning: {args.png.name} is {width}x{height}; a square icon looks best",
                file=sys.stderr,
            )
        images = [
            (size, encode_png(size, size, resize_rgba(width, height, rows, size)))
            for size in SIZES
        ]
        print(f"Read {args.png} ({width}x{height})")
    else:
        images = []
        for size in SIZES:
            rendered = render_mark(size)
            images.append((size, encode_png(size, size, rendered)))
        print("Drew the built-in Gandar mark")

    write_ico(args.out, images)
    print(f"Wrote {args.out} ({args.out.stat().st_size} bytes): sizes {list(SIZES)}")

    if args.preview:
        size = SIZES[-1]
        args.preview.parent.mkdir(parents=True, exist_ok=True)
        args.preview.write_bytes(dict(images)[size])
        print(f"Wrote {args.preview} ({size}x{size})")

    if args.proof:
        write_proof_sheet(args.proof, images)
        print(f"Wrote {args.proof}")

    if args.discord_assets:
        for name, path in write_discord_assets(args.discord_assets):
            print(f"Wrote {path} ({DISCORD_SIZES[name]}x{DISCORD_SIZES[name]})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
