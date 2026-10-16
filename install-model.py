#!/usr/bin/env python3
"""
Install a Seed-VC model from a ZIP archive or a directory.

Usage:
    python install-model.py <path-to-zip-or-directory>

The archive (or directory) must contain:
    - model.pth    (required)
    - config.yml   (required)

Files are copied to: ./my_models/<name>/
where <name> is the archive's base name without extension.

On success, prints the exact `python app_vc.py ...` command to run
Seed-VC with the installed model.
"""
import argparse
import os
import shutil
import sys
import zipfile

MY_MODELS_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "my_models")


def fail(msg):
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(1)


def install_from_zip(zip_path, target_dir):
    with zipfile.ZipFile(zip_path, "r") as z:
        z.extractall(target_dir)


def install_from_dir(src_dir, target_dir):
    os.makedirs(target_dir, exist_ok=True)
    for name in os.listdir(src_dir):
        src = os.path.join(src_dir, name)
        dst = os.path.join(target_dir, name)
        if os.path.isdir(src):
            shutil.copytree(src, dst, dirs_exist_ok=True)
        else:
            shutil.copy2(src, dst)


def find_files(target_dir):
    """
    Walk target_dir and return (model_pth, config_yml), or (None, None).
    Looks for the first .pth file (any name) and the first .yml/.yaml
    that starts with 'config'.
    """
    model_pth = None
    config_yml = None
    for root, _, files in os.walk(target_dir):
        for f in files:
            full = os.path.join(root, f)
            if model_pth is None and f.endswith(".pth"):
                model_pth = full
            if config_yml is None and (f.endswith(".yml") or f.endswith(".yaml")):
                if f.lower().startswith("config"):
                    config_yml = full
        if model_pth and config_yml:
            break
    return model_pth, config_yml


def main():
    parser = argparse.ArgumentParser(
        description="Install a Seed-VC model from a ZIP archive or directory."
    )
    parser.add_argument("source", help="Path to .zip archive or a directory with model.pth + config.yml")
    args = parser.parse_args()

    src = os.path.abspath(args.source)
    if not os.path.exists(src):
        fail(f"source not found: {src}")

    # Determine name and target dir
    if os.path.isdir(src):
        name = os.path.basename(src.rstrip("/\\"))
    elif src.lower().endswith(".zip"):
        name = os.path.splitext(os.path.basename(src))[0]
    else:
        fail(f"source must be a .zip file or a directory, got: {src}")

    target_dir = os.path.join(MY_MODELS_DIR, name)

    if os.path.exists(target_dir):
        fail(f"target already exists: {target_dir}\n"
             f"       remove it first, or use a different source name.")

    os.makedirs(target_dir, exist_ok=True)

    print(f"Installing from: {src}")
    print(f"          into: {target_dir}")

    try:
        if os.path.isdir(src):
            install_from_dir(src, target_dir)
        else:
            install_from_zip(src, target_dir)
    except Exception as e:
        # cleanup partial install
        shutil.rmtree(target_dir, ignore_errors=True)
        fail(f"extraction failed: {e}")

    model_pth, config_yml = find_files(target_dir)
    if not model_pth:
        shutil.rmtree(target_dir, ignore_errors=True)
        fail("no .pth file found inside the archive")
    if not config_yml:
        shutil.rmtree(target_dir, ignore_errors=True)
        fail("no config .yml/.yaml file found inside the archive")

    print()
    print("Installed successfully.")
    print(f"  model : {model_pth}")
    print(f"  config: {config_yml}")
    print()
    print("To run Seed-VC with this model:")
    print()
    print(f"  cd {os.path.dirname(os.path.abspath(__file__))}")
    print(f"  source .venv/bin/activate")
    print(f"  python app_vc.py \\")
    print(f"      --checkpoint {model_pth} \\")
    print(f"      --config {config_yml}")
    print()


if __name__ == "__main__":
    main()
