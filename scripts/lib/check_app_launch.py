#!/usr/bin/env python3
"""Bounded native launch verification. All modified files and screenshots are temporary."""

import os
from pathlib import Path
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


def main():
    source = Path(sys.argv[1])
    timeout = int(sys.argv[2])
    with tempfile.TemporaryDirectory(prefix="dockey-app-launch-") as temporary:
        stage = Path(temporary)
        broken_directory = stage / "missing-font"
        broken_app = copy_app(source, broken_directory)
        resources = broken_app / "Contents/Resources/Dockey_Dockey.bundle"
        fonts = list(resources.rglob("Geist-Regular.ttf"))
        if len(fonts) != 1 or fonts[0].is_symlink():
            raise LaunchCheckError("expected one real Geist-Regular.ttf inside the app resource bundle")
        fonts[0].unlink()
        # Re-sign the disposable copy so rejection proves resource validation,
        # rather than a stale code signature or operating-system launch failure.
        subprocess.run(
            ["/usr/bin/codesign", "--force", "--deep", "--sign", "-", str(broken_app)],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
        )
        subprocess.run(
            ["/usr/bin/codesign", "--verify", "--deep", "--strict", str(broken_app)],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
        )
        status, output = launch(
            broken_app, ["--demo", "--verify-resources"], broken_directory, timeout
        )
        if status == 0 or "Dockey bundled font verification failed." not in output:
            raise LaunchCheckError("missing bundled font was not explicitly rejected")

        intact_directory = stage / "intact"
        intact_app = copy_app(source, intact_directory)
        screenshot = intact_directory / "dockey-demo.png"
        status, output = launch(
            intact_app,
            ["--demo", "--verify-resources", "--appearance", "dark", "--screenshot", str(screenshot)],
            intact_directory,
            timeout,
        )
        if status != 0:
            raise LaunchCheckError(f"intact app exited with status {status}:\n{output}")
        if "Dockey bundled fonts verified." not in output:
            raise LaunchCheckError("intact app did not confirm bundle-contained font verification")
        width, height = verify_png(screenshot)
        print(
            f"Native launch check passed: missing font rejected; intact app resources verified; "
            f"{width}x{height} demo PNG decoded. No Docker connection was used."
        )


if __name__ == "__main__":
    try:
        main()
    except (LaunchCheckError, OSError, subprocess.SubprocessError) as error:
        print(f"Dockey native launch check failed: {error}", file=sys.stderr)
        sys.exit(1)
