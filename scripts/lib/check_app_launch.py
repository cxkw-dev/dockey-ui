#!/usr/bin/env python3
"""Bounded native launch verification. All modified files and screenshots are temporary."""

import os
from pathlib import Path
import plistlib
import shutil
import signal
import struct
import subprocess
import sys
import tempfile
import time


class LaunchCheckError(RuntimeError):
    pass


def stop_process(process):
    if process.poll() is not None:
        return
    try:
        os.killpg(process.pid, signal.SIGTERM)
        process.wait(timeout=2)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.wait(timeout=2)
    except ProcessLookupError:
        pass


def launch(app, arguments, directory, timeout):
    log = directory / "launch.log"
    environment = os.environ.copy()
    # Debug resource overrides must not make an invalid app appear self-contained.
    environment.pop("PACKAGE_RESOURCE_BUNDLE_PATH", None)
    environment.pop("PACKAGE_RESOURCE_BUNDLE_URL", None)
    with log.open("wb") as output:
        process = subprocess.Popen(
            [str(app / "Contents/MacOS/Dockey"), *arguments],
            cwd=directory,
            env=environment,
            stdout=output,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )
        deadline = time.monotonic() + timeout
        try:
            while process.poll() is None:
                if time.monotonic() >= deadline:
                    raise LaunchCheckError(
                        "native launch timed out; a working macOS graphical session is required"
                    )
                if log.stat().st_size > 1024 * 1024:
                    raise LaunchCheckError("native launch exceeded the 1 MiB output limit")
                time.sleep(0.1)
        finally:
            stop_process(process)
    if log.stat().st_size > 1024 * 1024:
        raise LaunchCheckError("native launch exceeded the 1 MiB output limit")
    with log.open("rb") as recorded:
        recorded.seek(max(0, log.stat().st_size - 16384))
        output = recorded.read(16384).decode("utf-8", errors="replace")
    return process.returncode, output


def copy_app(source, directory):
    directory.mkdir()
    app = directory / "Dockey.app"
    subprocess.run(["/usr/bin/ditto", str(source), str(app)], check=True)
    return app


def resource_bundle(app):
    return app / "Contents/Resources/Dockey_Dockey.bundle"


def set_resource_layout(app, layout):
    """Normalize only a disposable app copy to either supported SwiftPM layout."""
    bundle = resource_bundle(app)
    candidates = [bundle / "Resources", bundle / "Contents/Resources/Resources"]
    payloads = [path for path in candidates if (path / "Fonts/Geist-Regular.ttf").is_file()]
    if len(payloads) != 1 or any(path.is_symlink() for path in bundle.rglob("*")):
        raise LaunchCheckError("expected one self-contained font payload in the copied app")
    if layout not in ("flat", "wrapped"):
        raise LaunchCheckError(f"unsupported resource layout: {layout}")
    payload = app.parent / "resource-payload"
    shutil.copytree(payloads[0], payload)
    shutil.rmtree(bundle)
    destination = bundle / ("Resources" if layout == "flat" else "Contents/Resources/Resources")
    shutil.copytree(payload, destination)
    shutil.rmtree(payload)
    if layout == "wrapped":
        with (bundle / "Contents/Info.plist").open("wb") as metadata:
            plistlib.dump(
                {
                    "CFBundleIdentifier": "dev.dockey.resources",
                    "CFBundleName": "Dockey_Dockey",
                    "CFBundlePackageType": "BNDL",
                    "CFBundleVersion": "1",
                },
                metadata,
            )


def resign_app(app):
    # Re-sign modified disposable copies so failures exercise resource validation,
    # rather than a stale signature or operating-system launch rejection.
    subprocess.run(
        ["/usr/bin/codesign", "--force", "--deep", "--sign", "-", str(app)],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
    )
    subprocess.run(
        ["/usr/bin/codesign", "--verify", "--deep", "--strict", str(app)],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
    )


def verify_png(path):
    if not path.is_file():
        raise LaunchCheckError("native launch did not create a screenshot")
    if path.stat().st_size > 64 * 1024 * 1024:
        raise LaunchCheckError("native screenshot exceeded the 64 MiB size limit")
    data = path.read_bytes()
    if len(data) < 1024 or data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
        raise LaunchCheckError("native launch did not create a valid PNG")
    width, height = struct.unpack(">II", data[16:24])
    if width < 800 or height < 500:
        raise LaunchCheckError("native screenshot is smaller than the expected app window")
    result = subprocess.run(
        ["/usr/bin/sips", "-g", "pixelWidth", "-g", "pixelHeight", str(path)],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    if f"pixelWidth: {width}" not in result.stdout or f"pixelHeight: {height}" not in result.stdout:
        raise LaunchCheckError("ImageIO could not decode the native screenshot")
    return width, height


def check_layout(source, stage, layout, timeout):
    intact_directory = stage / f"{layout}-intact"
    intact_app = copy_app(source, intact_directory)
    set_resource_layout(intact_app, layout)
    resign_app(intact_app)

    broken_directory = stage / f"{layout}-missing-font"
    broken_app = copy_app(intact_app, broken_directory)
    fonts = list(resource_bundle(broken_app).rglob("Geist-Regular.ttf"))
    if len(fonts) != 1 or fonts[0].is_symlink():
        raise LaunchCheckError("expected one real Geist-Regular.ttf inside the app resource bundle")
    fonts[0].unlink()
    resign_app(broken_app)
    status, output = launch(broken_app, ["--demo", "--verify-resources"], broken_directory, timeout)
    if status == 0 or "Dockey bundled font verification failed." not in output:
        raise LaunchCheckError(f"{layout}: missing bundled font was not explicitly rejected")

    screenshot = intact_directory / "dockey-demo.png"
    status, output = launch(
        intact_app,
        ["--demo", "--verify-resources", "--appearance", "dark", "--screenshot", str(screenshot)],
        intact_directory,
        timeout,
    )
    if status != 0:
        raise LaunchCheckError(f"{layout}: intact app exited with status {status}:\n{output}")
    if "Dockey bundled fonts verified." not in output:
        raise LaunchCheckError(f"{layout}: intact app did not confirm font verification")
    width, height = verify_png(screenshot)
    print(
        f"Native launch check passed ({layout} resources): missing font rejected; "
        f"intact app resources verified; {width}x{height} demo PNG decoded.",
        flush=True,
    )


def main():
    source = Path(sys.argv[1])
    timeout = int(sys.argv[2])
    with tempfile.TemporaryDirectory(prefix="dockey-app-launch-") as temporary:
        for layout in ("flat", "wrapped"):
            check_layout(source, Path(temporary), layout, timeout)
    print("Both SwiftPM resource layouts passed. No Docker connection was used.")


if __name__ == "__main__":
    try:
        main()
    except (LaunchCheckError, OSError, subprocess.SubprocessError) as error:
        print(f"Dockey native launch check failed: {error}", file=sys.stderr)
        sys.exit(1)
