"""client.py's maintenance command `update <sha>` (hot update of the hub and
every machine, hub_update.py), and the code lines `status` prints."""
import asyncio
import json
import time

import websockets

from client_connection import connect, control
from hub_update import SHA  # noqa: F401 (client.py checks a commit with it)

POLL_SECONDS = 1.0  # between status polls while the hub and machines come back (tests shorten it)


async def ask_status(url):
	"""The hub's status answer, or None while it is restarting."""
	try:
		connection = await asyncio.wait_for(connect(url, {"type": "status"}), 10)
	except (OSError, asyncio.TimeoutError, websockets.InvalidHandshake, websockets.ConnectionClosed):
		return None
	try:
		return json.loads(await asyncio.wait_for(connection.recv(), 10))
	except (asyncio.TimeoutError, websockets.ConnectionClosed, ValueError):
		return None
	finally:
		await connection.socket.close()


async def update(url, commit, force, wait):
	"""Asks the hub to update; then polls until it is back on the commit and
	every machine connected is on it too, or `wait` seconds. 0 when all are."""
	began = time.time()
	async with control(url, {"type": "update", "commit": commit, "force": force}) as connection:
		try:
			answer = json.loads(await connection.recv())
		except websockets.ConnectionClosed:
			answer = {"type": "error", "text": "the hub closed the connection without answering (does it know update?)"}
	if answer.get("type") != "updating":
		print(f"update refused: {answer.get('text', answer)}", flush=True)
		return 1
	told, boot = answer.get("machines", 0), answer.get("boot")
	print(f"update {commit[:12]}: the hub checked it out and told {told} machines; waiting for it to come back", flush=True)
	back, up, on = None, [], []
	while time.time() < began + wait:
		state = await ask_status(url)
		if state and state.get("boot") != boot and state.get("code") == commit:
			if back is None:
				back = time.time() - began
				print(f"hub back on {commit[:12]} after {back:.0f}s", flush=True)
			codes, up = state.get("codes", {}), state.get("up", [])
			on = [name for name in up if codes.get(name) == commit]
			if len(up) >= told and len(on) == len(up):
				break
		await asyncio.sleep(POLL_SECONDS)
	if back is None:
		print(f"the hub did not come back on {commit[:12]} within {wait}s (machine 1's coordinator.log says why)", flush=True)
		return 1
	behind = [name for name in up if name not in on]
	print(f"{len(on)} of {len(up)} machines on {commit[:12]} after {time.time() - began:.0f}s"
		+ (f"; not yet: {' '.join(behind)}" if behind else "") + (f"; {told} were up before" if len(up) < told else ""), flush=True)
	return 0 if not behind and len(up) >= told else 1


def code_lines(answer):
	"""For status: machines whose code differs from the hub's."""
	code, codes = answer.get("code"), answer.get("codes", {})
	if not code:
		return []
	other = [f"{name}={codes[name][:12] if codes.get(name) else '?'}" for name in answer.get("up", []) if codes.get(name) != code]
	return [f"machines on other code than the hub's {code[:12]}: {' '.join(other)}"] if other else []
