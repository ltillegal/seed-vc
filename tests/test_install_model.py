import importlib.util
import tempfile
import unittest
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("install_model", ROOT / "install-model.py")
install_model = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(install_model)


class InstallFromZipTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.target = self.base / "model"
        self.target.mkdir()

    def archive(self, members):
        path = self.base / "model.zip"
        with zipfile.ZipFile(path, "w") as z:
            for name, content in members:
                z.writestr(name, content)
        return path

    def test_safe_extraction(self):
        path = self.archive([
            ("model.pth", "weights"),
            ("config.yml", "config"),
            ("nested/extra.txt", "extra"),
        ])

        install_model.install_from_zip(path, self.target)

        self.assertEqual((self.target / "model.pth").read_text(), "weights")
        self.assertEqual((self.target / "config.yml").read_text(), "config")
        self.assertEqual((self.target / "nested" / "extra.txt").read_text(), "extra")

    def test_parent_traversal_rejected(self):
        path = self.archive([("../escaped.txt", "bad")])

        with self.assertRaisesRegex(ValueError, "unsafe path"):
            install_model.install_from_zip(path, self.target)

        self.assertFalse((self.base / "escaped.txt").exists())

    def test_absolute_path_rejected(self):
        escaped = self.base / "absolute.txt"
        self.addCleanup(escaped.unlink, missing_ok=True)
        path = self.archive([(str(escaped), "bad")])

        with self.assertRaisesRegex(ValueError, "unsafe path"):
            install_model.install_from_zip(path, self.target)

        self.assertFalse(escaped.exists())

    def test_duplicate_destination_rejected(self):
        path = self.archive([("a.txt", "one"), ("./a.txt", "two")])

        with self.assertRaisesRegex(ValueError, "duplicate path"):
            install_model.install_from_zip(path, self.target)


if __name__ == "__main__":
    unittest.main()
