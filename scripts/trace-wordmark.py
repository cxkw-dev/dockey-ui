# /// script
# requires-python = ">=3.12,<3.13"
# dependencies = ["pillow==12.0.0", "vtracer==0.6.12"]
# ///
"""Trace the selected Rounded 01 reference into an editable, monochrome SVG.

Run: uv run scripts/trace-wordmark.py
After uv has cached these pinned development dependencies, regeneration is offline.
The app does not import these development tools or load the source PNG.
"""
from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path
import re
import tempfile
import xml.etree.ElementTree as ET

from PIL import Image
import vtracer


ROOT = Path(__file__).resolve().parent.parent
DIRECTORY = ROOT / "design-assets" / "wordmark"
TOKEN = re.compile(r"[MLCQZ]|[-+]?(?:\d*\.\d+|\d+\.?\d*)(?:[eE][-+]?\d+)?")
ARITY = {"M": 2, "L": 2, "C": 6, "Q": 4, "Z": 0}
PARAMETERS = dict(
    colormode="binary", mode="spline", filter_speckle=4, corner_threshold=60,
    length_threshold=3.5, max_iterations=10, splice_threshold=45, path_precision=3,
)


def flatten_path(data: str, transform: str) -> str:
    """Normalize the pinned tracer's absolute curves and translation only."""
    translation = re.fullmatch(r"translate\(([-\d.]+)[ ,]+([-\d.]+)\)", transform)
    if translation is None:
        raise ValueError(f"Unsupported tracer transform: {transform!r}")
    dx, dy = map(float, translation.groups())
    if TOKEN.sub("", data).strip(" \t\r\n,"):
        raise ValueError("Unsupported path syntax")
    tokens = TOKEN.findall(data)
    output: list[str] = []
    cursor = 0
    while cursor < len(tokens):
        operation = tokens[cursor]
        count = ARITY[operation]
        values = list(map(float, tokens[cursor + 1:cursor + 1 + count]))
        if len(values) != count or not all(map(math.isfinite, values)):
            raise ValueError("Invalid path coordinates")
        values = [value + (dx if index % 2 == 0 else dy) for index, value in enumerate(values)]
        output.append(operation + " ".join(f"{value:.3f}" for value in values))
        cursor += count + 1
    return " ".join(output)


def main() -> None:
    reference = DIRECTORY / "rounded-reference.png"
    with Image.open(reference) as image:
        width, height = image.size
        if not 1 <= width <= 4096 or not 1 <= height <= 4096:
            raise ValueError("Unexpected reference dimensions")
        mask = image.convert("L").point(lambda pixel: 0 if pixel >= 128 else 255)
    with tempfile.TemporaryDirectory(prefix="dockey-wordmark-") as temporary:
        mask_path = Path(temporary) / "mask.png"
        trace_path = Path(temporary) / "trace.svg"
        mask.save(mask_path)
        vtracer.convert_image_to_svg_py(str(mask_path), str(trace_path), **PARAMETERS)
        paths = [
            flatten_path(element.attrib["d"], element.attrib.get("transform", ""))
            for element in ET.parse(trace_path).getroot()
            if element.tag == "{http://www.w3.org/2000/svg}path"
        ]
    if not paths:
        raise ValueError("The selected wordmark has no contours")
    outline = DIRECTORY / "rounded-outline.svg"
    outline.write_text(
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}" role="img" aria-labelledby="title">\n'
        '  <title id="title">Dockey — Rounded 01</title>\n'
        f'  <path fill="currentColor" d="{" ".join(paths)}"/>\n'
        '</svg>\n', encoding="utf-8",
    )
    manifest = {
        "design": "Rounded 01",
        "selection": "Owner-selected wordmark from the ten-concept comparison board",
        "reference": {"file": reference.name, "sha256": hashlib.sha256(reference.read_bytes()).hexdigest()},
        "outline": {"file": outline.name, "sha256": hashlib.sha256(outline.read_bytes()).hexdigest()},
        "vectorization": {"tool": "vtracer", "version": "0.6.12", "threshold": 128, **PARAMETERS},
        "runtime": "Cached native SwiftUI paths; no source image, script font, or tracing tools bundled",
        "license": "Project artwork under Apache-2.0",
    }
    (DIRECTORY / "SOURCE.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"Traced Rounded 01: {width} × {height}, {len(paths)} compound contours.")


if __name__ == "__main__":
    main()
