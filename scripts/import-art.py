"""Import the two-times exports from the owner-supplied MiNa design archives."""
from io import BytesIO
from pathlib import Path
from urllib.parse import unquote
from zipfile import ZipFile
import json
import re
from PIL import Image

root = Path(__file__).resolve().parents[1]
sources = json.loads(Path(__file__).with_name("design-sources.json").read_text())
designs = next(path.parent for path in root.glob("*/*_slices.zip"))
destination = root / "ios/MiNa/Artwork"
for group, archive in sources.items():
    directory = destination / group
    directory.mkdir(parents=True, exist_ok=True)
    with ZipFile(designs / unquote(archive)) as source:
        filenames = [name for name in source.namelist() if re.search(r"@2x(?:\(\d+\))?\.png$", name)]
        for number, filename in enumerate(filenames, 1):
            picture = Image.open(BytesIO(source.read(filename))).convert("RGBA")
            if group == "signIn" and number == 1:
                # Replace the legacy wordmark area with sky sampled from the same artwork.
                # All controls and the MiNa wordmark are drawn as accessible interface text.
                for left, top, right, bottom in ((112, 431, 280, 467), (139, 475, 259, 528)):
                    region = (left * 2, top * 2, right * 2, bottom * 2)
                    x1, y1, x2, y2 = region
                    strip = picture.crop((x1, y1 - 1, x2, y1))
                    lower = picture.crop((x1, y2, x2, y2 + 1))
                    for y in range(y1, y2):
                        picture.paste(Image.blend(strip, lower, (y-y1)/(y2-y1)), (x1, y))
                picture.save(directory / "welcome.webp", quality=93)
                continue
            if group == "medals":
                picture.thumbnail((260, 120), Image.Resampling.LANCZOS)
            picture.save(directory / f"{number}.webp", quality=92, method=4)
