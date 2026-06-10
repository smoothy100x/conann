#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
import uuid
import zipfile
from pathlib import Path


PYTHON_BY_TAG = {
    "cp310": r"C:\Users\benfo\.pyenv\pyenv-win\versions\3.10.11\python.exe",
    "cp311": r"C:\Users\benfo\.pyenv\pyenv-win\versions\3.11.9\python.exe",
    "cp312": r"C:\Users\benfo\.pyenv\pyenv-win\versions\3.12.10\python.exe",
    "cp313": r"C:\Users\benfo\.pyenv\pyenv-win\versions\3.13.13\python.exe",
    "cp314": r"C:\Users\benfo\.pyenv\pyenv-win\versions\3.14.5\python.exe",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Rebuild Windows wheels through the canonical pyproject metadata "
            "using native payloads extracted from already-built Windows wheels."
        )
    )
    parser.add_argument(
        "--package-root",
        type=Path,
        default=Path(__file__).resolve().parents[1],
        help="Canonical conann package root.",
    )
    parser.add_argument(
        "--wheel-dir",
        type=Path,
        default=None,
        help="Directory containing Windows conann wheels.",
    )
    parser.add_argument(
        "--backup-dir",
        type=Path,
        default=None,
        help="Directory for original wheels before replacement.",
    )
    parser.add_argument(
        "--source-version",
        default="0.1.1",
        help="Existing wheel version to use as the native payload source.",
    )
    parser.add_argument(
        "--target-version",
        default="0.1.1",
        help="Version expected from canonical package metadata.",
    )
    return parser.parse_args()


def wheel_tag(path: Path) -> str:
    match = re.search(r"-(cp\d+)-\1-win_amd64\.whl$", path.name)
    if not match:
        raise ValueError(f"Could not infer CPython tag from wheel name: {path.name}")
    return match.group(1)


def require_python(tag: str) -> Path:
    try:
        python = Path(PYTHON_BY_TAG[tag])
    except KeyError as exc:
        raise KeyError(f"No pyenv Python mapping for {tag}") from exc
    if not python.exists():
        raise FileNotFoundError(f"Missing Python for {tag}: {python}")
    return python


def extract_wheel(wheel: Path, destination: Path) -> None:
    with zipfile.ZipFile(wheel) as zf:
        zf.extractall(destination)


def run(cmd: list[str], cwd: Path) -> None:
    print("+", " ".join(cmd), flush=True)
    subprocess.run(cmd, cwd=cwd, check=True)


def rebuild_one(package_root: Path, wheel: Path, backup_dir: Path, target_version: str) -> Path:
    tag = wheel_tag(wheel)
    python = require_python(tag)
    temp_root = package_root / "tmp"
    temp_root.mkdir(parents=True, exist_ok=True)
    tmp_path = temp_root / f"repack-{tag}-{uuid.uuid4().hex[:8]}"
    tmp_path.mkdir(parents=True, exist_ok=True)

    extracted = tmp_path / "extracted"
    wheelhouse = tmp_path / "wheelhouse"
    build_package = tmp_path / "package"
    extracted.mkdir()
    wheelhouse.mkdir()
    (build_package / "src").mkdir(parents=True)

    for name in ("pyproject.toml", "setup.py", "README.md", "LICENSE"):
        shutil.copy2(package_root / name, build_package / name)

    extract_wheel(wheel, extracted)
    payload = extracted / "faiss"
    if not payload.exists():
        payload = extracted / "conann"
    if not payload.exists():
        raise FileNotFoundError(f"Could not find faiss/ or conann/ payload in {wheel}")

    run(
        [
            str(python),
            str(package_root / "tools" / "stage_conann_package.py"),
            "--source-python-dir",
            str(payload),
            "--package-dir",
            str(build_package / "src" / "conann"),
        ],
        cwd=package_root,
    )

    run(
        [
            str(python),
                "-m",
                "pip",
                "wheel",
                str(build_package),
                "--no-build-isolation",
                "--no-deps",
                "--wheel-dir",
            str(wheelhouse),
        ],
        cwd=package_root,
    )

    rebuilt = sorted(wheelhouse.glob(f"conann-{target_version}-{tag}-{tag}-win_amd64.whl"))
    if len(rebuilt) != 1:
        raise RuntimeError(f"Expected one rebuilt wheel for {tag}, found {rebuilt}")

    backup_dir.mkdir(parents=True, exist_ok=True)
    backup = backup_dir / wheel.name
    if not backup.exists():
        shutil.copy2(wheel, backup)
    target = wheel.with_name(rebuilt[0].name)
    shutil.copy2(rebuilt[0], target)
    return target


def main() -> None:
    args = parse_args()
    package_root = args.package_root.resolve()
    wheel_dir = (args.wheel_dir or package_root / "wheels" / "win_amd64").resolve()
    backup_dir = (args.backup_dir or wheel_dir / "bad_metadata_backup").resolve()

    wheels = sorted(wheel_dir.glob(f"conann-{args.source_version}-cp*-cp*-win_amd64.whl"))
    if not wheels:
        raise FileNotFoundError(f"No Windows conann wheels found in {wheel_dir}")

    rebuilt = []
    for wheel in wheels:
        print(f"Rebuilding {wheel.name}", flush=True)
        rebuilt.append(rebuild_one(package_root, wheel, backup_dir, args.target_version))

    print("Rebuilt wheels:")
    for wheel in rebuilt:
        print(wheel)


if __name__ == "__main__":
    main()
