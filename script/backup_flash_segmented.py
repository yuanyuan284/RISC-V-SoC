"""Read EF2 internal Flash in independently checked CPU JTAG segments."""

import argparse
from datetime import datetime
from pathlib import Path
import re
import subprocess
import uuid

from inspect_flash_dump import FLASH_SIZE, inspect

FLASH_BASE = 0x30000000
TAP = "JTAG tap: soc.cpu tap/device found: 0x10002fff"
EXAMINED = "[soc.cpu] Examination succeed"


class BackupError(RuntimeError):
    pass


def _tcl_path(path: Path) -> str:
    value = path.resolve().as_posix()
    if any(char in value for char in "{}\r\n"):
        raise BackupError("Backup path contains characters unsafe for OpenOCD Tcl")
    return "{" + value + "}"


def _read_chunk(openocd: str, config: Path, root: Path, path: Path,
                offset: int, size: int, timeout: int, runner) -> bool:
    commands = (f"init; halt; dump_image {_tcl_path(path)} "
                f"0x{FLASH_BASE + offset:08x} 0x{size:x}; shutdown")
    command = [openocd, "-f", str(config), "-c", commands]
    try:
        result = runner(command, cwd=root, capture_output=True, text=True,
                        encoding="utf-8", errors="replace", timeout=timeout)
        log = (result.stdout or "") + "\n" + (result.stderr or "")
        clean = (result.returncode == 0 and TAP in log and EXAMINED in log
                 and not re.search(r"(?m)^Error\s*:", log))
    except subprocess.TimeoutExpired as exc:
        log = f"OpenOCD timed out after {timeout} seconds: {exc}\n"
        clean = False
    except OSError as exc:
        log = f"OpenOCD could not start: {exc}\n"
        clean = False
    path.with_suffix(path.suffix + ".openocd.log").write_text(log, encoding="utf-8")
    return clean and path.is_file() and path.stat().st_size == size


def backup(*, openocd: str, config: Path, bitstream: Path, output_dir: Path,
           timeout: int = 120, chunk_size: int = 65536, read_passes: int = 2,
           max_attempts: int = 2, plan_only: bool = False, runner=subprocess.run,
           name: str | None = None) -> Path | None:
    if chunk_size < 4096 or chunk_size > 65536 or FLASH_SIZE % chunk_size:
        raise BackupError("Chunk size must divide 512 KiB and be 4..64 KiB")
    if read_passes < 2 or max_attempts < 1 or timeout < 1:
        raise BackupError("Use at least two read passes, one attempt, and a positive timeout")
    if not bitstream.is_file() or not config.is_file():
        raise BackupError("Flash bitstream or OpenOCD config is missing")
    root = Path(__file__).resolve().parents[1]
    if name is None:
        name = (f"ef2_internal_flash_{datetime.now():%Y%m%d-%H%M%S}_"
                f"{uuid.uuid4().hex[:8]}.bin")
    output = output_dir / name
    partial = Path(str(output) + ".partial")
    segments = output_dir / (name + ".segments")
    count = FLASH_SIZE // chunk_size
    print(f"Read-only 512 KiB Flash backup: {count} x {chunk_size} bytes, "
          f"{read_passes} independent passes per segment, "
          f"{max_attempts} attempts per pass", flush=True)
    print(f"Local bitstream (not device attestation): {bitstream}", flush=True)
    print(f"Output: {output}", flush=True)
    if plan_only:
        print("Plan only: OpenOCD was not started and no file was created.", flush=True)
        return None
    if output.exists() or partial.exists() or segments.exists():
        raise BackupError("Backup output already exists; refusing to overwrite it")
    output_dir.mkdir(parents=True, exist_ok=True)
    segments.mkdir()
    accepted = []
    for index in range(count):
        offset = index * chunk_size
        reference = None
        first_path = None
        for read_pass in range(1, read_passes + 1):
            for attempt in range(1, max_attempts + 1):
                path = segments / (f"chunk{index:02d}_pass{read_pass}_"
                                   f"attempt{attempt}.bin")
                clean = _read_chunk(openocd, config, root, path,
                                    offset, chunk_size, timeout, runner)
                if clean:
                    break
                print(f"Chunk {index + 1}/{count}, pass {read_pass}, "
                      f"attempt {attempt} failed; inspect {path}.openocd.log",
                      flush=True)
            else:
                raise BackupError(f"Chunk {index + 1} pass {read_pass} failed; "
                                  "no complete backup was published")
            data = path.read_bytes()
            if reference is None:
                reference, first_path = data, path
            elif data != reference:
                mismatch = next(i for i, (a, b) in enumerate(zip(reference, data))
                                if a != b)
                raise BackupError(f"Independent reads differ at physical "
                                  f"0x{offset + mismatch:05x}; no complete "
                                  "backup was published")
        accepted.append(first_path)
        print(f"Chunk {index + 1}/{count} verified at 0x{offset:05x}", flush=True)
    with partial.open("xb") as combined:
        for path in accepted:
            combined.write(path.read_bytes())
    data = partial.read_bytes()
    result = inspect(data)
    if data != b"".join(path.read_bytes() for path in accepted):
        raise BackupError("Assembled backup differs from verified segments")
    if output.exists():
        raise BackupError("Backup output appeared during capture; refusing overwrite")
    partial.rename(output)
    print(f"Complete verified backup: {output}", flush=True)
    print(f"Size: {len(data)} bytes; SHA256: {result['sha256']}", flush=True)
    print(f"Segment files and OpenOCD logs: {segments}", flush=True)
    return output


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--openocd", required=True)
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--bitstream", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--timeout", type=int, default=120)
    parser.add_argument("--chunk-size", type=int, default=65536)
    parser.add_argument("--read-passes", type=int, default=2)
    parser.add_argument("--max-attempts", type=int, default=2)
    parser.add_argument("--plan-only", action="store_true")
    args = parser.parse_args()
    try:
        backup(openocd=args.openocd, config=args.config,
               bitstream=args.bitstream, output_dir=args.output_dir,
               timeout=args.timeout, chunk_size=args.chunk_size,
               read_passes=args.read_passes, max_attempts=args.max_attempts,
               plan_only=args.plan_only)
    except BackupError as exc:
        parser.exit(1, f"Backup failed: {exc}\n")


if __name__ == "__main__":
    main()
