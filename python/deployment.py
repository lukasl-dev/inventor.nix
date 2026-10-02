"""Validate local installer media and discover Inventor release directories.

Installed executable presence is not proof of licensing or application health.
Inventor can install several release years together; never choose one by age.
"""

import datetime
import hashlib
import json
import re
import sys
from pathlib import Path


def validate_installer(installer: Path) -> None:
    if not installer.is_file() or installer.suffix.casefold() != ".exe":
        raise SystemExit("Provide an existing official Windows installer executable.")
    with installer.open("rb") as source:
        signature = source.read(2)
    if signature != b"MZ":
        raise SystemExit(
            "Installer is not a Windows executable (missing MZ signature)."
        )


def installed_executables(prefix: Path, year: str = "") -> list[Path]:
    if year and not re.fullmatch(r"20\d{2}", year):
        raise SystemExit("Inventor year must be four digits (20xx).")
    root = prefix / "drive_c/Program Files/Autodesk"
    if not root.is_dir():
        return []
    if not root.resolve().is_relative_to(prefix.resolve()):
        raise SystemExit("Autodesk installation directory escapes the Inventor prefix.")

    candidates: set[Path] = set()
    for release in root.iterdir():
        match = re.fullmatch(r"Inventor (20\d{2})", release.name, re.IGNORECASE)
        if not match or (year and match[1] != year) or not release.is_dir():
            continue
        for directory in release.iterdir():
            if directory.name.casefold() != "bin" or not directory.is_dir():
                continue
            for executable in directory.iterdir():
                if (
                    executable.name.casefold() != "inventor.exe"
                    or not executable.is_file()
                ):
                    continue
                resolved = executable.resolve()
                if not resolved.is_relative_to(root.resolve()):
                    raise SystemExit(
                        "Inventor executable escapes its Autodesk installation directory."
                    )
                candidates.add(resolved)
    return sorted(candidates)


def resolve_executable(prefix: Path, year: str = "") -> Path:
    candidates = installed_executables(prefix, year)
    if len(candidates) == 1:
        return candidates[0]
    if not candidates:
        raise SystemExit(
            "Inventor.exe not found. Inspect the installation with 'inventor doctor'."
        )
    raise SystemExit(
        "Multiple Inventor installations found. Select one with 'inventor run --year YYYY'."
    )


def record_installation(
    prefix: Path, data_directory: Path, installer: Path, wine_version: str
) -> None:
    executables = installed_executables(prefix)
    if not executables:
        raise SystemExit(
            "Installer exited without producing Inventor.exe; no success metadata recorded."
        )
    with installer.open("rb") as source:
        digest = hashlib.file_digest(source, "sha256").hexdigest()
    metadata: dict[str, str | list[str]] = {
        "checked_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "installer_path": str(installer),
        "installer_sha256": digest,
        "wine_version": wine_version,
        "executables": [
            str(path.relative_to(prefix.resolve())) for path in executables
        ],
        "validation": "Executable presence only; launch, licensing, and file operations unverified.",
    }
    destination = data_directory / "installation.json"
    temporary = destination.with_suffix(".tmp")
    temporary.write_text(json.dumps(metadata, indent=2) + "\n")
    temporary.replace(destination)


def main() -> None:
    command, *arguments = sys.argv[1:]
    if command == "validate":
        (installer,) = arguments
        validate_installer(Path(installer))
    elif command == "resolve":
        prefix, year = arguments
        print(resolve_executable(Path(prefix), year))
    elif command == "record":
        prefix, data, installer, wine_version = arguments
        record_installation(Path(prefix), Path(data), Path(installer), wine_version)
    else:
        raise SystemExit(f"Unknown deployment operation: {command}")


if __name__ == "__main__":
    main()
