"""Write a deterministic page archive and an integrity manifest."""
from hashlib import sha256
import json
import os
from pathlib import Path
import sys
from tempfile import NamedTemporaryFile
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo

stage, output = map(Path, sys.argv[1:])
files = sorted(path for path in stage.rglob("*") if path.is_file() and not path.name.startswith("."))
fingerprints = {}

def append(archive, name, data):
    entry = ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
    entry.compress_type = ZIP_DEFLATED
    entry.external_attr = 0o100644 << 16
    archive.writestr(entry, data)

with NamedTemporaryFile(dir=output.parent, delete=False) as temporary:
    target = Path(temporary.name)
try:
    with ZipFile(target, "w") as archive:
        for path in files:
            name = path.relative_to(stage).as_posix()
            if name == "manifest.json" or name.split("/")[0] == "private-media":
                raise ValueError(f"Reserved page resource name: {name}")
            data = path.read_bytes()
            fingerprints[name] = sha256(data).hexdigest()
            append(archive, name, data)
        append(archive, "manifest.json", json.dumps(fingerprints, sort_keys=True).encode())
    target.chmod(0o644)
    os.replace(target, output)
finally:
    target.unlink(missing_ok=True)
