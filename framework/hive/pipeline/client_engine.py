"""client.py engine <sha>: an engine compile on one machine with cargo
(pipeline/hub_engine.py), its output printed as it comes."""
import asyncio
import json
import time

import websockets

from client_connection import MAX_MESSAGE, alert, control


async def engine(url, commit, wait):
	"""Runs an engine check and prints its output as it comes; 0 when it compiled."""
	began = time.time()
	async with control(url, {"type": "engine", "commit": commit}, max_size=MAX_MESSAGE) as connection:
		first = json.loads(await connection.recv())
		if first.get("type") != "engine-posted":
			print(f"engine check refused: {first.get('text', first)}", flush=True)
			return 1
		task = first["task"]
		print(f"engine check {task} of {commit[:12]}; machines with cargo: {' '.join(first['cargo']) or 'none yet (it waits for one)'}", flush=True)
		seen = 0
		while True:
			left = began + wait - time.time()
			if left <= 0:
				print(f"ENGINE TIMEOUT: no result in {wait}s", flush=True)
				return 1
			try:
				event = json.loads(await asyncio.wait_for(connection.recv(), left))
			except asyncio.TimeoutError:
				continue
			except websockets.ConnectionClosed:
				print("the control connection dropped before the engine check ended", flush=True)
				return 3
			if event.get("task") != task:
				continue
			if event["type"] == "engine-output":
				for line in event.get("lines", []):
					print(line, flush=True)
				seen += len(event.get("lines", []))
			elif event["type"] == "redealt":
				alert(f"ALERT REDEALT: engine check from {event['from']} to {event['to']}: {event['reason']} | nothing; it starts again there")
			elif event["type"] == "engine-finished":
				if not event["ok"] and not seen:
					print("\n".join(event.get("tail", [])), flush=True)
				print(f"ENGINE {'OK' if event['ok'] else 'FAILED'} on {event['machine']} in {event.get('seconds')}s"
					+ ("" if event["ok"] else f" (exit {event.get('code')})"), flush=True)
				return 0 if event["ok"] else 1
