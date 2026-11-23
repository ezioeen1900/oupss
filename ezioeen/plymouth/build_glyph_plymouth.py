#!/usr/bin/env python3
"""Generate 1080p-normalized (auto-scaled to 2560x1600 by glyph.script) Nothing OS / Glyph Plymouth assets."""
import math
import os
from PIL import Image, ImageDraw, ImageFilter, ImageFont

OUT = "/tmp/glyph-plymouth-stage"
os.makedirs(OUT, exist_ok=True)

FONT_MONO = "/home/ezioeen/.local/share/glyph/config/fonts/SpaceMono-Regular.ttf"

# Crisp 5x7 Nothing Dot-Matrix bitmap glyphs for "WELCOME EZIOEEN"
BITMAP = {
    "W": ["10001", "10001", "10001", "10101", "10101", "11011", "10001"],
    "E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
    "L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
    "C": ["01110", "10001", "10000", "10000", "10000", "10001", "01110"],
    "O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
    "M": ["10001", "11011", "10101", "10101", "10001", "10001", "10001"],
    "Z": ["11111", "00001", "00010", "00100", "01000", "10000", "11111"],
    "I": ["111", "010", "010", "010", "010", "010", "111"],
    "N": ["10001", "11001", "10101", "10011", "10001", "10001", "10001"],
    " ": ["0000", "0000", "0000", "0000", "0000", "0000", "0000"],
}

SS = 4  # 4x supersampling for razor-sharp edges

def make_circle(size, radius, color, glow_radius=0, glow_color=None):
    big = Image.new("RGBA", (size * SS, size * SS), (0, 0, 0, 0))
    c = (size * SS) / 2
    if glow_radius > 0 and glow_color:
        gd = ImageDraw.Draw(big)
        gr = radius * SS
        gd.ellipse((c - gr, c - gr, c + gr, c + gr), fill=glow_color)
        big = big.filter(ImageFilter.GaussianBlur(glow_radius * SS))
    d = ImageDraw.Draw(big)
    r = radius * SS
    d.ellipse((c - r, c - r, c + r, c + r), fill=color)
    return big.resize((size, size), Image.Resampling.LANCZOS)

# 1. Background subtle dot-matrix tile (1920x1080 pure black + faint 28px dot grid)
bg = Image.new("RGBA", (1920, 1080), (0, 0, 0, 255))
bd = ImageDraw.Draw(bg)
for x in range(20, 1920, 28):
    for y in range(20, 1080, 28):
        bd.rectangle((x, y, x + 1, y + 1), fill=(255, 255, 255, 13))
bg.save(os.path.join(OUT, "bg.png"))

# 2. Outer 48-tick precision dial (280x280)
def make_dial(alpha_major, alpha_minor):
    S = 280
    big = Image.new("RGBA", (S * SS, S * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(big)
    c = (S * SS) / 2
    R_out = 124 * SS
    for i in range(48):
        ang = -math.pi / 2 + (i / 48.0) * math.pi * 2
        major = (i % 4 == 0)
        r_in = R_out - (10 if major else 6) * SS
        col = (242, 242, 242, alpha_major if major else alpha_minor)
        w = int((2.2 if major else 1.4) * SS)
        d.line(
            (c + math.cos(ang) * r_in, c + math.sin(ang) * r_in,
             c + math.cos(ang) * R_out, c + math.sin(ang) * R_out),
            fill=col, width=w
        )
    return big.resize((S, S), Image.Resampling.LANCZOS)

make_dial(28, 16).save(os.path.join(OUT, "dial_dim.png"))
make_dial(115, 68).save(os.path.join(OUT, "dial_lit.png"))

# 3. 16-dot Nothing ring dot (20x20) & Central Nothing Red core dot (64x64 with soft glow)
make_circle(20, 5.2, (242, 242, 242, 255)).save(os.path.join(OUT, "ring_dot.png"))
make_circle(64, 9.5, (215, 25, 33, 255), glow_radius=9.0, glow_color=(215, 25, 33, 200)).save(os.path.join(OUT, "core_red.png"))

# 4. Dot-Matrix Wordmark: "WELCOME EZIOEEN"
def make_wordmark(text, pitch=7.0, dot_r=2.35):
    chars = list(text)
    cols = sum(len(BITMAP[ch][0]) for ch in chars) + 2 * (len(chars) - 1)
    pad = 16
    W = int(math.ceil((cols - 1) * pitch + pad * 2))
    H = int(math.ceil(6 * pitch + pad * 2))
    big = Image.new("RGBA", (W * SS, H * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(big)
    x0 = pad * SS
    y0 = pad * SS
    for ch in chars:
        g = BITMAP[ch]
        for r, row in enumerate(g):
            for c_idx, bit in enumerate(row):
                if bit == "1":
                    cx = x0 + c_idx * pitch * SS
                    cy = y0 + r * pitch * SS
                    rr = dot_r * SS
                    d.ellipse((cx - rr, cy - rr, cx + rr, cy + rr), fill=(242, 242, 242, 255))
        x0 += (len(g[0]) + 2) * pitch * SS
    return big.resize((W, H), Image.Resampling.LANCZOS)

make_wordmark("WELCOME EZIOEEN", pitch=7.2, dot_r=2.45).save(os.path.join(OUT, "wordmark.png"))

# 5. Top-left subtle corner badge ("GLYPH · BOOT")
corner = Image.new("RGBA", (260 * SS, 48 * SS), (0, 0, 0, 0))
cd = ImageDraw.Draw(corner)
try:
    fnt = ImageFont.truetype(FONT_MONO, 13 * SS)
except Exception:
    fnt = ImageFont.load_default()
cd.ellipse((4 * SS, 14 * SS, 12 * SS, 22 * SS), fill=(215, 25, 33, 255))
cd.text((22 * SS, 9 * SS), "GLYPH · SYSTEM BOOT", font=fnt, fill=(140, 140, 140, 210))
corner.resize((260, 48), Image.Resampling.LANCZOS).save(os.path.join(OUT, "corner.png"))

# 6. 24-dot segmented progress bar dots (24x24)
make_circle(24, 3.6, (42, 42, 42, 255)).save(os.path.join(OUT, "prog_dim.png"))
make_circle(24, 3.8, (242, 242, 242, 255)).save(os.path.join(OUT, "prog_lit.png"))
make_circle(24, 4.8, (215, 25, 33, 255), glow_radius=4.5, glow_color=(215, 25, 33, 190)).save(os.path.join(OUT, "prog_red.png"))

# 7. Write glyph.plymouth & glyph.script
with open(os.path.join(OUT, "glyph.plymouth"), "w") as f:
    f.write("""[Plymouth Theme]
Name=glyph
Description=Nothing OS / Glyph precision dot-matrix boot splash (Welcome Ezioeen)
ModuleName=script

[script]
ImageDir=/usr/share/plymouth/themes/glyph
ScriptFile=/usr/share/plymouth/themes/glyph/glyph.script
""")

with open(os.path.join(OUT, "glyph.script"), "w") as f:
    f.write("""# glyph — Nothing OS / Glyph Plymouth boot splash (Welcome Ezioeen)

Window.SetBackgroundTopColor(0.0, 0.0, 0.0);
Window.SetBackgroundBottomColor(0.0, 0.0, 0.0);

W = Window.GetWidth();
H = Window.GetHeight();
OX = Window.GetX();
OY = Window.GetY();
s = H / 1080.0;
CX = OX + W / 2;
CY = OY + H * 0.45;
PI = 3.14159265;

fun load(name) {
    local.img = Image(name);
    if (global.s != 1)
        img = img.Scale(Math.Int(img.GetWidth() * global.s + 0.5), Math.Int(img.GetHeight() * global.s + 0.5));
    return img;
}

fun place_center(img, cx, cy, z) {
    local.sp = Sprite(img);
    sp.SetPosition(Math.Int(cx - img.GetWidth() / 2), Math.Int(cy - img.GetHeight() / 2), z);
    return sp;
}

# Background grid
bg_sp = Sprite(Image("bg.png").Scale(W, H));
bg_sp.SetPosition(OX, OY, -100);

# Top-left corner badge
corner_img = load("corner.png");
corner_sp = Sprite(corner_img);
corner_sp.SetPosition(Math.Int(OX + 52 * s), Math.Int(OY + 38 * s), 5);
corner_sp.SetOpacity(0.85);

# Outer 48-tick dial
dial_dim_sp = place_center(load("dial_dim.png"), CX, CY, 8);
dial_lit_sp = place_center(load("dial_lit.png"), CX, CY, 9);
dial_lit_sp.SetOpacity(0.0);

# 16-dot Nothing Glyph rotating ring
dot_img = load("ring_dot.png");
R_ring = 80.0 * s;
for (i = 0; i < 16; i++) {
    ang = -PI / 2.0 + (i / 16.0) * PI * 2.0;
    ring_ang[i] = ang;
    dx = CX + Math.Cos(ang) * R_ring;
    dy = CY + Math.Sin(ang) * R_ring;
    ring_sp[i] = place_center(dot_img, dx, dy, 12);
    ring_sp[i].SetOpacity(0.18);
}

# Central Nothing Red breathing core
core_sp = place_center(load("core_red.png"), CX, CY, 15);

# Wordmark: WELCOME EZIOEEN
wm_sp = place_center(load("wordmark.png"), CX, CY + 178 * s, 12);
wm_sp.SetOpacity(0.0);

# 24-dot segmented progress bar
p_dim = load("prog_dim.png");
p_lit = load("prog_lit.png");
p_red = load("prog_red.png");
BARS = 24;
SPAN = 340.0 * s;
BX0 = CX - SPAN / 2.0;
BY = CY + 234 * s;
for (i = 0; i < BARS; i++) {
    px = BX0 + (i / (BARS - 1.0)) * SPAN;
    prog_sp[i] = place_center(p_dim, px, BY, 12);
}

tick = 0.0;
boot_prog = 0.0;

fun progress_cb(duration, progress) {
    global.boot_prog = progress;
}
Plymouth.SetBootProgressFunction(progress_cb);

fun refresh_cb() {
    global.tick = global.tick + 0.02;
    t = global.tick;

    # Smooth fade-in of dial & wordmark
    fade = t * 1.4;
    if (fade > 1.0) fade = 1.0;
    dial_lit_sp.SetOpacity(fade);
    wm_sp.SetOpacity(fade);

    # Rotating 16-dot wave
    rot = t * 2.6;
    for (i = 0; i < 16; i++) {
        w = 0.5 + 0.5 * Math.Cos(ring_ang[i] - rot);
        w3 = w * w * w;
        op = 0.14 + 0.86 * w3;
        ring_sp[i].SetOpacity(op);
    }

    # Central red core pulse
    pulse = 0.72 + 0.28 * Math.Sin(t * 4.2);
    core_sp.SetOpacity(pulse);

    # Progress bar (combine Plymouth progress with smooth minimum ramp so fast boots look great)
    p = global.boot_prog;
    ramp = t / 3.2;
    if (ramp > 0.92) ramp = 0.92;
    if (p < ramp) p = ramp;
    if (p > 1.0) p = 1.0;

    lit_n = Math.Int(p * BARS + 0.5);
    for (i = 0; i < BARS; i++) {
        if (i == lit_n - 1 && lit_n < BARS)
            prog_sp[i].SetImage(p_red);
        else if (i < lit_n)
            prog_sp[i].SetImage(p_lit);
        else
            prog_sp[i].SetImage(p_dim);
    }
}
Plymouth.SetRefreshFunction(refresh_cb);
""")
print("Built Glyph Plymouth assets successfully in", OUT)
