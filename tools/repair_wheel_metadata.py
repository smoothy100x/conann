#!/usr/bin/env python3
from __future__ import annotations

import argparse
import base64
import csv
import hashlib
import io
import re
import tempfile
import zipfile
from pathlib import Path


DIST_INFO = "conann-0.1.1.dist-info"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Repair ConANN wheel metadata in-place.")
    parser.add_argument("wheels", nargs="+", type=Path)
    parser.add_argument("--requires-python", default=">=3.10")
    return parser.parse_args()


def sha256_digest(data: bytes) -> str:
    digest = hashlib.sha256(data).digest()
    return "sha256=" + base64.urlsafe_b64encode(digest).rstrip(b"=").decode("ascii")


def update_metadata(data: bytes, requires_python: str) -> bytes:
    text = data.decode("utf-8")
    if re.search(r"(?m)^Requires-Python:", text):
        text = re.sub(r"(?m)^Requires-Python:.*$", f"Requires-Python: {requires_python}", text)
    else:
        text = text.replace(
            "Description-Content-Type:",
            f"Requires-Python: {requires_python}\nDescription-Content-Type:",
            1,
        )
    if not re.search(r"(?m)^Description-Content-Type:", text):
        text = text.replace("\n\n", "\nDescription-Content-Type: text/markdown\n\n", 1)
    return text.encode("utf-8")


def record_bytes(files: dict[str, bytes]) -> bytes:
    output = io.StringIO(newline="")
    writer = csv.writer(output)
    for name in sorted(files):
        if name.endswith("/RECORD"):
            writer.writerow([name, "", ""])
        else:
            data = files[name]
            writer.writerow([name, sha256_digest(data), str(len(data))])
    return output.getvalue().encode("utf-8")


def repair_wheel(path: Path, requires_python: str) -> None:
    path = path.resolve()
    metadata_name = f"{DIST_INFO}/METADATA"
    record_name = f"{DIST_INFO}/RECORD"

    with zipfile.ZipFile(path, "r") as src:
        files = {info.filename: src.read(info.filename) for info in src.infolist() if not info.is_dir()}

    if metadata_name not in files:
        raise FileNotFoundError(f"{path} does not contain {metadata_name}")
    if record_name not in files:
        raise FileNotFoundError(f"{path} does not contain {record_name}")

    files[metadata_name] = update_metadata(files[metadata_name], requires_python)
    files[record_name] = b""
    files[record_name] = record_bytes(files)

    with tempfile.NamedTemporaryFile(delete=False, suffix=".whl", dir=path.parent) as tmp:
        tmp_path = Path(tmp.name)

    try:
        with zipfile.ZipFile(tmp_path, "w", compression=zipfile.ZIP_DEFLATED) as dst:
            for name, data in files.items():
                dst.writestr(name, data)
        tmp_path.replace(path)
    finally:
        if tmp_path.exists():
            tmp_path.unlink()


def main() -> None:
    args = parse_args()
    for wheel in args.wheels:
        repair_wheel(wheel, args.requires_python)
        print(f"repaired {wheel}")


if __name__ == "__main__":
    main()
