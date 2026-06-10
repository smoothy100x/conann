#!/usr/bin/env python3
from __future__ import annotations

import argparse
import platform
import re
import shutil
from pathlib import Path


PYTHON_FILES = [
    "__init__.py",
    "loader.py",
    "class_wrappers.py",
    "gpu_wrappers.py",
    "extra_wrappers.py",
    "array_conversions.py",
]

SWIG_VARIANTS = [
    "",
    "_avx2",
    "_avx512",
    "_sve",
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Stage generated FAISS Python bindings as package conann.")
    parser.add_argument(
        "--source-python-dir",
        type=Path,
        required=True,
        help="CMake build/faiss/python directory containing generated bindings.",
    )
    parser.add_argument(
        "--package-dir",
        type=Path,
        required=True,
        help="Destination package directory, normally src/conann.",
    )
    return parser.parse_args()


def copy_required_file(src_dir: Path, dst_dir: Path, name: str) -> None:
    src = src_dir / name
    if not src.exists():
        raise FileNotFoundError(f"Missing required generated file: {src}")
    shutil.copy2(src, dst_dir / name)


def copy_optional_file(src_dir: Path, dst_dir: Path, name: str) -> bool:
    src = src_dir / name
    if not src.exists():
        return False
    shutil.copy2(src, dst_dir / name)
    return True


def copy_optional_glob(src_dir: Path, dst_dir: Path, pattern: str) -> int:
    count = 0
    for src in sorted(src_dir.glob(pattern)):
        if src.is_file():
            shutil.copy2(src, dst_dir / src.name)
            count += 1
    return count


def rewrite_imports(path: Path) -> None:
    text = path.read_text(encoding="utf-8")

    if path.name == "__init__.py":
        text = text.replace("from faiss import class_wrappers",
                            "from . import class_wrappers")
        text = text.replace("from faiss.gpu_wrappers import *",
                            "from .gpu_wrappers import *")
        text = text.replace("from faiss.array_conversions import *",
                            "from .array_conversions import *")
        text = text.replace("from faiss.extra_wrappers import",
                            "from .extra_wrappers import")
        text = re.sub(
            r"__version__ = \"%d\.%d\.%d\" % "
            r"\(FAISS_VERSION_MAJOR,\s*FAISS_VERSION_MINOR,\s*"
            r"FAISS_VERSION_PATCH\)",
            '__version__ = "0.1.1"\n__faiss_version__ = "1.9.0"',
            text,
            flags=re.MULTILINE,
        )
        text = re.sub(
            r'(?m)^__version__\s*=\s*["\'][^"\']+["\']',
            '__version__ = "0.1.1"',
            text,
        )
        text = re.sub(
            r'(?m)^__faiss_version__\s*=\s*["\'][^"\']+["\']',
            '__faiss_version__ = "1.9.0"',
            text,
        )
        if "__faiss_version__" not in text:
            text += '\n__version__ = "0.1.1"\n__faiss_version__ = "1.9.0"\n'

    replacements = [
        ("from faiss.loader import", "from conann.loader import"),
        ("from faiss.contrib", "from conann.contrib"),
        ("import faiss.contrib", "import conann.contrib"),
    ]
    for old, new in replacements:
        text = text.replace(old, new)

    text = re.sub(r"(?m)^import faiss$", "import conann as faiss", text)
    path.write_text(text, encoding="utf-8")


def stage_package(src_dir: Path, package_dir: Path) -> None:
    src_dir = src_dir.resolve()
    package_dir = package_dir.resolve()

    if not src_dir.exists():
        raise FileNotFoundError(f"Generated Python directory does not exist: {src_dir}")

    shutil.rmtree(package_dir, ignore_errors=True)
    package_dir.mkdir(parents=True, exist_ok=True)
    for stale in list(package_dir.glob("*")):
        if stale.name == "__pycache__":
            continue
        if stale.is_dir():
            shutil.rmtree(stale, ignore_errors=True)
        else:
            stale.unlink(missing_ok=True)

    for name in PYTHON_FILES:
        copy_required_file(src_dir, package_dir, name)

    ext = ".pyd" if platform.system() == "Windows" else ".so"
    found_extension = False
    for variant in SWIG_VARIANTS:
        py_name = f"swigfaiss{variant}.py"
        lib_name = f"_swigfaiss{variant}{ext}"
        found_py = copy_optional_file(src_dir, package_dir, py_name)
        found_lib = copy_optional_file(src_dir, package_dir, lib_name)
        found_extension = found_extension or (found_py and found_lib)

    if not found_extension:
        variants = ", ".join(f"_swigfaiss{variant}{ext}" for variant in SWIG_VARIANTS)
        raise FileNotFoundError(f"No generated SWIG extension found. Expected one of: {variants}")

    callbacks_so = "libfaiss_python_callbacks.so"
    copy_optional_file(src_dir, package_dir, callbacks_so)
    copy_optional_file(src_dir, package_dir, "libfaiss_python_callbacks.pyd")
    copy_optional_glob(src_dir, package_dir, "*.dll")

    contrib_src = src_dir / "contrib"
    if contrib_src.exists():
        shutil.copytree(contrib_src, package_dir / "contrib")

    for py_file in package_dir.rglob("*.py"):
        rewrite_imports(py_file)


def main() -> None:
    args = parse_args()
    stage_package(args.source_python_dir, args.package_dir)


if __name__ == "__main__":
    main()
