from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET

root = Path(sys.argv[1])
icons = sorted(root.glob("*.svg"))
if not icons:
    raise SystemExit("No bundled SVG icons found")

for path in icons:
    source = path.read_text(encoding="utf-8")
    if re.search(r"<!DOCTYPE|<!ENTITY", source, re.IGNORECASE):
        raise SystemExit(f"{path.name}: XML declarations are not allowed")
    for node in ET.fromstring(source).iter():
        tag = node.tag.rsplit("}", 1)[-1].lower()
        if tag in {"script", "foreignobject", "image"}:
            raise SystemExit(f"{path.name}: unsupported {tag} element")
        for key, value in node.attrib.items():
            name = key.rsplit("}", 1)[-1].lower()
            if name.startswith("on") or (name == "href" and not value.startswith("#")):
                raise SystemExit(f"{path.name}: external reference or event handler")
            if re.search(r"https?://|@import", value, re.IGNORECASE):
                raise SystemExit(f"{path.name}: external reference")
            for reference in re.findall(r"url\(([^)]+)\)", value):
                if not reference.strip(" \t\r\n\"'").startswith("#"):
                    raise SystemExit(f"{path.name}: external URL")
