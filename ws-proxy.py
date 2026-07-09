#!/usr/bin/env python3
import asyncio
import base64
import hashlib
import os
import socket

WS_MAGIC = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
LISTEN_PORT = int(os.environ.get("WS_PORT", "8880"))
TARGET_HOST = os.environ.get("WS_TARGET_HOST", "127.0.0.1")
TARGET_PORT = int(os.environ.get("WS_TARGET_PORT", "22"))

def make_accept_key(ws_key: str) -> str:
    sha1 = hashlib.sha1((ws_key + WS_MAGIC).encode()).digest()
    return base64.b64encode(sha1).decode()

async def handle_client(reader, writer):
    try:
        # Membaca buffer jumbo agar muat request berlapis dari DarkTunnel
        raw_headers = await reader.read(16384)
        if not raw_headers:
            writer.close()
            return

        raw_text = raw_headers.decode(errors="ignore")
        
        # Cari Sec-WebSocket-Key secara fleksibel di baris mana pun
        ws_key = None
        for line in raw_text.split("\r\n"):
            if "sec-websocket-key" in line.lower():
                try:
                    ws_key = line.split(":", 1)[1].strip()
                    break
                except Exception:
                    pass

        if not ws_key:
            ws_key = base64.b64encode(b"dummy-key-premium-salt").decode()

        # Jabat tangan WebSocket yang bersih standar industri
        response = (
            "HTTP/1.1 101 Switching Protocols\r\n"
            "Upgrade: websocket\r\n"
            "Connection: Upgrade\r\n"
            f"Sec-WebSocket-Accept: {make_accept_key(ws_key)}\r\n\r\n"
        )
        writer.write(response.encode())
        await writer.drain()

        # Hubungkan ke Dropbear SSH internal
        try:
            target_reader, target_writer = await asyncio.open_connection(TARGET_HOST, TARGET_PORT)
        except Exception:
            writer.close()
            return

        # SUNTIK OPTIMASI LEVEL KERNEL (Biar nempel kayak perangko di Python)
        sock = writer.get_extra_info('socket')
        if sock:
            sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 1)
            try:
                sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_KEEPIDLE, 30)
                sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_KEEPINTVL, 10)
                keepcnt = getattr(socket, 'TCP_KEEPCNT', 6)
                sock.setsockopt(socket.IPPROTO_TCP, keepcnt, 12)
            except Exception:
                pass

        # Jalur 1: HP -> SSH (Penyaring Payload Enhanced Memotong Sampah PATCH/BMOVE)
        async def pipe_client_to_ssh(src, dst):
            first_packet = True
            try:
                while True:
                    data = await src.read(65536)
                    if not data: break
                    if first_packet:
                        if b"SSH-" in data:
                            idx = data.find(b"SSH-")
                            dst.write(data[idx:])
                            await dst.drain()
                            first_packet = False
                        else:
                            continue
                    else:
                        dst.write(data)
                        await dst.drain()
            except Exception: pass
            finally: dst.close()

        # Jalur 2: SSH -> HP (Injeksi Heartbeat Perangko \x89\x00 tiap 5 detik)
        async def pipe_ssh_to_client(src, dst):
            try:
                while True:
                    try:
                        data = await asyncio.wait_for(src.read(65536), timeout=5.0)
                        if not data: break
                        dst.write(data)
                        await dst.drain()
                    except asyncio.TimeoutError:
                        # Tembak pancingan biner biar HTTP Custom/DarkTunnel mengunci jalur
                        dst.write(b"\x89\x00")
                        await dst.drain()
            except Exception: pass
            finally: dst.close()

        await asyncio.gather(
            pipe_client_to_ssh(reader, target_writer),
            pipe_ssh_to_client(target_reader, writer)
        )
    except Exception:
        pass
    finally:
        try: writer.close()
        except Exception: pass

async def main():
    server = await asyncio.start_server(handle_client, "0.0.0.0", LISTEN_PORT)
    async with server:
        await server.serve_forever()

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass
