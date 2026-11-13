#!/usr/bin/env python3
"""Proves the hive's hub (coordinator.py) with fake machines: the real
Coordinator runs in this process on localhost ports, and fake machines talk
to it over real websockets. Lease timeouts are shortened through the
constructor.

  GAME_ROOT=<game folder> python3 framework/hive/hub/test_queue.py [-v]

Its own cases run the hub with no plugin loaded, a made-up task kind
registered by the test. Then every plugin game.toml's hive_plugins names
that has a tests module (framework/hive/<name>/tests.py) adds its cases:
its cases(harness) is given this module, for Hub, until, check, the timings
and the real agent (AGENT, framework/scripts/standby-agent.py). One PASS or FAIL line
per case; exits 0 only when every case passes.
"""
import asyncio
import importlib
import importlib.util
import json
import os
import shutil
import sys
import tempfile
import time
import traceback

import websockets

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
VERBOSE = "-v" in sys.argv
import hub_config  # noqa: E402
if not VERBOSE:
	# Every hub module, and every plugin's hub module, binds hub_config.say when imported.
	hub_config.say = lambda message: None
import client  # noqa: E402
import coordinator as hub  # noqa: E402
import hive_plugins  # noqa: E402
import wire  # noqa: E402
from units import Task  # noqa: E402

# The real agent (framework/scripts/standby-agent.py), for its heartbeat and its take/cancel.
_spec = importlib.util.spec_from_file_location("agent_script", os.path.join(HERE, "..", "..", "scripts", "standby-agent.py"))
AGENT = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(AGENT)
if not VERBOSE:
	# The agent's modules bind agent.common.say, and so will the plugins' agent modules.
	for _name, _module in list(sys.modules.items()):
		if (_name.startswith("agent.") or _module is AGENT) and hasattr(_module, "say"):
			_module.say = lambda message: None

KEY = "test-worker-key"
TIMEOUTS = {"grace": 1.0, "silent": 1.5, "wedged": 4.0}
BEAT = 0.2  # a fake's heartbeat
CANCEL_SECONDS = 0.3  # how long a fake takes to kill a unit
CASE_SECONDS = 20


async def until(condition, timeout=10, step=0.02):
	deadline = time.time() + timeout
	while not condition():
		if time.time() > deadline:
			raise TimeoutError("condition not met in time")
		await asyncio.sleep(step)


def check(condition, problem):
	if not condition:
		raise AssertionError(problem)


class Hub:
	"""The real Coordinator on two free localhost ports, writing into a
	temporary folder, with the plugins named (None: game.toml's) set up with
	`settings`; machines() connects fakes of the class `fake`."""

	def __init__(self, plugins=None, settings=None, fake=None):
		self.plugins, self.settings, self.fake = plugins, settings or {}, fake

	async def start(self, folder=None):
		"""In a new temporary folder, or in `folder` to take over a stopped hub's tasks file and results."""
		self.folder = folder or tempfile.mkdtemp(prefix="queue-test-")
		self.c = hub.Coordinator(test_without_identity=True, timeouts=TIMEOUTS, worker_key=KEY,
			tasks_file=os.path.join(self.folder, "tasks.json"), results=os.path.join(self.folder, "results"), plugins=self.plugins)
		self.c.plugins.start(self.settings)
		self.c.loop = asyncio.get_running_loop()
		self.agents = await websockets.serve(self.c.agent, "127.0.0.1", 0, max_size=hub.MAX_MESSAGE)
		self.control = await websockets.serve(self.c.control, "127.0.0.1", 0, max_size=hub.MAX_CONTROL_MESSAGE)
		self.agent_url = f"ws://127.0.0.1:{self.agents.sockets[0].getsockname()[1]}"
		self.control_url = f"ws://127.0.0.1:{self.control.sockets[0].getsockname()[1]}"
		return self

	async def stop(self, fakes=(), keep=False):
		for fake in fakes:
			await fake.kill()
		if self.c.watchdog:
			self.c.watchdog.cancel()
		self.agents.close()
		self.control.close()
		# A session's open connection can hold wait_closed; it is not what's tested.
		try:
			await asyncio.wait_for(asyncio.gather(self.agents.wait_closed(), self.control.wait_closed()), 1)
		except asyncio.TimeoutError:
			pass
		if not keep:
			shutil.rmtree(self.folder, ignore_errors=True)

	async def machines(self, names, **options):
		fakes = [self.fake(self, name, **options) for name in names]
		await asyncio.gather(*(fake.connect() for fake in fakes))
		return fakes

	def task(self, identity):
		return self.c.tasks.get(identity) or self.c.finished[identity][0]


# --- the hub with no plugin ---

class Echo(Task):
	"""A made-up task kind: a unit is "say this back"."""

	def text(self, slot):
		return f"echo {slot}"


class Mini:
	"""A bare machine g<n>: takes a unit, sends back its text as a file and
	says done after `seconds`, heartbeating; answers a cancel with idle."""

	def __init__(self, at, name, seconds=0.3):
		self.hub, self.name, self.seconds = at, name, seconds
		self.socket = None
		self.running = {}  # unit -> its asyncio task
		self.received = []  # units dealt to it

	async def connect(self):
		self.socket = await websockets.connect(self.hub.agent_url, max_size=hub.MAX_MESSAGE)
		await self.socket.send(json.dumps({"type": "hello", "token": "test", "shard": int(self.name[1:]), "count": 2, "units": []}))
		self.reader = asyncio.ensure_future(self.read())

	async def read(self):
		try:
			async for message in self.socket:
				event = json.loads(message)
				if event["type"] == "task":
					unit = (event["id"], event["shard"])
					self.received.append(unit)
					self.running[unit] = asyncio.ensure_future(self.work(unit, event))
				elif event["type"] == "cancel":
					running = self.running.pop((event["task"], event["shard"]), None)
					if running:
						running.cancel()
					await self.send(json.dumps({"type": "idle", "task": event["task"], "shard": event["shard"]}))
		except websockets.ConnectionClosed:
			pass

	async def send(self, message):
		await self.socket.send(message)

	async def work(self, unit, event):
		ends = time.time() + self.seconds
		while time.time() < ends:
			await self.send(json.dumps({"type": "progress", "task": unit[0], "shard": unit[1], "stage": "echo",
				"line": "", "quiet": 0, "seconds": 0}))
			await asyncio.sleep(BEAT)
		data = event["task"].encode()
		await self.send(wire.pack({"type": "file", "task": unit[0], "shard": unit[1], "path": "out.txt", "size": len(data)}, data))
		await self.send(json.dumps({"type": "done", "task": unit[0], "shard": unit[1], "summary": "status=DONE\n"}))
		self.running.pop(unit, None)

	async def kill(self):
		for running in self.running.values():
			running.cancel()
		if self.socket:
			await self.socket.close()


class Events:
	"""Stands in for a watching session: every event the hub emits."""

	def __init__(self):
		self.events = []

	async def send(self, message):
		self.events.append(json.loads(message))

	def of(self, kind):
		return [event for event in self.events if event["type"] == kind]


async def bare_hub(seconds):
	at = await Hub(plugins=[], fake=Mini).start()
	fakes = await at.machines(["g1", "g2"], seconds=seconds)
	await until(lambda: len(at.c.connected()) == 2)
	events = Events()
	at.c.watchers.add(events)
	return at, fakes, events


async def case_hub_a():
	"""No plugin: a made-up kind's units dealt to two machines; one is lost,
	its unit is re-dealt to the other, and both results come in."""
	at, fakes, events = await bare_hub(0.8)
	try:
		check(not at.c.plugins.loaded and not at.c.plugins.messages and not at.c.plugins.requests, "a plugin was loaded")
		task = Echo(at.c.new_task_id("x"), 2, at.c.results)
		await at.c.add_task(task)
		await at.c.deal()
		await until(lambda: all(fake.running for fake in fakes))
		lost = next(fake for fake in fakes if fake.received[0][1] == 1)
		await lost.kill()
		await until(lambda: events.of("finished"), timeout=8)
		redealt = events.of("redealt")
		check(len(redealt) == 1 and redealt[0]["from"] == lost.name and redealt[0]["shard"] == 1 and "closed" in redealt[0]["reason"],
			f"re-deals: {redealt}")
		results = {slot: open(os.path.join(task.out, f"S{slot}", "out.txt")).read() for slot in (1, 2)}
		check(results == {1: "echo 1", 2: "echo 2"}, f"results: {results}")
		check(sorted(task.done) == [1, 2] and task.id not in at.c.tasks and not task.leases, "hub bookkeeping not finished")
		return f"2 echo units on g1+g2, {lost.name} lost mid-unit, S1 re-dealt to {redealt[0]['to']}, both results in, task finished"
	finally:
		await at.stop(fakes)


async def case_hub_b():
	"""No plugin: a machine's message of an unknown kind is dropped and logged
	once, its connection carries on; a session's unknown request gets an error."""
	at, fakes, events = await bare_hub(0.6)
	try:
		task = Echo(at.c.new_task_id("x"), 1, at.c.results)
		await at.c.add_task(task)
		await at.c.deal()
		await until(lambda: any(fake.running for fake in fakes))
		holder = next(fake for fake in fakes if fake.running)
		lease = task.leases[1]
		for kind in ("bogus", "bogus", ["not", "a", "kind"]):
			await holder.send(json.dumps({"type": kind, "task": task.id, "shard": 1, "lease": lease.number}))
		await until(lambda: events.of("finished"), timeout=5)
		check(at.c.roster[holder.name].socket is not None, "the machine was dropped")
		check(at.c.refused_kinds == {(holder.name, "bogus"), (holder.name, "['not', 'a', 'kind']")}, f"refused: {at.c.refused_kinds}")
		socket = await websockets.connect(at.control_url)
		await socket.send(json.dumps({"type": "build", "ref": "abc1234"}))
		answer = json.loads(await socket.recv())
		await socket.close()
		check(answer == {"type": "error", "text": "unknown request build"}, f"answered {answer}")
		return "unknown message kinds dropped, the unit still finished; a request no plugin registered answered with an error"
	finally:
		await at.stop(fakes)


CASES = [("hub-a", case_hub_a), ("hub-b", case_hub_b)]


async def main():
	started = time.time()
	failed = 0
	# Each plugin's own cases (framework/hive/<name>/tests.py).
	sys.path.insert(0, hive_plugins.HIVE)
	for name in hive_plugins.names():
		if importlib.util.find_spec(f"{name}.tests") is not None:
			CASES.extend(importlib.import_module(f"{name}.tests").cases(sys.modules[__name__]))
	for name, case in CASES:
		began = time.time()
		try:
			detail = await asyncio.wait_for(case(), CASE_SECONDS)
			print(f"PASS {name} ({time.time() - began:.1f}s): {detail}", flush=True)
		except Exception as error:
			failed += 1
			reason = str(error) or type(error).__name__
			print(f"FAIL {name} ({time.time() - began:.1f}s): {reason}", flush=True)
			if VERBOSE:
				traceback.print_exc()
	print(f"{len(CASES) - failed} of {len(CASES)} cases passed in {time.time() - started:.1f}s", flush=True)
	return 1 if failed else 0


if __name__ == "__main__":
	sys.exit(asyncio.run(main()))
