from pathlib import Path
import json
import zipfile

root = Path(__file__).resolve().parent.parent
mod = root / "mods-unpacked" / "tang-AutoShop"
version = json.loads((mod / "manifest.json").read_text(encoding="utf-8"))["version_number"]
output = root / "dist" / ("tang-AutoShop-" + version + ".zip")
output.parent.mkdir(exist_ok=True)
with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as archive:
    for path in sorted(mod.rglob("*")):
        if path.is_file() and path.suffix in {".gd", ".json", ".md"}:
            archive.write(path, path.relative_to(root).as_posix())
print(output)
