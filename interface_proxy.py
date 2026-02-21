"""
Interface-Bound Proxy Server

A local HTTP/HTTPS proxy that forces all outgoing connections through a
specific network interface by binding to its IP address. Point your browser
proxy settings to 127.0.0.1:<port> and all traffic will exit via the
chosen interface.

Usage:
    python interface_proxy.py                  # interactive interface selection
    python interface_proxy.py --bind 192.168.1.50
    python interface_proxy.py --bind 192.168.1.50 --port 8118
    python interface_proxy.py --bind 192.168.1.50 --daemon
"""

import argparse
import asyncio
import ipaddress
import logging
import os
import signal
import socket
import sys
import functools

LOG_FORMAT = "%(asctime)s [%(levelname)s] %(message)s"
logger = logging.getLogger("ifproxy")


# ---------------------------------------------------------------------------
# Utility: list local network interfaces
# ---------------------------------------------------------------------------

def list_interfaces() -> list[dict]:
    results: list[dict] = []
    try:
        import psutil
        addrs = psutil.net_if_addrs()
        stats = psutil.net_if_stats()
        for iface, addr_list in addrs.items():
            if not stats.get(iface, object()).isup:
                continue
            for addr in addr_list:
                if addr.family == socket.AF_INET and not addr.address.startswith("127."):
                    results.append({"name": iface, "ip": addr.address})
    except ImportError:
        hostname = socket.gethostname()
        try:
            for info in socket.getaddrinfo(hostname, None, socket.AF_INET):
                ip = info[4][0]
                if not ip.startswith("127."):
                    results.append({"name": "(unknown)", "ip": ip})
        except socket.gaierror:
            pass
    return results


def pick_interface_interactive() -> str:
    ifaces = list_interfaces()
    if not ifaces:
        logger.error("No non-loopback network interfaces found.")
        sys.exit(1)

    print("\n  Available network interfaces:\n")
    for idx, iface in enumerate(ifaces, 1):
        print(f"    [{idx}]  {iface['ip']:>15s}   ({iface['name']})")

    print()
    while True:
        try:
            choice = int(input("  Select interface number: "))
            if 1 <= choice <= len(ifaces):
                return ifaces[choice - 1]["ip"]
        except (ValueError, EOFError):
            pass
        print("  Invalid choice, try again.")


# ---------------------------------------------------------------------------
# Core proxy logic
# ---------------------------------------------------------------------------

async def pipe(reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
    try:
        while True:
            data = await reader.read(65536)
            if not data:
                break
            writer.write(data)
            await writer.drain()
    except (ConnectionResetError, BrokenPipeError, ConnectionAbortedError, OSError):
        pass
    finally:
        try:
            if not writer.is_closing():
                writer.close()
        except OSError:
            pass


def _blocking_connect(bind_ip: str, host: str, port: int) -> socket.socket:
    infos = socket.getaddrinfo(host, port, socket.AF_INET, socket.SOCK_STREAM)
    if not infos:
        raise OSError(f"Could not resolve {host}")

    last_err = None
    for family, stype, proto, canonname, sockaddr in infos:
        sock = socket.socket(family, stype, proto)
        try:
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            sock.settimeout(15)
            sock.bind((bind_ip, 0))
            sock.connect(sockaddr)
            sock.settimeout(None)
            return sock
        except OSError as e:
            last_err = e
            sock.close()

    raise last_err or OSError(f"Failed to connect to {host}:{port}")


class InterfaceBoundProxy:

    def __init__(self, bind_ip: str, listen_host: str = "127.0.0.1", listen_port: int = 8118):
        self.bind_ip = bind_ip
        self.listen_host = listen_host
        self.listen_port = listen_port

    async def _open_remote(self, host: str, port: int) -> tuple[asyncio.StreamReader, asyncio.StreamWriter]:
        loop = asyncio.get_running_loop()
        sock = await loop.run_in_executor(
            None,
            functools.partial(_blocking_connect, self.bind_ip, host, port),
        )
        sock.setblocking(False)
        reader, writer = await asyncio.open_connection(sock=sock)
        return reader, writer

    async def _handle_connect(
        self,
        target_host: str,
        target_port: int,
        client_reader: asyncio.StreamReader,
        client_writer: asyncio.StreamWriter,
        http_version: str,
    ):
        try:
            remote_reader, remote_writer = await self._open_remote(target_host, target_port)
        except OSError as exc:
            client_writer.write(f"{http_version} 502 Bad Gateway\r\n\r\n".encode())
            await client_writer.drain()
            logger.warning("CONNECT %s:%d failed: %s", target_host, target_port, exc)
            return

        client_writer.write(f"{http_version} 200 Connection established\r\n\r\n".encode())
        await client_writer.drain()
        logger.info("CONNECT %s:%d via %s", target_host, target_port, self.bind_ip)

        await asyncio.gather(
            pipe(client_reader, remote_writer),
            pipe(remote_reader, client_writer),
        )

    async def _handle_http(
        self,
        method: str,
        url: str,
        http_version: str,
        header_lines: list[bytes],
        body_prefix: bytes,
        client_reader: asyncio.StreamReader,
        client_writer: asyncio.StreamWriter,
    ):
        if url.lower().startswith("http://"):
            rest = url[7:]
        else:
            rest = url
        slash_idx = rest.find("/")
        if slash_idx == -1:
            host_part, path = rest, "/"
        else:
            host_part, path = rest[:slash_idx], rest[slash_idx:]

        if ":" in host_part:
            host, port_str = host_part.rsplit(":", 1)
            port = int(port_str)
        else:
            host, port = host_part, 80

        try:
            remote_reader, remote_writer = await self._open_remote(host, port)
        except OSError as exc:
            client_writer.write(f"{http_version} 502 Bad Gateway\r\n\r\n".encode())
            await client_writer.drain()
            logger.warning("HTTP %s %s failed: %s", method, url, exc)
            return

        logger.info("HTTP  %s %s via %s", method, url, self.bind_ip)

        request_line = f"{method} {path} {http_version}\r\n".encode()
        remote_writer.write(request_line)
        for hdr in header_lines:
            remote_writer.write(hdr + b"\r\n")
        remote_writer.write(b"\r\n")
        if body_prefix:
            remote_writer.write(body_prefix)
        await remote_writer.drain()

        await asyncio.gather(
            pipe(client_reader, remote_writer),
            pipe(remote_reader, client_writer),
        )

    async def _handle_client(self, client_reader: asyncio.StreamReader, client_writer: asyncio.StreamWriter):
        peer = client_writer.get_extra_info("peername")
        try:
            raw_line = await asyncio.wait_for(client_reader.readline(), timeout=30)
            if not raw_line:
                return

            request_line = raw_line.decode("utf-8", errors="replace").strip()
            parts = request_line.split()
            if len(parts) < 3:
                return

            method, target, http_version = parts[0], parts[1], parts[2]

            header_lines: list[bytes] = []
            while True:
                hdr = await asyncio.wait_for(client_reader.readline(), timeout=30)
                if hdr in (b"\r\n", b"\n", b""):
                    break
                header_lines.append(hdr.rstrip(b"\r\n"))

            if method.upper() == "CONNECT":
                if ":" in target:
                    host, port_str = target.rsplit(":", 1)
                    port = int(port_str)
                else:
                    host, port = target, 443
                await self._handle_connect(host, port, client_reader, client_writer, http_version)
            else:
                await self._handle_http(method, target, http_version, header_lines, b"", client_reader, client_writer)
        except (asyncio.TimeoutError, ConnectionResetError, BrokenPipeError, ConnectionAbortedError, OSError):
            pass
        except Exception:
            logger.exception("Unexpected error from %s", peer)
        finally:
            try:
                if not client_writer.is_closing():
                    client_writer.close()
            except OSError:
                pass

    async def run(self):
        server = await asyncio.start_server(
            self._handle_client,
            self.listen_host,
            self.listen_port,
        )
        addrs = ", ".join(str(s.getsockname()) for s in server.sockets)
        logger.info("Proxy running on %s", addrs)
        logger.info("Outgoing traffic bound to %s", self.bind_ip)
        logger.info("Browser proxy: %s:%d", self.listen_host, self.listen_port)

        async with server:
            await server.serve_forever()


# ---------------------------------------------------------------------------
# Entry
# ---------------------------------------------------------------------------

def setup_logging(logfile: str | None = None, verbose: bool = False):
    level = logging.DEBUG if verbose else logging.INFO
    handlers: list[logging.Handler] = []

    if logfile:
        fh = logging.FileHandler(logfile, encoding="utf-8")
        fh.setFormatter(logging.Formatter(LOG_FORMAT))
        handlers.append(fh)
    else:
        sh = logging.StreamHandler()
        sh.setFormatter(logging.Formatter(LOG_FORMAT))
        handlers.append(sh)

    logging.basicConfig(level=level, handlers=handlers, force=True)


def main():
    parser = argparse.ArgumentParser(
        description="Local HTTP/HTTPS proxy that routes traffic through a chosen network interface."
    )
    parser.add_argument(
        "--bind", "-b",
        help="IP address of the network interface to use for outgoing connections. "
             "If omitted you will be prompted to pick one interactively.",
    )
    parser.add_argument(
        "--port", "-p", type=int, default=8118,
        help="Local port the proxy listens on (default: 8118).",
    )
    parser.add_argument(
        "--listen", "-l", default="127.0.0.1",
        help="Address to listen on (default: 127.0.0.1).",
    )
    parser.add_argument(
        "--logfile",
        help="Write logs to this file instead of the console.",
    )
    parser.add_argument(
        "--pidfile",
        help="Write the process ID to this file (for stop/kill scripts).",
    )
    parser.add_argument(
        "--verbose", "-v", action="store_true",
        help="Enable debug logging.",
    )
    parser.add_argument(
        "--list-interfaces", action="store_true", dest="list_ifaces",
        help="Print available interfaces as tab-separated lines and exit.",
    )
    args = parser.parse_args()

    if args.list_ifaces:
        for iface in list_interfaces():
            print(f"{iface['ip']}\t{iface['name']}")
        sys.exit(0)

    setup_logging(logfile=args.logfile, verbose=args.verbose)

    bind_ip = args.bind or pick_interface_interactive()

    try:
        ipaddress.ip_address(bind_ip)
    except ValueError:
        logger.error("'%s' is not a valid IP address.", bind_ip)
        sys.exit(1)

    if args.pidfile:
        with open(args.pidfile, "w") as f:
            f.write(str(os.getpid()))
        logger.info("PID %d written to %s", os.getpid(), args.pidfile)

    proxy = InterfaceBoundProxy(bind_ip, args.listen, args.port)

    try:
        asyncio.run(proxy.run())
    except KeyboardInterrupt:
        logger.info("Proxy stopped by user.")
    finally:
        if args.pidfile and os.path.exists(args.pidfile):
            os.remove(args.pidfile)


if __name__ == "__main__":
    main()
