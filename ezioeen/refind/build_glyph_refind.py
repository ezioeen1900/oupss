#!/usr/bin/env python3
"""Generate native 2560x1600 Nothing OS / Glyph rEFInd bootloader theme."""
import math
import os
import shutil
from PIL import Image, ImageDraw, ImageFilter, ImageFont

OUT = "/tmp/glyph-refind-stage"
ICONS = os.path.join(OUT, "icons")
if os.path.exists(OUT):
    shutil.rmtree(OUT)
os.makedirs(ICONS, exist_ok=True)

FONT_MONO = "/home/ezioeen/.local/share/glyph/config/fonts/SpaceMono-Regular.ttf"
SS = 4

# 11x11 dot-matrix grids
ICON_CACHY = [
    "00011111000",
    "00111111100",
    "01110000110",
    "11100000000",
    "11000110000",
    "11001111000",
    "11000110000",
    "11100000000",
    "01110000110",
    "00111111100",
    "00011111000",
]

ICON_WIN = [
    "11111011111",
    "11111011111",
    "11111011111",
    "11111011111",
    "11111011111",
    "00000000000",
    "11111011111",
    "11111011111",
    "11111011111",
    "11111011111",
    "11111011111",
]

ICON_GENERIC = [
    "00011111000",
    "01100000110",
    "10000000001",
    "10001110001",
    "10011011001",
    "10010101001",
    "10011011001",
    "10001110001",
    "10000000001",
    "01100000110",
    "00011111000",
]

# 1. Native 2560x1600 banner.png (matches Plymouth bg.png dot grid pitch ~41px)
W, H = 2560, 1600
banner = Image.new("RGB", (W, H), (0, 0, 0))
bd = ImageDraw.Draw(banner)
step = round(28 * (1600 / 1080))  # 41px — exact match with scaled Plymouth bg.png!
ox = round(20 * (1600 / 1080))
for x in range(ox, W, step):
    for y in range(ox, H, step):
        bd.rectangle((x, y, x + 1, y + 1), fill=(14, 14, 14))

# Top header & subtle decorative arc (supersampled overlay)
ov = Image.new("RGBA", (W, H), (0, 0, 0, 0))
od = ImageDraw.Draw(ov)
fnt_hdr = ImageFont.truetype(FONT_MONO, 20)
od.ellipse((74, 58, 86, 70), fill=(215, 25, 33, 255))
od.text((102, 51), "GLYPH · REFIND BOOTLOADER", font=fnt_hdr, fill=(140, 140, 140, 215))
txt_r = "UEFI · 2560x1600"
tw = od.textbbox((0, 0), txt_r, font=fnt_hdr)[2]
od.text((W - 74 - tw, 51), txt_r, font=fnt_hdr, fill=(80, 80, 80, 200))

# Subtle dial tick arc above OS row
arc_cy = int(H * 0.50 + 420)
for i in range(-20, 21):
    ang = -math.pi / 2 + i * 0.032
    r1 = 590
    r2 = 606 if i % 4 == 0 else 599
    col = (255, 255, 255, 34 if i % 4 == 0 else 18)
    od.line(
        (W / 2 + math.cos(ang) * r1, arc_cy + math.sin(ang) * r1,
         W / 2 + math.cos(ang) * r2, arc_cy + math.sin(ang) * r2),
        fill=col, width=2
    )
banner = Image.alpha_composite(banner.convert("RGBA"), ov).convert("RGB")
banner.save(os.path.join(OUT, "banner.png"))

# 2. selection_big.png (216x216) & selection_small.png (96x96)
def make_selection(size, ring_r, red_r, stroke_w):
    big = Image.new("RGBA", (size * SS, size * SS), (0, 0, 0, 0))
    c = (size * SS) / 2
    # Red glow at 12 o'clock
    ry = c - ring_r * SS
    gd = ImageDraw.Draw(big)
    gr = red_r * 2.2 * SS
    gd.ellipse((c - gr, ry - gr, c + gr, ry + gr), fill=(215, 25, 33, 185))
    big = big.filter(ImageFilter.GaussianBlur(3.2 * SS))

    d = ImageDraw.Draw(big)
    # Dark inner disc
    ir = (ring_r - 12) * SS
    d.ellipse((c - ir, c - ir, c + ir, c + ir), fill=(20, 20, 20, 235))
    # Crisp white outer ring
    rr = ring_r * SS
    d.ellipse((c - rr, c - rr, c + rr, c + rr), outline=(242, 242, 242, 235), width=int(stroke_w * SS))
    # Crisp Nothing Red 12 o'clock dot
    dr = red_r * SS
    d.ellipse((c - dr, ry - dr, c + dr, ry + dr), fill=(215, 25, 33, 255))
    return big.resize((size, size), Image.Resampling.LANCZOS)

make_selection(216, 98, 6.8, 2.4).save(os.path.join(OUT, "selection_big.png"))
make_selection(96, 42, 4.2, 2.0).save(os.path.join(OUT, "selection_small.png"))

# 3. OS Icons (192x192): subtle dotted outer ring + crisp dot-matrix glyph
def make_os_icon(grid):
    S = 192
    big = Image.new("RGBA", (S * SS, S * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(big)
    c = (S * SS) / 2
    # Subtle 32-dot outer ring (visible when unselected; sits neatly inside selection_big when selected)
    R_dots = 78 * SS
    for i in range(32):
        ang = (i / 32.0) * math.pi * 2
        dx = c + math.cos(ang) * R_dots
        dy = c + math.sin(ang) * R_dots
        r = 1.6 * SS
        d.ellipse((dx - r, dy - r, dx + r, dy + r), fill=(255, 255, 255, 48))

    # 11x11 dot-matrix center icon
    rows, cols = len(grid), len(grid[0])
    pitch = 7.4 * SS
    dot_r = 2.65 * SS
    x0 = c - ((cols - 1) * pitch) / 2
    y0 = c - ((rows - 1) * pitch) / 2
    for r_i in range(rows):
        for c_i in range(cols):
            if grid[r_i][c_i] == "1":
                px = x0 + c_i * pitch
                py = y0 + r_i * pitch
                d.ellipse((px - dot_r, py - dot_r, px + dot_r, py + dot_r), fill=(242, 242, 242, 245))
    return big.resize((S, S), Image.Resampling.LANCZOS)

img_cachy = make_os_icon(ICON_CACHY)
img_win = make_os_icon(ICON_WIN)
img_gen = make_os_icon(ICON_GENERIC)

for n in ["os_cachyos.png", "os_arch.png", "os_linux.png", "boot_linux.png", "os_endeavouros.png", "os_manjaro.png", "os_systemd.png"]:
    img_cachy.save(os.path.join(ICONS, n))
for n in ["os_win.png", "os_win8.png", "os_win10.png", "os_win11.png", "boot_win.png"]:
    img_win.save(os.path.join(ICONS, n))
for n in [
    "os_artful.png", "os_bionic.png", "os_centos.png", "os_chakra.png", "os_chrome.png",
    "os_clover.png", "os_crunchbang.png", "os_debian.png", "os_devuan.png", "os_elementary.png",
    "os_fedora.png", "os_freebsd.png", "os_frugalware.png", "os_gentoo.png", "os_gummiboot.png",
    "os_haiku.png", "os_hwtest.png", "os_kubuntu.png", "os_legacy.png", "os_linuxmint.png",
    "os_lubuntu.png", "os_mac.png", "os_mageia.png", "os_mandriva.png", "os_netbsd.png",
    "os_network.png", "os_opensuse.png", "os_redhat.png", "os_refind.png", "os_refit.png",
    "os_slackware.png", "os_suse.png", "os_trusty.png", "os_ubuntu.png", "os_uefi.png",
    "os_unknown.png", "os_void.png", "os_xenial.png", "os_xubuntu.png", "os_zesty.png"
]:
    img_gen.save(os.path.join(ICONS, n))

# 4. Small Tool / Function Icons (72x72)
def make_tool_icon(kind):
    S = 72
    big = Image.new("RGBA", (S * SS, S * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(big)
    c = (S * SS) / 2
    # Subtle outer circle
    ro = 28 * SS
    d.ellipse((c - ro, c - ro, c + ro, c + ro), outline=(255, 255, 255, 45), width=int(1.4 * SS))
    col = (225, 225, 225, 235)
    w = int(2.2 * SS)
    if kind == "power":
        r = 10.5 * SS
        d.arc((c - r, c - r + 1.5 * SS, c + r, c + r + 1.5 * SS), start=-55, end=235, fill=col, width=w)
        d.line((c, c - 12 * SS, c, c - 1 * SS), fill=(215, 25, 33, 255), width=w)
    elif kind == "reboot":
        r = 10.5 * SS
        d.arc((c - r, c - r, c + r, c + r), start=-30, end=260, fill=col, width=w)
        # Arrow head
        ax = c + math.cos(math.radians(-30)) * r
        ay = c + math.sin(math.radians(-30)) * r
        d.polygon([(ax, ay - 4 * SS), (ax + 4.5 * SS, ay + 2.5 * SS), (ax - 3.5 * SS, ay + 2.5 * SS)], fill=col)
    elif kind == "uefi":
        r = 8.5 * SS
        d.rectangle((c - r, c - r, c + r, c + r), outline=col, width=w)
        for off in (-5, 0, 5):
            p = off * SS
            d.line((c + p, c - r - 3.5 * SS, c + p, c - r), fill=col, width=int(1.6 * SS))
            d.line((c + p, c + r, c + p, c + r + 3.5 * SS), fill=col, width=int(1.6 * SS))
    elif kind == "shell":
        d.line((c - 8 * SS, c - 5 * SS, c - 1 * SS, c, c - 8 * SS, c + 5 * SS), fill=col, width=w)
        d.line((c + 1 * SS, c + 5 * SS, c + 9 * SS, c + 5 * SS), fill=col, width=w)
    else:
        # Minimalist 4-dot diamond
        for dx, dy in [(0, -7), (7, 0), (0, 7), (-7, 0)]:
            rr = 2.4 * SS
            d.ellipse((c + dx * SS - rr, c + dy * SS - rr, c + dx * SS + rr, c + dy * SS + rr), fill=col)
    return big.resize((S, S), Image.Resampling.LANCZOS)

t_pow = make_tool_icon("power")
t_reb = make_tool_icon("reboot")
t_uefi = make_tool_icon("uefi")
t_sh = make_tool_icon("shell")
t_gen = make_tool_icon("other")

t_pow.save(os.path.join(ICONS, "func_shutdown.png"))
t_reb.save(os.path.join(ICONS, "func_reset.png"))
t_uefi.save(os.path.join(ICONS, "func_firmware.png"))
t_uefi.save(os.path.join(ICONS, "tool_fwupdate.png"))
t_sh.save(os.path.join(ICONS, "tool_shell.png"))
for n in [
    "func_about.png", "func_bootorder.png", "func_csr_rotate.png", "func_exit.png",
    "func_hidden.png", "func_install.png", "tool_apple_rescue.png", "tool_memtest.png",
    "tool_mok_tool.png", "tool_netboot.png", "tool_part.png", "tool_rescue.png",
    "tool_windows_rescue.png", "arrow_left.png", "arrow_right.png", "mouse.png"
]:
    t_gen.save(os.path.join(ICONS, n))

# Transparent 1x1 badges so drive stickers never clutter icons
empty = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
for n in ["transparent.png", "vol_efi.png", "vol_external.png", "vol_internal.png", "vol_net.png", "vol_optical.png"]:
    empty.save(os.path.join(ICONS, n))

# 5. font.png: 96 fixed-width cells (ASCII 32..126 + replacement glyph), BLACK (0,0,0,alpha) so rEFInd inverts to crisp white on dark banner!
CELL_W, CELL_H = 14, 30
font_img = Image.new("RGBA", (CELL_W * 96, CELL_H), (0, 0, 0, 0))
fd = ImageDraw.Draw(font_img)
fnt = ImageFont.truetype(FONT_MONO, 20)
for idx in range(96):
    ch = chr(32 + idx) if idx < 95 else "?"
    x0 = idx * CELL_W
    bbox = fd.textbbox((0, 0), ch, font=fnt)
    cw = bbox[2] - bbox[0]
    fd.text((x0 + (CELL_W - cw) / 2 - bbox[0], 3), ch, font=fnt, fill=(0, 0, 0, 255))
font_img.save(os.path.join(OUT, "font.png"))

# 6. theme.conf
with open(os.path.join(OUT, "theme.conf"), "w") as f:
    f.write("""# Nothing OS / Glyph rEFInd Theme (2560x1600 native)
hideui singleuser,hints,arrows,badges
icons_dir themes/glyph/icons
banner themes/glyph/banner.png
banner_scale fillscreen
big_icon_size 192
small_icon_size 72
selection_big themes/glyph/selection_big.png
selection_small themes/glyph/selection_small.png
font themes/glyph/font.png
""")

print("Generated Glyph rEFInd theme in", OUT, "with", len(os.listdir(ICONS)), "icons")
