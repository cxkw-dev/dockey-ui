#!/usr/bin/env python3
"""Generate bundled vector renderings from reviewed, local SVG sources.

Run with pinned tooling:
DYLD_FALLBACK_LIBRARY_PATH=/opt/homebrew/lib uv run --with cairosvg==2.8.2 \
    --python 3.12 python design/services/generate-vendor-pdfs.py

This is an offline development tool. Dockey does not depend on Python or Cairo.
"""

from hashlib import sha256
import json
from pathlib import Path
import shutil

import cairocffi as cairo
import cairosvg


class ReproduciblePDFSurface(cairo.PDFSurface):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        # Cairo otherwise embeds the current time in compressed PDF metadata.
        self.set_metadata(cairo.PDF_METADATA_CREATE_DATE, "2026-10-28T00:00:00Z")
        self.set_metadata(cairo.PDF_METADATA_MOD_DATE, "2026-10-28T00:00:00Z")


def main():
    assert cairosvg.__version__ == "2.8.2", "Use the pinned CairoSVG version."
    cairosvg.surface.PDFSurface.surface_class = ReproduciblePDFSurface
    directory = Path(__file__).resolve().parent
    destination = directory.parents[1] / "Sources/Dockey/Resources/ServiceIcons"
    destination.mkdir(parents=True, exist_ok=True)
    records = []
    for service in ["clickhouse", "langfuse", "temporal", "mongodb", "postgresql", "ai-focus"]:
        for theme in ["light", "dark"]:
            source = directory / ("" if service in ["postgresql", "ai-focus"] else "vendor") / f"{service}-{theme}.svg"
            svg = source.read_bytes()
            pdf = cairosvg.svg2pdf(bytestring=svg)
            assert pdf == cairosvg.svg2pdf(bytestring=svg), "Non-deterministic conversion."
            assert pdf.startswith(b"%PDF-"), "Invalid PDF output."
            assert b"/Image" not in pdf, "Unexpected raster image."
            (destination / source.with_suffix(".pdf").name).write_bytes(pdf)
            shutil.copyfile(source, destination / source.name)
            records.append({
                "svg": str(source.relative_to(directory)),
                "svgSHA256": sha256(svg).hexdigest(),
                "pdf": str((destination / source.with_suffix(".pdf").name).relative_to(directory.parents[1])),
                "pdfSHA256": sha256(pdf).hexdigest(),
            })
    manifest = {
        "generator": "generate-vendor-pdfs.py",
        "cairoSVGVersion": cairosvg.__version__,
        "cairoVersion": cairo.cairo_version_string(),
        "metadataDate": "2026-10-28T00:00:00Z",
        "changes": "Offline vector format conversion only; source viewBox, aspect ratio, geometry and colors preserved. Fixed metadata dates, no paths or usernames.",
        "upstreamProvenance": ["vendor/SOURCES.json", "library/SOURCES.json", "AI_FOCUS_SOURCE.json"],
        "assets": records,
    }
    (directory / "PDF_SOURCES.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print("Generated and byte-checked twelve vector PDFs and copied twelve source SVGs.")


if __name__ == "__main__":
    main()
