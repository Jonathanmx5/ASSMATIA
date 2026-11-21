"""Génère les visuels du README à partir des captures de l'app (docs/screenshots/raw)."""
import os
from PIL import Image, ImageDraw, ImageFilter, ImageFont

RAW = 'docs/screenshots/raw'
OUT = 'docs/screenshots'

def font(size, bold=True):
    for f in (['C:/Windows/Fonts/segoeuib.ttf'] if bold else ['C:/Windows/Fonts/segoeui.ttf']):
        if os.path.exists(f):
            return ImageFont.truetype(f, size)
    return ImageFont.load_default()

def phone(shot, width):
    """Capture dans un cadre de téléphone arrondi avec ombre."""
    im = Image.open(shot).convert('RGB')
    h = int(im.height * width / im.width)
    im = im.resize((width, h), Image.LANCZOS)
    b = int(width * .035); r = int(width * .11)
    W, H = width + 2 * b, h + 2 * b
    frame = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(frame)
    d.rounded_rectangle([0, 0, W - 1, H - 1], r + b, fill=(34, 30, 58, 255))
    mask = Image.new('L', (width, h), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, width - 1, h - 1], r, fill=255)
    frame.paste(im, (b, b), mask)
    pad = 60
    out = Image.new('RGBA', (W + 2 * pad, H + 2 * pad), (0, 0, 0, 0))
    sh = Image.new('RGBA', out.size, (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle([pad, pad + 24, pad + W, pad + H + 24], r + b, fill=(80, 50, 160, 90))
    out = Image.alpha_composite(out, sh.filter(ImageFilter.GaussianBlur(28)))
    out.alpha_composite(frame, (pad, pad))
    return out

def gradient(w, h, stops):
    g = Image.new('RGB', (w, h))
    px = g.load()
    for x in range(w):
        for y in range(h):
            t = (x / w * .6 + y / h * .4)
            for i in range(len(stops) - 1):
                a, b = stops[i], stops[i + 1]
                lo, hi = i / (len(stops) - 1), (i + 1) / (len(stops) - 1)
                if lo <= t <= hi:
                    k = (t - lo) / (hi - lo)
                    px[x, y] = tuple(int(a[j] + (b[j] - a[j]) * k) for j in range(3))
                    break
    return g

def bubbles(img, items):
    o = Image.new('RGBA', img.size, (0, 0, 0, 0)); d = ImageDraw.Draw(o)
    for x, y, r, c in items:
        d.ellipse([x - r, y - r, x + r, y + r], fill=c + (60,))
    return Image.alpha_composite(img.convert('RGBA'), o)

# ---- Bannière ----
W, H = 1800, 900
bg = gradient(W // 4, H // 4, [(143, 211, 254), (185, 166, 255), (255, 179, 199)]).resize((W, H), Image.BICUBIC)
bg = bubbles(bg, [(120, 120, 160, (255, 194, 75)), (1700, 140, 120, (93, 183, 240)), (1650, 820, 200, (255, 143, 184)), (80, 820, 130, (76, 201, 166))])
d = ImageDraw.Draw(bg)
logo = Image.open('assets/logo_a8.png').convert('RGBA').resize((150, 150), Image.LANCZOS)
d.ellipse([90, 240, 290, 440], fill=(255, 255, 255, 255))
bg.alpha_composite(logo, (115, 265))
d.text((90, 470), 'ASSMATIA', font=font(92), fill='white')
d.text((92, 600), "L'appli des", font=font(46), fill='white')
d.text((92, 655), 'assistantes maternelles', font=font(46), fill='white')
d.text((92, 735), 'Contrats · Planning · Paie', font=font(32, bold=False), fill='white')
d.text((92, 777), 'Fiscal · Partage parents', font=font(32, bold=False), fill='white')
for i, (name, x, y, w) in enumerate([('recaps', 1010, 90, 330), ('enfants', 760, 170, 300), ('planning', 1330, 170, 300)]):
    pass
shots = [('enfants', 760, 150, 290), ('recaps', 1035, 60, 330), ('planning', 1360, 150, 290)]
for name, x, y, w in [shots[0], shots[2], shots[1]]:
    bg.alpha_composite(phone(f'{RAW}/{name}.png', w), (x - 60, y - 60))
bg.convert('RGB').save(f'{OUT}/banner.png', optimize=True)

# ---- Vignettes individuelles ----
for n in os.listdir(RAW):
    p = phone(f'{RAW}/{n}', 360)
    p.save(f'{OUT}/{n}', optimize=True)
print('ok')
