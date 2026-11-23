"""Draws Hamal's project logo: a gold letter with a wax seal, flying to the right.

Run: python3 media/make_logo.py  ->  media/hamal-logo.png (1024 x 1024)
Drawn at 3x and scaled down so the edges come out smooth. Not shipped with the addon.
"""
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
SS = 3  # supersampling
W = SIZE * SS
HERE = os.path.dirname(os.path.abspath(__file__))


def s(v):
    return int(round(v * SS))


def box(x0, y0, x1, y1):
    return [s(x0), s(y0), s(x1), s(y1)]


def rgba(arr):
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")


def vertical_gradient(top, bottom, y0, y1):
    """Full-canvas image whose colour runs from top (at y0) to bottom (at y1)."""
    t = np.clip((np.arange(W)[:, None] - s(y0)) / max(1, s(y1) - s(y0)), 0, 1)
    arr = np.zeros((W, W, 4))
    for i in range(3):
        arr[..., i] = np.broadcast_to(top[i] + (bottom[i] - top[i]) * t, (W, W))
    arr[..., 3] = 255
    return rgba(arr)


def fill(layer, mask, image):
    layer.alpha_composite(Image.composite(image, Image.new("RGBA", (W, W), (0, 0, 0, 0)), mask))


def mask_of(draw_fn):
    m = Image.new("L", (W, W), 0)
    draw_fn(ImageDraw.Draw(m))
    return m


# Background: dark slate, lighter behind the letter, with a warm glow.
yy, xx = np.mgrid[0:W, 0:W].astype(np.float32)
d = np.sqrt((xx - s(590)) ** 2 + (yy - s(500)) ** 2) / (W * 0.78)
d = np.clip(d, 0, 1) ** 1.15
inner, outer = np.array([44, 49, 61]), np.array([11, 13, 17])
bg_arr = np.zeros((W, W, 4), np.float32)
for i in range(3):
    bg_arr[..., i] = inner[i] + (outer[i] - inner[i]) * d
bg_arr[..., 3] = 255
bg = rgba(bg_arr)
del yy, xx, d, bg_arr

glow = Image.new("RGBA", (W, W), (0, 0, 0, 0))
ImageDraw.Draw(glow).ellipse(box(250, 170, 930, 850), fill=(230, 184, 92, 70))
bg.alpha_composite(glow.filter(ImageFilter.GaussianBlur(s(110))))

# The letter, drawn level and then tilted.
layer = Image.new("RGBA", (W, W), (0, 0, 0, 0))
EX0, EY0, EX1, EY1 = 320, 320, 860, 690
CX = (EX0 + EX1) / 2
TIP = EY0 + (EY1 - EY0) * 0.56
GOLD_TOP, GOLD_BOTTOM = (247, 212, 124), (206, 150, 60)
INK = (92, 58, 20, 255)

# Speed lines behind the letter, fading out to the left.
for y, length, strength in ((EY0 + 80, 190, 1.0), (EY0 + 185, 240, 0.8), (EY0 + 290, 150, 0.6)):
    x1 = EX0 - 36
    x0 = x1 - length
    bar = mask_of(lambda dr: dr.rounded_rectangle(box(x0, y - 19, x1, y + 19), radius=s(19), fill=255))
    fade = np.clip((np.arange(W)[None, :] - s(x0)) / max(1, s(x1) - s(x0)), 0, 1) ** 1.4 * strength
    a = np.asarray(bar, np.float32) * np.broadcast_to(fade, (W, W))
    col = np.zeros((W, W, 4), np.float32)
    col[..., 0], col[..., 1], col[..., 2], col[..., 3] = 236, 190, 98, a
    layer.alpha_composite(rgba(col))

body = mask_of(lambda dr: dr.rounded_rectangle(box(EX0, EY0, EX1, EY1), radius=s(34), fill=255))
fill(layer, body, vertical_gradient(GOLD_TOP, GOLD_BOTTOM, EY0, EY1))

dr = ImageDraw.Draw(layer)
# Lower folds.
for corner in ((EX0 + 26, EY1 - 26), (EX1 - 26, EY1 - 26)):
    dr.line([s(corner[0]), s(corner[1]), s(CX), s(TIP + 20)], fill=(170, 116, 42, 210), width=s(9))

# Flap.
flap_pts = [(s(EX0 + 10), s(EY0 + 10)), (s(CX), s(TIP)), (s(EX1 - 10), s(EY0 + 10))]
flap = mask_of(lambda m: m.polygon(flap_pts, fill=255))
fill(layer, flap, vertical_gradient((253, 230, 165), (234, 182, 88), EY0, TIP))
dr.line(flap_pts, fill=INK, width=s(14), joint="curve")
dr.rounded_rectangle(box(EX0, EY0, EX1, EY1), radius=s(34), outline=INK, width=s(14))

# Wax seal with an H.
SR = 104
dr.ellipse(box(CX - SR, TIP - SR, CX + SR, TIP + SR), fill=(84, 20, 15, 255))
dr.ellipse(box(CX - SR + 10, TIP - SR + 10, CX + SR - 10, TIP + SR - 10), fill=(156, 44, 33, 255))
hl = Image.new("RGBA", (W, W), (0, 0, 0, 0))
ImageDraw.Draw(hl).ellipse(box(CX - 62, TIP - 78, CX + 26, TIP - 20), fill=(214, 92, 74, 120))
layer.alpha_composite(hl.filter(ImageFilter.GaussianBlur(s(14))))
dr.ellipse(box(CX - 77, TIP - 77, CX + 77, TIP + 77), outline=(196, 78, 62, 255), width=s(6))


def letter_h(ox, oy, colour):
    dr.rectangle(box(CX - 48 + ox, TIP - 54 + oy, CX - 19 + ox, TIP + 54 + oy), fill=colour)
    dr.rectangle(box(CX + 19 + ox, TIP - 54 + oy, CX + 48 + ox, TIP + 54 + oy), fill=colour)
    dr.rectangle(box(CX - 19 + ox, TIP - 12 + oy, CX + 19 + ox, TIP + 12 + oy), fill=colour)


letter_h(3, 4, (70, 14, 10, 255))
letter_h(0, 0, (243, 207, 120, 255))

layer = layer.rotate(9, resample=Image.BICUBIC, center=(s(CX), s((EY0 + EY1) / 2)))

# Soft shadow under the letter.
alpha = layer.getchannel("A").point(lambda v: v * 0.55)
shadow = Image.new("RGBA", (W, W), (0, 0, 0, 255))
shadow.putalpha(alpha)
shadow = shadow.filter(ImageFilter.GaussianBlur(s(22)))
bg.alpha_composite(shadow, (0, s(24)))
bg.alpha_composite(layer)

out = bg.convert("RGB").resize((SIZE, SIZE), Image.LANCZOS)
out.save(os.path.join(HERE, "hamal-logo.png"), optimize=True)
print("wrote", os.path.join(HERE, "hamal-logo.png"))
