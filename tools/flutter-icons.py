# Usage: python3 tools/flutter-icons.py app   (needs Pillow)
# Renders the --recall icon (public/icons/icon.svg) for each platform.
import json, os, sys
from PIL import Image, ImageDraw
root = sys.argv[1]
BG = (0xF6, 0xF5, 0xF2, 255); DASH = (0x2B, 0x54, 0xC9, 255)
SS = 4

def draw(size, *, inset=0.0, radius=0.0, dashes=((112,232,128,48,12),(272,232,128,48,12)), alpha=True):
    S = size*SS
    im = Image.new('RGBA', (S,S), (0,0,0,0) if alpha else BG)
    d = ImageDraw.Draw(im)
    off = inset*S; box = S-2*off; k = box/512
    d.rounded_rectangle([off,off,off+box-1,off+box-1], radius=radius*k, fill=BG)
    for x,y,w,h,r in dashes:
        d.rounded_rectangle([off+x*k, off+y*k, off+(x+w)*k-1, off+(y+h)*k-1], radius=r*k, fill=DASH)
    im = im.resize((size,size), Image.LANCZOS)
    return im if alpha else im.convert('RGB')

# iOS: full-bleed opaque square; the system applies its own mask.
ios = f'{root}/ios/Runner/Assets.xcassets/AppIcon.appiconset'
for img in json.load(open(f'{ios}/Contents.json'))['images']:
    pt = float(img['size'].split('x')[0]); sc = int(img['scale'][0])
    draw(round(pt*sc), alpha=False).save(f"{ios}/{img['filename']}")

# macOS: rounded square inset on a transparent canvas (Apple's grid: 824 of 1024).
mac = f'{root}/macos/Runner/Assets.xcassets/AppIcon.appiconset'
for n in (16,32,64,128,256,512,1024):
    draw(n, inset=100/1024, radius=112).save(f'{mac}/app_icon_{n}.png')

# Android legacy launcher icons (pre-API 26); adaptive icons are XML.
res = f'{root}/android/app/src/main/res'
for dpi,n in (('mdpi',48),('hdpi',72),('xhdpi',96),('xxhdpi',144),('xxxhdpi',192)):
    draw(n, inset=4/48, radius=112).save(f'{res}/mipmap-{dpi}/ic_launcher.png')
print('ok')
