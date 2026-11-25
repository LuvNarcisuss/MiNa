"""Prepare MiNa's immutable public Storage release from its design sources."""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import shutil
import wave

root = Path(__file__).resolve().parents[1] / "ios" / "MiNa"
parser = argparse.ArgumentParser()
parser.add_argument("output", type=Path)
out = parser.parse_args().output
out.mkdir(parents=True, exist_ok=True)
art = root / "Artwork"
images = {p.relative_to(art).with_suffix("").as_posix(): base64.b64encode(p.read_bytes()).decode()
          for p in sorted(art.rglob("*.webp"))}
sounds = {}
for sound in sorted(art.rglob("*.wav")):
    with wave.open(str(sound), "rb") as audio:
        sounds[sound.stem] = {"seconds": audio.getnframes() / audio.getframerate(),
                              "sha256": hashlib.sha256(sound.read_bytes()).hexdigest()}
    shutil.copyfile(sound, out / sound.name)
font = art / "emoji" / "MiNaReactions.ttf"
catalog = {"images": images, "font": base64.b64encode(font.read_bytes()).decode(),
           "policies": json.loads((root / "policies.json").read_bytes()), "sounds": sounds}
(out / "interface.json").write_bytes(json.dumps(catalog, separators=(",", ":"), sort_keys=True).encode())
shutil.copyfile(root.parents[1] / "supabase/collections/interface/library.json", out / "library.json")
shutil.copyfile(art / "emoji" / "Attribution.txt", out / "Attribution.txt")
shutil.copyfile(root / "Assets.xcassets/AppIcon.appiconset/MiNa.png", out / "MiNa.png")
shutil.copyfile(art / "launch/Launch.png", out / "Launch.png")
print(f"{len(images)} images, {len(sounds)} soundscapes, catalog SHA-256 {hashlib.sha256((out / 'interface.json').read_bytes()).hexdigest()}")
