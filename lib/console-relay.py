#!/usr/bin/env python3
"""console-relay.py LISTEN_PORT TARGET_PORT: forward 0.0.0.0:LISTEN_PORT to 127.0.0.1:TARGET_PORT.

mesh-llm serves its management routes (Configuration, Plugins) only to a loopback peer. Docker's
published port reaches the node from the bridge address, so the laptop browser gets 403. This relay
runs inside the container, so the node sees 127.0.0.1 as the peer. The container publishes the relay
port on the laptop's loopback only (README, "Start").
"""
import asyncio
import sys


async def pipe(r, w):
    try:
        while data := await r.read(65536):
            w.write(data)
            await w.drain()
    except (ConnectionError, OSError):
        pass
    finally:
        w.close()


async def handle(cr, cw, target):
    try:
        ur, uw = await asyncio.open_connection("127.0.0.1", target)
    except OSError:
        cw.close()
        return
    await asyncio.gather(pipe(cr, uw), pipe(ur, cw))


async def main(listen, target):
    server = await asyncio.start_server(lambda r, w: handle(r, w, target), "0.0.0.0", listen)
    async with server:
        await server.serve_forever()


asyncio.run(main(int(sys.argv[1]), int(sys.argv[2])))
