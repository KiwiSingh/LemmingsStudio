#!/usr/bin/env python3
"""Generate Lemmings Studio's app icon as a full macOS .iconset (supersampled)."""
import math, os
from PIL import Image, ImageDraw, ImageFilter

SS = 2048
OUT = 1024

def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))

def gradient(size, top, bottom):
    img = Image.new("RGB", (size, size))
    px = img.load()
    for y in range(size):
        row = lerp(top, bottom, y / (size - 1))
        for x in range(size):
            px[x, y] = row
    return img

def radial(size, color, cx, cy, radius, strength):
    g = Image.new("L", (size, size), 0)
    px = g.load()
    for y in range(size):
        for x in range(size):
            d = math.hypot(x - cx, y - cy) / radius
            v = max(0.0, 1.0 - d)
            px[x, y] = int(255 * (v ** 2) * strength)
    glow = Image.new("RGB", (size, size), color)
    return glow, g

def squircle_mask(size, n=5.0):
    m = Image.new("L", (size, size), 0)
    px = m.load()
    c = (size - 1) / 2.0
    r = c
    for y in range(size):
        for x in range(size):
            v = (abs(x - c) / r) ** n + (abs(y - c) / r) ** n
            if v <= 1.0:
                px[x, y] = 255
            elif v <= 1.04:
                px[x, y] = int(255 * (1.04 - v) / 0.04)
    return m

S = SS
INDIGO = (0x46, 0x35, 0x7C)
TEAL   = (0x0E, 0x27, 0x3A)

bg = gradient(S, INDIGO, TEAL)
g1, a1 = radial(S, (0x72, 0x5B, 0xCC), S * 0.30, S * 0.28, S * 0.80, 0.55)
bg = Image.composite(g1, bg, a1)
g2, a2 = radial(S, (0x1C, 0x6E, 0x70), S * 0.80, S * 0.84, S * 0.62, 0.45)
bg = Image.composite(g2, bg, a2).convert("RGBA")

wave_mask = Image.new("L", (S, S), 0)
wd = ImageDraw.Draw(wave_mask)
midy = S * 0.52
pts = []
N = 500
for i in range(N + 1):
    t = i / N
    x = S * 0.12 + t * (S * 0.76)
    env = math.sin(math.pi * t) ** 0.7
    y = midy - (S * 0.205 * env) * math.sin(2 * math.pi * 2.3 * t + 0.4)
    pts.append((x, y))

# Build a clean thick stroke as a single offset polygon (no per-segment seams).
hw = S * 0.023
left, right = [], []
for i, (x, y) in enumerate(pts):
    x0, y0 = pts[max(0, i-1)]
    x1, y1 = pts[min(N, i+1)]
    tx, ty = x1 - x0, y1 - y0
    tl = math.hypot(tx, ty) or 1.0
    nx, ny = -ty / tl, tx / tl          # unit normal
    left.append((x + nx*hw, y + ny*hw))
    right.append((x - nx*hw, y - ny*hw))
wd.polygon(left + right[::-1], fill=255)
for end in (pts[0], pts[-1]):           # round caps
    wd.ellipse([end[0]-hw, end[1]-hw, end[0]+hw, end[1]+hw], fill=255)
wave_mask = wave_mask.filter(ImageFilter.GaussianBlur(S * 0.0015))   # tiny edge soften
stroke = int(hw * 2)

wave_grad = gradient(S, (0x77, 0xF2, 0xCC), (0x9E, 0xEA, 0x4E))
glow_a = wave_mask.filter(ImageFilter.GaussianBlur(S * 0.012))
glow_layer = Image.composite(Image.new("RGBA", (S, S), (0x77, 0xF2, 0xCC, 110)),
                             Image.new("RGBA", (S, S), (0, 0, 0, 0)), glow_a)
bg = Image.alpha_composite(bg, glow_layer)
bg.paste(wave_grad, (0, 0), wave_mask)

draw = ImageDraw.Draw(bg)
draw.line([(S*0.12, midy), (S*0.88, midy)], fill=(255, 255, 255, 46), width=int(S*0.004))

def rrect(box, rad, fill):
    draw.rounded_rectangle(box, radius=rad, fill=fill)

u = S * 0.052
lx = S * 0.215
ly = midy - 0.2 * u
rrect([lx-1.4*u, ly-0.2*u, lx+1.4*u, ly+2.0*u], rad=0.7*u, fill=(0xF4, 0xD9, 0xC0, 255))
rrect([lx-1.4*u, ly+0.95*u, lx+1.4*u, ly+2.0*u], rad=0.55*u, fill=(0x2E, 0x6C, 0xF0, 255))
rrect([lx-1.3*u, ly-1.15*u, lx+1.3*u, ly+0.1*u], rad=0.6*u, fill=(0x46, 0xC2, 0x4A, 255))
draw.ellipse([lx-1.55*u, ly-0.75*u, lx-0.35*u, ly+0.45*u], fill=(0x46, 0xC2, 0x4A, 255))
draw.ellipse([lx+0.35*u, ly-0.75*u, lx+1.55*u, ly+0.45*u], fill=(0x46, 0xC2, 0x4A, 255))
for ex in (-0.5, 0.5):
    draw.ellipse([lx+ex*u-0.16*u, ly+0.2*u, lx+ex*u+0.16*u, ly+0.55*u], fill=(0x22,0x22,0x2A,255))

sheen = Image.new("L", (S, S), 0)
ImageDraw.Draw(sheen).ellipse([-S*0.3, -S*0.8, S*1.3, S*0.40], fill=64)
sheen = sheen.filter(ImageFilter.GaussianBlur(S * 0.04))
gloss = Image.composite(Image.new("RGBA", (S, S), (255, 255, 255, 255)),
                        Image.new("RGBA", (S, S), (0, 0, 0, 0)), sheen)
bg = Image.alpha_composite(bg, gloss)
bg.putalpha(255)

mask = squircle_mask(S, n=5.0)
comp = Image.new("RGBA", (S, S), (0, 0, 0, 0))
comp.paste(bg, (0, 0), mask)
final = comp.resize((OUT, OUT), Image.LANCZOS)

os.makedirs("Icon/AppIcon.iconset", exist_ok=True)
final.save("Icon/icon_1024_preview.png")
for name, sz in [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]:
    final.resize((sz, sz), Image.LANCZOS).save(f"Icon/AppIcon.iconset/{name}")
print("Icon + iconset written.")
