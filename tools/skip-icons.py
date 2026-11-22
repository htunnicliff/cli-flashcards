# Usage: python3 tools/skip-icons.py   (needs Pillow)
# Renders the --recall icon (public/icons/icon.svg) for the Skip app in apple/.
import json, os
from PIL import Image, ImageDraw

ROOT = os.path.join(os.path.dirname(__file__), '..', 'apple')
BG = (0xF6, 0xF5, 0xF2, 255); DASH = (0x2B, 0x54, 0xC9, 255)
DASHES = ((112, 232, 128, 48, 12), (272, 232, 128, 48, 12))
SS = 4

def draw(size, *, inset=0.0, radius=0.0, background=True, dashes=True, alpha=True, color=DASH):
    S = size * SS
    im = Image.new('RGBA', (S, S), (0, 0, 0, 0) if alpha else BG)
    d = ImageDraw.Draw(im)
    off = inset * S; box = S - 2 * off; k = box / 512
    if background:
        d.rounded_rectangle([off, off, off + box - 1, off + box - 1], radius=radius * k, fill=BG)
    if dashes:
        for x, y, w, h, r in DASHES:
            d.rounded_rectangle([off + x * k, off + y * k, off + (x + w) * k - 1, off + (y + h) * k - 1], radius=r * k, fill=color)
    im = im.resize((size, size), Image.LANCZOS)
    return im if alpha else im.convert('RGB')

# iOS, iPadOS and macOS share one asset catalog.
icons = f'{ROOT}/Darwin/Assets.xcassets/AppIcon.appiconset'
contents = json.load(open(f'{icons}/Contents.json'))
images = [i for i in contents['images'] if i['idiom'] != 'mac']
for n in (16, 32, 128, 256, 512):
    for scale in (1, 2):
        images.append({'filename': f'AppIcon-mac-{n}@{scale}x.png', 'idiom': 'mac', 'scale': f'{scale}x', 'size': f'{n}x{n}'})
contents['images'] = images
json.dump(contents, open(f'{icons}/Contents.json', 'w'), indent=2)
for img in images:
    pt = float(img['size'].split('x')[0]); px = round(pt * int(img['scale'][0]))
    if img['idiom'] == 'mac':
        # Apple's macOS grid: a rounded square 824 of 1024, on a transparent canvas.
        draw(px, inset=100 / 1024, radius=112).save(f"{icons}/{img['filename']}")
    else:
        # Full-bleed and opaque; the system applies its own mask.
        draw(px, alpha=False).save(f"{icons}/{img['filename']}")

# Android adaptive icon layers (108dp canvas, 72dp safe zone) and a legacy icon.
res = f'{ROOT}/Android/app/src/main/res'
safe = 18 / 108
for dpi, n in (('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)):
    draw(n, inset=4 / 48, radius=112).save(f'{res}/mipmap-{dpi}/ic_launcher.png')
    draw(n, dashes=False).save(f'{res}/mipmap-{dpi}/ic_launcher_background.png')
    draw(n, inset=safe, background=False).save(f'{res}/mipmap-{dpi}/ic_launcher_foreground.png')
    draw(n, inset=safe, background=False, color=(255, 255, 255, 255)).save(f'{res}/mipmap-{dpi}/ic_launcher_monochrome.png')
print('ok')
