import sys
from PIL import Image, ImageDraw

src_path, out_path = sys.argv[1], sys.argv[2]

img = Image.open(src_path).convert("RGBA")
w, h = img.size

# Flood-fill from the four corners through near-white pixels only, turning
# them transparent. This leaves any white that is enclosed by the artwork
# (e.g. the white ring that is part of the logo itself) untouched, since
# it is never reachable from the corners.
seed_color = (255, 255, 255, 0)
thresh = 30
for seed in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]:
    px = img.getpixel(seed)
    if px[0] >= 235 and px[1] >= 235 and px[2] >= 235:
        ImageDraw.floodfill(img, seed, seed_color, thresh=thresh)

# Pad onto a square transparent canvas (centered) so every icon frame
# Pillow generates from it is exactly square -- a non-square source
# otherwise produces near-square-but-off frames like 256x251.
side = max(w, h)
square = Image.new("RGBA", (side, side), (0, 0, 0, 0))
square.paste(img, ((side - w) // 2, (side - h) // 2), img)

sizes = [(16, 16), (32, 32), (48, 48), (256, 256)]
square.save(out_path, format="ICO", sizes=sizes)
print(f"Wrote {out_path} with sizes: {sizes}")
