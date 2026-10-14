"""Expose the real RTL JTAG pins to OpenOCD's remote_bitbang adapter."""
import argparse
from pathlib import Path
import socket
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--vvp', default='vvp')
    parser.add_argument('--port', type=int, default=9824)
    parser.add_argument('--image', type=Path, default=ROOT / 'build/debug/remote.vvp')
    args = parser.parse_args()
    proc = subprocess.Popen([args.vvp, str(args.image)], cwd=ROOT / 'build/stage3',
                            stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                            stderr=sys.stderr, bufsize=65536)
    try:
        while True:
            line = proc.stdout.readline()
            if not line:
                raise RuntimeError('RTL exited before initialization')
            if b'JTAG_SIM_READY' in line:
                break
            print(line.decode(errors='replace').rstrip(), flush=True)
        with socket.socket() as server:
            server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            server.bind(('127.0.0.1', args.port))
            server.listen(1)
            print(f'JTAG simulator listening on 127.0.0.1:{args.port}', flush=True)
            client, _ = server.accept()
            with client:
                client.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
                while packet := client.recv(4096):
                    commands = bytes(c for c in packet if 48 <= c <= 55 or c in (82, 81))
                    if commands:
                        proc.stdin.write(commands)
                        proc.stdin.flush()
                    response = bytearray()
                    for _ in range(commands.count(82)):
                        while True:
                            line = proc.stdout.readline()
                            if not line:
                                raise RuntimeError('RTL exited during JTAG scan')
                            if line.startswith(b'TDO:'):
                                bit = line[4:5]
                                if bit not in (b'0', b'1'):
                                    raise RuntimeError(f'Unknown TDO value: {line!r}')
                                response.extend(bit)
                                break
                            print(line.decode(errors='replace').rstrip(), flush=True)
                    if response:
                        client.sendall(response)
                    if 81 in commands:
                        break
    finally:
        if proc.poll() is None:
            proc.stdin.close()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.terminate()
                proc.wait(timeout=5)


if __name__ == '__main__':
    main()
