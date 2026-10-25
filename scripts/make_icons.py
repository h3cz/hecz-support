# Render the Hecz Support app icon set from the hecz.dev favicon mark.
import sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter
out = sys.argv[1]
S = 1024
def mark(size=S, bg=True):
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    r = int(S * 14 / 64)
    if bg:
        # plum gradient square, matching the dark universe of hecz.dev
        grad = Image.new("RGBA", (S, S))
        gd = ImageDraw.Draw(grad)
        for y in range(S):
            t = y / S
            c = (int(0x2A + (0x0F - 0x2A) * t), int(0x1B + (0x0F - 0x1B) * t), int(0x3D + (0x1A - 0x3D) * t), 255)
            gd.line([(0, y), (S, y)], fill=c)
        mask = Image.new("L", (S, S), 0)
        ImageDraw.Draw(mask).rounded_rectangle([0, 0, S - 1, S - 1], r, fill=255)
        im.paste(grad, (0, 0), mask)
        d.rounded_rectangle([32, 32, S - 33, S - 33], r - 24, outline=(0x8B, 0x7D, 0xA8, 46), width=10)
    f = ImageFont.truetype("/usr/share/fonts/ttf-dejavu/DejaVuSerif-BoldItalic.ttf", int(S * 0.74))
    d.text((int(S * 0.22), int(S * 0.80)), "h", font=f, fill=(0xFA, 0xF8, 0xF5, 255), anchor="ls")
    cx, cy, cr = int(S * 0.745), int(S * 0.72), int(S * 0.075)
    d.ellipse([cx - cr, cy - cr, cx + cr, cy + cr], fill=(0x8B, 0x7D, 0xA8, 255))
    return im.resize((size, size), Image.LANCZOS)

big = mark()
big.resize((512, 512), Image.LANCZOS).save(f"{out}/icon.png")
for s, n in [(32, "32x32.png"), (64, "64x64.png"), (128, "128x128.png"), (256, "128x128@2x.png")]:
    big.resize((s, s), Image.LANCZOS).save(f"{out}/{n}")
big.save(f"{out}/app_icon.ico", sizes=[(16,16),(20,20),(24,24),(32,32),(40,40),(48,48),(64,64),(128,128),(256,256)])
big.save(f"{out}/tray-icon.ico", sizes=[(16,16),(20,20),(24,24),(32,32),(48,48)])
big.resize((48, 48), Image.LANCZOS).save(f"{out}/preview-48.png")
big.resize((16, 16), Image.LANCZOS).resize((64, 64), Image.NEAREST).save(f"{out}/preview-16-zoom.png")

# In-app logo: graffiti wordmark, trimmed of its white backdrop edges.
g = Image.open(sys.argv[2]).convert("RGBA")
bbox = g.getbbox()
g = g.crop(bbox)
g.thumbnail((600, 400), Image.LANCZOS)
g.save(f"{out}/logo.png")
