#!/usr/bin/env python3
"""Exercise resource-layout conversion without building or launching the app."""

import importlib.util
from pathlib import Path
import shutil
import tempfile
import unittest
from unittest import mock


spec = importlib.util.spec_from_file_location(
    "check_app_launch", Path(__file__).parent / "lib/check_app_launch.py"
)
launch_check = importlib.util.module_from_spec(spec)
spec.loader.exec_module(launch_check)


class ResourceLayoutTests(unittest.TestCase):
    def exercise_resources_only(self, intact_status):
        with tempfile.TemporaryDirectory(prefix="dockey-layout-test-") as temporary:
            root = Path(temporary)
            app = root / "fixture/Dockey.app"
            fonts = launch_check.resource_bundle(app) / "Resources/Fonts"
            fonts.mkdir(parents=True)
            (fonts / "Geist-Regular.ttf").write_bytes(b"fixture font")
            stage = root / "stage"
            stage.mkdir()

            def copy_fixture(source, directory):
                directory.mkdir()
                destination = directory / "Dockey.app"
                shutil.copytree(source, destination)
                return destination

            responses = [
                (1, "Dockey bundled font verification failed."),
                (intact_status, "Dockey bundled fonts verified."),
            ]
            with mock.patch.object(launch_check, "copy_app", side_effect=copy_fixture), \
                mock.patch.object(launch_check, "resign_app"), \
                mock.patch.object(launch_check, "launch", side_effect=responses) as launch, \
                mock.patch.object(launch_check, "verify_png") as png:
                if intact_status == 0:
                    launch_check.check_layout(app, stage, "flat", 1, resources_only=True)
                else:
                    with self.assertRaises(launch_check.LaunchCheckError):
                        launch_check.check_layout(app, stage, "flat", 1, resources_only=True)
                self.assertEqual(launch.call_count, 2)
                for call in launch.call_args_list:
                    self.assertEqual(call.args[1], ["--demo", "--verify-resources"])
                png.assert_not_called()
                broken = stage / "flat-missing-font/Dockey.app"
                self.assertEqual(list(launch_check.resource_bundle(broken).rglob("Geist-Regular.ttf")), [])

    def test_resources_only_skips_gui_but_keeps_negative_and_intact_startup_checks(self):
        self.exercise_resources_only(intact_status=0)

    def test_resources_only_does_not_suppress_intact_startup_failure(self):
        self.exercise_resources_only(intact_status=1)

    def test_both_source_layouts_convert_to_both_target_layouts(self):
        for source_layout in ("flat", "wrapped"):
            for target_layout in ("flat", "wrapped"):
                with self.subTest(source=source_layout, target=target_layout):
                    with tempfile.TemporaryDirectory(prefix="dockey-layout-test-") as temporary:
                        app = Path(temporary) / "Dockey.app"
                        bundle = launch_check.resource_bundle(app)
                        relative = (
                            "Resources" if source_layout == "flat"
                            else "Contents/Resources/Resources"
                        )
                        payload = bundle / relative
                        (payload / "Fonts").mkdir(parents=True)
                        files = {
                            "Fonts/Geist-Regular.ttf": b"font fixture bytes",
                            "Fonts/Geist-OFL.txt": b"license fixture bytes",
                            "dockey-mark.svg": b"artwork fixture bytes",
                        }
                        for name, contents in files.items():
                            (payload / name).write_bytes(contents)
                        executable = app / "Contents/MacOS/Dockey"
                        executable.parent.mkdir(parents=True)
                        executable.write_bytes(b"untouched executable fixture")

                        launch_check.set_resource_layout(app, target_layout)

                        relative = (
                            "Resources" if target_layout == "flat"
                            else "Contents/Resources/Resources"
                        )
                        for name, contents in files.items():
                            self.assertEqual((bundle / relative / name).read_bytes(), contents)
                        self.assertEqual(len(list(bundle.rglob("Geist-Regular.ttf"))), 1)
                        self.assertEqual(executable.read_bytes(), b"untouched executable fixture")
                        self.assertFalse((app.parent / "resource-payload").exists())
                        if target_layout == "flat":
                            self.assertFalse((bundle / "Contents").exists())
                        else:
                            self.assertTrue((bundle / "Contents/Info.plist").is_file())
                            self.assertFalse((bundle / "Resources").exists())

    def test_symlink_payload_is_rejected_before_copy(self):
        with tempfile.TemporaryDirectory(prefix="dockey-layout-test-") as temporary:
            app = Path(temporary) / "Dockey.app"
            fonts = launch_check.resource_bundle(app) / "Resources/Fonts"
            fonts.mkdir(parents=True)
            outside = Path(temporary) / "outside.ttf"
            outside.write_bytes(b"outside fixture")
            (fonts / "Geist-Regular.ttf").symlink_to(outside)
            with self.assertRaises(launch_check.LaunchCheckError):
                launch_check.set_resource_layout(app, "wrapped")
            self.assertEqual(outside.read_bytes(), b"outside fixture")


if __name__ == "__main__":
    unittest.main()
