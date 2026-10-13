"""Generate UART frame hex files from the cross-compiled applications."""
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
from uart_upload import packet

build = Path(__file__).resolve().parents[1] / "build"
for name in ("app_a", "app_b"):
    frame = packet((build / f"{name}.bin").read_bytes())
    (build / f"{name}.frame.hex").write_text(
        "".join(f"{byte:02x}\n" for byte in frame), encoding="ascii")
    print(f"{name}: {len(frame)} frame bytes")
